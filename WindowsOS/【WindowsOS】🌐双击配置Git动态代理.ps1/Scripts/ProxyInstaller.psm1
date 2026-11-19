# ProxyInstaller.psm1 | JobsGitProxyConfigurator
# Created by Jobs on 2026年10月22日，星期四.
# URL仅在终端展示层着色；日志和机器响应保留纯文本。
# 仅用于终端URL展示，不改变调用者数据。
function Test-JobsEnterChoiceColor {
    param([Collections.IDictionary]$Capabilities = $null)
    if ($null -eq $Capabilities) {
        try {
            $environment = [Environment]::GetEnvironmentVariables('Process')
            $Capabilities = @{ HostName = $Host.Name; InputRedirected = [Console]::IsInputRedirected; OutputRedirected = [Console]::IsOutputRedirected;
                               ErrorRedirected = [Console]::IsErrorRedirected; NoColorPresent = $environment.Contains('NO_COLOR');
                               PlainOutput = $env:PLAIN_OUTPUT; Term = $env:TERM; Windows = ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT); VirtualTerminal = $false; SourceTree = ($env:IS_SOURCETREE_RUNTIME -eq '1') }
            if ($null -ne $Host.UI.PSObject.Properties['SupportsVirtualTerminal']) { $Capabilities.VirtualTerminal = $Host.UI.SupportsVirtualTerminal }
            foreach ($key in $environment.Keys) { if ([string]$key -match '^(?i:SOURCE_?TREE)') { $Capabilities.SourceTree = $true; break } }
        } catch { return $false }
    }
    return ($Capabilities.HostName -eq 'ConsoleHost' -and -not $Capabilities.InputRedirected -and -not $Capabilities.OutputRedirected -and
            -not $Capabilities.ErrorRedirected -and -not $Capabilities.NoColorPresent -and $Capabilities.PlainOutput -ne '1' -and
            $Capabilities.Term -ine 'dumb' -and (-not [string]::IsNullOrEmpty($Capabilities.Term) -or ($Capabilities.Contains('Windows') -and $Capabilities.Windows)) -and -not $Capabilities.SourceTree -and $Capabilities.VirtualTerminal)
}
# 仅用于终端URL展示，不改变调用者数据。
function Get-JobsUrlRanges {
    param([string]$Text)
    $pattern = '[A-Za-z][A-Za-z0-9+.-]*://[^\s<>"''\x1b]+'
    $punctuation = '，。；：！？、（）【】《》「」『』“”‘’'
    $offset = 0
    while ($offset -lt $Text.Length) {
        $match = [regex]::Match($Text.Substring($offset), $pattern)
        if (-not $match.Success) { break }
        $start = $offset + $match.Index
        $url = $match.Value
        foreach ($mark in $punctuation.ToCharArray()) {
            $at = $url.IndexOf($mark)
            if ($at -ge 0) { $url = $url.Substring(0, $at) }
        }
        while ($url.Length) {
            $last = $url.Substring($url.Length - 1, 1)
            $unmatched = $false
            foreach ($pair in @(@('(', ')'), @('[', ']'), @('{', '}'))) {
                if ($last -eq $pair[1] -and ([regex]::Matches($url, [regex]::Escape($pair[1]))).Count -gt ([regex]::Matches($url, [regex]::Escape($pair[0]))).Count) { $unmatched = $true }
            }
            if ('. , ; : ! ?'.Split(' ') -contains $last -or $unmatched) { $url = $url.Substring(0, $url.Length - 1) }
            else { break }
        }
        [pscustomobject]@{ Start = $start; End = $start + $url.Length }
        $offset = $start + $url.Length
    }
}
# 仅用于终端URL展示，不改变调用者数据。
function Format-JobsUrlText {
    param([AllowEmptyString()][string]$Text, [switch]$Color)
    $control = '\x1b\][^\x1b\x07]*(?:\x07|\x1b\\)|\x1b\[[0-?]*[ -/]*[@-~]'
    $sgr = '\x1b\[[0-9;:]*m'
    $value = [regex]::Replace($Text, $control, {
        param($match)
        if ($Color -and $match.Value -match ('^' + $sgr + '$')) { return $match.Value }
        return ''
    })
    if (-not $Color) { return $value }
    $styles = @{}; $visible = New-Object Text.StringBuilder; $offset = 0
    foreach ($match in [regex]::Matches($value, $sgr)) {
        [void]$visible.Append($value.Substring($offset, $match.Index - $offset))
        $index = $visible.Length
        if (-not $styles.ContainsKey($index)) { $styles[$index] = '' }
        $styles[$index] += $match.Value
        $offset = $match.Index + $match.Length
    }
    [void]$visible.Append($value.Substring($offset))
    $plain = $visible.ToString(); $starts = @{}; $ends = @{}
    foreach ($range in @(Get-JobsUrlRanges $plain)) { $starts[$range.Start] = $true; $ends[$range.End - 1] = $true }
    $escape = [string][char]27; $active = ''; $inUrl = $false; $output = New-Object Text.StringBuilder
    for ($index = 0; $index -le $plain.Length; $index++) {
        if ($styles.ContainsKey($index)) {
            $tokens = $styles[$index]; [void]$output.Append($tokens)
            foreach ($match in [regex]::Matches($tokens, $sgr)) {
                $token = $match.Value; $code = $token.Substring(2, $token.Length - 3)
                $fields = $code.Split(';'); $reset = $code -eq ''
                for ($item = 0; $item -lt $fields.Count; $item++) {
                    if ($fields[$item] -eq '0') { $reset = $true }
                    if (@('38', '48', '58') -contains $fields[$item] -and $item + 1 -lt $fields.Count) {
                        if ($fields[$item + 1] -eq '2') { $item += 4 }
                        elseif ($fields[$item + 1] -eq '5') { $item += 2 }
                    }
                }
                if ($reset) { $active = '' }
                $active += $token
            }
            if ($inUrl) { [void]$output.Append($escape + '[32;4m') }
        }
        if ($index -eq $plain.Length) { break }
        if ($starts.ContainsKey($index)) { [void]$output.Append($escape + '[32;4m'); $inUrl = $true }
        [void]$output.Append($plain[$index])
        if ($ends.ContainsKey($index)) { [void]$output.Append($escape + '[0m' + $active); $inUrl = $false }
    }
    return $output.ToString()
}
# 仅用于终端URL展示，不改变调用者数据。
function Get-JobsDisplayBaseStyle {
    param([Collections.IDictionary]$Parameters)
    $codes = @{ Black=30; DarkBlue=34; DarkGreen=32; DarkCyan=36; DarkRed=31; DarkMagenta=35; DarkYellow=33; Gray=37; DarkGray=90; Blue=94; Green=92; Cyan=96; Red=91; Magenta=95; Yellow=93; White=97 }
    $style = ''; $escape = [string][char]27
    if ($Parameters.ContainsKey('ForegroundColor')) { $style += $escape + '[' + $codes[[string]$Parameters.ForegroundColor] + 'm' }
    if ($Parameters.ContainsKey('BackgroundColor')) { $style += $escape + '[' + ($codes[[string]$Parameters.BackgroundColor] + 10) + 'm' }
    return $style
}
# 单次绘制URL并保存纯文本信息记录，兼容原Write-Host参数。
function Write-JobsUrlText {
    [CmdletBinding()]
    param([Parameter(Position=0)][AllowNull()][object]$Object, [switch]$NoNewline, [ConsoleColor]$ForegroundColor, [ConsoleColor]$BackgroundColor, [object]$Separator = ' ')
    $text = if ($Object -is [array]) { $Object -join [string]$Separator } else { [string]$Object }
    $plain = Format-JobsUrlText $text
    if (-not (Test-JobsEnterChoiceColor)) { Write-Host $plain -NoNewline:$NoNewline; return }
    $baseStyle = Get-JobsDisplayBaseStyle $PSBoundParameters
    $rendered = Format-JobsUrlText ($baseStyle + $text + ([string][char]27+'[0m')) -Color
    $message = New-Object Management.Automation.HostInformationMessage
    $message.Message = $plain
    $message.NoNewLine = [bool]$NoNewline
    if ($PSBoundParameters.ContainsKey('ForegroundColor')) { $message.ForegroundColor = $ForegroundColor }
    if ($PSBoundParameters.ContainsKey('BackgroundColor')) { $message.BackgroundColor = $BackgroundColor }
    Write-Information -MessageData $message -Tags 'JobsDisplay' -InformationAction SilentlyContinue
    [Console]::Write($rendered)
    if (-not $NoNewline) { [Console]::WriteLine() }
}

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:ProxyOwner='Jobs.GitDynamicProxy.v1'
# Separate runtime from menu releases, so menu updates do not replace live Git.
function Get-JobsProxyPaths {
    $root=Join-Path $env:LOCALAPPDATA 'JobsGitNetworkStrategy'
    return @{Root=$root;Bin=(Join-Path $root 'runtime/bin');Active=(Join-Path $root 'active.clixml');Snapshots=(Join-Path $root 'snapshots');Log=(Join-Path $root 'install.log')}
}
# This one current-user value is the only environment configuration we change.
function Read-JobsProxyUserPath {
    $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
    if ($null -eq $key) { return @{Exists=$false;Kind='ExpandString';Value=''} }
    try {
        if ('Path' -notin @($key.GetValueNames())) { return @{Exists=$false;Kind='ExpandString';Value=''} }
        $kind=$key.GetValueKind('Path').ToString()
        if ($kind -notin @('String','ExpandString')) { throw '用户 PATH 类型未知，停止修改。' }
        return @{Exists=$true;Kind=$kind;Value=[string]$key.GetValue('Path',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}
    } finally { $key.Dispose() }
}
# Restore missing, empty and typed values without clearing other environment entries.
function Write-JobsProxyUserPath {
    param($State)
    $key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
    try {
        if ($State.Exists) { $key.SetValue('Path',[string]$State.Value,[Microsoft.Win32.RegistryValueKind]([Enum]::Parse([Microsoft.Win32.RegistryValueKind],$State.Kind))) }
        else { $key.DeleteValue('Path',$false) }
    } finally { $key.Dispose() }
}
# Snapshots can contain PATH; restrict the directory to the current user.
function New-JobsProxyPrivateDirectory {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        $item=Get-Item -LiteralPath $Path -Force
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw '配置路径不是可信普通目录。' }
    } else { [void][IO.Directory]::CreateDirectory($Path) }
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        $identity=[Security.Principal.WindowsIdentity]::GetCurrent().User
        $acl=New-Object Security.AccessControl.DirectorySecurity
        $acl.SetAccessRuleProtection($true,$false)
        $rule=New-Object Security.AccessControl.FileSystemAccessRule($identity,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
        $acl.AddAccessRule($rule)
        [IO.Directory]::SetAccessControl($Path,$acl)
    }
}
# Links, directories and unknown additions prevent replacement of the runtime.
function Get-JobsProxyRuntimeFiles {
    param([string]$Directory)
    $files=@{}
    if (-not (Test-Path -LiteralPath $Directory)) { return $files }
    $root=Get-Item -LiteralPath $Directory -Force
    if (-not $root.PSIsContainer -or ($root.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw '运行态目录不是普通目录。' }
    $allowed=@('git.exe','Policy.ps1','NetworkPolicy.psm1','real-git.path','OpenGitCmd.cmd','OpenGitPowerShell.cmd','owner.json')
    foreach ($item in Get-ChildItem -LiteralPath $Directory -Force) {
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.Name -notin $allowed) { throw '运行态存在未知或链接条目，停止覆盖。' }
        $files[$item.Name]=[Convert]::ToBase64String([IO.File]::ReadAllBytes($item.FullName))
    }
    return $files
}
# 区分源码包装与原生 Git 回调产物，运行态文件名继续满足 Shim 固定契约。
function Get-JobsProxySourcePath {
    param([string]$Name)
    $relative = if ($Name -eq 'Policy.ps1') { 'Policy.ps1/Policy.ps1' } else { $Name }
    return (Join-Path $PSScriptRoot $relative)
}
# Stable source digests avoid recompiling or creating snapshots on repeat installs.
function Get-JobsProxySourceHash {
    $values=@()
    foreach ($name in @('GitShim.cs','Policy.ps1','NetworkPolicy.psm1')) {
        $path=Get-JobsProxySourcePath $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw ('独立包缺少运行源码：'+$name) }
        $values += (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
    return ($values -join ':')
}
# Find a real executable outside our runtime; never replace a Git installation.
# 将选择器诊断交给当前业务日志，先剥离控制码并脱敏展示地址。
function Write-JobsFzfStatus {
    [CmdletBinding()]
    param([string]$Text)
    $plain = $Text -replace '\x1b\][^\x07]*(?:\x07|\x1b\\)', '' -replace '\x1b\[[0-?]*[ -/]*[@-~]', ''
    $plain = $plain -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@' -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]'
    foreach ($name in @('Write-JobsHarmonyMessage', 'Write-JobsPackagerMessage', 'Write-JobsLog', 'Write-JobsUrlText')) {
        $writer = Get-Command $name -CommandType Function -ErrorAction SilentlyContinue
        if ($writer) { & $writer $plain; return }
    }
    Write-Host $plain
}

# 复用现有 Windows argv 引号规则，不通过命令字符串求值。
function ConvertTo-JobsFzfArgument {
    param([AllowNull()][AllowEmptyString()][string]$Value)
    if ($null -eq $Value) { $Value = '' }
    if ($Value.IndexOf([char]0) -ge 0) { throw '参数不能包含空字符。' }
    $quoted = New-Object Text.StringBuilder
    [void]$quoted.Append('"')
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq [char]92) { $slashes++; continue }
        if ($character -eq [char]34) {
            [void]$quoted.Append([char]92, (2 * $slashes + 1))
            [void]$quoted.Append([char]34)
        } else {
            if ($slashes -gt 0) { [void]$quoted.Append([char]92, $slashes) }
            [void]$quoted.Append($character)
        }
        $slashes = 0
    }
    if ($slashes -gt 0) { [void]$quoted.Append([char]92, (2 * $slashes)) }
    [void]$quoted.Append('"')
    return $quoted.ToString()
}

