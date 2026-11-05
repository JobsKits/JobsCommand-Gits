# GitTools.psm1 | JobsCommand@Gits
# Created by Jobs on 2026年10月23日，星期五.
# 共享原生 Windows Git 实现；不在导入时执行业务。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:LogFile = $null
$script:DryRun = $false
$script:SshAuthenticatedAccount = ''
$script:SkippedDirectories = @('.git','node_modules','Pods','.dart_tool','build','DerivedData')
# 日志只收集业务结果，不记录认证信息和私钥。
function Write-JobsLog {
    param([string]$Message)
    $safe = $Message -replace '(https?://)[^/@\s]+@','$1***@' -replace '(https?://[^\s?#]+)[?#][^\s]*','$1?[redacted]'
    Write-Host $safe
    if ($script:LogFile) { [IO.File]::AppendAllText($script:LogFile,$safe+[Environment]::NewLine,(New-Object Text.UTF8Encoding($false))) }
}
# 外部命令失败立即停止；不拼接命令字符串，也不通过 Invoke-Expression 执行输入。
function Invoke-JobsNative {
    param([string]$Program,[string[]]$Arguments,[switch]$AllowFailure,[switch]$Quiet)
    $command=Get-Command $Program -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $oldPreference=$ErrorActionPreference
    $oldConsoleEncoding=[Console]::OutputEncoding
    try {
        # Git 的路径输出为 UTF-8，不能按终端当前代码页解码。
        [Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
        $ErrorActionPreference='Continue'
        $global:LASTEXITCODE=0
        $output=@(& $command.Source @Arguments 2>&1 | ForEach-Object { $_.ToString() })
        $result=$LASTEXITCODE
    } finally {
        [Console]::OutputEncoding=$oldConsoleEncoding
        $ErrorActionPreference=$oldPreference
    }
    if (-not $Quiet) { foreach ($line in $output) { Write-JobsLog $line } }
    if ($result -ne 0 -and -not $AllowFailure) { throw "$Program 执行失败（$result），已停止；详情见日志。" }
    return @{Code=$result;Lines=$output;Text=($output -join "`n")}
}
# 每条 Git 命令只在自身进程使用 Gitee HTTPS 兼容规则。
function Invoke-JobsGit {
    param([string]$Repository,[string[]]$Arguments,[switch]$AllowFailure,[switch]$Quiet)
    $prefix=@('--literal-pathspecs','-c','core.quotepath=false','-c','color.ui=false','-c','url.https://gitee.com/.insteadOf=git@gitee.com:','-c','url.https://gitee.com/.insteadOf=ssh://git@gitee.com/','-c','url.https://gitee.com/.insteadOf=ssh://git@gitee.com:22/')
    if ($Repository) { $prefix+=@('-C',$Repository) }
    return Invoke-JobsNative 'git' ($prefix+$Arguments) -AllowFailure:$AllowFailure -Quiet:$Quiet
}
# 读取单值配置；缺项保持为空，不吞掉其它错误。
function Get-JobsConfig {
    param([string]$Repository,[string]$Key,[string]$File)
    $arguments=@('config')
    if ($File) { $arguments+=@('--file',$File) }
    $answer=Invoke-JobsGit $Repository ($arguments+@('--get',$Key)) -AllowFailure -Quiet
    if ($answer.Code -eq 1) { return '' }
    if ($answer.Code -ne 0) { throw "读取配置失败：$Key" }
    return $answer.Text
}
# 仅解析普通真实目录，拒绝重解析点，避免目录遍历越界。
function Resolve-JobsDirectory {
    param([string]$Path)
    $value=$Path.Trim().Trim('"')
    $item=Get-Item -LiteralPath $value -Force -ErrorAction Stop
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "不是普通目录：$value" }
    $ancestor=$item.Parent
    while ($null -ne $ancestor) {
        if ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "上层目录含重解析点：$value" }
        $ancestor=$ancestor.Parent
    }
    return $item.FullName
}
# 子模块路径只接受安全相对路径，并逐段拒绝链接与 Windows 保留名。
function Resolve-JobsChildPath {
    param([string]$Parent,[string]$Relative)
    if ([IO.Path]::IsPathRooted($Relative) -or $Relative -match '[\x00-\x1f:<>|?*]' -or $Relative -match '(^|[\\/])(\.|\.\.|\.git|)([\\/]|$)') { throw "不安全子模块路径：$Relative" }
    $parts=@($Relative -split '[\\/]')
    $current=$Parent
    foreach ($part in $parts) {
        if ($part -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$' -or $part -match '[. ]$') { throw "Windows 不支持此路径：$Relative" }
        $current=Join-Path $current $part
        if (Test-Path -LiteralPath $current) {
            $item=Get-Item -LiteralPath $current -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "路径含重解析点：$current" }
            if ($current -ne (Join-Path $Parent ($parts -join [IO.Path]::DirectorySeparatorChar)) -and (Test-Path -LiteralPath (Join-Path $current '.git'))) { throw '子模块路径跨过另一个 Git 仓库。' }
        }
    }
    return $current
}
# 命令行传入路径优先；默认从入口所在 Git 工作树定位。
function Get-JobsRepository {
    param([string]$Path,[string]$EntryDirectory)
    if (-not $Path) { $Path=Read-Host "目标 Git 仓库目录（回车使用入口所属仓库 $EntryDirectory）" }
    if (-not $Path) { $Path=$EntryDirectory }
    $directory=Resolve-JobsDirectory $Path
    $result=Invoke-JobsGit $directory @('rev-parse','--show-toplevel') -Quiet
    return Resolve-JobsDirectory $result.Text
}
# 显式确认任何会丢弃、覆盖、提交、创建远端或改变配置的操作。
function Confirm-JobsYes {
    param([string]$Message)
    Write-JobsLog "风险：$Message"
    if ([Console]::IsInputRedirected) { throw '没有可交互终端，已停止。' }
    if ((Read-Host '仅输入精确大写 YES 执行，其它取消') -cne 'YES') { throw '用户已取消，未执行此步骤。' }
}
# 编号选择避免依赖 fzf，空输入取首项，0 取消。
function Select-JobsItem {
    param([string]$Title,[object[]]$Items)
    if ($Items.Count -eq 0) { throw "$Title：没有候选项。" }
    Write-JobsLog $Title
    for ($i=0;$i -lt $Items.Count;$i++) { Write-JobsLog (('{0}、{1}' -f ($i+1),$Items[$i])) }
    $choice=Read-Host '输入编号（回车 1，0 取消）'
    if ($choice -eq '') { $choice='1' }
    $number=0
    if (-not [int]::TryParse($choice,[ref]$number) -or $number -lt 1 -or $number -gt $Items.Count) { throw '选择已取消或编号无效。' }
    return $Items[$number-1]
}
# 多选同步使用逗号分隔编号，拒绝不完整或越界输入。
function Select-JobsMultipleItems {
    param([string]$Title,[object[]]$Items)
    if ($Items.Count -eq 0) { throw "$Title：没有候选项。" }
    Write-JobsLog $Title
    for ($i=0;$i -lt $Items.Count;$i++) { Write-JobsLog (('{0}、{1}' -f ($i+1),$Items[$i])) }
    $answer=Read-Host '输入逗号分隔编号（例如 1,3）；回车或 0 取消'
    if (-not $answer -or $answer -eq '0') { throw '已取消多选。' }
    $selected=@()
    foreach ($part in ($answer -split ',')) {
        $number=0
        if (-not [int]::TryParse($part.Trim(),[ref]$number) -or $number -lt 1 -or $number -gt $Items.Count) { throw '多选编号无效。' }
        if ($Items[$number-1] -notin $selected) { $selected+=$Items[$number-1] }
    }
    return $selected
}
# 扫描包含 .git 目录或文件的工作树，跳过依赖、产物和链接。
function Get-JobsRepositories {
    param([string]$Root)
    $queue=New-Object 'Collections.Generic.Queue[string]'
    $queue.Enqueue((Resolve-JobsDirectory $Root))
    while ($queue.Count -gt 0) {
        $folder=$queue.Dequeue()
        if (Test-Path -LiteralPath (Join-Path $folder '.git')) { $folder }
        foreach ($child in Get-ChildItem -LiteralPath $folder -Directory -Force) {
            if ($child.Name -notin $script:SkippedDirectories -and -not ($child.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $queue.Enqueue($child.FullName) }
        }
    }
}
# 读取登记保留 section、URL、branch 缺省与扩展字段。
function Get-JobsModules {
    param([string]$Repository)
    $file=Join-Path $Repository '.gitmodules'
    if (-not (Test-Path -LiteralPath $file)) { return }
    if ((Get-Item -LiteralPath $file -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw '.gitmodules 不能是链接。' }
    $keys=Invoke-JobsGit $Repository @('config','--file',$file,'--name-only','--get-regexp','^submodule\..*\.path$') -AllowFailure -Quiet
    if ($keys.Code -notin @(0,1)) { throw '.gitmodules 无法解析。' }
    $seen=@{}
    foreach ($key in $keys.Lines) {
        $section=$key.Substring(10,$key.Length-15)
        $path=Get-JobsConfig $Repository $key $file
        [void](Resolve-JobsChildPath $Repository $path)
        if ($seen.ContainsKey($path)) { throw "重复子模块路径：$path" }
        $seen[$path]=$true
        [pscustomobject]@{Section=$section;Path=$path;Url=(Get-JobsConfig $Repository "submodule.$section.url" $file);Branch=(Get-JobsConfig $Repository "submodule.$section.branch" $file)}
    }
}
# 解析 Git URL 的协议、端口及 namespace；本地 URL 保留明确地址。
function Split-JobsGitUrl {
    param([string]$Url)
    if ($Url -match '^(?<prefix>(?:https?|ssh|git)://[^/]+/)(?<path>[^?#]+)$' -or $Url -match '^(?<prefix>[^/@:]+@[^/:]+:)(?<path>[^?#]+)$') {
        $prefix=$Matches.prefix; $path=$Matches.path.TrimEnd('/')
        if ($path -match '(^|/)\.\.?(/|$)' -or $path -match '\s') { throw 'URL 路径非法。' }
        return @{Prefix=$prefix;Path=$path;Namespace=($path -replace '/[^/]+$','');Name=($path -replace '^.*/','')}
    }
    return $null
}
# 相对 URL 使用父仓远端的目录语义，保留任意主机与端口。
function Resolve-JobsGitUrl {
    param([string]$ParentUrl,[string]$Url)
    if ($Url -notmatch '^\.\.?/') { return $Url }
    $parent=Split-JobsGitUrl $ParentUrl
    if (-not $parent) {
        if ([IO.Path]::IsPathRooted($ParentUrl)) { return [IO.Path]::GetFullPath((Join-Path $ParentUrl $Url)) }
        throw "不能解析相对地址：$ParentUrl"
    }
    $stack=New-Object 'Collections.Generic.List[string]'
    foreach ($part in (($parent.Path+'/'+$Url) -split '/')) {
        if ($part -eq '.' -or $part -eq '') { continue }
        if ($part -eq '..') { if ($stack.Count -eq 0) { throw '相对 URL 越界。' }; $stack.RemoveAt($stack.Count-1) } else { $stack.Add($part) }
    }
    return $parent.Prefix+($stack -join '/')
}
# 全部父子线路可以逐一证明同 namespace 与同仓名才写共享相对地址。
function Get-JobsRegistrationUrl {
    param([string]$Parent,[string]$Child,[string]$Origin)
    $parentRemotes=(Invoke-JobsGit $Parent @('remote') -Quiet).Lines
    $childRemotes=(Invoke-JobsGit $Child @('remote') -Quiet).Lines
    if ($parentRemotes.Count -eq 0) { return $Origin }
    $name=''
    foreach ($remote in $parentRemotes) {
        if ($remote -notin $childRemotes) { return $Origin }
        $p=Split-JobsGitUrl (Get-JobsConfig $Parent "remote.$remote.url")
        $c=Split-JobsGitUrl (Get-JobsConfig $Child "remote.$remote.url")
        if (-not $p -or -not $c -or $p.Prefix -cne $c.Prefix -or $p.Namespace -cne $c.Namespace) { return $Origin }
        if ($name -and $name -cne $c.Name) { return $Origin }; $name=$c.Name
    }
    return '../'+$name
}
# 关联变更前备份精确配置、索引和清单，保留恢复依据。
function Backup-JobsAssociation {
    param([string]$Repository)
    $gitDirectory=(Invoke-JobsGit $Repository @('rev-parse','--absolute-git-dir') -Quiet).Text
    $backup=Join-Path $gitDirectory ('jobs-submodule-backups/'+(Get-Date -Format 'yyyy.MM.dd HH-mm-ss')+'-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($backup)
    foreach ($name in @('index','config')) { $source=Join-Path $gitDirectory $name; if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination (Join-Path $backup $name) } }
    $modules=Join-Path $Repository '.gitmodules'
    if (Test-Path -LiteralPath $modules) { Copy-Item -LiteralPath $modules -Destination (Join-Path $backup 'gitmodules') }
    Write-JobsLog "关联备份：$backup"
    return $backup
}
# 记录确认前的磁盘指纹，写入前再次验证。
function Get-JobsAssociationFingerprint {
    param([string]$Repository)
    $gitDirectory=(Invoke-JobsGit $Repository @('rev-parse','--absolute-git-dir') -Quiet).Text
    $values=@()
    foreach ($file in @((Join-Path $gitDirectory 'index'),(Join-Path $gitDirectory 'config'),(Join-Path $Repository '.gitmodules'))) {
        if (Test-Path -LiteralPath $file) { $values+=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash } else { $values+='absent' }
    }
    return $values -join ':'
}
# 增量关联与磁盘对齐共用预检；普通登记保留旧指针和暂缺目录。
function Invoke-JobsAssociate {
    param([string]$Repository,[switch]$Align)
    $gitDirectory=(Invoke-JobsGit $Repository @('rev-parse','--absolute-git-dir') -Quiet).Text
    $common=(Invoke-JobsGit $Repository @('rev-parse','--git-common-dir') -Quiet).Text
    if (-not [IO.Path]::IsPathRooted($common)) { $common=Join-Path $Repository $common }
    if ([IO.Path]::GetFullPath($common) -ne [IO.Path]::GetFullPath($gitDirectory)) { throw '链接工作树不参与子模块归集。' }
    if ((Invoke-JobsGit $Repository @('ls-files','--unmerged') -Quiet).Text) { throw '父仓索引有冲突。' }
    $moduleDiff=Invoke-JobsGit $Repository @('diff','--quiet','--','.gitmodules') -AllowFailure -Quiet
    if ($moduleDiff.Code -ne 0) { throw '.gitmodules 有未暂存差异，请先处理暂存边界。' }
    $fingerprint=Get-JobsAssociationFingerprint $Repository
    $existing=@(Get-JobsModules $Repository)
    $paths=New-Object 'Collections.Generic.List[string]'
    foreach ($folder in Get-ChildItem -LiteralPath $Repository -Directory -Force) {
        if ($folder.Name -notin $script:SkippedDirectories -and -not ($folder.Attributes -band [IO.FileAttributes]::ReparsePoint) -and (Test-Path -LiteralPath (Join-Path $folder.FullName '.git'))) { $paths.Add($folder.Name) }
    }
    foreach ($module in $existing) { if ((Test-Path -LiteralPath (Join-Path (Resolve-JobsChildPath $Repository $module.Path) '.git')) -and $module.Path -notin $paths) { $paths.Add($module.Path) } }
    $plan=@()
    foreach ($path in $paths) {
        $child=Resolve-JobsChildPath $Repository $path
        $root=(Invoke-JobsGit $child @('rev-parse','--show-toplevel') -Quiet).Text
        if ([IO.Path]::GetFullPath($root) -ne [IO.Path]::GetFullPath($child)) { throw "不是独立子仓：$path" }
        $childGit=(Invoke-JobsGit $child @('rev-parse','--absolute-git-dir') -Quiet).Text
        $childCommon=(Invoke-JobsGit $child @('rev-parse','--git-common-dir') -Quiet).Text
        if (-not [IO.Path]::IsPathRooted($childCommon)) { $childCommon=Join-Path $child $childCommon }
        if ([IO.Path]::GetFullPath($childCommon) -ne [IO.Path]::GetFullPath($childGit)) { throw "子仓为链接工作树：$path" }
        $head=(Invoke-JobsGit $child @('rev-parse','--verify','HEAD^{commit}') -Quiet).Text
        $module=@($existing | Where-Object { $_.Path -eq $path })
        $isNew=$module.Count -eq 0
        if ($isNew) { $section=$path; $url=Get-JobsConfig $child 'remote.origin.url'; if (-not $url) { throw "子仓缺少 origin：$path" }; $url=Get-JobsRegistrationUrl $Repository $child $url }
        else { $section=$module[0].Section; $url=$module[0].Url; if (-not $url) { $url=Get-JobsConfig $child 'remote.origin.url' }; if (-not $url) { throw "子仓缺少 URL：$path" } }
        $target=Resolve-JobsChildPath (Join-Path $gitDirectory 'modules') $section
        if ([IO.Path]::GetFullPath($childGit) -ne [IO.Path]::GetFullPath($target)) {
            if (-not (Test-Path -LiteralPath (Join-Path $child '.git') -PathType Container)) { throw "子仓元数据在父仓之外：$path" }
            if (Test-Path -LiteralPath $target) { throw "元数据目标已存在，未覆盖：$target" }
        }
        $entries=(Invoke-JobsGit $Repository @('ls-files','--stage','--',$path) -Quiet).Lines
        if (@($entries | Where-Object { $_ -notmatch '^160000 [0-9a-f]+ 0\t' }).Count -gt 0) { throw "父仓以普通文件或冲突记录跟踪 $path，请先人工处理。" }
        $branch=(Invoke-JobsGit $child @('symbolic-ref','--quiet','--short','HEAD') -Quiet -AllowFailure).Text
        $plan+=[pscustomobject]@{Path=$path;Child=$child;Section=$section;Url=$url;Head=$head;New=$isNew;Branch=$branch;NeedLink=($entries.Count -eq 0 -or $Align)}
        Write-JobsLog "关联计划：$path；section=$section；URL=$url；登记当前指针=$($entries.Count -eq 0 -or $Align)"
    }
    $stale=@($existing | Where-Object { $_.Path -notin $paths })
    if ($Align) { foreach ($item in $stale) { Write-JobsLog "移除缺失关联与 gitlink：$($item.Path)（保留 Git 历史缓存）" } }
    if ($script:DryRun) { Write-JobsLog '只读计划：没有写入配置、索引或元数据。'; return }
    Confirm-JobsYes '按以上计划修改父仓 .gitmodules、索引和本地登记，并归集 Git 元数据；不提交、不推送。'
    if ((Get-JobsAssociationFingerprint $Repository) -cne $fingerprint) { throw '确认期间父仓配置或索引已变化。' }
    foreach ($item in $plan) { if ((Invoke-JobsGit $item.Child @('rev-parse','HEAD') -Quiet).Text -ne $item.Head) { throw '确认期间子仓 HEAD 已变化。' } }
    $lockPath=Join-Path $gitDirectory 'jobs-windows-associate.lock'
    $lock=[IO.File]::Open($lockPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {
        [void](Backup-JobsAssociation $Repository)
        $file=Join-Path $Repository '.gitmodules'
        if ($Align) {
            foreach ($item in $stale) {
                [void](Invoke-JobsGit $Repository @('config','--file',$file,'--remove-section',('submodule.'+$item.Section)))
                [void](Invoke-JobsGit $Repository @('update-index','--force-remove','--',$item.Path))
                $local=Get-JobsConfig $Repository ('submodule.'+$item.Section+'.url')
                if ($local) { [void](Invoke-JobsGit $Repository @('config','--local','--remove-section',('submodule.'+$item.Section))) }
            }
        }
        foreach ($item in $plan) {
            $prefix='submodule.'+$item.Section
            if ($item.New) { [void](Invoke-JobsGit $Repository @('config','--file',$file,($prefix+'.path'),$item.Path)); if ($item.Branch) { [void](Invoke-JobsGit $Repository @('config','--file',$file,($prefix+'.branch'),$item.Branch)) } }
            if (-not (Get-JobsConfig $Repository ($prefix+'.url') $file)) { [void](Invoke-JobsGit $Repository @('config','--file',$file,($prefix+'.url'),$item.Url)) }
            if ($item.NeedLink) { [void](Invoke-JobsGit $Repository @('update-index','--add','--cacheinfo',('160000,'+$item.Head+','+$item.Path))) }
        }
        if (Test-Path -LiteralPath $file) { [void](Invoke-JobsGit $Repository @('add','--','.gitmodules')) }
        foreach ($item in $plan) {
            [void](Invoke-JobsGit $Repository @('submodule','init','--',$item.Path))
            [void](Invoke-JobsGit $Repository @('submodule','absorbgitdirs','--',$item.Path))
            if ((Invoke-JobsGit $item.Child @('rev-parse','HEAD') -Quiet).Text -ne $item.Head) { throw '子仓 HEAD 意外变化。' }
            if (-not (Test-Path -LiteralPath (Join-Path $item.Child '.git') -PathType Leaf)) { throw '元数据归集核验失败。' }
        }
        Write-JobsLog '关联已完成，保留本地差异供审查。'
    } finally { $lock.Dispose(); [IO.File]::Delete($lockPath) }
}
# 只有明确配置有效过滤器才恢复和验证；未配置时不安装。
function Restore-JobsMarkdownToc {
    param([string]$Repository)
    $clean=Get-JobsConfig $Repository 'filter.jobs-markdown-toc.clean'
    $smudge=Get-JobsConfig $Repository 'filter.jobs-markdown-toc.smudge'
    if (-not $clean -and -not $smudge) { Write-JobsLog "无目录过滤器，跳过：$Repository"; return }
    if (-not $clean -or -not $smudge) { throw "目录过滤器不完整：$Repository" }
    $tool=Join-Path $Repository '.jobs-markdown-toc/MarkdownToc.mjs'
    if (-not (Test-Path -LiteralPath $tool)) { throw "目录工具缺失：$Repository" }
    Push-Location -LiteralPath $Repository
    try {
        [void](Invoke-JobsNative 'node' @($tool,'restore'))
        [void](Invoke-JobsNative 'node' @($tool,'verify'))
    } finally { Pop-Location }
}
# 同步前逐仓保护源码、暂存与未跟踪内容；YES 仅作用于当前仓。
function Assert-JobsClean {
    param([string]$Repository)
    while ($true) {
        $state=(Invoke-JobsGit $Repository @('status','--porcelain','--untracked-files=all','--ignore-submodules=all') -Quiet).Text
        if (-not $state) { return }
        Write-JobsLog "未提交仓库：$Repository`n$state"
        if ($script:DryRun) { throw '预览发现未提交内容，未修改。' }
        $answer=Read-Host '外部处理后回车复检；精确 YES 舍弃当前仓源码及未跟踪文件；其它取消'
        if ($answer -ceq 'YES') {
            [void](Invoke-JobsGit $Repository @('reset','--hard','--no-recurse-submodules','HEAD'))
            [void](Invoke-JobsGit $Repository @('clean','-fd'))
        } elseif ($answer -ne '') { throw '已取消；保留仓库状态。' }
    }
}
# 远端默认分支由服务器 HEAD 决定，不猜 main/master。
function Get-JobsRemoteBranch {
    param([string]$Repository,[string]$Url)
    $metadata=Invoke-JobsGit $Repository @('ls-remote','--symref',$Url,'HEAD') -Quiet
    foreach ($line in $metadata.Lines) { if ($line -match '^ref: refs/heads/(.+)\s+HEAD$') { return $Matches[1] } }
    throw "无法确定远端默认分支：$Url"
}
# 只允许已有历史快进；游离 HEAD 的独有提交也保留。
function Update-JobsBranch {
    param([string]$Repository,[string]$Url,[string]$Branch,[string]$Remote='origin')
    if ($Branch -notmatch '^\S+$' -or $Branch.StartsWith('-')) { throw '目标分支无效。' }
    if (-not $Url -or $Url.StartsWith('-') -or $Url -match '[\x00-\x1f]' -or $Url -match '^[A-Za-z][A-Za-z0-9+.-]*::') { throw '下载 URL 无效或使用外部协议助手。' }
    [void](Invoke-JobsGit $Repository @('check-ref-format',('refs/heads/'+$Branch)) -Quiet)
    Write-JobsLog "Git 来源｜拉取`n仓库：$Repository`n分支：$Branch`n来源：$Url"
    [void](Invoke-JobsGit $Repository @('fetch','--no-recurse-submodules','--no-tags',$Url,('+refs/heads/'+$Branch+':refs/remotes/'+$Remote+'/'+$Branch)))
    $target=(Invoke-JobsGit $Repository @('rev-parse',('refs/remotes/'+$Remote+'/'+$Branch+'^{commit}')) -Quiet).Text
    Assert-JobsClean $Repository
    $head=Invoke-JobsGit $Repository @('rev-parse','--verify','HEAD') -AllowFailure -Quiet
    if ($head.Code -eq 0) {
        $preserved=Invoke-JobsGit $Repository @('merge-base','--is-ancestor',$head.Text,$target) -AllowFailure -Quiet
        if ($preserved.Code -ne 0) { throw "本地或游离 HEAD 存在独有提交，保留并停止：$Repository" }
    }
    $local=Invoke-JobsGit $Repository @('show-ref','--verify','--quiet',('refs/heads/'+$Branch)) -AllowFailure -Quiet
    if ($local.Code -eq 0) {
        $advance=Invoke-JobsGit $Repository @('merge-base','--is-ancestor',('refs/heads/'+$Branch),$target) -AllowFailure -Quiet
        if ($advance.Code -ne 0) { throw "目标本地分支领先或分叉：$Repository" }
        [void](Invoke-JobsGit $Repository @('checkout','--no-recurse-submodules','--no-overwrite-ignore',$Branch))
        [void](Invoke-JobsGit $Repository @('-c',('branch.'+$Branch+'.mergeOptions='),'merge','--ff-only','--no-autostash','--no-overwrite-ignore','--no-edit',$target))
    } else { [void](Invoke-JobsGit $Repository @('checkout','--no-recurse-submodules','--no-overwrite-ignore','-b',$Branch,$target)) }
    [void](Invoke-JobsGit $Repository @('branch',('--set-upstream-to='+$Remote+'/'+$Branch),$Branch))
    Restore-JobsMarkdownToc $Repository
    Write-JobsLog "同步成功：$Branch → $target；来源：$Url"
}
# 逐层使用直接父仓的 URL、branch 和实际分支，始终恢复本地跟踪分支。
function Sync-JobsModules {
    param([string]$Repository,[string]$ParentUrl,[bool]$Recursive=$true,[string[]]$Selected=@())
    $parentBranch=(Invoke-JobsGit $Repository @('symbolic-ref','--quiet','--short','HEAD') -AllowFailure -Quiet).Text
    foreach ($module in @(Get-JobsModules $Repository)) {
        if ($Selected.Count -gt 0 -and $module.Path -notin $Selected) { continue }
        if (-not $module.Url) { throw "子模块 URL 缺失：$($module.Path)" }
        $entry=(Invoke-JobsGit $Repository @('ls-files','--stage','--',$module.Path) -Quiet).Text
        if ($entry -notmatch '^160000 [0-9a-f]+ 0\t[^\r\n]+$') { throw "子模块缺少唯一正常 gitlink，请先修复关联：$($module.Path)" }
        $child=Resolve-JobsChildPath $Repository $module.Path
        $url=Resolve-JobsGitUrl $ParentUrl $module.Url
        if (-not $url -or $url.StartsWith('-') -or $url -match '[\x00-\x1f]' -or $url -match '^[A-Za-z][A-Za-z0-9+.-]*::') { throw '子模块 URL 无效或使用外部协议助手。' }
        $branch=$module.Branch
        if ($branch -eq '.') { $branch=$parentBranch; if (-not $branch) { throw 'branch=. 需要直接父仓位于分支。' } }
        Write-JobsLog "Git 来源｜子仓`n对象：$($module.Path)`n来源：$url`n目标：$child"
        if ($script:DryRun) { Write-JobsLog "只读计划：分支=$branch；递归=$Recursive"; continue }
        if (-not $branch) { $branch=Get-JobsRemoteBranch $Repository $url }
        if (-not (Test-Path -LiteralPath (Join-Path $child '.git'))) {
            if ((Test-Path -LiteralPath $child) -and @(Get-ChildItem -LiteralPath $child -Force).Count -gt 0) { throw "未初始化目标非空：$child" }
            $gitDirectory=(Invoke-JobsGit $Repository @('rev-parse','--absolute-git-dir') -Quiet).Text
            $cache=Resolve-JobsChildPath (Join-Path $gitDirectory 'modules') $module.Section
            if (Test-Path -LiteralPath $cache) { throw "存在旧 Git 缓存，先核验和恢复其工作树，未覆盖：$cache" }
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $child))
            # no-checkout 让真实远端先写入配置，机器目录过滤器首次检出即可匹配。
            [void](Invoke-JobsGit '' @('clone','--no-checkout','--branch',$branch,'--',$url,$child))
            [void](Invoke-JobsGit $child @('checkout','--no-recurse-submodules','--no-overwrite-ignore',$branch))
            [void](Invoke-JobsGit $Repository @('submodule','init','--',$module.Path))
            [void](Invoke-JobsGit $Repository @('submodule','absorbgitdirs','--',$module.Path))
        }
        $actual=(Invoke-JobsGit $child @('rev-parse','--show-toplevel') -Quiet).Text
        if ([IO.Path]::GetFullPath($actual) -ne [IO.Path]::GetFullPath($child)) { throw '子仓路径不是独立 Git 根目录。' }
        Update-JobsBranch $child $url $branch
        if ($Recursive) { Sync-JobsModules $child $url $true }
    }
}
# 下载模式保留现有分支最新策略，维护模式可按清单、现有、选择或地址执行。
function Invoke-JobsDownload {
    param([string]$Repository,[bool]$Recursive=$true)
    $mode='只拉取已有登记（默认）'
    if (-not $script:DryRun) { $mode=Select-JobsItem '同步用途' @('只拉取已有登记（默认）','维护：配置清单全部','维护：目前已有的','维护：选择指定子模块','维护：添加一个地址') }
    $remote=Get-JobsConfig $Repository 'remote.origin.url'
    $branch=(Invoke-JobsGit $Repository @('symbolic-ref','--quiet','--short','HEAD') -AllowFailure -Quiet).Text
    if (-not $remote) { throw '入口仓缺少 origin，先配置明确远端。' }
    $selected=@()
    if ($mode -like '维护*') {
        if ($mode -like '*配置清单全部') {
            $names=@('JobsOCBaseConfigDemo','JobsSwiftBaseConfigDemo','JobsFlutterBaseConfigDemo')
            foreach ($name in $names) {
                if ($name -notin @(Get-JobsModules $Repository | ForEach-Object { $_.Path })) {
                    $url=Read-Host "请填写 $name 在当前父仓线路的真实完整 URL（不猜镜像地址）"
                    if (-not $url -or $url.StartsWith('-')) { throw 'URL 不能为空或以 - 开头。' }
                    Confirm-JobsYes "新增并下载 $name；来源：$url"
                    [void](Invoke-JobsGit $Repository @('submodule','add','--',$url,$name))
                }
            }
        } elseif ($mode -like '*添加一个地址') {
            $url=Read-Host '真实完整 Git URL'; $path=Read-Host '本地相对目录'
            [void](Resolve-JobsChildPath $Repository $path)
            if (-not $url -or $url.StartsWith('-')) { throw 'URL 无效。' }
            Confirm-JobsYes "新增并下载：$url → $path"
            [void](Invoke-JobsGit $Repository @('submodule','add','--',$url,$path)); $selected=@($path)
        } elseif ($mode -like '*目前已有的') {
            $selected=@(Get-JobsModules $Repository | Where-Object { Test-Path -LiteralPath (Join-Path (Join-Path $Repository $_.Path) '.git') } | ForEach-Object { $_.Path })
            if ($selected.Count -eq 0) { Write-JobsLog '没有已初始化子仓，无需更新。'; return }
        } else { $selected=@(Select-JobsMultipleItems '选择子模块（可多选）' @(Get-JobsModules $Repository | ForEach-Object { $_.Path })) }
        $depth=Read-Host '回车向下递归；输入 1 仅直属'; if ($depth -eq '1') { $Recursive=$false }
    } elseif (-not $script:DryRun) {
        if ($branch) {
            $upstream=Get-JobsConfig $Repository ('branch.'+$branch+'.remote')
            $merge=Get-JobsConfig $Repository ('branch.'+$branch+'.merge')
            if (-not $upstream -or $upstream -eq '.' -or $merge -notmatch '^refs/heads/(.+)$') { throw '当前入口分支需要明确远程上游。' }
            $remote=Get-JobsConfig $Repository ('remote.'+$upstream+'.url')
            Update-JobsBranch $Repository $remote $Matches[1] $upstream
        } else {
            $targetBranch=''
            $super=(Invoke-JobsGit $Repository @('rev-parse','--show-superproject-working-tree') -AllowFailure -Quiet).Text
            if ($super) {
                foreach ($module in @(Get-JobsModules $super)) {
                    $path=Resolve-JobsChildPath $super $module.Path
                    if ([IO.Path]::GetFullPath($path) -eq [IO.Path]::GetFullPath($Repository)) { $targetBranch=$module.Branch; break }
                }
                if ($targetBranch -eq '.') {
                    $targetBranch=(Invoke-JobsGit $super @('symbolic-ref','--quiet','--short','HEAD') -Quiet).Text
                    if (-not $targetBranch) { throw '入口 branch=. 要求直接父仓位于明确分支。' }
                }
            }
            if (-not $targetBranch) { $targetBranch=Get-JobsRemoteBranch $Repository $remote }
            Update-JobsBranch $Repository $remote $targetBranch
        }
    }
    Sync-JobsModules $Repository $remote $Recursive $selected
    Write-JobsLog '同步完成；子仓保持本地跟踪分支，gitlink 差异留待审查，未提交或推送。'
}
# 回退菜单支持上一提交、tag 与 reflog；执行前保留恢复分支。
function Invoke-JobsReset {
    param([string]$Repository)
    if ((Invoke-JobsGit $Repository @('diff','--cached','--name-only') -Quiet).Text) { throw '暂存区有改动，请先处理后回退。' }
    $choice=Select-JobsItem '回退来源' @('上一提交','tag','reflog')
    $target='HEAD^'
    if ($choice -eq 'tag') { $target=Select-JobsItem '选择 tag' @((Invoke-JobsGit $Repository @('tag','--sort=-version:refname') -Quiet).Lines) }
    if ($choice -eq 'reflog') { $line=Select-JobsItem '选择 reflog' @((Invoke-JobsGit $Repository @('reflog','--format=%H %gs','-n','100') -Quiet).Lines); $target=($line -split ' ')[0] }
    $sha=(Invoke-JobsGit $Repository @('rev-parse','--verify',($target+'^{commit}')) -Quiet).Text
    $mode=Select-JobsItem '回退方式' @('soft（保留工作区和索引）','hard（丢弃工作区和索引）')
    Confirm-JobsYes "回退到 $sha；模式 $mode"
    $backup='jobs-before-reset-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
    [void](Invoke-JobsGit $Repository @('branch',$backup,'HEAD'))
    $flag='--soft'; if ($mode -like 'hard*') { $flag='--hard' }
    [void](Invoke-JobsGit $Repository @('reset',$flag,$sha))
    Write-JobsLog "原提交恢复分支：$backup；hard 不能靠分支恢复未提交文件。"
}
# 悬空对象恢复为分支或二进制文件，不直接合并所有对象造成连续冲突。
function Invoke-JobsRecover {
    param([string]$Repository)
    $objects=(Invoke-JobsGit $Repository @('fsck','--full','--no-reflogs','--unreachable') -Quiet).Lines
    $candidates=@($objects | Where-Object { $_ -match '^(dangling|unreachable) (commit|tree|blob) [0-9a-f]+$' })
    if ($candidates.Count -eq 0) { Write-JobsLog '未找到可恢复的悬空对象。'; return }
    $selected=Select-JobsItem '选择恢复对象' $candidates
    $parts=$selected -split ' '; $kind=$parts[1]; $sha=$parts[2]
    Confirm-JobsYes "恢复 $kind $sha 为新分支或 recovered 文件；不覆盖原文件、不自动合并。"
    if ($kind -in @('commit','tree')) {
        if ($kind -eq 'tree') { $sha=(Invoke-JobsGit $Repository @('commit-tree',$sha,'-m',('恢复 tree '+$sha)) -Quiet).Text }
        $name='recovered-'+$kind+'-'+$sha.Substring(0,12)
        [void](Invoke-JobsGit $Repository @('branch',$name,$sha)); Write-JobsLog "恢复分支：$name，可自行检查后合并。"
    } else {
        $folder=Join-Path $Repository 'recovered/blobs'; [void][IO.Directory]::CreateDirectory($folder)
        $file=Join-Path $folder ($sha+'.bin')
        if (Test-Path -LiteralPath $file) { throw "目标已存在：$file" }
        # cmd 原生重定向可能破坏路径；使用进程输出字节流保留原始 blob。
        $start=New-Object Diagnostics.ProcessStartInfo
        $start.FileName=(Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
        $start.WorkingDirectory=$Repository; $start.Arguments='cat-file blob '+$sha; $start.UseShellExecute=$false; $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
        $process=[Diagnostics.Process]::Start($start); $stream=[IO.File]::Open($file,[IO.FileMode]::CreateNew)
        try { $process.StandardOutput.BaseStream.CopyTo($stream); $errors=$process.StandardError.ReadToEnd(); $process.WaitForExit(); if ($process.ExitCode -ne 0) { throw $errors } }
        finally { $stream.Dispose(); $process.Dispose() }
        Write-JobsLog "二进制对象已恢复：$file"
    }
}
# 批量提交按后代先父仓顺序，明确确认后才 add/commit，失败即停。
function Invoke-JobsBatchCommit {
    param([string]$Root)
    $repositories=@(Get-JobsRepositories $Root | Sort-Object Length -Descending)
    foreach ($repository in $repositories) { Write-JobsLog "提交范围：$repository" }
    if ($script:DryRun) { return }
    Confirm-JobsYes '批量暂存并提交以上仓库全部改动；不执行推送。'
    $message=Read-Host '提交说明（回车使用时间）'; if (-not $message) { $message='自动提交：'+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') }
    foreach ($repository in $repositories) {
        if ((Invoke-JobsGit $repository @('status','--porcelain') -Quiet).Text) { [void](Invoke-JobsGit $repository @('add','--all')); [void](Invoke-JobsGit $repository @('commit','-m',$message)) }
        else { Write-JobsLog "无改动，跳过：$repository" }
    }
}
# 提交关键词按字面量匹配，展示选择提交详情。
function Invoke-JobsSearch {
    param([string]$Repository)
    $keyword=Read-Host '提交说明关键词'; if (-not $keyword) { throw '关键词不能为空。' }
    $items=@((Invoke-JobsGit $Repository @('log','--all','--fixed-strings',('--grep='+$keyword),'--format=%H %ad %s','--date=short') -Quiet).Lines)
    if ($items.Count -eq 0) { Write-JobsLog '没有匹配提交。'; return }
    $item=Select-JobsItem '选择提交' $items
    [void](Invoke-JobsGit $Repository @('show','--stat','--format=fuller',($item -split ' ')[0],'--'))
}
# 分支交点优先 fork-point，失败采用所有最近共同祖先。
function Invoke-JobsForkPoint {
    param([string]$Repository)
    $branches=@((Invoke-JobsGit $Repository @('for-each-ref','--format=%(refname)','refs/heads','refs/remotes') -Quiet).Lines)
    $left=Select-JobsItem '基线分支' $branches; $right=Select-JobsItem '目标分支' $branches
    $point=Invoke-JobsGit $Repository @('merge-base','--fork-point',$left,$right) -AllowFailure -Quiet
    if ($point.Code -ne 0) { $point=Invoke-JobsGit $Repository @('merge-base','--all',$left,$right) -Quiet }
    foreach ($sha in $point.Lines) { [void](Invoke-JobsGit $Repository @('show','--no-patch','--format=fuller',$sha)) }
}
# 从已登记子树移除运行态索引记录，同时保留真实文件。
function Invoke-JobsRuntimeCleanup {
    param([string]$Repository)
    $repositories=@($Repository)
    foreach ($module in @(Get-JobsModules $Repository)) { $child=Resolve-JobsChildPath $Repository $module.Path; if (Test-Path -LiteralPath (Join-Path $child '.git')) { $repositories+=$child } }
    $patterns=@('codex配置文件夹/','**/.codex/sessions/','**/.codex/.tmp/','**/plugins/cache/','**/tmp/arg0/','**/shell_snapshots/','**/session_index.jsonl','**/state_*.sqlite','**/state_*.sqlite-*','**/.codex/logs*.sqlite','**/.codex/logs*.sqlite-*')
    $plans=@()
    foreach ($repo in $repositories) {
        $files=@((Invoke-JobsGit $repo @('ls-files','-z') -Quiet).Text -split "`0" | Where-Object { $_ -match '(^|/)(codex配置文件夹|\.codex/(sessions|\.tmp)|plugins/cache|tmp/arg0|shell_snapshots)(/|$)|(^|/)(session_index\.jsonl|state_.*\.sqlite(?:-.*)?|logs.*\.sqlite(?:-.*)?)$' })
        $plans+=@{Repo=$repo;Files=$files}; Write-JobsLog "运行态计划：$repo；移除索引 $($files.Count) 项，真实文件保留。"
    }
    if ($script:DryRun) { return }
    Confirm-JobsYes '写入忽略规则，并从以上仓库索引移除匹配运行态文件；不提交、不删除文件。'
    foreach ($plan in $plans) {
        [void](Backup-JobsAssociation $plan.Repo)
        $ignore=Join-Path $plan.Repo '.gitignore'; $current=''; if (Test-Path -LiteralPath $ignore) { $current=[IO.File]::ReadAllText($ignore) }
        foreach ($pattern in $patterns) { if ($pattern -cnotin @($current -split '\r?\n')) { $current+="`n"+$pattern } }
        [IO.File]::WriteAllText($ignore,$current+"`n",(New-Object Text.UTF8Encoding($false)))
        foreach ($file in $plan.Files) { [void](Invoke-JobsGit $plan.Repo @('--literal-pathspecs','rm','--cached','--',$file)) }
    }
}
# 有效行数钩子使用 Git for Windows 自带 sh 启动 PowerShell，保留已有钩子。
function Install-JobsMarkdownHook {
    param([string]$Repository)
    $hook=(Invoke-JobsGit $Repository @('rev-parse','--git-path','hooks/pre-commit') -Quiet).Text
    if (-not [IO.Path]::IsPathRooted($hook)) { $hook=Join-Path $Repository $hook }
    if (Test-Path -LiteralPath $hook) { throw '已有 pre-commit 钩子，保留原文件；请先自行整合。' }
    Confirm-JobsYes '安装 pre-commit：更新含“当前总行数：0 行”的 Markdown 并仅重新暂存原本整文件暂存的文档；部分暂存停止。'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $hook))
    $worker=Join-Path (Split-Path -Parent $hook) 'jobs-markdown-lines.ps1'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'MarkdownLines.ps1') -Destination $worker -ErrorAction Stop
    [IO.File]::WriteAllText($hook,"#!/bin/sh`nexec powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"`$(dirname `"`$0`")/jobs-markdown-lines.ps1`"`n",(New-Object Text.UTF8Encoding($false)))
    Write-JobsLog "钩子已安装：$hook"
}
# Windows PowerShell 5.1 的原生调用会丢失空参数，统一按 Win32 规则保留空口令与路径。
function ConvertTo-JobsSshArgument {
    param([AllowEmptyString()][string]$Value)
    $value=[regex]::Replace($Value,'(\\*)"','$1$1\"')
    $value=[regex]::Replace($value,'(\\+)$','$1$1')
    return '"'+$value+'"'
}
# SSH 专用有界进程调用；输出只交调用方判定，不把私钥或认证响应写日志。
function Invoke-JobsSshProcess {
    param([string]$Program,[string[]]$Arguments,[int]$TimeoutMilliseconds=20000)
    $command=Get-Command $Program -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$command.Source
    $info.Arguments=(@($Arguments | ForEach-Object { ConvertTo-JobsSshArgument $_ }) -join ' ')
    $info.UseShellExecute=$false
    $info.CreateNoWindow=$true
    $info.RedirectStandardInput=$true
    $info.RedirectStandardOutput=$true
    $info.RedirectStandardError=$true
    $info.StandardOutputEncoding=New-Object Text.UTF8Encoding($false)
    $info.StandardErrorEncoding=New-Object Text.UTF8Encoding($false)
    $info.EnvironmentVariables['GH_PROMPT_DISABLED']='1'
    # auth status 已显式指定主机；避免 GH_HOST 为未登录用户合成空账号 401。
    if ($Program -eq 'gh' -and $Arguments.Count -ge 2 -and $Arguments[0] -ceq 'auth' -and $Arguments[1] -ceq 'status') {
        $info.EnvironmentVariables.Remove('GH_HOST')
    }
    $info.EnvironmentVariables['GIT_TERMINAL_PROMPT']='0'
    $info.EnvironmentVariables['SSH_ASKPASS_REQUIRE']='never'
    $process=New-Object Diagnostics.Process
    $process.StartInfo=$info
    try {
        if (-not $process.Start()) { throw "$Program 无法启动。" }
        $process.StandardInput.Close()
        $outputTask=$process.StandardOutput.ReadToEndAsync()
        $errorTask=$process.StandardError.ReadToEndAsync()
        $timer=[Diagnostics.Stopwatch]::StartNew()
        while (-not $process.WaitForExit(100)) {
            if ($timer.ElapsedMilliseconds -ge $TimeoutMilliseconds) {
                $process.Kill()
                $process.WaitForExit()
                throw "$Program 超时，已停止本次调用。"
            }
        }
        $process.WaitForExit()
        return @{Code=$process.ExitCode;Text=$outputTask.Result;Error=$errorTask.Result}
    } finally { $process.Dispose() }
}
# 只为 SSH 入口检查 fzf，避免改变其它业务的选择器及依赖。
function Select-JobsSshAction {
    $command=Get-Command fzf -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) { throw '缺少 fzf。请先运行 winget install --id junegunn.fzf -e，重新打开终端后再试；官方来源：https://github.com/junegunn/fzf/releases' }
    $version=Invoke-JobsSshProcess $command.Source @('--version')
    $help=Invoke-JobsSshProcess $command.Source @('--help')
    if ($version.Code -ne 0 -or -not $version.Text.Trim() -or $help.Code -ne 0) { throw 'fzf 无法正常运行，请修复后重试。' }
    foreach ($flag in @('--height','--layout','--border','--header','--bind','--prompt','--no-sort')) {
        if (-not $help.Text.Contains($flag)) { throw "fzf 缺少 $flag，请更新后重试。" }
    }
    if ([Console]::IsInputRedirected) { throw '没有可交互终端，已停止密钥配置。' }
    $savedOptions=[Environment]::GetEnvironmentVariable('FZF_DEFAULT_OPTS','Process')
    $savedOptionsFile=[Environment]::GetEnvironmentVariable('FZF_DEFAULT_OPTS_FILE','Process')
    $savedOutputEncoding=$OutputEncoding
    $savedConsoleEncoding=[Console]::OutputEncoding
    try {
        $env:FZF_DEFAULT_OPTS=''
        $env:FZF_DEFAULT_OPTS_FILE=''
        $OutputEncoding=New-Object Text.UTF8Encoding($false)
        [Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
        Write-Host 'ED25519（推荐）：现代算法，密钥更短，签名通常更快，适合新环境。' -ForegroundColor Cyan
        Write-Host 'RSA 4096：用于不支持 ED25519 的旧系统。' -ForegroundColor Cyan
        $rows=@('ED25519（推荐）','RSA 4096','打开 GitHub 公钥网页','打开 GitHub Token 网页','打开本机密钥文件夹','取消本轮')
        $selected=@($rows | & $command.Source '--height=50%' '--layout=reverse' '--border' '--no-sort' '--header=方向键 / Tab 选择；Enter 确认；Esc 取消' '--prompt=密钥算法 > ' '--bind=tab:down,btab:up,esc:abort')
        $code=$LASTEXITCODE
    } finally {
        [Environment]::SetEnvironmentVariable('FZF_DEFAULT_OPTS',$savedOptions,'Process')
        [Environment]::SetEnvironmentVariable('FZF_DEFAULT_OPTS_FILE',$savedOptionsFile,'Process')
        $OutputEncoding=$savedOutputEncoding
        [Console]::OutputEncoding=$savedConsoleEncoding
    }
    if ($code -eq 130 -or $code -eq 1 -or ($selected.Count -eq 1 -and $selected[0] -ceq '取消本轮')) { throw '用户已取消，未配置密钥。' }
    if ($code -ne 0) { throw "fzf 失败（$code），未配置密钥。" }
    if ($selected.Count -ne 1 -or $selected[0] -cnotin @('ED25519（推荐）','RSA 4096','打开 GitHub 公钥网页','打开 GitHub Token 网页','打开本机密钥文件夹')) { throw 'fzf 返回空选或无效结果，未配置密钥。' }
    return $selected[0]
}
# 辅助入口执行后返回根菜单，只有实际算法选择才进入密钥业务。
function Select-JobsSshAlgorithm {
    while ($true) {
        $action=Select-JobsSshAction
        switch -CaseSensitive ($action) {
            'ED25519（推荐）' { return 'ed25519' }
            'RSA 4096' { return 'rsa' }
            '打开 GitHub 公钥网页' { Start-Process 'https://github.com/settings/ssh/new' }
            '打开 GitHub Token 网页' { Start-Process 'https://github.com/settings/tokens' }
            '打开本机密钥文件夹' {
                $folder=Join-Path ([Environment]::GetFolderPath('UserProfile')) '.ssh'
                Test-JobsSshRegularPath $folder
                [void][IO.Directory]::CreateDirectory($folder)
                Start-Process explorer.exe -ArgumentList @($folder)
            }
            default { throw '算法选择异常，未配置密钥。' }
        }
    }
}
# 运行目录与密钥配置不跟随重解析点，避免把个人文件写到其它位置。
function Test-JobsSshRegularPath {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        if ((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "SSH 路径是重解析点，已停止：$Path" }
    }
}
# 同邮箱、同算法且空口令可验证的密钥才复用，已有其它文件一律保留。
function Find-JobsSshKey {
    param([string]$Folder,[string]$Algorithm,[string]$Email)
    if (-not (Test-Path -LiteralPath $Folder)) { return '' }
    foreach ($publicFile in @(Get-ChildItem -LiteralPath $Folder -Filter 'id*personal*.pub' -File | Sort-Object Name)) {
        $key=$publicFile.FullName.Substring(0,$publicFile.FullName.Length-4)
        if (-not (Test-Path -LiteralPath $key -PathType Leaf)) { continue }
        Test-JobsSshRegularPath $key
        Test-JobsSshRegularPath $publicFile.FullName
        $public=[IO.File]::ReadAllText($publicFile.FullName).Trim()
        $parts=@($public -split '\s+',3)
        $expectedType='ssh-ed25519'; if ($Algorithm -eq 'rsa') { $expectedType='ssh-rsa' }
        if ($parts.Count -ne 3 -or $parts[0] -cne $expectedType -or $parts[2] -cne $Email) { continue }
        $fingerprint=Invoke-JobsSshProcess 'ssh-keygen' @('-lf',$publicFile.FullName)
        if ($fingerprint.Code -ne 0 -or ($Algorithm -eq 'rsa' -and $fingerprint.Text -notmatch '^4096\s')) { continue }
        $derived=Invoke-JobsSshProcess 'ssh-keygen' @('-y','-P','','-f',$key)
        if ($derived.Code -ne 0) { continue }
        $derivedParts=@($derived.Text.Trim() -split '\s+')
        if ($derivedParts.Count -ge 2 -and $derivedParts[0] -ceq $parts[0] -and $derivedParts[1] -ceq $parts[1]) { return $key }
    }
    return ''
}
# 新私钥只给当前 Windows 用户访问权限，不修改已有密钥的 ACL。
function Protect-JobsSshPrivateKey {
    param([string]$Key)
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $result=Invoke-JobsSshProcess 'icacls.exe' @($Key,'/inheritance:r','/grant:r',('*'+$sid+':(F)'))
    if ($result.Code -ne 0) { throw "无法保护新私钥权限，已停止：$Key" }
}
# 根据所选算法分配个人密钥名，重名时追加邮箱摘要与序号，不覆盖现存内容。
function New-JobsSshKey {
    param([string]$Folder,[string]$Algorithm,[string]$Email)
    [void][IO.Directory]::CreateDirectory($Folder)
    $base=Join-Path $Folder ('id_'+$Algorithm+'_personal')
    $key=$base
    $hash=[Security.Cryptography.SHA256]::Create()
    try { $suffix=([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($Email)))).Replace('-','').Substring(0,12).ToLowerInvariant() } finally { $hash.Dispose() }
    $index=0
    while ((Test-Path -LiteralPath $key) -or (Test-Path -LiteralPath ($key+'.pub'))) {
        $index++
        $key=$base+'_'+$suffix
        if ($index -gt 1) { $key+='_'+$index }
    }
    $arguments=@('-q','-t',$Algorithm,'-C',$Email,'-f',$key,'-N','')
    if ($Algorithm -eq 'rsa') { $arguments+=@('-b','4096') }
    $result=Invoke-JobsSshProcess 'ssh-keygen' $arguments
    if ($result.Code -ne 0 -or -not (Test-Path -LiteralPath $key -PathType Leaf) -or -not (Test-Path -LiteralPath ($key+'.pub') -PathType Leaf)) { throw "ssh-keygen 未完成；未覆盖已有密钥。目标：$key" }
    Protect-JobsSshPrivateKey $key
    Write-JobsSshLog "已生成个人密钥（空口令）：$key"
    return $key
}
# 在密钥目录独占创建说明；既有任意同名项都保留，写失败不阻断 SSH 配置。
function Write-JobsSshReadme {
    param([string]$Folder,[string]$Key)
    $readme=Join-Path $Folder 'README.md'
    if ($null -ne (Get-Item -LiteralPath $readme -Force -ErrorAction SilentlyContinue)) {
        Write-JobsSshLog '密钥目录 README.md 已被占用，原内容保持不变，跳过生成。'
        return
    }
    $text=@'
# 🔑Jobs GitHub SSH 密钥目录说明

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

本目录属于当前系统用户，用于保存 SSH 密钥、连接配置和已信任主机记录。本说明由 Jobs SSH 配置工具首次生成；已有 README.md 或任意同名项时保留并跳过，不覆盖、不追加、不更新。

本轮实际私钥文件名：`__JOBS_SSH_KEY__`；对应公钥文件名：`__JOBS_SSH_KEY__.pub`。这里只说明文件用途，不包含私钥正文、Token 或密码。

## 一、<span id="ssh-files">目录中的文件</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 文件 | 作用与使用方式 |
| --- | --- |
| `config` | OpenSSH 客户端连接配置，保存 Host、User、IdentityFile 等选项，决定访问 GitHub 时使用哪把私钥。 |
| `id_ed25519_personal` | ED25519 个人私钥，必须仅由本人妥善保管，不能上传到 GitHub、代码仓库、聊天或公开网盘。 |
| `id_ed25519_personal.pub` | 上述私钥对应的公钥，可复制到 [GitHub SSH 公钥设置](https://github.com/settings/ssh/new)；上传的是完整公钥行。 |
| `id_rsa_personal` / `id_rsa_personal.pub` | 选择 RSA 4096 时的私钥与公钥，分别遵循相同的保管与登记规则。 |
| `known_hosts` | 保存已验证的远端服务器主机公钥，用于识别服务器、防止连接到冒充主机；它不是你的个人公钥清单。 |
| `README.md` | 本说明文件，仅解释目录用途，不参与 SSH 认证。 |

同算法和邮箱匹配的密钥可以复用；默认文件名已被其它密钥占用时，工具会追加邮箱摘要和必要序号，例如 `id_ed25519_personal_摘要_1`，其公钥始终为同名文件追加 `.pub`。以本轮实际文件名和 `config` 中的 IdentityFile 为准，不要根据示例改名。旧密钥、配置备份及其它账户文件也可能存在，本表不代表目录中只允许这些文件。

## 二、<span id="ssh-safety">公私钥区别与安全保管</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 私钥用于证明你的身份，文件没有 `.pub` 后缀；公钥用于让 GitHub 识别对应私钥，文件带 `.pub` 后缀。两者必须配对，文件名不是 GitHub 账号。
- 新建密钥使用空口令，应保护本机登录权限、磁盘与离线备份。只公开公钥，不分享私钥、Token 或密码；私钥泄漏时应立即在 GitHub 删除对应公钥并更换密钥。
- 不要删除或盲目替换 `known_hosts` 来绕过主机指纹警告，应先通过官方来源核实主机变更。
- 此说明不会证明公钥已在 GitHub 登记。密钥文件存在、本机配置成功与 GitHub 认证通过是不同阶段。

## 三、<span id="ssh-test">添加公钥后测试</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 登录正确的 GitHub 账号，打开 [新增 SSH 公钥](https://github.com/settings/ssh/new)，类型选 Authentication Key，粘贴对应 `.pub` 文件的完整公钥并保存；不要粘贴私钥正文。
- GUI 使用“测试 SSH 连接”按钮；终端脚本可用相同邮箱与算法重新运行，会优先复用匹配的密钥，再测试连接。不要为重复测试删除已有密钥。
- 终端可运行 `ssh -T git@github.com` 检查当前 SSH 配置；工具内测试会强制使用本轮私钥。首次连接须核对官方主机指纹，不能盲目信任未知主机。
- 成功时 GitHub 返回 `Hi 用户名! You've successfully authenticated`，并说明不提供 Shell 访问；该成功响应的退出码通常是 1。`Permission denied (publickey)` 表示尚未认证成功，应核对公钥登记账号、实际使用的私钥及网络。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
'@
    $text=$text.Replace('__JOBS_SSH_KEY__',[IO.Path]::GetFileName($Key))
    $stream=$null
    $created=$false
    try {
        $stream=[IO.File]::Open($readme,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
        $created=$true
        $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes($text+"`r`n")
        $stream.Write($bytes,0,$bytes.Length)
        $stream.Flush()
        Write-JobsSshLog '已在密钥目录生成 README.md 文件用途说明。'
    } catch {
        if (-not $created -and $null -ne (Get-Item -LiteralPath $readme -Force -ErrorAction SilentlyContinue)) {
            Write-JobsSshLog '密钥目录 README.md 已被占用，保留先到的文件，跳过生成。'
        } else {
            Write-JobsSshLog '提示：无法创建或写入密钥目录 README.md；密钥与 SSH 配置流程继续。'
        }
    } finally { if ($null -ne $stream) { $stream.Dispose() } }
}
# 托管块置前保证本次 IdentityFile 优先；保留原正文，已有配置先完整备份。
function Set-JobsSshConfiguration {
    param([string]$Folder,[string]$Key)
    $config=Join-Path $Folder 'config'
    Test-JobsSshRegularPath $config
    $text=''; if (Test-Path -LiteralPath $config) { $text=[IO.File]::ReadAllText($config) }
    $begin='# BEGIN JOBS PERSONAL SSH'
    $end='# END JOBS PERSONAL SSH'
    $beginCount=([regex]::Matches($text,'(?m)^# BEGIN JOBS PERSONAL SSH\r?$')).Count
    $endCount=([regex]::Matches($text,'(?m)^# END JOBS PERSONAL SSH\r?$')).Count
    if ($beginCount -ne $endCount -or $beginCount -gt 1) { throw 'SSH config 托管标记异常，原配置未改动。' }
    $remaining=$text
    if ($beginCount -eq 1) {
        $pattern='(?ms)^# BEGIN JOBS PERSONAL SSH\r?\n.*?^# END JOBS PERSONAL SSH(?:\r?\n|$)'
        if ($remaining -notmatch $pattern) { throw 'SSH config 托管块不完整，原配置未改动。' }
        $remaining=[regex]::Replace($remaining,$pattern,'')
    }
    $identity=$Key.Replace('\','/').Replace('%','%%')
    if ($identity -match '[\r\n"]') { throw '密钥路径不能安全写入 SSH config。' }
    $block=$begin+"`r`nHost github.com github-personal`r`n  HostName github.com`r`n  User git`r`n  IdentitiesOnly yes`r`n  IdentityFile `""+$identity+"`"`r`n"+"Host *`r`n"+$end+"`r`n"
    $updated=$block+$remaining
    if ($updated -ceq $text) { Write-JobsSshLog 'SSH config 已匹配本次私钥。'; return }
    if (Test-Path -LiteralPath $config) {
        $backup=$config+'.backup-'+[guid]::NewGuid().ToString('N')
        Copy-Item -LiteralPath $config -Destination $backup -ErrorAction Stop
        Write-JobsSshLog "SSH config 备份：$backup"
    }
    [IO.File]::WriteAllText($config,$updated,(New-Object Text.UTF8Encoding($false)))
    Write-JobsSshLog "已配置 github.com / github-personal 的 IdentityFile：$Key"
}
# 优先复用已运行的 agent；不提权、不更改系统服务启动类型。
function Add-JobsSshAgentKey {
    param([string]$Key)
    try {
        $result=Invoke-JobsSshProcess 'ssh-add' @($Key)
        if ($result.Code -eq 0) { Write-JobsSshLog '已加载本次密钥到 ssh-agent。'; return $true }
        Write-JobsSshLog '提示：ssh-agent 当前不可用，未加载密钥；OpenSSH 仍可通过已配置的 IdentityFile 直接使用空口令私钥。'
    } catch { Write-JobsSshLog '提示：未能调用 ssh-add，agent 加载未完成；IdentityFile 配置已保留。' }
    return $false
}
# 只分析活跃账号的结构化状态，授权响应和令牌不进入日志。
function Get-JobsSshGithubAuthState {
    try {
        $result=Invoke-JobsSshProcess 'gh' @('auth','status','--active','--hostname','github.com','--json','hosts')
    } catch {
        if ($_.Exception.Message -match '超时|timeout|timed out') { return 'timeout' }
        return 'check_failed'
    }
    try {
        $response=$result.Text | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $response.hosts -or $response.hosts -isnot [pscustomobject]) { return 'check_failed' }
        $properties=@($response.hosts.PSObject.Properties)
        $hostProperty=$properties | Where-Object { $_.Name -ceq 'github.com' } | Select-Object -First 1
        if (-not $hostProperty) {
            if ($properties.Count -eq 0 -and $result.Code -in @(0,1)) { return 'not_logged_in' }
            return 'check_failed'
        }
        if ($hostProperty.Value -isnot [array]) { return 'check_failed' }
        $accounts=@($hostProperty.Value)
        if ($accounts.Count -eq 0 -and $result.Code -in @(0,1)) { return 'not_logged_in' }
        if ($result.Code -ne 0) { return 'check_failed' }
        $active=@($accounts | Where-Object { $_.active -is [bool] -and $_.active })
        if ($active.Count -ne 1) { return 'check_failed' }
        if ($active[0].state -ceq 'success') { return 'ready' }
        if ($active[0].state -ceq 'timeout') { return 'timeout' }
        if ($active[0].state -cne 'error' -or $active[0].error -isnot [string]) { return 'check_failed' }
        $diagnostic=$active[0].error
        if ($diagnostic -match '(?i)HTTP[ :]+401\b') { return 'invalid' }
        if ($diagnostic -match '(?i)HTTP[ :]+403\b') { return 'forbidden' }
        if ($diagnostic -match '(?i)timeout|timed out|connection|resolve|network|certificate|tls|dial tcp|no such host') { return 'network' }
        return 'check_failed'
    } catch { return 'check_failed' }
}
# 所有提示均为本地固定文本，不能回显原始授权响应。
function Get-JobsSshGithubAuthFailure {
    param([string]$State)
    switch -CaseSensitive ($State) {
        'not_logged_in' { return 'gh 已安装，但尚未登录 github.com。请运行 gh auth login --hostname github.com，或在公钥网页添加。' }
        'invalid' { return 'gh 已安装，但当前 GitHub 登录凭据被拒绝（HTTP 401）。请重新登录授权，或在公钥网页添加；无需重新生成本地密钥。' }
        'forbidden' { return 'gh 已安装，但 GitHub 拒绝授权检查请求（HTTP 403）。请检查授权与访问限制，或在公钥网页添加。' }
        'timeout' { return 'gh 已安装，但登录状态检测超时，未判断凭据是否有效。请检查网络后重试，或在公钥网页添加。' }
        'network' { return 'gh 已安装，但网络或证书问题导致登录状态检测失败，未判断凭据是否有效。请检查网络后重试。' }
        default { return 'gh 已安装，但无法确认登录状态。请检查 gh 版本及网络后重试，或在公钥网页添加；未将检测失败判定为授权失效。' }
    }
}
# 仅在已登录账号的已验证邮箱匹配时自动登记，缺认证或权限时交官方页面兜底。
function Register-JobsSshPublicKey {
    param([string]$Key,[string]$Email)
    $public=[IO.File]::ReadAllText($Key+'.pub').Trim()
    try { Set-Clipboard -Value $public; Write-JobsSshLog '公钥已复制到剪贴板。' } catch { Write-JobsSshLog "提示：剪贴板不可用，公钥文件：$Key.pub" }
    $registered=$false
    $failure='未检测到 GitHub CLI（gh）。可安装 gh 后授权，或在 GitHub 公钥网页添加。'
    if (Get-Command gh -CommandType Application -ErrorAction SilentlyContinue) {
        try {
            $authState=Get-JobsSshGithubAuthState
            if ($authState -cne 'ready') { throw (Get-JobsSshGithubAuthFailure $authState) }
            $account=Invoke-JobsSshProcess 'gh' @('api','--hostname','github.com','user','--jq','.login')
            $emails=Invoke-JobsSshProcess 'gh' @('api','--hostname','github.com','user/emails','--paginate','--jq','.[] | select(.verified) | .email')
            if ($account.Code -ne 0 -or $emails.Code -ne 0) { throw 'GitHub 登录或邮箱读取权限不可用。' }
            $login=$account.Text.Trim()
            if ($login -notmatch '^[A-Za-z0-9][A-Za-z0-9-]*$') { throw 'GitHub 当前账号无法验证。' }
            $verified=@(($emails.Text -split '[\r\n]+') | Where-Object { $_ -ieq $Email })
            if ($verified.Count -eq 0) { throw '邮箱不属于当前 GitHub CLI 账号的已验证邮箱，未向该账号登记。' }
            Write-JobsSshLog ('GitHub 登记账号：'+$login)
            $keys=Invoke-JobsSshProcess 'gh' @('api','--hostname','github.com','user/keys','--paginate','--jq','.[].key')
            if ($keys.Code -ne 0) { throw '当前账号缺少公钥管理权限。' }
            $parts=@($public -split '\s+',3)
            $keyValue=$parts[0]+' '+$parts[1]
            $existing=@(($keys.Text -split '[\r\n]+') | Where-Object { $fields=@($_ -split '\s+',3); $fields.Count -ge 2 -and (($fields[0..1] -join ' ') -ceq $keyValue) })
            if ($existing.Count -eq 0) {
                $title='Jobs personal '+[Environment]::MachineName+' '+[IO.Path]::GetFileName($Key)
                $added=Invoke-JobsSshProcess 'gh' @('api','--hostname','github.com','--method','POST','user/keys','-f',('title='+$title),'-f',('key='+$public))
                if ($added.Code -ne 0) { throw 'GitHub 拒绝登记公钥；请检查认证、admin:public_key 权限或公钥归属。' }
                $record=$added.Text | ConvertFrom-Json
                if (-not $record.id -or -not $record.key -or ((@($record.key -split '\s+',3)[0..1] -join ' ') -cne $keyValue)) { throw 'GitHub 返回结果无法验证，未标记登记成功。' }
                Write-JobsSshLog '公钥已自动登记到匹配邮箱的 GitHub 账号。'
            } else { Write-JobsSshLog '当前 GitHub 账号已登记本次公钥，无需重复添加。' }
            $registered=$true
        } catch { $failure=$_.Exception.Message }
    }
    if (-not $registered) {
        Write-JobsSshLog ('待完成：公钥未自动登记。'+$failure)
        Write-JobsSshLog '请在 GitHub 官方页面登录相应账号并粘贴公钥：https://github.com/settings/ssh/new'
        try { Start-Process 'https://github.com/settings/ssh/new' } catch { Write-JobsSshLog '提示：无法打开浏览器，请使用上方官方地址。' }
    }
    return $registered
}
# 仅通过 GitHub 官方 HTTPS 元数据准备首次主机密钥，已有条目不自动替换。
function Initialize-JobsSshKnownHosts {
    param([string]$Folder)
    $known=Join-Path $Folder 'known_hosts'
    Test-JobsSshRegularPath $known
    if (Test-Path -LiteralPath $known) {
        $found=Invoke-JobsSshProcess 'ssh-keygen' @('-F','github.com','-f',$known)
        if ($found.Code -eq 0) { Write-JobsSshLog '保留已有 GitHub known_hosts 条目；连接时继续严格校验。'; return $true }
        if ($found.Code -ne 1) { Write-JobsSshLog '待完成：无法检查 known_hosts，保留原文件。'; return $false }
    }
    $source='https://api.github.com/meta'
    Write-JobsSshLog "主机密钥来源：GitHub 官方 HTTPS $source → $known"
    $savedProtocol=[Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol=$savedProtocol -bor [Net.SecurityProtocolType]::Tls12
        $response=Invoke-WebRequest -Uri $source -UseBasicParsing -TimeoutSec 15 -Headers @{'User-Agent'='Jobs-Personal-SSH';Accept='application/vnd.github+json'}
        $metadata=$response.Content | ConvertFrom-Json
        $keys=@($metadata.ssh_keys)
        if ($keys.Count -eq 0) { throw '官方响应没有主机密钥。' }
        $lines=@()
        foreach ($entry in $keys) {
            if ($entry -notmatch '^(ssh-ed25519|ecdsa-sha2-nistp256|ssh-rsa) [A-Za-z0-9+/]+={0,2}$') { throw '官方响应包含无效主机密钥格式。' }
            $parts=@($entry -split ' ',2)
            $bytes=[Convert]::FromBase64String($parts[1])
            if ($bytes.Length -lt 8) { throw '官方主机密钥过短。' }
            $length=([int]$bytes[0]*16777216)+([int]$bytes[1]*65536)+([int]$bytes[2]*256)+[int]$bytes[3]
            if ($length -lt 1 -or $length -gt $bytes.Length-4 -or [Text.Encoding]::ASCII.GetString($bytes,4,$length) -cne $parts[0]) { throw '官方主机密钥类型与内容不一致。' }
            $lines+='github.com '+$entry
        }
        $prefix=''; if ((Test-Path -LiteralPath $known) -and (Get-Item -LiteralPath $known).Length -gt 0) { $prefix="`r`n" }
        [IO.File]::AppendAllText($known,$prefix+($lines -join "`r`n")+"`r`n",(New-Object Text.UTF8Encoding($false)))
        Write-JobsSshLog '已加入来自 GitHub 官方 HTTPS 的主机密钥。'
        return $true
    } catch { Write-JobsSshLog '待完成：无法取得或验证 GitHub 官方主机密钥，未新增 known_hosts 条目。'; return $false }
    finally { [Net.ServicePointManager]::SecurityProtocol=$savedProtocol }
}
# Win32 文件身份和硬链接均不读取私钥正文，也不要求符号链接或管理员权限。
function Initialize-JobsSshFileLinkApi {
    if (('Jobs.SshFileLinks' -as [type])) { return }
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace Jobs {
    public static class SshFileLinks {
        [StructLayout(LayoutKind.Sequential)]
        private struct FileInformation {
            public uint Attributes;
            public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
            public System.Runtime.InteropServices.ComTypes.FILETIME AccessTime;
            public System.Runtime.InteropServices.ComTypes.FILETIME WriteTime;
            public uint VolumeSerial, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
        }
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        private static extern SafeFileHandle CreateFile(string path, uint access, uint sharing,
            IntPtr security, uint disposition, uint flags, IntPtr template);
        [DllImport("kernel32.dll", SetLastError=true)]
        private static extern bool GetFileInformationByHandle(SafeFileHandle file, out FileInformation information);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        private static extern bool CreateHardLink(string destination, string source, IntPtr security);
        public static string Identity(string path) {
            using (SafeFileHandle file = CreateFile(path, 0, 7, IntPtr.Zero, 3, 0x00200000, IntPtr.Zero)) {
                if (file.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
                FileInformation information;
                if (!GetFileInformationByHandle(file, out information))
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                if ((information.Attributes & (0x400U | 0x10U)) != 0)
                    throw new IOException("E_SSH_LINK_REPARSE_OR_DIRECTORY");
                return information.VolumeSerial.ToString("X8") + ":" + information.IndexHigh.ToString("X8") + information.IndexLow.ToString("X8");
            }
        }
        public static void Create(string source, string destination) {
            if (!CreateHardLink(destination, source, IntPtr.Zero))
                throw new Win32Exception(Marshal.GetLastWin32Error());
        }
    }
}
'@ -ErrorAction Stop
}
# 与源文件同一文件身份才视为已有正确硬链接，拒绝复制品和重解析点。
function Get-JobsSshFileIdentity {
    param([string]$Path)
    Initialize-JobsSshFileLinkApi
    return [Jobs.SshFileLinks]::Identity($Path)
}
function New-JobsSshHardLink {
    param([string]$Source,[string]$Destination)
    Initialize-JobsSshFileLinkApi
    [Jobs.SshFileLinks]::Create($Source,$Destination)
}
# 仅为本轮严格认证返回的实际账号添加一对硬链接；失败不改变认证结论。
function Add-JobsSshSourceTreeAliases {
    param([string]$Folder,[string]$Key,[string]$Account)
    if (-not $Account -or $Account -cne $script:SshAuthenticatedAccount -or $Account -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,38}$') { return }
    try {
        Test-JobsSshRegularPath $Folder
        $folderPath=[IO.Path]::GetFullPath($Folder).TrimEnd([char[]]'\/')
        $keyFolder=[IO.Path]::GetFullPath((Split-Path -Parent $Key)).TrimEnd([char[]]'\/')
        if (-not [string]::Equals($folderPath,$keyFolder,[StringComparison]::OrdinalIgnoreCase)) { throw 'E_SSH_KEY_DIRECTORY' }
        $pairs=@(
            @{Source=$Key;Alias=(Join-Path $Folder ($Account+'-GitHub'))},
            @{Source=($Key+'.pub');Alias=(Join-Path $Folder ($Account+'-GitHub.pub'))}
        )
        foreach ($pair in $pairs) {
            $source=Get-Item -LiteralPath $pair.Source -Force -ErrorAction Stop
            if ($source.PSIsContainer -or ($source.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'E_SSH_KEY_SOURCE' }
            $pair.Identity=Get-JobsSshFileIdentity $pair.Source
        }
        foreach ($pair in $pairs) {
            $existing=Get-Item -LiteralPath $pair.Alias -Force -ErrorAction SilentlyContinue
            if ($null -ne $existing) {
                if ($existing.PSIsContainer -or ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Get-JobsSshFileIdentity $pair.Alias) -cne $pair.Identity) {
                    Write-JobsSshLog ("Sourcetree 密钥别名与已有文件冲突，已保留："+$pair.Alias+"。SSH 认证仍已通过；账户用户名应为 $Account。")
                    return
                }
            }
        }
        foreach ($pair in $pairs) {
            $existing=Get-Item -LiteralPath $pair.Alias -Force -ErrorAction SilentlyContinue
            if ($null -ne $existing -and -not $existing.PSIsContainer -and -not ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -and (Get-JobsSshFileIdentity $pair.Alias) -ceq $pair.Identity) { continue }
            try { New-JobsSshHardLink $pair.Source $pair.Alias }
            catch {
                $existing=Get-Item -LiteralPath $pair.Alias -Force -ErrorAction SilentlyContinue
                if ($null -ne $existing -and -not $existing.PSIsContainer -and -not ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -and (Get-JobsSshFileIdentity $pair.Alias) -ceq $pair.Identity) { continue }
                throw
            }
        }
        Write-JobsSshLog ("已为认证账号 $Account 配置 Sourcetree 密钥硬链接；Sourcetree 账户用户名也应填写 $Account。")
    } catch {
        Write-JobsSshLog ("提示：Sourcetree 密钥别名未完成，已保留已有文件、原密钥和配置；SSH 认证仍已通过。账户用户名应为 $Account，无需管理员权限，也未复制私钥正文。")
    }
}
# 只验证本次密钥，拒绝密码提示与未知主机自动信任，避免旧 agent 密钥造成误报。
function Test-JobsSshConnection {
    param([string]$Folder,[string]$Key)
    $script:SshAuthenticatedAccount=''
    $emptyConfig=Join-Path ([IO.Path]::GetTempPath()) ('JobsSsh-empty-'+[guid]::NewGuid().ToString('N'))
    [IO.File]::WriteAllText($emptyConfig,'',(New-Object Text.UTF8Encoding($false)))
    try {
        $arguments=@('-F',$emptyConfig,'-T','-i',$Key,'-o','IdentitiesOnly=yes','-o','IdentityAgent=none','-o','BatchMode=yes','-o','ConnectTimeout=10','-o','ConnectionAttempts=1','-o','StrictHostKeyChecking=yes','-o','UpdateHostKeys=no','-o',('UserKnownHostsFile="'+(Join-Path $Folder 'known_hosts').Replace('\','/').Replace('%','%%')+'"'),'git@github.com')
        $result=Invoke-JobsSshProcess 'ssh' $arguments 15000
        $message=$result.Text+$result.Error
        $match=[regex]::Match($message,"(?m)^Hi ([A-Za-z0-9][A-Za-z0-9-]{0,38})! You've successfully authenticated, but GitHub does not provide shell access\.\r?$")
        if ($result.Code -eq 1 -and $match.Success) {
            $script:SshAuthenticatedAccount=$match.Groups[1].Value
            Write-JobsSshLog ("本次私钥的 GitHub SSH 认证已通过，账号："+$script:SshAuthenticatedAccount+'。')
            return $true
        }
        Write-JobsSshLog '待完成：本次私钥的 GitHub SSH 认证未通过；请检查公钥登记、网络与 known_hosts 中已验证的 GitHub 主机指纹。未自动信任未知主机。'
        return $false
    } catch { Write-JobsSshLog '待完成：SSH 连接检查无法完成或超时；本地密钥与配置已保留。'; return $false }
    finally { Remove-Item -LiteralPath $emptyConfig -Force -ErrorAction SilentlyContinue }
}
# 选择与输入完成后统一执行，内核不重复收集输入或确认。
function Invoke-JobsSshSetup {
    param([string]$Email,[ValidateSet('ed25519','rsa')][string]$Algorithm)
    foreach ($program in @('ssh-keygen','ssh','icacls.exe')) { [void](Get-Command $program -CommandType Application -ErrorAction Stop) }
    $email=$Email.Trim()
    if (-not $email -or $email -notmatch '^[^\s@]+@[^\s@]+\.[^\s@]+$') { throw '请输入有效个人邮箱。' }
    $folder=Join-Path ([Environment]::GetFolderPath('UserProfile')) '.ssh'
    Test-JobsSshRegularPath $folder
    $key=Find-JobsSshKey $folder $Algorithm $email
    if ($key) { Write-JobsSshLog "复用匹配邮箱及算法的个人密钥：$key" } else { $key=New-JobsSshKey $folder $Algorithm $email }
    Write-JobsSshReadme $folder $key
    Set-JobsSshConfiguration $folder $key
    $agentLoaded=Add-JobsSshAgentKey $key
    $registered=Register-JobsSshPublicKey $key $email
    $knownHostsReady=Initialize-JobsSshKnownHosts $folder
    $authenticated=$false
    if ($knownHostsReady) { $authenticated=Test-JobsSshConnection $folder $key }
    if ($authenticated) { Add-JobsSshSourceTreeAliases $folder $key $script:SshAuthenticatedAccount }
    Write-JobsSshLog 'SourceTree：已准备 OpenSSH 配置；请在 工具 → 选项 → 一般 中使用 OpenSSH。未自动修改 SourceTree 设置，也未把 PuTTY/Pageant 标记为已配置。'
    Write-JobsSshLog "本地配置完成；agent加载=$agentLoaded；GitHub公钥登记=$registered；本次私钥认证=$authenticated；私钥：$key"
    return [pscustomobject]@{Key=$key;AgentLoaded=$agentLoaded;Registered=$registered;Authenticated=$authenticated}
}
# SSH 业务沿用公共日志，不加载窗口或事件回调。
function Write-JobsSshLog {
    param([string]$Message)
    Write-JobsLog $Message
}
# 完成算法选择和邮箱校验后才创建本次日志。
function Start-JobsSshCliLog {
    $script:LogFile=Join-Path ([IO.Path]::GetTempPath()) ('JobsGit-ssh-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$PID+'.log')
    Write-JobsSshLog "日志：$script:LogFile"
}
# 返回用户指定的可编辑默认邮箱，不读取或修改全局 Git 配置。
function Get-JobsSshDefaultEmail {
    return '295060456@qq.com'
}
# 内置自述只确认一次，任何非空输入取消后续业务。
function Confirm-JobsSshCliIntro {
    Write-Host '==================== 私人账户 SSH 密钥配置 ====================' -ForegroundColor Red
    Write-Host '选择算法并填写邮箱，自动生成或复用个人密钥、配置 OpenSSH，尝试加载 agent、登记 GitHub 公钥并验证连接。' -ForegroundColor Blue
    Write-Host '影响：当前用户 .ssh、剪贴板及匹配邮箱的 GitHub 公钥；新密钥使用空口令，现有密钥不覆盖。'
    Write-Host '仅在未占用时新建 .ssh/README.md 用途说明；已有同名文件、链接或目录均保留。'
    Write-Host 'GitHub 严格认证通过后，以实际账号添加 Sourcetree 普通硬链接；不改原密钥名，冲突文件保留，无需管理员权限。'
    Write-Host '权限、认证或 SourceTree 设置未完成时逐项说明；不自动提权、安装工具、提交或推送。按 Ctrl+C 随时取消。'
    if ([Console]::IsInputRedirected) { throw '请在可交互终端或双击 CMD 入口执行；未配置密钥。' }
    $answer=Read-Host '已了解用途与影响，按回车继续；其它输入取消'
    if ($null -eq $answer) { throw '输入已结束，未配置密钥。' }
    if ($answer -ne '') { Write-JobsSshLog '已取消，未配置密钥。'; return $false }
    return $true
}
# 邮箱只收集一次，空输入使用指定默认值，非法输入直接停止。
function Read-JobsSshEmail {
    $default=Get-JobsSshDefaultEmail
    $prompt='个人邮箱'
    if ($default) { $prompt+="（直接回车使用 $default）" }
    $email=Read-Host $prompt
    if ($null -eq $email) { throw '输入已结束，未配置密钥。' }
    if (-not $email) { $email=$default }
    $email=$email.Trim()
    if (-not $email -or $email -notmatch '^[^\s@]+@[^\s@]+\.[^\s@]+$') { throw '邮箱无效，未配置密钥。' }
    return $email
}
# CLI 平台检查独立封装，非 Windows 不执行真实 SSH 配置。
function Test-JobsSshCliEnvironment {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows SSH 入口需要 Windows；其它系统仅允许隔离验证。' }
    if ($PSVersionTable.PSVersion -lt [version]'5.1') { throw '需要 Windows PowerShell 5.1 或更新版本。' }
}
# 黑窗 CLI：一次自述确认、fzf 算法选择和一次邮箱输入后执行内核。
function Invoke-JobsSshKey {
    if (-not (Confirm-JobsSshCliIntro)) { return }
    Test-JobsSshCliEnvironment
    $algorithm=Select-JobsSshAlgorithm
    $email=Read-JobsSshEmail
    Start-JobsSshCliLog
    [void](Invoke-JobsSshSetup -Email $email -Algorithm $algorithm)
}
# GitHub API 通过 gh 已登录身份，避免明文 Token 输入与日志。
function Invoke-JobsCreateRepository {
    $name=Read-Host '新仓名'; if ($name -notmatch '^[A-Za-z0-9_.-]+$') { throw '仓名无效。' }
    $visibility=Select-JobsItem '可见性' @('private','public')
    [void](Invoke-JobsNative 'gh' @('auth','status','--hostname','github.com'))
    Confirm-JobsYes "在当前 gh 登录账号创建 $visibility 仓库 $name；此操作创建真实远端。"
    $result=Invoke-JobsNative 'gh' @('api','--hostname','github.com','user/repos','--method','POST','-f',('name='+$name),'-F',('private='+($visibility -eq 'private').ToString().ToLowerInvariant()),'--jq','.html_url')
    if ($result.Text -notmatch '^https://github\.com/[^/]+/[^/]+$') { throw '返回地址异常，请先检查远端，避免重复创建。' }
    Start-Process $result.Text
}
# 视频二进制上传一次，结果验证后复制地址，不修改 README。
function Invoke-JobsVideoUpload {
    $repo=(Read-Host 'GitHub 仓库地址或 owner/repo').Trim().TrimEnd('/') -replace '^https://github\.com/','' -replace '^git@github\.com:','' -replace '\.git$',''
    if ($repo -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw '仓库格式无效。' }
    $file=Get-Item -LiteralPath (Read-Host '视频路径').Trim('"') -ErrorAction Stop
    $content=@{'.mp4'='video/mp4';'.mov'='video/quicktime';'.webm'='video/webm'}
    if ($file.PSIsContainer -or $file.Length -le 0 -or -not $content.ContainsKey($file.Extension.ToLowerInvariant())) { throw '需要非空 MP4/MOV/WEBM 文件。' }
    [void](Invoke-JobsNative 'gh' @('auth','status','--hostname','github.com'))
    $metadata=(Invoke-JobsNative 'gh' @('api','--hostname','github.com',('repos/'+$repo),'--jq','[.id,.permissions.push] | @tsv') -Quiet).Text -split "`t"
    if ($metadata.Count -ne 2 -or $metadata[1] -ne 'true') { throw '需要目标仓库写权限。' }
    Confirm-JobsYes "上传视频为 GitHub 附件：$repo；重复运行产生新附件，删除限制见 README。"
    $result=Invoke-JobsNative 'gh' @('api','https://uploads.github.com/user-attachments/assets','--method','POST','--header','Content-Type: application/octet-stream','--input',$file.FullName,'--raw-field',('name='+$file.Name),'--raw-field',('content_type='+$content[$file.Extension.ToLowerInvariant()]),'--raw-field',('repository_id='+$metadata[0]),'--jq','.url')
    if ($result.Text -notmatch '^https://github\.com/user-attachments/assets/[A-Za-z0-9-]+$') { throw '返回异常；先检查是否已上传，勿盲目重试。' }
    Set-Clipboard -Value $result.Text
}
# 下载 SourceTree 库优先安全更新已有仓库，非空非仓目录停止。
function Invoke-JobsSourceTreeDownload {
    $url='https://github.com/JobsKits/SourceTree.sh.git'
    $target=Read-Host '下载目录（回车使用用户目录下 SourceTree.command）'
    if (-not $target) { $target=Join-Path ([Environment]::GetFolderPath('UserProfile')) 'SourceTree.command' }
    $target=[IO.Path]::GetFullPath($target.Trim('"'))
    Write-JobsLog "来源：$url`n目标：$target"
    if (Test-Path -LiteralPath (Join-Path $target '.git')) {
        [void](Resolve-JobsDirectory $target)
        if ((Get-JobsConfig $target 'remote.origin.url') -cne $url) { throw '已有仓库 origin 与 SourceTree.sh 官方配置不同，未接管。' }
        Update-JobsBranch $target $url (Get-JobsRemoteBranch $target $url)
    }
    else {
        if ((Test-Path -LiteralPath $target) -and @(Get-ChildItem -LiteralPath $target -Force).Count -gt 0) { throw '目标非空，未删除或覆盖。' }
        [void](Invoke-JobsGit '' @('clone','--',$url,$target))
    }
    Start-Process explorer.exe -ArgumentList @($target)
}
# 子模块重建先完整移动备份旧工作树，逐项 YES，再添加清单，不自动提交。
function Invoke-JobsRebuildModules {
    param([string]$Repository)
    $modules=@(Get-JobsModules $Repository)
    foreach ($item in $modules) { Write-JobsLog "将备份并重建关联：$($item.Path) → $($item.Url)" }
    if ($script:DryRun) { return }
    Confirm-JobsYes '备份并移除现有子模块关联，然后按 JobsCommand 五仓清单重新添加；旧工作树保存在备份，不自动提交。'
    Assert-JobsClean $Repository
    $parentGit=(Invoke-JobsGit $Repository @('rev-parse','--absolute-git-dir') -Quiet).Text
    $metadata=@{}
    foreach ($module in $modules) {
        $child=Resolve-JobsChildPath $Repository $module.Path
        if (Test-Path -LiteralPath (Join-Path $child '.git')) {
            Assert-JobsClean $child
            $actual=(Invoke-JobsGit $child @('rev-parse','--absolute-git-dir') -Quiet).Text
            $expected=Resolve-JobsChildPath (Join-Path $parentGit 'modules') $module.Section
            $standalone=Join-Path $child '.git'
            if ([IO.Path]::GetFullPath($actual) -ne [IO.Path]::GetFullPath($expected) -and -not (Test-Path -LiteralPath $standalone -PathType Container)) { throw "子模块元数据归属不明：$child" }
            if ([IO.Path]::GetFullPath($actual) -eq [IO.Path]::GetFullPath($expected)) { $metadata[$module.Path]=$actual }
        } else {
            $cache=Resolve-JobsChildPath (Join-Path $parentGit 'modules') $module.Section
            if (Test-Path -LiteralPath $cache) { throw "未初始化子仓有缓存，先核验其归属：$cache" }
        }
    }
    $backup=Backup-JobsAssociation $Repository
    $records=@()
    foreach ($module in $modules) {
        $child=Resolve-JobsChildPath $Repository $module.Path
        if (Test-Path -LiteralPath $child) { $destination=Join-Path $backup ('worktrees/'+$module.Path); [void][IO.Directory]::CreateDirectory((Split-Path -Parent $destination)); Move-Item -LiteralPath $child -Destination $destination }
        if ($metadata.ContainsKey($module.Path)) {
            $metaBackup=Join-Path $backup ('metadata/'+$module.Section)
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $metaBackup))
            Move-Item -LiteralPath $metadata[$module.Path] -Destination $metaBackup
            $records+=@{Path=$module.Path;GitDirectory=$metadata[$module.Path];MetadataBackup=$metaBackup}
        }
        [void](Invoke-JobsGit $Repository @('update-index','--force-remove','--',$module.Path))
        $file=Join-Path $Repository '.gitmodules'
        [void](Invoke-JobsGit $Repository @('config','--file',$file,'--remove-section',('submodule.'+$module.Section)))
        if (Get-JobsConfig $Repository ('submodule.'+$module.Section+'.url')) { [void](Invoke-JobsGit $Repository @('config','--local','--remove-section',('submodule.'+$module.Section))) }
    }
    [IO.File]::WriteAllText((Join-Path $backup 'worktree-metadata-map.json'),($records|ConvertTo-Json -Depth 4),(New-Object Text.UTF8Encoding($false)))
    Write-JobsLog "原工作树与元数据按原始字节分开备份；恢复时按 worktree-metadata-map.json 还原原位置：$backup"
    foreach ($name in @('Flutter','iOS','Gits','Others')) {
        $path='JobsGenesis@JobsCommand.'+$name; $url='../JobsCommand-'+$name+'.git'
        Write-JobsLog "来源：$url → $path"
        [void](Invoke-JobsGit $Repository @('submodule','add','--',$url,$path))
    }
    [void](Invoke-JobsGit $Repository @('submodule','add','--','../JobsSh.git','JobsGenesis@JobsSh'))
    $url=Get-JobsConfig $Repository 'remote.origin.url'; Sync-JobsModules $Repository $url $true
    Write-JobsLog "重建完成，尚未提交或推送；备份：$backup"
}
# 独立入口统一首屏说明与确认，预览仅支持明确只读的操作。
function Invoke-JobsGitTool {
    param([string]$Action,[string]$Title,[string]$Description,[string]$EntryDirectory,[string]$Repository,[switch]$DryRun,[switch]$DirectOnly)
    $script:LogFile=$null; $script:DryRun=[bool]$DryRun
    Write-Host $Title -ForegroundColor Red
    Write-Host $Description -ForegroundColor Blue
    Write-Host '运行范围由目标目录决定；危险步骤必须精确 YES。按 Ctrl+C 取消；日志写入系统临时目录。'
    if ($DryRun -and $Action -notin @('download','associate','align','convert','batch','runtime','rebuild')) { throw '此入口不支持只读预览，未执行。' }
    if (-not $DryRun) {
        if ([Console]::IsInputRedirected) { throw '请通过 CMD 双击入口或交互 PowerShell 执行；没有交互输入时停止。' }
        if ((Read-Host '已了解用途与影响，按回车继续；其它取消') -ne '') { return }
    }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -and -not $DryRun) { throw '业务入口需要 Windows。macOS 只能进行解析与隔离模块验证。' }
    $script:LogFile=Join-Path ([IO.Path]::GetTempPath()) ('JobsGit-'+$Action+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$PID+'.log')
    Write-JobsLog "日志：$script:LogFile"
    $needsRepository=$Action -notin @('ssh','create','video','sourcetree','open-flutter','open-oc','open-ockit')
    if ($needsRepository) {
        [void](Invoke-JobsGit '' @('--version') -Quiet)
        if ($DryRun -and -not $Repository) { $Repository=$EntryDirectory }
        if ($Action -in @('batch','convert')) {
            if (-not $Repository) { $Repository=Read-Host '扫描起点目录（可为普通仓库集合目录）' }
            if (-not $Repository) { $Repository=$EntryDirectory }
            $Repository=Resolve-JobsDirectory $Repository
        } else { $Repository=Get-JobsRepository $Repository $EntryDirectory }
        Write-JobsLog "目标仓库：$Repository"
    }
    switch ($Action) {
        'download' { Invoke-JobsDownload $Repository (-not $DirectOnly) }
        'associate' { Invoke-JobsAssociate $Repository }
        'align' { Invoke-JobsAssociate $Repository -Align }
        'convert' { foreach ($repo in @(Get-JobsRepositories $Repository | Sort-Object Length -Descending)) { Invoke-JobsAssociate $repo } }
        'reset' { Invoke-JobsReset $Repository }
        'recover' { Invoke-JobsRecover $Repository }
        'batch' { Invoke-JobsBatchCommit $Repository }
        'runtime' { Invoke-JobsRuntimeCleanup $Repository }
        'search' { Invoke-JobsSearch $Repository }
        'forkpoint' { Invoke-JobsForkPoint $Repository }
        'hook' { Install-JobsMarkdownHook $Repository }
        'ssh' { Invoke-JobsSshKey }
        'create' { Invoke-JobsCreateRepository }
        'video' { Invoke-JobsVideoUpload }
        'sourcetree' { Invoke-JobsSourceTreeDownload }
        'rebuild' { Invoke-JobsRebuildModules $Repository }
        'open-flutter' { Start-Process 'https://github.com/flutter/flutter' }
        'open-oc' { Start-Process 'https://github.com/JobsKits/JobsOCBaseConfigDemo' }
        'open-ockit' { Start-Process 'https://github.com/JobsKits/JobsOCKit' }
        default { throw "未知功能：$Action" }
    }
    Write-JobsLog '处理完成。'
}
Export-ModuleMember -Function *-Jobs*
