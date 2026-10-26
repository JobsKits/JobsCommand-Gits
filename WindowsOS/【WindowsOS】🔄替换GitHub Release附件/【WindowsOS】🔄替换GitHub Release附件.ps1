# 脚本自述：
# - 名称：【WindowsOS】🔄替换GitHub Release附件.ps1
# - 用途：选择 GitHub 仓库、分支、已发布 Release 和本地同名附件，备份后替换并下载验证。
# - 平台：Windows 10 / 11，Windows PowerShell 5.1 或 PowerShell 7；依赖 Git、gh、fzf。
# - 边界：先回车阅读确认，fzf 子层 ← 返回，最终精确 YES 才删除旧附件并上传；失败保留现场。
# - 不切换分支、不移动 Tag、不提交推送、不创建版本、不自动回滚或重试覆盖。

$script:ReleaseState = $null

# 展示无需依赖或文件写入的帮助。
function Show-ReleaseHelp {
    Write-Host '用法：.\【WindowsOS】🔄替换GitHub Release附件.cmd [分支 版本Tag] [选项]'
    Write-Host '  main v1.0.0          校验分支包含 Tag 提交，替换该版本的同名附件。'
    Write-Host '  --repo-dir 目录      基 Git 仓库，包含本仓及直属已初始化子模块。'
    Write-Host '  --source-dir 目录    新附件目录，只读取顶层精确同名非空普通文件。'
    Write-Host '  --help              显示帮助；不联网、不登录、不安装、不创建日志。'
    Write-Host '位置参数同时提供或同时省略；省略时 fzf 选择分支和 Release。'
    Write-Host '单选 Enter 确认；多选 Enter 勾选/取消、Space 确认、Ctrl+A 全选、Ctrl+D 清空。'
    Write-Host '非根选择器 ← 返回上一层，目录输入 :back 返回，Esc / Ctrl+C 取消，空选不执行。'
    Write-Host '仅支持 github.com 已发布且可修改的 Release；不执行上传文件本身。'
}
# 在建立运行目录前说明用途、风险并请求回车。
function Show-ReleaseIntro {
    param([string[]]$Arguments)
    Write-Host '【WindowsOS】🔄替换GitHub Release附件' -ForegroundColor Red
    Write-Host '1、用途：选择仓库、分支、Release 和本地同名附件，备份后更新远端。' -ForegroundColor Blue
    Write-Host '2、分支仅校验 Tag 历史，上传内容来自本地；不切分支、不提交推送或移动 Tag。' -ForegroundColor Blue
    Write-Host '3、精确 YES 后按已备份的附件 ID 删除旧文件，再上传；失败可能只完成一部分。' -ForegroundColor Blue
    Write-Host '4、fzf 子层 ← 返回上层；Esc / Ctrl+C 取消；日志、快照及 RESTORE.txt 保留在临时目录。' -ForegroundColor Blue
    if ($Arguments -ccontains '--help') {
        Show-ReleaseHelp
        return $false
    }
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        throw '本工具需要交互终端；请双击 CMD 或在 Windows Terminal 运行。--help 可非交互查看。'
    }
    $answer = Read-ReleaseInput '已了解用途与影响，按回车继续；其它输入取消'
    return ($answer -ceq '')
}
# 读取一行并把 EOF 当作停止条件。
function Read-ReleaseInput {
    param([string]$Prompt)
    Write-Host ($Prompt + '：') -NoNewline
    $line = [Console]::ReadLine()
    if ($null -eq $line) {
        throw '输入已结束，停止操作。'
    }
    return $line
}
# 建立独立运行目录与仅影响当前进程的工具环境。
function Initialize-ReleaseRuntime {
    $script:ReleaseState = @{
        WorkDir = Join-Path ([IO.Path]::GetTempPath()) ('GitHub-Release-Replace.' + [Guid]::NewGuid().ToString('N'))
        LogFile = ''; RepoOption = ''; SourceOption = ''; BranchArgument = ''; TagArgument = ''
        RepoDir = ''; Repository = ''; Branch = ''; Tag = ''; SourceDir = ''; TagSha = ''; BranchSha = ''
        RepoDirs = @(); Selected = @(); Selection = @(); ExpectedAssets = @(); Plan = $null
        Queries = @{}; Action = ''; Picked = @(); Steps = @(); Completed = 0; UploadStarted = $false
        Utf8 = New-Object Text.UTF8Encoding($false)
    }
    [void][IO.Directory]::CreateDirectory($script:ReleaseState.WorkDir)
    $script:ReleaseState.LogFile = Join-Path $script:ReleaseState.WorkDir 'Release-Replace.log'
    [IO.File]::WriteAllText($script:ReleaseState.LogFile, '', $script:ReleaseState.Utf8)
    $env:GH_HOST = 'github.com'
    $env:GH_PAGER = 'cat'
    $env:GH_PROMPT_DISABLED = '1'
    Write-ReleaseLog ('➤ 本次材料：' + $script:ReleaseState.WorkDir)
}
# 同步显示并落盘纯文本日志。
function Write-ReleaseLog {
    param([string]$Message)
    Write-Host $Message
    if ($script:ReleaseState -and $script:ReleaseState.LogFile) {
        [IO.File]::AppendAllText($script:ReleaseState.LogFile, $Message + [Environment]::NewLine, $script:ReleaseState.Utf8)
    }
}
# 对 Windows 原生命令行参数逐项引用，避免空格与引号改变边界。
function ConvertTo-NativeArgument {
    param([AllowEmptyString()][string]$Value)
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}
# 执行原生程序；二进制 stdout 直接写流，避免 PowerShell 5.1 转码损坏附件。
function Invoke-ReleaseProcess {
    param([string]$File, [string[]]$Arguments, [string]$OutputFile = '', [string]$WorkingDirectory = '', [switch]$AllowFailure)
    $command = Get-Command $File -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $command.Source
    $info.Arguments = (($Arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' ')
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    if ($WorkingDirectory) { $info.WorkingDirectory = $WorkingDirectory }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    $memory = $null
    $stream = $null
    $started = $false
    try {
        [void]$process.Start()
        $started = $true
        $errorTask = $process.StandardError.ReadToEndAsync()
        if ($OutputFile) {
            $stream = [IO.File]::Open($OutputFile, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
            $process.StandardOutput.BaseStream.CopyTo($stream)
            $stream.Dispose()
            $stream = $null
            $output = ''
        } else {
            $memory = New-Object IO.MemoryStream
            $process.StandardOutput.BaseStream.CopyTo($memory)
            $output = [Text.Encoding]::UTF8.GetString($memory.ToArray())
        }
        $process.WaitForExit()
        $errors = $errorTask.GetAwaiter().GetResult()
        if ($errors -and $script:ReleaseState -and $script:ReleaseState.LogFile) {
            [IO.File]::AppendAllText($script:ReleaseState.LogFile, $errors, $script:ReleaseState.Utf8)
        }
        $code = $process.ExitCode
        if ($code -ne 0 -and -not $AllowFailure) {
            throw ('命令失败：{0}，退出码 {1}；详见本轮日志。' -f $File, $code)
        }
        return [pscustomobject]@{ Code = $code; Output = $output; Error = $errors }
    } finally {
        if ($stream) { $stream.Dispose() }
        if ($memory) { $memory.Dispose() }
        if ($started -and -not $process.HasExited) { $process.Kill() }
        $process.Dispose()
    }
}
# 保存审计 JSON，数组的零项和单项形状保持不变。
function Save-ReleaseJson {
    param([object]$Value, [string]$Path)
    $json = ConvertTo-Json -InputObject $Value -Depth 60
    [IO.File]::WriteAllText($Path, $json, $script:ReleaseState.Utf8)
}
# 读取固定 GitHub 主机的 JSON；写操作不自动重试。
function Get-ReleaseApi {
    param([string]$Endpoint)
    $result = Invoke-ReleaseProcess 'gh' @('api', '--hostname', 'github.com', '--method', 'GET', $Endpoint)
    try { return ConvertFrom-Json -InputObject $result.Output } catch { throw ('GitHub JSON 响应无法解析：' + $Endpoint) }
}
# 逐页读取列表并校验数组形状，避免漏掉第 100 项之后的附件。
function Get-ReleaseApiArray {
    param([string]$Endpoint)
    $result = Invoke-ReleaseProcess 'gh' @('api', '--hostname', 'github.com', '--method', 'GET', '--paginate', '--slurp', $Endpoint)
    try { $pages = @(ConvertFrom-Json -InputObject $result.Output) } catch { throw ('GitHub 分页响应无法解析：' + $Endpoint) }
    if (-not $result.Output.TrimStart().StartsWith('[')) { throw '分页响应必须是数组。' }
    $all = New-Object 'Collections.Generic.List[object]'
    foreach ($page in $pages) {
        if ($page -isnot [Array]) { throw '分页响应中存在非数组页面。' }
        foreach ($item in $page) { $all.Add($item) }
    }
    return ,($all.ToArray())
}
# 解析参数并要求分支、Tag 成对提供。
function Read-ReleaseArguments {
    param([string[]]$Arguments)
    $positional = New-Object 'Collections.Generic.List[string]'
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $argument = $Arguments[$i]
        if ($argument -ceq '--repo-dir' -or $argument -ceq '--source-dir') {
            if ($i + 1 -ge $Arguments.Count) { throw ($argument + ' 缺少目录。') }
            $i++
            if ($argument -ceq '--repo-dir') { $script:ReleaseState.RepoOption = $Arguments[$i] }
            else { $script:ReleaseState.SourceOption = $Arguments[$i] }
        } elseif ($argument.StartsWith('--')) { throw ('未知选项：' + $argument) }
        else { $positional.Add($argument) }
    }
    if ($positional.Count -ne 0 -and $positional.Count -ne 2) { throw '位置参数必须同时提供：分支 版本Tag。' }
    if ($positional.Count -eq 2) {
        if ([string]::IsNullOrEmpty($positional[0]) -or [string]::IsNullOrEmpty($positional[1]) -or ($positional -join '') -match '\p{Cc}') { throw '分支和 Tag 不能为空或包含控制字符。' }
        $script:ReleaseState.BranchArgument = $positional[0]
        $script:ReleaseState.TagArgument = $positional[1]
    }
}
# 只读检查平台、工具能力和登录；缺依赖时给出官方安装入口并停止。
function Test-ReleaseEnvironment {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or [Environment]::OSVersion.Version.Major -lt 10) { throw 'Windows 版要求 Windows 10 或更新版本。' }
    if ($PSVersionTable.PSVersion -lt [version]'5.1') { throw '需要 Windows PowerShell 5.1 或 PowerShell 7。' }
    $sources = @{ git = 'https://git-scm.com/download/win'; gh = 'https://cli.github.com/'; fzf = 'https://github.com/junegunn/fzf/releases' }
    foreach ($tool in @('git', 'gh', 'fzf')) {
        if (-not (Get-Command $tool -CommandType Application -ErrorAction SilentlyContinue)) { throw ('缺少依赖 {0}。官方来源：{1}；安装并重新打开终端后再运行。' -f $tool, $sources[$tool]) }
        [void](Invoke-ReleaseProcess $tool @('--version'))
    }
    $help = (Invoke-ReleaseProcess 'fzf' @('--help')).Output
    foreach ($flag in @('--footer', '--expect', '--bind', '--print-query')) {
        if (-not $help.Contains($flag)) { throw ('fzf 缺少选项 ' + $flag + '，请更新后重新运行。') }
    }
    [void](Invoke-ReleaseProcess 'gh' @('auth', 'status', '--hostname', 'github.com'))
}
# 规范化用户粘贴或拖入的单个目录，不把路径作为代码执行。
function Resolve-ReleaseDirectory {
    param([string]$Value)
    if ($Value -match '\p{Cc}') { throw '目录不能包含控制字符。' }
    $candidate = $Value
    if ($candidate.Length -ge 2 -and (($candidate[0] -eq '"' -and $candidate[$candidate.Length - 1] -eq '"') -or ($candidate[0] -eq "'" -and $candidate[$candidate.Length - 1] -eq "'"))) { $candidate = $candidate.Substring(1, $candidate.Length - 2) }
    $item = Get-Item -LiteralPath $candidate -Force -ErrorAction Stop
    if (-not $item.PSIsContainer) { throw ('不是目录：' + $candidate) }
    return $item.FullName
}
# 定位基仓库，仅列出本仓和直属已初始化子模块。
function Find-ReleaseRepositories {
    $root = ''
    if ($script:ReleaseState.RepoOption) { $root = Resolve-ReleaseDirectory $script:ReleaseState.RepoOption }
    else {
        foreach ($candidate in @((Get-Location).ProviderPath, $PSScriptRoot)) {
            $result = Invoke-ReleaseProcess 'git' @('-C', $candidate, 'rev-parse', '--show-toplevel') -AllowFailure
            if ($result.Code -eq 0) { $root = $result.Output.TrimEnd("`r", "`n"); break }
        }
        if (-not $root) {
            $inputPath = Read-ReleaseInput '拖入目标 Git 仓库或父仓目录（空输入取消）'
            if ($inputPath -ceq '') { $script:ReleaseState.Action = 'cancel'; return }
            $root = Resolve-ReleaseDirectory $inputPath
        }
    }
    $root = (Invoke-ReleaseProcess 'git' @('-C', $root, 'rev-parse', '--show-toplevel')).Output.TrimEnd("`r", "`n")
    if ($root -match '\p{Cc}') { throw '仓库路径含控制字符。' }
    $directories = New-Object 'Collections.Generic.List[string]'
    $directories.Add((Resolve-ReleaseDirectory $root))
    $modules = Join-Path $root '.gitmodules'
    if (Test-Path -LiteralPath $modules -PathType Leaf) {
        $result = Invoke-ReleaseProcess 'git' @('config', '-z', '--file', $modules, '--get-regexp', '\.path$') -AllowFailure
        if ($result.Code -ne 0 -and $result.Code -ne 1) { throw '无法读取 .gitmodules。' }
        foreach ($record in $result.Output.Split([char]0)) {
            if (-not $record.Contains("`n")) { continue }
            $child = $record.Substring($record.IndexOf("`n") + 1)
            if (-not $child -or $child -match '\p{Cc}') { continue }
            $candidate = Join-Path $root $child
            if (-not (Test-Path -LiteralPath (Join-Path $candidate '.git'))) { continue }
            $found = Invoke-ReleaseProcess 'git' @('-C', $candidate, 'rev-parse', '--show-toplevel') -AllowFailure
            if ($found.Code -ne 0) { continue }
            $actual = Resolve-ReleaseDirectory $found.Output.TrimEnd("`r", "`n")
            $prefix = $directories[0].TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
            if ($actual.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -and -not $directories.Contains($actual)) { $directories.Add($actual) }
        }
    }
    $script:ReleaseState.RepoDirs = $directories.ToArray()
}
# 调用 fzf 并区分返回、取消、空选及错误；Windows transform 由 cmd.exe 执行。
function Select-ReleaseFzf {
    param([string]$Key, [string[]]$Labels, [switch]$Multiple, [string]$Back = '')
    $script:ReleaseState.Action = 'empty'
    $script:ReleaseState.Picked = @()
    if ($Labels.Count -eq 0) { return }
    $hint = 'Enter 确认；Esc / Ctrl+C 取消'
    $options = @('--sync', '--layout=reverse', '--border', '--height=80%', '--delimiter=\t', '--with-nth=2..', '--print-query', ('--prompt=' + $Key + ' > '))
    if ($script:ReleaseState.Queries.ContainsKey($Key)) { $options += '--query=' + $script:ReleaseState.Queries[$Key] }
    if ($Multiple) {
        $hint = 'Enter 勾选/取消；Space 确认；Ctrl+A 全选；Ctrl+D 清空；空选不执行；Esc / Ctrl+C 取消'
        $options += @('--multi', '--bind', 'enter:toggle,ctrl-a:select-all,ctrl-d:deselect-all,esc:abort,space:transform:if %FZF_SELECT_COUNT% GTR 0 (echo accept) else (echo print^(__JOBS_EMPTY__^)+accept)')
    } else { $options += @('--bind', 'enter:accept,esc:abort') }
    if ($Back) { $hint += '；← 返回' + $Back; $options += '--expect=left' }
    $options += @('--header=' + $hint, '--footer=' + $hint)
    $rows = @(for ($i = 0; $i -lt $Labels.Count; $i++) { ($i + 1).ToString() + "`t" + $Labels[$i] })
    $savedOptions = [Environment]::GetEnvironmentVariable('FZF_DEFAULT_OPTS', 'Process')
    $savedOptionsFile = [Environment]::GetEnvironmentVariable('FZF_DEFAULT_OPTS_FILE', 'Process')
    $savedShell = [Environment]::GetEnvironmentVariable('SHELL', 'Process')
    $savedEncoding = $global:OutputEncoding
    $savedConsoleEncoding = [Console]::OutputEncoding
    try {
        $env:FZF_DEFAULT_OPTS = ''
        $env:FZF_DEFAULT_OPTS_FILE = ''
        $env:SHELL = $env:ComSpec
        $global:OutputEncoding = New-Object Text.UTF8Encoding($false)
        [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
        $output = @($rows | & fzf @options)
        $code = $LASTEXITCODE
    } finally {
        [Environment]::SetEnvironmentVariable('FZF_DEFAULT_OPTS', $savedOptions, 'Process')
        [Environment]::SetEnvironmentVariable('FZF_DEFAULT_OPTS_FILE', $savedOptionsFile, 'Process')
        [Environment]::SetEnvironmentVariable('SHELL', $savedShell, 'Process')
        $global:OutputEncoding = $savedEncoding
        [Console]::OutputEncoding = $savedConsoleEncoding
    }
    if ($output -ccontains '__JOBS_EMPTY__') { return }
    if ($output.Count -gt 0) { $script:ReleaseState.Queries[$Key] = $output[0] }
    $offset = 1
    if ($Back) {
        if ($output.Count -gt 1 -and $output[1] -ceq 'left' -and ($code -eq 0 -or $code -eq 1)) { $script:ReleaseState.Action = 'back'; return }
        $offset++
    }
    if ($code -eq 130) { $script:ReleaseState.Action = 'cancel'; return }
    if ($code -eq 1) { return }
    if ($code -ne 0) { throw ('fzf 失败，退出码 ' + $code) }
    $picked = @()
    for ($i = $offset; $i -lt $output.Count; $i++) {
        if ($output[$i] -notmatch '^(\d+)\t') { throw '选择结果编号无效。' }
        $index = [int]$Matches[1] - 1
        if ($index -lt 0 -or $index -ge $Labels.Count -or $output[$i] -cne $rows[$index]) { throw '选择结果不在原始候选清单中。' }
        if ($picked -notcontains $index) { $picked += $index }
    }
    if ($picked.Count -gt 0) { $script:ReleaseState.Picked = $picked; $script:ReleaseState.Action = 'selected' }
}
# 只解析明确的 github.com 远端，不展示含凭据 URL。
function ConvertFrom-GitHubRemote {
    param([string]$Url)
    if ($Url -cmatch '^(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?/?$') { return $Matches[1] }
    return ''
}
# 选择仓库并清除依赖旧仓库的下层状态。
function Select-ReleaseRepository {
    Select-ReleaseFzf '仓库' $script:ReleaseState.RepoDirs
    if ($script:ReleaseState.Action -cne 'selected') { return }
    $chosen = $script:ReleaseState.RepoDirs[$script:ReleaseState.Picked[0]]
    if ($chosen -cne $script:ReleaseState.RepoDir) {
        $script:ReleaseState.Repository = ''; $script:ReleaseState.Branch = ''; $script:ReleaseState.Tag = ''; $script:ReleaseState.SourceDir = ''; $script:ReleaseState.Queries = @{}
    }
    $script:ReleaseState.RepoDir = $chosen
}
# 选择 GitHub 远端并确认当前账户具有写权限。
function Select-ReleaseRemote {
    $remotes = (Invoke-ReleaseProcess 'git' @('-C', $script:ReleaseState.RepoDir, 'remote')).Output -split '\r?\n'
    $repositories = @(); $labels = @()
    foreach ($remote in $remotes) {
        if (-not $remote -or $remote -match '\p{Cc}') { continue }
        $url = (Invoke-ReleaseProcess 'git' @('-C', $script:ReleaseState.RepoDir, 'remote', 'get-url', $remote)).Output.TrimEnd("`r", "`n")
        $repository = ConvertFrom-GitHubRemote $url
        if ($repository) { $repositories += $repository; $labels += $remote + ' → ' + $repository }
    }
    if ($repositories.Count -eq 0) { throw '所选仓库没有支持的 github.com 远端。' }
    Select-ReleaseFzf '远端' $labels -Back '仓库'
    if ($script:ReleaseState.Action -cne 'selected') { return }
    $chosen = $repositories[$script:ReleaseState.Picked[0]]
    if ($chosen -cne $script:ReleaseState.Repository) { $script:ReleaseState.Branch = ''; $script:ReleaseState.Tag = ''; $script:ReleaseState.SourceDir = ''; $script:ReleaseState.Queries.Remove('分支'); $script:ReleaseState.Queries.Remove('版本'); $script:ReleaseState.Queries.Remove('附件') }
    $script:ReleaseState.Repository = $chosen
    $repositoryInfo = Get-ReleaseApi ('repos/' + $chosen)
    Save-ReleaseJson $repositoryInfo (Join-Path $script:ReleaseState.WorkDir 'repository.json')
    if ($repositoryInfo.permissions.push -ne $true) { throw '当前 gh 账户缺少目标仓库写权限。' }
    $script:ReleaseState.Branch = $script:ReleaseState.BranchArgument
    $script:ReleaseState.Tag = $script:ReleaseState.TagArgument
}
# 选择远端分支，变更后清理版本和来源状态。
function Select-ReleaseBranch {
    $branches = Get-ReleaseApiArray ('repos/' + $script:ReleaseState.Repository + '/branches?per_page=100')
    $names = @($branches | ForEach-Object { [string]$_.name })
    foreach ($name in $names) { if (-not $name -or $name -match '\p{Cc}') { throw '远端分支名无法安全展示。' } }
    Select-ReleaseFzf '分支' $names -Back '远端'
    if ($script:ReleaseState.Action -cne 'selected') { return }
    $chosen = $names[$script:ReleaseState.Picked[0]]
    if ($chosen -cne $script:ReleaseState.Branch) { $script:ReleaseState.Tag = ''; $script:ReleaseState.SourceDir = ''; $script:ReleaseState.Queries.Remove('版本'); $script:ReleaseState.Queries.Remove('附件') }
    $script:ReleaseState.Branch = $chosen
}
# 选择已发布版本；不可变状态在后续预检中明确拒绝。
function Select-ReleaseVersion {
    $releases = Get-ReleaseApiArray ('repos/' + $script:ReleaseState.Repository + '/releases?per_page=100')
    $names = @($releases | Where-Object { $_.draft -eq $false } | ForEach-Object { [string]$_.tag_name })
    foreach ($name in $names) { if (-not $name -or $name -match '\p{Cc}') { throw 'Release Tag 无法安全展示。' } }
    Select-ReleaseFzf '版本' $names -Back '分支'
    if ($script:ReleaseState.Action -cne 'selected') { return }
    $chosen = $names[$script:ReleaseState.Picked[0]]
    if ($chosen -cne $script:ReleaseState.Tag) { $script:ReleaseState.SourceDir = ''; $script:ReleaseState.Queries.Remove('附件') }
    $script:ReleaseState.Tag = $chosen
}
# 精确解析 Tag 引用及附注标签到提交 SHA，避免同名分支混淆。
function Resolve-ReleaseTagCommit {
    $object = Get-ReleaseApi ('repos/' + $script:ReleaseState.Repository + '/git/ref/tags/' + [Uri]::EscapeDataString($script:ReleaseState.Tag))
    for ($depth = 0; $depth -le 10; $depth++) {
        $sha = [string]$object.object.sha
        if ($sha -cnotmatch '^[a-fA-F0-9]{40,64}$') { throw 'Tag 对象 SHA 无效。' }
        if ($object.object.type -ceq 'commit') { return $sha }
        if ($object.object.type -cne 'tag') { throw 'Tag 没有指向提交。' }
        $object = Get-ReleaseApi ('repos/' + $script:ReleaseState.Repository + '/git/tags/' + $sha)
    }
    throw '附注 Tag 嵌套超过 10 层。'
}
# 按提交 SHA 校验 Tag 属于指定远端分支历史。
function Test-ReleaseBranchAndTag {
    $branch = Get-ReleaseApi ('repos/' + $script:ReleaseState.Repository + '/branches/' + [Uri]::EscapeDataString($script:ReleaseState.Branch))
    $sha = [string]$branch.commit.sha
    if ($sha -cnotmatch '^[a-fA-F0-9]{40,64}$') { throw '分支提交 SHA 无效。' }
    $script:ReleaseState.BranchSha = $sha
    $script:ReleaseState.TagSha = Resolve-ReleaseTagCommit
    $comparison = Get-ReleaseApi ('repos/' + $script:ReleaseState.Repository + '/compare/' + $script:ReleaseState.TagSha + '...' + $sha)
    if (@('ahead', 'identical') -cnotcontains $comparison.status -or $comparison.base_commit.sha -cne $script:ReleaseState.TagSha) { throw 'Tag 提交不属于指定远端分支历史。' }
    Write-ReleaseLog ('➤ 校验｜{0}｜分支 {1}｜Tag {2}｜提交 {3}' -f $script:ReleaseState.Repository, $script:ReleaseState.Branch, $script:ReleaseState.Tag, $script:ReleaseState.TagSha)
}
# 读取并保存完整快照，拒绝草稿、不可变版本、重名及未完成附件。
function Get-ReleaseSnapshot {
    param([string]$Prefix)
    $release = Get-ReleaseApi ('repos/' + $script:ReleaseState.Repository + '/releases/tags/' + [Uri]::EscapeDataString($script:ReleaseState.Tag))
    if ($release.tag_name -cne $script:ReleaseState.Tag -or $release.draft -ne $false -or $release.immutable -ne $false -or [string]$release.id -notmatch '^\d+$') { throw 'Release 不存在、未发布、不可变或响应无效。' }
    $assets = Get-ReleaseApiArray ('repos/' + $script:ReleaseState.Repository + '/releases/' + $release.id + '/assets?per_page=100')
    $seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($asset in $assets) {
        if ([string]$asset.id -notmatch '^\d+$' -or $asset.name -isnot [string] -or [string]$asset.size -notmatch '^\d+$' -or $asset.state -cne 'uploaded' -or -not $seen.Add($asset.name)) { throw '附件清单无效、重名或存在未完成上传。' }
    }
    Save-ReleaseJson $release ($Prefix + '.release.json')
    Save-ReleaseJson @($assets) ($Prefix + '.assets.json')
    return [pscustomobject]@{ Release = $release; Assets = @($assets) }
}
# 限定可映射到单个 Windows 文件的名称，并排除 gh 标签分隔符。
function Test-ReleaseFilename {
    param([string]$Name)
    if (-not $Name -or $Name -ceq '.' -or $Name -ceq '..' -or $Name -match '[\p{Cc}<>:"/\\|?*#]' -or $Name.EndsWith('.') -or $Name.EndsWith(' ') -or $Name -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') { return $false }
    return $true
}
# 检验候选是精确大小写同名的非空普通文件，排除链接与重解析点。
function Get-ReleaseSourceFile {
    param([string]$Directory, [string]$Name)
    if (-not (Test-ReleaseFilename $Name)) { return $null }
    foreach ($item in (Get-ChildItem -LiteralPath $Directory -Force -ErrorAction Stop)) {
        if ([StringComparer]::Ordinal.Equals($item.Name, $Name) -and -not $item.PSIsContainer -and $item.Length -gt 0 -and -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $item }
    }
    return $null
}
# 选择来源目录及精确同名附件；输入 :back 返回实际上层。
function Select-ReleaseFiles {
    Test-ReleaseBranchAndTag
    $script:ReleaseState.Plan = Get-ReleaseSnapshot (Join-Path $script:ReleaseState.WorkDir 'plan')
    $default = Join-Path $script:ReleaseState.RepoDir ('Releases/' + $script:ReleaseState.Tag)
    if (-not (Test-Path -LiteralPath $default -PathType Container)) { $default = $script:ReleaseState.RepoDir }
    if ($script:ReleaseState.SourceDir) { $default = $script:ReleaseState.SourceDir }
    if ($script:ReleaseState.SourceOption) { $default = $script:ReleaseState.SourceOption }
    Write-ReleaseLog ('➤ 新附件默认目录：' + $default)
    $inputPath = Read-ReleaseInput '拖入新附件目录；回车使用默认目录；:back 返回上一选择器'
    if ($inputPath -ceq ':back') { $script:ReleaseState.Action = 'back'; return }
    if ($inputPath -ceq '') { $inputPath = $default }
    $script:ReleaseState.SourceDir = Resolve-ReleaseDirectory $inputPath
    $names = @(); $labels = @()
    foreach ($asset in $script:ReleaseState.Plan.Assets) {
        $item = Get-ReleaseSourceFile $script:ReleaseState.SourceDir $asset.name
        if ($item) { $names += $asset.name; $labels += '{0}｜{1} 字节' -f $asset.name, $item.Length }
    }
    if ($names.Count -eq 0) { Write-ReleaseLog '⚠ 该目录没有可替换的同名非空普通文件。' }
    Select-ReleaseFzf '附件' $labels -Multiple -Back $script:ReleaseState.Steps[$script:ReleaseState.Steps.Count - 2]
    if ($script:ReleaseState.Action -ceq 'selected') { $script:ReleaseState.Selected = @($script:ReleaseState.Picked | ForEach-Object { $names[$_] }) }
}
# 循环导航至真实上一层，未完成计划时不备份、不上传。
function Read-ReleasePlan {
    if ($script:ReleaseState.Action -ceq 'cancel') { return $false }
    $steps = @('仓库', '远端')
    if (-not $script:ReleaseState.BranchArgument) { $steps += @('分支', '版本') }
    $steps += '附件'
    $script:ReleaseState.Steps = $steps
    $index = 0
    while ($index -lt $steps.Count) {
        switch ($steps[$index]) {
            '仓库' { Select-ReleaseRepository }
            '远端' { Select-ReleaseRemote }
            '分支' { Select-ReleaseBranch }
            '版本' { Select-ReleaseVersion }
            '附件' { Select-ReleaseFiles }
        }
        switch ($script:ReleaseState.Action) {
            'selected' { $index++ }
            'back' { if ($index -gt 0) { $index-- } }
            'cancel' { Write-ReleaseLog 'ℹ 已取消；远端未修改。'; return $false }
            'empty' { Write-ReleaseLog 'ℹ 空选或没有匹配项；远端未修改。'; return $false }
            default { throw '选择器返回未知状态。' }
        }
    }
    return $true
}
# 计算文件 SHA-256，统一使用小写十六进制。
function Get-ReleaseSha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
# 保存上传副本和原始资产记录，确认后不再依赖源目录内容。
function Save-ReleasePlan {
    foreach ($directory in @('staged', 'backup', 'verified')) { [void][IO.Directory]::CreateDirectory((Join-Path $script:ReleaseState.WorkDir $directory)) }
    $selection = @()
    foreach ($name in $script:ReleaseState.Selected) {
        $item = Get-ReleaseSourceFile $script:ReleaseState.SourceDir $name
        if (-not $item) { throw ('源文件状态变化：' + $name) }
        $staged = Join-Path (Join-Path $script:ReleaseState.WorkDir 'staged') $name
        [IO.File]::Copy($item.FullName, $staged, $false)
        $old = @($script:ReleaseState.Plan.Assets | Where-Object { $_.name -ceq $name })
        if ($old.Count -ne 1) { throw ('远端不存在唯一同名附件：' + $name) }
        $selection += [pscustomobject]@{ name = $name; old = $old[0]; source = $item.FullName; new_sha256 = Get-ReleaseSha256 $staged; new_size = (Get-Item -LiteralPath $staged).Length }
    }
    $script:ReleaseState.Selection = $selection
    $script:ReleaseState.ExpectedAssets = @($script:ReleaseState.Plan.Assets)
    Save-ReleaseJson @($selection) (Join-Path $script:ReleaseState.WorkDir 'selection.json')
    Save-ReleaseJson @($script:ReleaseState.ExpectedAssets) (Join-Path $script:ReleaseState.WorkDir 'expected-live.assets.json')
    Write-ReleaseLog ('➤ 替换目标｜GitHub｜https://github.com/' + $script:ReleaseState.Repository + '/releases/tag/' + $script:ReleaseState.Tag)
    Write-ReleaseLog ('➤ 本地来源｜' + $script:ReleaseState.SourceDir)
    foreach ($entry in $selection) { Write-ReleaseLog ('  {0}｜旧 {1} 字节 → 新 {2} 字节｜SHA256 {3}' -f $entry.name, $entry.old.size, $entry.new_size, $entry.new_sha256) }
}
# 按资产 ID 下载到二进制文件，不使用 PowerShell 文本重定向。
function Receive-ReleaseAsset {
    param([object]$Asset, [string]$Destination)
    $endpoint = 'repos/' + $script:ReleaseState.Repository + '/releases/assets/' + $Asset.id
    Write-ReleaseLog ('➤ 下载来源｜GitHub｜https://api.github.com/' + $endpoint)
    Write-ReleaseLog ('➤ 下载位置｜' + $Destination)
    [void](Invoke-ReleaseProcess 'gh' @('api', '--hostname', 'github.com', '--method', 'GET', '--header', 'Accept: application/octet-stream', $endpoint) -OutputFile $Destination)
    if ((Get-Item -LiteralPath $Destination).Length -ne $Asset.size) { throw ('下载大小不一致：' + $Destination) }
    if ($Asset.digest -and [string]$Asset.digest -cne ('sha256:' + (Get-ReleaseSha256 $Destination))) { throw ('下载摘要不一致或摘要格式不支持：' + $Destination) }
}
# 引用 PowerShell 字面参数供手动恢复时审查执行。
function ConvertTo-ReleaseLiteral {
    param([string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}
# 备份并校验所有旧附件，生成需要人工审查的恢复命令。
function Backup-ReleaseAssets {
    $restore = @('手动恢复前先核对远端当前内容，避免覆盖其他人的后续更新。', '以下命令删除同名附件后上传备份，不能恢复原 ID 和下载计数；不是原子操作。', ('目标：https://github.com/' + $script:ReleaseState.Repository + '/releases/tag/' + $script:ReleaseState.Tag), ('Set-Location -LiteralPath ' + (ConvertTo-ReleaseLiteral $script:ReleaseState.WorkDir)), '')
    $restorePath = Join-Path $script:ReleaseState.WorkDir 'RESTORE.txt'
    [IO.File]::WriteAllLines($restorePath, $restore, $script:ReleaseState.Utf8)
    foreach ($entry in $script:ReleaseState.Selection) {
        $destination = Join-Path (Join-Path $script:ReleaseState.WorkDir 'backup') $entry.name
        Receive-ReleaseAsset $entry.old $destination
        $digest = Get-ReleaseSha256 $destination
        [IO.File]::AppendAllText((Join-Path $script:ReleaseState.WorkDir 'backup.sha256'), ($digest + '  ' + $entry.name + [Environment]::NewLine), $script:ReleaseState.Utf8)
        $label = [string]$entry.old.label
        if ($label -match '\p{Cc}') { throw '旧附件标签含控制字符，无法安全生成恢复命令。' }
        $spec = './backup/' + $entry.name
        if ($label) { $spec += '#' + $label }
        $command = 'gh release upload --repo ' + (ConvertTo-ReleaseLiteral $script:ReleaseState.Repository) + ' --clobber -- ' + (ConvertTo-ReleaseLiteral $script:ReleaseState.Tag) + ' ' + (ConvertTo-ReleaseLiteral $spec)
        [IO.File]::AppendAllText($restorePath, $command + [Environment]::NewLine, $script:ReleaseState.Utf8)
        Write-ReleaseLog ('✔ 已备份并校验：' + $entry.name)
    }
}
# 构造不含上传时间戳的 Release 固定字段。
function Get-ReleaseCanonicalMetadata {
    param([object]$Release)
    $value = [ordered]@{}
    foreach ($field in @('id', 'tag_name', 'target_commitish', 'name', 'body', 'draft', 'prerelease', 'immutable', 'published_at')) { $value[$field] = $Release.$field }
    return ConvertTo-Json -InputObject $value -Depth 10 -Compress
}
# 对附件按名称做序数排序并保留并发保护字段，忽略下载计数。
function Get-ReleaseCanonicalAssets {
    param([object[]]$Assets)
    $map = New-Object 'Collections.Generic.SortedDictionary[string,object]' ([StringComparer]::Ordinal)
    foreach ($asset in $Assets) {
        $value = [ordered]@{}
        foreach ($field in @('id', 'name', 'size', 'digest', 'state', 'label', 'content_type')) { $value[$field] = $asset.$field }
        $map.Add($asset.name, $value)
    }
    return ConvertTo-Json -InputObject @($map.Values) -Depth 10 -Compress
}
# 比较完整快照和 Tag 提交，避免覆盖并发变更。
function Test-ReleaseSnapshotUnchanged {
    param([object[]]$ExpectedAssets, [string]$Prefix)
    $current = Get-ReleaseSnapshot (Join-Path $script:ReleaseState.WorkDir $Prefix)
    if ((Get-ReleaseCanonicalMetadata $current.Release) -cne (Get-ReleaseCanonicalMetadata $script:ReleaseState.Plan.Release)) { throw 'Release 元信息发生变化，已停止。' }
    if ((Get-ReleaseCanonicalAssets $current.Assets) -cne (Get-ReleaseCanonicalAssets $ExpectedAssets)) { throw '附件快照发生并发变化，已停止后续覆盖。' }
    if ((Resolve-ReleaseTagCommit) -cne $script:ReleaseState.TagSha) { throw 'Tag 提交在执行期间发生变化。' }
}
# 在最终精确 YES 后再复检远端；其它输入安全取消。
function Confirm-ReleaseReplacement {
    Write-ReleaseLog ('⚠ 即将覆盖 {0} / {1} 的 {2} 个同名附件。' -f $script:ReleaseState.Repository, $script:ReleaseState.Tag, $script:ReleaseState.Selection.Count)
    Write-ReleaseLog '⚠ 按已备份 ID 删除旧附件再上传；失败可能只完成一部分，不自动回滚或重试。'
    Write-ReleaseLog ('➤ 备份与恢复说明：' + $script:ReleaseState.WorkDir)
    $answer = Read-ReleaseInput '精确输入 YES 后回车执行；其它输入取消'
    if ($answer -cne 'YES') { Write-ReleaseLog 'ℹ 已取消覆盖；远端未修改，备份保留。'; return $false }
    Test-ReleaseSnapshotUnchanged $script:ReleaseState.Plan.Assets 'confirmed'
    return $true
}
# 用固定大小缓冲区逐字节比较，适用于大附件。
function Test-ReleaseBinaryEqual {
    param([string]$Left, [string]$Right)
    $first = [IO.File]::OpenRead($Left)
    $second = [IO.File]::OpenRead($Right)
    try {
        if ($first.Length -ne $second.Length) { return $false }
        $a = New-Object byte[] 65536
        $b = New-Object byte[] 65536
        while (($count = $first.Read($a, 0, $a.Length)) -gt 0) {
            $offset = 0
            while ($offset -lt $count) { $read = $second.Read($b, $offset, $count - $offset); if ($read -eq 0) { return $false }; $offset += $read }
            if (-not [Linq.Enumerable]::SequenceEqual([byte[]]$a, [byte[]]$b)) { return $false }
        }
        return $true
    } finally { $first.Dispose(); $second.Dispose() }
}
# 逐个精确删除已批准 ID、上传并按新 ID 下载核验，失败不盲目重放。
function Replace-ReleaseAssets {
    foreach ($entry in $script:ReleaseState.Selection) {
        Test-ReleaseSnapshotUnchanged $script:ReleaseState.ExpectedAssets ('live-' + $script:ReleaseState.Completed)
        $staged = Join-Path (Join-Path $script:ReleaseState.WorkDir 'staged') $entry.name
        if ((Get-ReleaseSha256 $staged) -cne $entry.new_sha256) { throw ('暂存文件已变化：' + $entry.name) }
        $label = [string]$entry.old.label
        $spec = './' + $entry.name
        if ($label) { $spec += '#' + $label }
        Write-ReleaseLog ('➤ 上传来源｜' + $staged)
        Write-ReleaseLog ('➤ 上传目标｜https://github.com/' + $script:ReleaseState.Repository + '/releases/tag/' + $script:ReleaseState.Tag)
        $script:ReleaseState.UploadStarted = $true
        [void](Invoke-ReleaseProcess 'gh' @('api', '--hostname', 'github.com', '--method', 'DELETE', ('repos/' + $script:ReleaseState.Repository + '/releases/assets/' + $entry.old.id)))
        [void](Invoke-ReleaseProcess 'gh' @('release', 'upload', '--repo', $script:ReleaseState.Repository, '--', $script:ReleaseState.Tag, $spec) -WorkingDirectory (Join-Path $script:ReleaseState.WorkDir 'staged'))
        $snapshot = Get-ReleaseSnapshot (Join-Path $script:ReleaseState.WorkDir ('after-' + ($script:ReleaseState.Completed + 1)))
        $found = @($snapshot.Assets | Where-Object { $_.name -ceq $entry.name })
        if ($found.Count -ne 1 -or $found[0].id -eq $entry.old.id) { throw ('上传后未找到唯一的新同名附件：' + $entry.name) }
        $newAsset = $found[0]
        $downloaded = Join-Path (Join-Path $script:ReleaseState.WorkDir 'verified') $entry.name
        Receive-ReleaseAsset $newAsset $downloaded
        if (-not (Test-ReleaseBinaryEqual $staged $downloaded) -or (Get-ReleaseSha256 $downloaded) -cne $entry.new_sha256) { throw ('上传后内容核验失败：' + $entry.name) }
        if ([string]$newAsset.label -cne $label) { throw ('附件显示标签未保留：' + $entry.name) }
        $script:ReleaseState.ExpectedAssets = @($script:ReleaseState.ExpectedAssets | ForEach-Object { if ($_.name -ceq $entry.name) { $newAsset } else { $_ } })
        Save-ReleaseJson @($script:ReleaseState.ExpectedAssets) (Join-Path $script:ReleaseState.WorkDir 'expected-live.assets.json')
        $script:ReleaseState.Completed++
        [IO.File]::AppendAllText((Join-Path $script:ReleaseState.WorkDir 'completed.txt'), ("{0}`t{1}`t{2}" -f $entry.name, $newAsset.id, $entry.new_sha256) + [Environment]::NewLine, $script:ReleaseState.Utf8)
        Write-ReleaseLog ('✔ 已替换并下载校验：' + $entry.name + '｜SHA256 ' + $entry.new_sha256)
    }
}
# 最终核对包含已替换附件在内的完整状态及固定 Tag 提交。
function Complete-ReleaseVerification {
    Test-ReleaseSnapshotUnchanged $script:ReleaseState.ExpectedAssets 'final'
    Write-ReleaseLog ('✔ 完成：{0}/{1} 个附件已替换并下载核验；其它附件、Release 元信息及 Tag 提交保持不变。' -f $script:ReleaseState.Completed, $script:ReleaseState.Selection.Count)
    Write-ReleaseLog ('➤ 查看：https://github.com/' + $script:ReleaseState.Repository + '/releases/tag/' + $script:ReleaseState.Tag)
    Write-ReleaseLog ('➤ 日志、备份及 RESTORE.txt：' + $script:ReleaseState.WorkDir)
    Write-ReleaseLog 'ℹ 临时目录可能被系统清理，需要长期保存时请自行复制本轮完整材料。'
}
# 编排交互、环境检查、计划备份、精确确认和替换验证，并恢复进程环境。
function Main {
    param([string[]]$Arguments)
    $savedPreference = $ErrorActionPreference
    $savedEnvironment = @{}
    foreach ($name in @('GH_HOST', 'GH_PAGER', 'GH_PROMPT_DISABLED')) { $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
    try {
        $ErrorActionPreference = 'Stop'
        if (-not (Show-ReleaseIntro $Arguments)) { return 0 }
        Initialize-ReleaseRuntime
        Read-ReleaseArguments $Arguments
        Test-ReleaseEnvironment
        Find-ReleaseRepositories
        if (-not (Read-ReleasePlan)) { return 0 }
        Save-ReleasePlan
        Backup-ReleaseAssets
        Test-ReleaseSnapshotUnchanged $script:ReleaseState.Plan.Assets 'before-upload'
        if (-not (Confirm-ReleaseReplacement)) { return 0 }
        Replace-ReleaseAssets
        Complete-ReleaseVerification
        return 0
    } catch {
        Write-ReleaseLog ('✖ ' + $_.Exception.Message)
        if ($script:ReleaseState) {
            if ($script:ReleaseState.UploadStarted) { Write-ReleaseLog ('⚠ 已校验 {0}/{1} 个附件；失败附件可能已经删除或上传，请先核对远端再审查 RESTORE.txt。' -f $script:ReleaseState.Completed, $script:ReleaseState.Selection.Count) }
            Write-ReleaseLog ('➤ 本次材料保留：' + $script:ReleaseState.WorkDir)
        }
        return 1
    } finally {
        foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process') }
        $ErrorActionPreference = $savedPreference
    }
}

exit (Main -Arguments @($args))