# 仅清理本次启动的 fzf；探针有单次上限，交互沿原终端运行，不改父进程环境。
function Invoke-JobsFzfProcess {
    param([string]$Executable, [string[]]$NativeArguments, [string[]]$InputLines = @(), [switch]$Probe)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Executable
    $start.Arguments = (@($NativeArguments | ForEach-Object { ConvertTo-JobsFzfArgument $_ }) -join ' ')
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = [bool]$Probe
    $start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    if ($Probe) { $start.StandardErrorEncoding = New-Object Text.UTF8Encoding($false) }
    foreach ($key in @('FZF_DEFAULT_OPTS', 'FZF_DEFAULT_OPTS_FILE', 'FZF_DEFAULT_COMMAND')) { [void]$start.EnvironmentVariables.Remove($key) }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = if ($Probe) { $process.StandardError.ReadToEndAsync() } else { $null }
        $inputWriter = New-Object IO.StreamWriter($process.StandardInput.BaseStream, (New-Object Text.UTF8Encoding($false)))
        $inputWriter.NewLine = "`n"
        try { foreach ($line in $InputLines) { $inputWriter.WriteLine($line) } } finally { $inputWriter.Dispose() }
        if ($Probe) {
            if (-not $process.WaitForExit(10000)) {
                $process.Kill(); $process.WaitForExit()
                return [pscustomobject]@{ Code = 124; Lines = @(); Error = 'fzf 健康探针超时（10 秒）。' }
            }
        } else { $process.WaitForExit() }
        $output = $outputTask.GetAwaiter().GetResult()
        $errorText = if ($errorTask) { $errorTask.GetAwaiter().GetResult() } else { '' }
        $lines = @()
        if ($output.Length -gt 0) { $lines = @($output.Replace("`r`n", "`n").TrimEnd([char]10) -split "`n") }
        return [pscustomobject]@{ Code = $process.ExitCode; Lines = $lines; Error = $errorText }
    } finally {
        try { if ($process.Id -gt 0 -and -not $process.HasExited) { $process.Kill(); $process.WaitForExit() } } catch { }
        $process.Dispose()
    }
}

