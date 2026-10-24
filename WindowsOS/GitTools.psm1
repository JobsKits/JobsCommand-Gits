# GitTools.psm1 | JobsCommand@Gits
# Created by Jobs on 2026年10月23日，星期五.
# 共享原生 Windows Git 实现；不在导入时执行业务。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:LogFile = $null
$script:DryRun = $false
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
    try {
        $ErrorActionPreference='Continue'
        $global:LASTEXITCODE=0
        $output=@(& $command.Source @Arguments 2>&1 | ForEach-Object { $_.ToString() })
        $result=$LASTEXITCODE
    } finally { $ErrorActionPreference=$oldPreference }
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
# 原生 OpenSSH 生成个人密钥，已有密钥不覆盖，配置只增补独立 Host。
function Invoke-JobsSshKey {
    [void](Get-Command ssh-keygen -CommandType Application -ErrorAction Stop)
    $email=Read-Host '个人邮箱'; if ($email -match '[\r\n]' -or -not $email) { throw '邮箱无效。' }
    $type=Select-JobsItem '密钥算法' @('ed25519','rsa 4096')
    $folder=Join-Path ([Environment]::GetFolderPath('UserProfile')) '.ssh'
    $key=Read-Host "密钥文件路径（回车 $folder/id_personal）"; if (-not $key) { $key=Join-Path $folder 'id_personal' }
    $key=[IO.Path]::GetFullPath($key.Trim('"'))
    if ((Test-Path -LiteralPath $key) -or (Test-Path -LiteralPath ($key+'.pub'))) { throw '密钥已存在，未覆盖。' }
    Confirm-JobsYes "生成 SSH 密钥：$key；口令由 ssh-keygen 交互收集，不写入日志。"
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $key))
    $arguments=@('-t','ed25519','-C',$email,'-f',$key); if ($type -like 'rsa*') { $arguments=@('-t','rsa','-b','4096','-C',$email,'-f',$key) }
    & ssh-keygen @arguments; if ($LASTEXITCODE -ne 0) { throw 'ssh-keygen 失败。' }
    $config=Join-Path $folder 'config'; $text=''; if (Test-Path -LiteralPath $config) { $text=[IO.File]::ReadAllText($config) }
    if ($text -notmatch '(?m)^Host\s+github-personal\s*$') {
        if (Test-Path -LiteralPath $config) { Copy-Item -LiteralPath $config -Destination ($config+'.backup-'+[guid]::NewGuid().ToString('N')) }
        $text+="`nHost github-personal`n  HostName github.com`n  User git`n  IdentitiesOnly yes`n  IdentityFile `""+($key -replace '\\','/')+"`"`n"
        [IO.File]::WriteAllText($config,$text,(New-Object Text.UTF8Encoding($false)))
    }
    $public=[IO.File]::ReadAllText($key+'.pub'); Write-Host $public; Set-Clipboard -Value $public
    Start-Process 'https://github.com/settings/ssh/new'
    if ((Read-Host '回车跳过 agent；输入 A 尝试添加到已经运行的 Windows ssh-agent') -ceq 'A') { [void](Invoke-JobsNative 'ssh-add' @($key)); [void](Invoke-JobsNative 'ssh-add' @('-l')) }
    if ((Read-Host '添加网页公钥后，输入 T 测试 github-personal；回车跳过') -ceq 'T') { & ssh -T git@github-personal; if ($LASTEXITCODE -notin @(0,1)) { throw 'SSH 连接失败。' } }
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