# 只刷新本次进程的工具搜索路径，不改写用户或系统 PATH。
function Update-JobsProcessPath {
    param([string]$ExecutableDirectory)
    $parts = New-Object 'Collections.Generic.List[string]'
    $separator = [IO.Path]::PathSeparator
    foreach ($value in @($ExecutableDirectory, [Environment]::GetEnvironmentVariable('Path', 'User'), [Environment]::GetEnvironmentVariable('Path', 'Machine'), $env:Path)) {
        foreach ($part in @(([string]$value) -split [regex]::Escape([string]$separator))) {
            if (-not [string]::IsNullOrWhiteSpace($part) -and -not $parts.Contains($part)) { $parts.Add($part) }
        }
    }
    $env:Path = $parts -join [string]$separator
}

# 查找当前用户已就绪的原生包管理器；只读调用不注册或安装组件。
function Find-JobsWinget {
    $command = Get-Command 'winget.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $candidates = @()
    if ($command) { $candidates += $command.Source }
    if ($env:LOCALAPPDATA) { $candidates += Join-Path $env:LOCALAPPDATA 'Microsoft/WindowsApps/winget.exe' }
    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if (-not [IO.File]::Exists($candidate)) { continue }
        try { $probe = Invoke-JobsFzfProcess $candidate @('--version') -Probe; if ($probe.Code -eq 0) { return $candidate } } catch [Management.Automation.PipelineStoppedException] { throw } catch { }
    }
    return $null
}

# 必需依赖才恢复当前用户 App Installer 注册或打开一次官方安装界面，并在原流程等待就绪。
function Get-JobsRequiredWinget {
    $winget = Find-JobsWinget
    if ($winget) { return $winget }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw '当前不是 Windows，未调用 App Installer 或安装 Windows 依赖。' }
    Write-JobsFzfStatus '本次需要 Windows 原生 App Installer/winget；仅注册当前用户已有组件，不接受许可或修改系统策略。'
    $registration = Get-Command Add-AppxPackage -ErrorAction SilentlyContinue
    if ($registration -and $registration.Parameters.ContainsKey('RegisterByFamilyName')) {
        try { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop } catch { Write-JobsFzfStatus ('App Installer 注册未就绪：' + $_.Exception.Message) }
        $winget = Find-JobsWinget
        if ($winget) { Update-JobsProcessPath ([IO.Path]::GetDirectoryName($winget)); return $winget }
    }
    Write-JobsFzfStatus '官方 App Installer：https://apps.microsoft.com/detail/9NBLGGH4NNS1；将打开一次官方页面。请按系统要求完成安装/许可，本入口持续复检并续行，Ctrl+C 停止等待。'
    Start-Process -FilePath 'ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1' -ErrorAction Stop | Out-Null
    while ($true) {
        Update-JobsProcessPath
        $winget = Find-JobsWinget
        if ($winget) { return $winget }
        Write-JobsFzfStatus '等待官方 App Installer 安装和当前用户注册；不会重复打开窗口，Ctrl+C 取消。'
        Start-Sleep -Seconds 3
    }
}

# 调用原生包管理器处理精确包，保留许可交互；原输出仅经脱敏展示，不用作选择结果。
function Invoke-JobsWingetPackage {
    param([string]$Winget, [string]$Package, [ValidateSet('install','upgrade','repair')][string]$Mode = 'install')
    $arguments = @($Mode, '--id', $Package, '--exact', '--source', 'winget', '--interactive')
    if ($Package -in @('junegunn.fzf','Git.Git')) { $arguments += @('--scope', 'user') }
    $text = New-Object 'Collections.Generic.List[string]'
    $previous = $ErrorActionPreference
    $logFailure = $null
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        $ErrorActionPreference = 'Continue'
        $global:LASTEXITCODE = -1
        & $Winget @arguments 2>&1 | ForEach-Object { $line = [string]$_; $text.Add($line); try { Write-JobsFzfStatus $line -ErrorAction Stop } catch { $logFailure = $_.Exception; throw } }
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previous }
    if ($logFailure) { throw $logFailure }
    return [pscustomobject]@{ Code = $code; Text = $text -join "`n" }
}

# 仅安装/升级代理前补齐必要原生 Git；检查与恢复调用保持只读，不进入本获取器。
# 键盘菜单只返回明确业务项，缺失选择器才在当前交互流程准备。
function Test-JobsFzfPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not [IO.File]::Exists($Path)) { return $false }
    try {
        $version = Invoke-JobsFzfProcess $Path @('--version') -Probe
        if ($version.Code -ne 0) { return $false }
        $marker = '__JOBS_FZF_HEALTH__'
        $probe = Invoke-JobsFzfProcess $Path @('--filter', $marker, '--no-multi', '--sync', '--layout=reverse', '--height=60%', '--border', '--delimiter', "`t", '--with-nth=2..', '--print-query', '--expect=left,space,enter', '--bind=up:up,down:down,tab:down,shift-tab:up,start:pos(1)') @("P`t$marker") -Probe
        return ($probe.Code -eq 0 -and $probe.Lines.Count -gt 0 -and $probe.Lines[-1] -ceq "P`t$marker")
    } catch [Management.Automation.PipelineStoppedException] { throw } catch { return $false }
}

# 键盘菜单只返回明确业务项，缺失选择器才在当前交互流程准备。
function Find-JobsFzf {
    $candidates = New-Object 'Collections.Generic.List[string]'
    foreach ($name in @('fzf.exe', 'fzf')) {
        $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { $candidates.Add($command.Source) }
    }
    if ($env:LOCALAPPDATA) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA 'Microsoft/WinGet/Links/fzf.exe'))
        $packages = Join-Path $env:LOCALAPPDATA 'Microsoft/WinGet/Packages'
        if ([IO.Directory]::Exists($packages)) {
            foreach ($directory in @(Get-ChildItem -LiteralPath $packages -Directory -Filter 'junegunn.fzf*' -ErrorAction SilentlyContinue)) {
                foreach ($file in @(Get-ChildItem -LiteralPath $directory.FullName -File -Recurse -Filter 'fzf.exe' -ErrorAction SilentlyContinue)) { $candidates.Add($file.FullName) }
            }
        }
    }
    if ($env:USERPROFILE) { $candidates.Add((Join-Path $env:USERPROFILE 'scoop/shims/fzf.exe')) }
    if ($env:ChocolateyInstall) { $candidates.Add((Join-Path $env:ChocolateyInstall 'bin/fzf.exe')) }
    foreach ($candidate in @($candidates | Select-Object -Unique)) { if (Test-JobsFzfPath $candidate) { return $candidate } }
    return $null
}

# 键盘菜单只返回明确业务项，缺失选择器才在当前交互流程准备。
function Ensure-JobsFzf {
    param([switch]$CheckOnly)
    $fzf = Find-JobsFzf
    if ($fzf) { if (-not $CheckOnly) { Update-JobsProcessPath ([IO.Path]::GetDirectoryName($fzf)) }; return $fzf }
    if ($CheckOnly) { throw 'fzf 路径、版本或所需选项尚未就绪；只读检查未安装或修复。' }
    if ([Console]::IsInputRedirected -or [Console]::IsErrorRedirected) { throw '键盘选择需要真实交互终端；未获取依赖或执行业务。' }
    Write-JobsFzfStatus '本次键盘选择需要健康 fzf；来源 https://github.com/microsoft/winget-pkgs（junegunn.fzf）。仅在缺失或损坏时获取，许可证仍由本人确认，Ctrl+C 可结束。'
    $winget = Get-JobsRequiredWinget
    $mode = 'install'
    $existing = Get-Command 'fzf.exe', 'fzf' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($existing) { $mode = 'repair' }
    $attempt = 0; $delay = 1
    while ($true) {
        $attempt++
        Write-JobsFzfStatus ("必需 fzf：$mode，第 $attempt 次；网络失败持续重试，不设总次数，Ctrl+C 结束。")
        $result = Invoke-JobsWingetPackage $winget 'junegunn.fzf' $mode
        if ($result.Code -in @(130, 1223, 1602, -1073741510, -2147023673)) { throw (New-Object OperationCanceledException('已取消 fzf 获取。')) }
        if ($result.Code -eq 0) {
            Update-JobsProcessPath
            $fzf = Find-JobsFzf
            if ($fzf) { Update-JobsProcessPath ([IO.Path]::GetDirectoryName($fzf)); Write-JobsFzfStatus ('fzf 已通过当前进程复检：' + $fzf); return $fzf }
            if ($mode -eq 'install') { $mode = 'repair'; Write-JobsFzfStatus '安装返回成功但选项复检失败，在同一流程尝试官方精确修复。'; continue }
            throw 'fzf 安装及官方修复后仍未通过实际选项复检；保留原错误，未进入业务。'
        }
        if ($result.Text -match '(?i)permission|access.denied|no.space|disk.full|hash|checksum|certificate|unauthor|license|agreement|unsupported|not.supported|unknown.command|unrecognized|no.applicable|not.found|权限|拒绝|空间不足|许可|协议|不支持|未知命令|无法找到|无适用') {
            $safeFailure = $result.Text -replace '\x1b\][^\x07]*(?:\x07|\x1b\\)', '' -replace '\x1b\[[0-?]*[ -/]*[@-~]', ''
            $safeFailure = $safeFailure -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@' -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]'
            throw ('必需 fzf 遇到确定的权限、许可、包或版本阻塞，退出码 ' + $result.Code + '；未继续业务。' + [Environment]::NewLine + $safeFailure)
        }
        Write-JobsFzfStatus ("fzf 获取失败，退出码 $($result.Code)；$delay 秒后继续本次流程。")
        Start-Sleep -Seconds $delay
        $delay = [Math]::Min(30, $delay * 2)
    }
}

# 键盘菜单只返回明确业务项，缺失选择器才在当前交互流程准备。
function Select-JobsFzfItems {
    param([string]$Title, [object[]]$Items, [switch]$Multiple, [switch]$Child, [switch]$RequireConfirmation, [hashtable]$State = $null)
    if ($Items.Count -eq 0) { return [pscustomobject]@{ Action = 'empty'; Items = @() } }
    if ($Items.Count -eq 1 -and -not $Multiple -and -not $RequireConfirmation) { return [pscustomobject]@{ Action = 'selected'; Items = @($Items[0]) } }
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected -or [Console]::IsErrorRedirected) { throw '键盘菜单需要完整交互终端；未安装依赖或继续业务。' }
    $environment = [Environment]::GetEnvironmentVariables('Process')
    foreach ($key in $environment.Keys) { if ([string]$key -match '^(?i:SOURCE_?TREE)') { throw 'Sourcetree 动作进程不能等待菜单；请按已声明的终端入口或明确参数执行。' } }
    $fzf = Ensure-JobsFzf
    $selected = New-Object 'Collections.Generic.HashSet[int]'
    $query = ''; $position = 1
    if ($null -ne $State) {
        if ($State.ContainsKey('Query')) { $query = [string]$State.Query }
        if ($State.ContainsKey('Position')) { $position = [Math]::Max(1, [int]$State.Position) }
        if ($State.ContainsKey('Checked')) {
            foreach ($savedIndex in @($State.Checked)) {
                if ([int]$savedIndex -ge 0 -and [int]$savedIndex -lt $Items.Count) { [void]$selected.Add([int]$savedIndex) }
            }
        }
    }
    while ($true) {
        $rows = New-Object 'Collections.Generic.List[string]'
        $rows.Add("C`t× 取消本轮")
        if ($Child) { $rows.Add("B`t← 返回上一层") }
        if ($Multiple) {
            $rows.Add("K`t确认已勾选（$($selected.Count) 项）")
            $rows.Add("A`t全选本轮全部项目")
            $rows.Add("Z`t清空已勾选")
        }
        for ($index = 0; $index -lt $Items.Count; $index++) {
            $display = ([string]$Items[$index]) -replace '[\r\n\t]', ' '
            if ($Multiple) { $display = $(if ($selected.Contains($index)) { '[✓] ' } else { '[ ] ' }) + $display }
            $rows.Add("D$index`t$display")
        }
        $navigation = if ($Child) { '← 返回上一层' } else { '← 取消' }
        $header = if ($Multiple) { "↑/↓ 或 Tab 导航；回车勾选/取消，空格确认；$navigation；操作行回车执行；Esc / Ctrl+C 取消" } else { "↑/↓ 或 Tab 导航；回车确认；$navigation；Esc / Ctrl+C 取消" }
        $position = [Math]::Min($position, $rows.Count)
        $arguments = @('--no-multi', '--sync', '--layout=reverse', '--height=60%', '--border', '--delimiter', "`t", '--with-nth=2..', '--print-query', '--expect=left,space,enter', ('--bind=up:up,down:down,tab:down,shift-tab:up,start:pos(' + $position + ')'), ('--prompt=' + $Title + ' > '), ('--header=' + $header), ('--query=' + $query))
        if ($environment.Contains('NO_COLOR') -or $env:PLAIN_OUTPUT -eq '1' -or $env:TERM -ieq 'dumb') { $arguments += @('--color=bw', '--no-bold') }
        $result = Invoke-JobsFzfProcess $fzf $arguments @($rows)
        $lines = @($result.Lines)
        $query = if ($lines.Count -gt 0) { [string]$lines[0] } else { '' }
        $key = if ($lines.Count -gt 1) { [string]$lines[1] } else { '' }
        if ($null -ne $State) { $State.Query = $query; $State.Checked = @($selected) }
        if ($key -ceq 'left') { return [pscustomobject]@{ Action = $(if ($Child) { 'back' } else { 'cancel' }); Items = @() } }
        if ($result.Code -in @(1, 130)) { return [pscustomobject]@{ Action = 'cancel'; Items = @() } }
        if ($result.Code -ne 0) { throw ('fzf 选择失败，退出码：' + $result.Code) }
        $record = if ($lines.Count -eq 3) { [string]$lines[2] } else { '' }
        if (-not $rows.Contains($record)) { throw '选择结果不属于本轮显示清单，未执行业务。' }
        $position = $rows.IndexOf($record) + 1
        if ($null -ne $State) { $State.Position = $position }
        $tag = ($record -split "`t", 2)[0]
        if ($tag -ceq 'C') { return [pscustomobject]@{ Action = 'cancel'; Items = @() } }
        if ($tag -ceq 'B') { return [pscustomobject]@{ Action = 'back'; Items = @() } }
        if ($Multiple) {
            if ($tag -ceq 'K' -or $key -ceq 'space') {
                $chosen = @()
                for ($index = 0; $index -lt $Items.Count; $index++) { if ($selected.Contains($index)) { $chosen += $Items[$index] } }
                return [pscustomobject]@{ Action = $(if ($chosen.Count) { 'selected' } else { 'empty' }); Items = $chosen }
            }
            if ($tag -ceq 'A') { for ($index = 0; $index -lt $Items.Count; $index++) { [void]$selected.Add($index) }; if ($null -ne $State) { $State.Checked = @($selected) }; continue }
            if ($tag -ceq 'Z') { $selected.Clear(); if ($null -ne $State) { $State.Checked = @() }; continue }
        }
        if ($tag -notmatch '^D([0-9]+)$') { throw '选择器返回无效操作行。' }
        $index = [int]$Matches[1]
        if (-not $Multiple) { return [pscustomobject]@{ Action = 'selected'; Items = @($Items[$index]) } }
        if ($selected.Contains($index)) { [void]$selected.Remove($index) } else { [void]$selected.Add($index) }
        if ($null -ne $State) { $State.Checked = @($selected) }
    }
}

# 配置、检查和恢复由真实动作表选择，默认取消，不再用空回车执行写操作。
function Select-JobsProxyConfigurationMode {
    $choice=Select-JobsFzfItems 'Git 动态入口用途（默认取消）' @('安装 / 更新当前用户动态入口','只读检查','精确恢复最新配置') -RequireConfirmation
    if($choice.Action -cne 'selected'){return $null}
    switch([string]$choice.Items[0]){
        '安装 / 更新当前用户动态入口'{return 'Install'}
        '只读检查'{return 'Check'}
        '精确恢复最新配置'{return 'Restore'}
        default{throw '用途不属于当前动作表，未修改配置。'}
    }
}

function Get-JobsRequiredProxyRealGit {
    param([string]$Runtime,[string]$TrustedGit='')
    if($TrustedGit -and [IO.File]::Exists($TrustedGit) -and -not [IO.Path]::GetFullPath($TrustedGit).StartsWith([IO.Path]::GetFullPath($Runtime),[StringComparison]::OrdinalIgnoreCase)){
        try{
            $probe=Invoke-JobsFzfProcess $TrustedGit @('--version') -Probe
            if($probe.Code -eq 130){throw (New-Object OperationCanceledException('原生 Git 体检已取消。'))}
            if($probe.Code -eq 0 -and ($probe.Lines -join "`n") -match '^git version '){return [IO.Path]::GetFullPath($TrustedGit)}
        }catch [Management.Automation.PipelineStoppedException]{throw}catch [OperationCanceledException]{throw}catch{}
    }
    try { return Find-JobsProxyRealGit $Runtime }
    catch [Management.Automation.PipelineStoppedException] { throw }
    catch {
        if (-not $_.Exception.Data.Contains('JobsProxyGitMissing')) { throw }
    }
    Write-JobsUrlText '当前已选安装 Git 动态入口，需要健康原生 Git for Windows；仅缺失/损坏时由 winget 精确获取 Git.Git（当前用户），许可由本人处理，Ctrl+C 停止。'
    $winget=Get-JobsRequiredWinget
    $mode='install';$delay=1
    $existing=Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue|Where-Object{-not [IO.Path]::GetFullPath($_.Source).StartsWith([IO.Path]::GetFullPath($Runtime),[StringComparison]::OrdinalIgnoreCase)}|Select-Object -First 1
    if($existing){$mode='repair'}
    while($true){
        $result=Invoke-JobsWingetPackage $winget 'Git.Git' $mode
        if($result.Code -in @(130,1223,1602,-1073741510,-2147023673)){throw (New-Object OperationCanceledException('Git 必要获取已取消，未写代理配置。'))}
        if($result.Code -eq 0){
            Update-JobsProcessPath
            try { return Find-JobsProxyRealGit $Runtime }
            catch [Management.Automation.PipelineStoppedException] { throw }
            catch {
                if(-not $_.Exception.Data.Contains('JobsProxyGitMissing')){throw}
                if($mode -ceq 'install'){$mode='repair';Write-JobsUrlText 'Git 安装返回成功但原生版本复检未通过；当前流程精确修复一次，不切换未知 Git。';continue}
                throw 'Git 获取及精确修复后仍未通过路径/版本复检；未写代理配置或要求另开终端绕过。'
            }
        }
        Write-JobsFzfStatus $result.Text
        if($result.Code -in @(126,127) -or $result.Text -match '(?i)permission|access.denied|no.space|disk.full|hash|checksum|certificate|unauthor|license|agreement|unsupported|not.supported|unknown.command|unrecognized|no.applicable|not.found|权限|拒绝|空间不足|许可|协议|不支持|未知命令|无法找到|无适用'){
            throw ('必需 Git 遇到确定本地、版本、权限或许可阻塞，退出码 '+$result.Code+'；未写代理配置。')
        }
        Write-JobsUrlText ("Git 获取网络未完成，$delay 秒后在本流程重试；Ctrl+C 停止，不重复确认下载。")
        Start-Sleep -Seconds $delay;$delay=[Math]::Min(30,$delay*2)
    }
}

function Find-JobsProxyRealGit {
    param([string]$Runtime)
    $candidates=@(Get-Command git.exe -CommandType Application -All -ErrorAction SilentlyContinue | ForEach-Object { $_.Source })
    foreach ($base in @($env:ProgramFiles,([Environment]::GetEnvironmentVariable('ProgramFiles(x86)')),$env:LOCALAPPDATA)) {
        if ($base) { $candidates += Join-Path $base 'Git/cmd/git.exe'; $candidates += Join-Path $base 'Programs/Git/cmd/git.exe' }
    }
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (-not $candidate -or [IO.Path]::GetFullPath($candidate).StartsWith([IO.Path]::GetFullPath($Runtime),[StringComparison]::OrdinalIgnoreCase)) { continue }
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $probe=Invoke-JobsFzfProcess $candidate @('--version') -Probe
        if($probe.Code -in @(130,1223,1602,-1073741510,-2147023673)){throw (New-Object OperationCanceledException('原生 Git 路径体检已取消；未获取依赖或写代理配置。'))}
        if ($probe.Code -eq 0 -and ($probe.Lines -join "`n") -match '^git version ') { return [IO.Path]::GetFullPath($candidate) }
    }
    $missing=New-Object InvalidOperationException('未找到健康的原生 Git for Windows；本次检查未安装或改变环境。')
    $missing.Data['JobsProxyGitMissing']=$true
    throw $missing
}
# Framework CodeDOM builds a true console EXE that GUI clients can select.
function Build-JobsProxyShim {
    param([string]$Output)
    Add-Type -Path (Join-Path $PSScriptRoot 'GitShim.cs') -OutputAssembly $Output -OutputType ConsoleApplication -ErrorAction Stop
    [void][Reflection.AssemblyName]::GetAssemblyName($Output)
}
# Launchers prepend only their own process PATH, ahead of machine Git entries.
function New-JobsProxyStage {
    param([string]$Directory,[string]$RealGit,[string]$Hash)
    New-JobsProxyPrivateDirectory $Directory
    Build-JobsProxyShim (Join-Path $Directory 'git.exe')
    foreach ($name in @('Policy.ps1','NetworkPolicy.psm1')) { Copy-Item -LiteralPath (Get-JobsProxySourcePath $name) -Destination $Directory }
    [IO.File]::WriteAllText((Join-Path $Directory 'real-git.path'),$RealGit,[Text.Encoding]::UTF8)
    $cmd='@echo off'+[Environment]::NewLine+'set "PATH=%~dp0;%PATH%"'+[Environment]::NewLine+'cmd.exe /d /k'+[Environment]::NewLine
    $ps='@echo off'+[Environment]::NewLine+'set "PATH=%~dp0;%PATH%"'+[Environment]::NewLine+
        '"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NoExit'+[Environment]::NewLine
    [IO.File]::WriteAllText((Join-Path $Directory 'OpenGitCmd.cmd'),$cmd,[Text.Encoding]::ASCII)
    [IO.File]::WriteAllText((Join-Path $Directory 'OpenGitPowerShell.cmd'),$ps,[Text.Encoding]::ASCII)
    [IO.File]::WriteAllText((Join-Path $Directory 'owner.json'),(@{Owner=$script:ProxyOwner;SourceHash=$Hash}|ConvertTo-Json),[Text.Encoding]::UTF8)
}
# Compare both registry value and type before any restore writes.
function Test-JobsProxyPathEqual {
    param($Left,$Right)
    return ([bool]$Left.Exists -eq [bool]$Right.Exists -and [string]$Left.Kind -ceq [string]$Right.Kind -and [string]$Left.Value -ceq [string]$Right.Value)
}
# State contains exact binary maps, and never supplies arbitrary restore paths.
function Read-JobsProxyActive {
    param($Paths)
    if (-not (Test-Path -LiteralPath $Paths.Active)) { return $null }
    $item=Get-Item -LiteralPath $Paths.Active -Force
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw '安装状态不可信。' }
    $state=Import-Clixml -LiteralPath $Paths.Active
    if ($state.Owner -cne $script:ProxyOwner -or [string]$state.Snapshot -notmatch '^[0-9A-Za-z-]+$') { throw '安装状态身份不匹配。' }
    return $state
}
# Preserve a byte token so an unrelated state edit is never overwritten.
function Get-JobsProxyActiveToken {
    param($Paths)
    if (-not (Test-Path -LiteralPath $Paths.Active)) { return $null }
    $item=Get-Item -LiteralPath $Paths.Active -Force
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw '安装状态不可信。' }
    return [Convert]::ToBase64String([IO.File]::ReadAllBytes($Paths.Active))
}
function Assert-JobsProxyActiveToken {
    param($Paths,$Expected)
    if ((Get-JobsProxyActiveToken $Paths) -cne $Expected) { throw '安装状态已有并发修改；停止，不覆盖。' }
}
# Serialize away from active, then replace it atomically after the concurrency check.
function Write-JobsProxyActive {
    param($Paths,$State,$Expected)
    $temporary=$Paths.Active+'.new-'+[guid]::NewGuid().ToString('N')
    try {
        $State | Export-Clixml -LiteralPath $temporary -Depth 12
        Assert-JobsProxyActiveToken $Paths $Expected
        if ($null -eq $Expected) { [IO.File]::Move($temporary,$Paths.Active) }
        else { [IO.File]::Replace($temporary,$Paths.Active,[NullString]::Value) }
    } finally { if (Test-Path -LiteralPath $temporary) { [IO.File]::Delete($temporary) } }
}
# A restored upgrade leaves the previous active version in place; do not treat it as unknown.
function Get-JobsProxyEffectiveState {
    param($State)
    $visited=0
    while ($null -ne $State -and $State.Restored) {
        $visited++
        if ($visited -gt 100) { throw '恢复链异常，停止。' }
        $State=$State.Previous
    }
    if ($null -ne $State -and $State.Owner -cne $script:ProxyOwner) { throw '历史状态身份不匹配。' }
    return $State
}
# Exact maps detect modified or extra runtime files.
function Test-JobsProxyFileMapEqual {
    param($Left,$Right)
    if ($Left.Count -ne $Right.Count) { return $false }
    foreach ($name in $Left.Keys) { if (-not $Right.ContainsKey($name) -or $Left[$name] -cne $Right[$name]) { return $false } }
    return $true
}
# Validate all managed fields together before any change.
function Assert-JobsProxyCurrent {
    param($Paths,$State)
    if (-not (Test-JobsProxyPathEqual (Read-JobsProxyUserPath) $State.AfterPath)) { throw '用户 PATH 已有后续修改；停止，不覆盖。' }
    if (-not (Test-JobsProxyFileMapEqual (Get-JobsProxyRuntimeFiles $Paths.Bin) $State.AfterFiles)) { throw '运行态已有后续修改；停止，不覆盖。' }
}
# A failed install may contain either before or after bytes, but never overwrite a concurrent third value.
function Assert-JobsProxyPartialState {
    param($Paths,$State)
    $path=Read-JobsProxyUserPath
    if (-not (Test-JobsProxyPathEqual $path $State.BeforePath) -and -not (Test-JobsProxyPathEqual $path $State.AfterPath)) { throw 'PATH 并发变化，保留快照。' }
    $files=Get-JobsProxyRuntimeFiles $Paths.Bin
    foreach ($name in $files.Keys) {
        $value=$files[$name]
        if ((-not $State.BeforeFiles.ContainsKey($name) -or $State.BeforeFiles[$name] -cne $value) -and
            (-not $State.AfterFiles.ContainsKey($name) -or $State.AfterFiles[$name] -cne $value)) { throw '运行态并发变化，保留快照。' }
    }
}
# Write or delete only known files in the private runtime.
function Set-JobsProxyRuntimeFiles {
    param([string]$Directory,$Files)
    New-JobsProxyPrivateDirectory $Directory
    $current=Get-JobsProxyRuntimeFiles $Directory
    foreach ($name in $current.Keys) { if (-not $Files.ContainsKey($name)) { [IO.File]::Delete((Join-Path $Directory $name)) } }
    foreach ($name in $Files.Keys) {
        if ($name -notin @('git.exe','Policy.ps1','NetworkPolicy.psm1','real-git.path','OpenGitCmd.cmd','OpenGitPowerShell.cmd','owner.json')) { throw '快照包含未知文件名。' }
        $path=Join-Path $Directory $name; $temporary=$path+'.new-'+[guid]::NewGuid().ToString('N')
        [IO.File]::WriteAllBytes($temporary,[Convert]::FromBase64String($Files[$name]))
        try { Move-Item -LiteralPath $temporary -Destination $path -Force } finally { if (Test-Path -LiteralPath $temporary) { [IO.File]::Delete($temporary) } }
    }
}
# Audit excludes original PATH, filesystem arguments and Git credentials.
function Write-JobsProxyInstallAudit {
    param($Paths,[string]$Action,[string]$Result)
    $line=('{0} action={1} result={2}' -f [DateTime]::UtcNow.ToString('o'),$Action,$Result)
    try { [IO.File]::AppendAllText($Paths.Log,$line+[Environment]::NewLine,[Text.Encoding]::UTF8) }
    catch { Write-Warning '配置已完成，但安装审计记录写入失败；请检查配置目录权限。' }
}
# Only an explicit configurator action installs the global user entry.
function Install-JobsGitProxy {
    $paths=Get-JobsProxyPaths; $activeToken=Get-JobsProxyActiveToken $paths
    $previous=Get-JobsProxyEffectiveState (Read-JobsProxyActive $paths); $hash=Get-JobsProxySourceHash
    $real=$null
    if ($previous -and -not $previous.Restored) {
        Assert-JobsProxyCurrent $paths $previous
        $storedGit=[IO.File]::ReadAllText((Join-Path $paths.Bin 'real-git.path'),[Text.Encoding]::UTF8).Trim()
        $real=Get-JobsRequiredProxyRealGit $paths.Bin -TrustedGit $storedGit
        if ($previous.SourceHash -ceq $hash -and [StringComparer]::OrdinalIgnoreCase.Equals($storedGit,$real)) { Update-JobsProcessPath $paths.Bin; Write-Host '当前版本、配置和原生 Git 均已复检，无需重复写入；当前进程 PATH 已刷新。'; return $previous }
    } elseif ((Get-JobsProxyRuntimeFiles $paths.Bin).Count) { throw '存在未知同名运行态，停止覆盖。' }
    if(-not $real){$real=Get-JobsRequiredProxyRealGit $paths.Bin}
    New-JobsProxyPrivateDirectory $paths.Root
    New-JobsProxyPrivateDirectory $paths.Snapshots
    $number=[DateTime]::UtcNow.ToString('yyyyMMddTHHmmss')+'-'+[guid]::NewGuid().ToString('N')
    $stage=Join-Path $paths.Root ('stage-'+$number)
    try {
        New-JobsProxyStage $stage $real $hash
        $beforePath=Read-JobsProxyUserPath
        $afterPath=@{Exists=$true;Kind=$beforePath.Kind;Value=($paths.Bin+';'+[string]$beforePath.Value)}
        $state=@{Owner=$script:ProxyOwner;Snapshot=$number;Restored=$false;SourceHash=$hash;BeforePath=$beforePath;AfterPath=$afterPath;
            BeforeFiles=(Get-JobsProxyRuntimeFiles $paths.Bin);AfterFiles=(Get-JobsProxyRuntimeFiles $stage);Previous=$previous}
        $state | Export-Clixml -LiteralPath (Join-Path $paths.Snapshots ($number+'.clixml')) -Depth 12
        Assert-JobsProxyActiveToken $paths $activeToken
        if ($previous -and -not $previous.Restored) { Assert-JobsProxyCurrent $paths $previous }
        elseif (-not (Test-JobsProxyPathEqual (Read-JobsProxyUserPath) $beforePath)) { throw '用户 PATH 在配置期间变化，停止。' }
        try {
            Set-JobsProxyRuntimeFiles $paths.Bin $state.AfterFiles
            Write-JobsProxyUserPath $state.AfterPath
            Write-JobsProxyActive $paths $state $activeToken
        } catch {
            $failure=$_
            try {
                Assert-JobsProxyPartialState $paths $state
                Set-JobsProxyRuntimeFiles $paths.Bin $state.BeforeFiles
                Write-JobsProxyUserPath $state.BeforePath
            } catch {
                Write-Warning '安装失败且存在未能安全撤回的状态；已保留快照，不强制覆盖。'
            }
            throw $failure
        }
        Update-JobsProcessPath $paths.Bin
        Write-JobsProxyInstallAudit $paths 'install' 'applied'
        Write-JobsUrlText ('Git 动态入口：'+(Join-Path $paths.Bin 'git.exe'))
        Write-Host '当前安装进程的 PATH 已刷新并使用原生 Git 完成复检；新开的子终端可用 OpenGitCmd.cmd / OpenGitPowerShell.cmd，并用检查动作核对实际路径。'
        Write-Host 'Sourcetree 请保存工作并退出后，将 System Git 指向上述真实 git.exe；本工具不修改不确定的应用偏好。'
        return $state
    } finally { if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force } }
}
# Read-only checks do not build, create directories or write audit.
function Test-JobsGitProxyInstallation {
    $paths=Get-JobsProxyPaths; $state=Get-JobsProxyEffectiveState (Read-JobsProxyActive $paths)
    if (-not $state) { Write-Host '当前没有生效中的 Git 动态配置。'; return $false }
    Assert-JobsProxyCurrent $paths $state
    $real=[IO.File]::ReadAllText((Join-Path $paths.Bin 'real-git.path'),[Text.Encoding]::UTF8).Trim()
    if (-not (Test-Path -LiteralPath $real -PathType Leaf)) { throw '原始 Git 路径已失效，请先恢复再重新配置。' }
    Write-JobsUrlText ('配置完整；真实 shim：'+(Join-Path $paths.Bin 'git.exe'))
    $resolved=Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($resolved) { Write-JobsUrlText ('当前进程解析的 Git：'+$resolved.Source) }
    Write-Host 'PATH 与应用选择不等于联网成功；Windows 桌面和远端需另行验证。'
    return $true
}
# Restore the latest operation once, preserving original absence, type and value.
function Restore-JobsGitProxy {
    $paths=Get-JobsProxyPaths; $activeToken=Get-JobsProxyActiveToken $paths; $state=Read-JobsProxyActive $paths
    if (-not $state -or $state.Restored) { Write-Host '没有需要恢复的最新配置。'; return }
    Assert-JobsProxyCurrent $paths $state
    Assert-JobsProxyActiveToken $paths $activeToken
    try {
        Set-JobsProxyRuntimeFiles $paths.Bin $state.BeforeFiles
        Write-JobsProxyUserPath $state.BeforePath
        $state.Restored=$true
        Write-JobsProxyActive $paths $state $activeToken
    } catch {
        $failure=$_
        try {
            Assert-JobsProxyPartialState $paths $state
            Set-JobsProxyRuntimeFiles $paths.Bin $state.AfterFiles
            Write-JobsProxyUserPath $state.AfterPath
        } catch { Write-Warning '恢复失败且存在不能安全回滚的状态；快照仍保留，不强制覆盖。' }
        throw $failure
    }
    $separator=[IO.Path]::PathSeparator
    $env:Path=(@(($env:Path -split [regex]::Escape([string]$separator))|Where-Object{ -not [StringComparer]::OrdinalIgnoreCase.Equals($_.Trim([char]34),$paths.Bin)}) -join [string]$separator)
    Update-JobsProcessPath
    Write-JobsProxyInstallAudit $paths 'restore' 'restored'

    Write-Host '已精确恢复最新配置前的用户 PATH 与运行态，并刷新当前进程；其它已启动应用保留其既有环境。Sourcetree 的 Git 选择继续由本人按原值恢复。'
}
Export-ModuleMember -Function Install-JobsGitProxy, Test-JobsGitProxyInstallation, Restore-JobsGitProxy, Select-JobsProxyConfigurationMode
