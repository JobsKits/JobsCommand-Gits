# Regression.ps1 | JobsCommand@Gits
# Created by Jobs on 2026年10月23日，星期五.
# 仅使用临时仓库、file 传输及隔离 Git 配置，不访问真实项目索引。
[CmdletBinding()]
param()
# BEGIN JOBS_TERMINAL_STYLE_V1 - session-only colors; no profile or registry changes.
function New-JobsTerminalStyleState {
    if ($PSVersionTable.PSVersion.Major -lt 5) { return @{ JobsTerminalPlainFallback = $true; Before = @{} } }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $Host.Name -ne 'ConsoleHost') { return $null }
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected -or [Console]::IsErrorRedirected) { return $null }
    if ((Test-Path Env:NO_COLOR) -or $env:TERM -ieq 'dumb' -or $env:PLAIN_OUTPUT -eq '1') { return $null }
    foreach ($key in [Environment]::GetEnvironmentVariables().Keys) {
        if ([string]$key -match '^(?i:SOURCE_?TREE)') { return $null }
    }
    if (-not ('Jobs.TerminalStyleV1.Native' -as [type])) {
        try {
        Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
namespace Jobs.TerminalStyleV1 {
    public static class Native {
        [StructLayout(LayoutKind.Explicit, Size=20, CharSet=CharSet.Unicode)]
        public struct InputRecord {
            [FieldOffset(0)] public ushort Kind;
            [FieldOffset(4)] public int Down;
            [FieldOffset(8)] public ushort Repeat;
            [FieldOffset(10)] public ushort Key;
            [FieldOffset(12)] public ushort Scan;
            [FieldOffset(14)] public char Character;
            [FieldOffset(16)] public uint Modifiers;
        }
        [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int n);
        [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
        [DllImport("kernel32.dll")] static extern bool GetConsoleMode(IntPtr h, out uint mode);
        [DllImport("kernel32.dll")] static extern bool SetConsoleMode(IntPtr h, uint mode);
        [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h, uint milliseconds);
        [DllImport("kernel32.dll")] static extern bool GetNumberOfConsoleInputEvents(IntPtr h, out uint count);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, ExactSpelling=true)] static extern bool ReadConsoleInputW(IntPtr h, [Out] InputRecord[] records, uint count, out uint read);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, ExactSpelling=true)] static extern bool WriteConsoleInputW(IntPtr h, InputRecord[] records, uint count, out uint written);
        const string OwnerName = "JOBS_TERMINAL_STYLE_WINDOWS_OWNER";
        static readonly string[] Keys = { "10", "11", "4;0", "4;1", "4;2", "4;3", "4;4", "4;5", "4;6", "4;7", "4;8", "4;9", "4;10", "4;11", "4;12", "4;13", "4;14", "4;15" };
        static readonly string[] Hex = { "000000", "ff5f56", "5fd787", "ffd75f", "5fafff", "d787ff", "5fd7ff", "eeeeee", "9e9e9e", "ff8787", "87ffaf", "ffff87", "87bfff", "ffafff", "afffff", "ffffff" };
        static readonly Regex Reply = new Regex("\\x1b\\](?<key>10|11|4;[0-9]{1,2});(?<rgb>rgb:[0-9a-f]{1,4}/[0-9a-f]{1,4}/[0-9a-f]{1,4})(?:\\x07|\\x1b\\\\)", RegexOptions.IgnoreCase);
        public sealed class State {
            public IntPtr Input, Output;
            public uint OutputMode;
            public ConsoleColor Foreground, Background;
            public Dictionary<string,string> Original, Applied;
            public string Owner, PreviousOwner, Recovery;
            public bool Active, ModeChanged, Fallback;
            public Dictionary<string,string> EnvironmentBefore = new Dictionary<string,string>();
        }
        static string Escape(string key, string value) { return "\x1b]" + key + ";" + value + "\x07"; }
        static string Rgb(string hex) { return "rgb:" + hex.Substring(0,2) + "/" + hex.Substring(2,2) + "/" + hex.Substring(4,2); }
        static string Normal(string rgb) {
            string[] parts = rgb.Substring(4).Split('/');
            for (int n=0; n<3; n++) {
                int maximum = (1 << (4 * parts[n].Length)) - 1;
                int value = Convert.ToInt32(parts[n],16);
                parts[n] = ((value * 65535L + maximum/2) / maximum).ToString("x4");
            }
            return String.Join("/",parts);
        }
        // Preserve unrelated key/window records instead of consuming user input during color queries.
        static Dictionary<string,string> Query(State state) {
            uint pending;
            if (!GetNumberOfConsoleInputEvents(state.Input,out pending) || pending != 0) { return null; }
            StringBuilder commands = new StringBuilder();
            foreach (string key in Keys) { commands.Append(Escape(key,"?")); }
            Console.Write(commands.ToString());
            List<InputRecord> records = new List<InputRecord>();
            List<int> characterIndices = new List<int>();
            StringBuilder text = new StringBuilder();
            Dictionary<string,string> result = new Dictionary<string,string>();
            Stopwatch timer = Stopwatch.StartNew();
            try {
                while (timer.ElapsedMilliseconds < 600) {
                    if (result.Count == Keys.Length && GetNumberOfConsoleInputEvents(state.Input,out pending) && pending == 0) { break; }
                    if (WaitForSingleObject(state.Input,20) != 0) { continue; }
                    InputRecord[] item = new InputRecord[1]; uint read;
                    if (!ReadConsoleInputW(state.Input,item,1,out read) || read != 1) { break; }
                    int index = -1;
                    if (item[0].Kind == 1 && item[0].Character != '\0') {
                        if (item[0].Down != 0) { index = text.Length; text.Append(item[0].Character); }
                        else if (text.Length != 0 && text[text.Length-1] == item[0].Character) { index = text.Length-1; }
                    }
                    records.Add(item[0]); characterIndices.Add(index);
                    foreach (Match match in Reply.Matches(text.ToString())) {
                        string key = match.Groups["key"].Value;
                        if (Array.IndexOf(Keys,key) >= 0) { result[key] = match.Groups["rgb"].Value; }
                    }
                }
            } finally {
                bool[] used = new bool[text.Length];
                foreach (Match match in Reply.Matches(text.ToString())) {
                    for (int n=match.Index; n<match.Index+match.Length; n++) { used[n] = true; }
                }
                List<InputRecord> replay = new List<InputRecord>();
                for (int n=0; n<records.Count; n++) {
                    int index = characterIndices[n];
                    if (index < 0 || !used[index]) { replay.Add(records[n]); }
                }
                if (replay.Count != 0) {
                    uint written;
                    if (!WriteConsoleInputW(state.Input,replay.ToArray(),(uint)replay.Count,out written) || written != replay.Count) {
                        Console.Error.WriteLine("[Jobs] Could not replay terminal input; color protection is unavailable.");
                        result.Clear();
                    }
                }
            }
            return result.Count == Keys.Length ? result : null;
        }
        static void Plain(State state) {
            foreach (string key in new string[] { "NO_COLOR", "PLAIN_OUTPUT", "FORCE_COLOR", "CLICOLOR", "ANSI_COLORS_DISABLED" }) {
                state.EnvironmentBefore[key] = Environment.GetEnvironmentVariable(key);
                Environment.SetEnvironmentVariable(key, key == "FORCE_COLOR" || key == "CLICOLOR" ? "0" : "1");
            }
            state.Fallback = true;
        }
        public static void Enter(State state) {
            try {
                state.Input = GetStdHandle(-10); state.Output = GetStdHandle(-11);
                uint inputMode;
                if (!GetConsoleMode(state.Input,out inputMode) || !GetConsoleMode(state.Output,out state.OutputMode)) { Plain(state); return; }
                IntPtr window = GetConsoleWindow();
                if (window == IntPtr.Zero) { Plain(state); return; }
                string identity = window.ToInt64().ToString("x");
                state.PreviousOwner = Environment.GetEnvironmentVariable(OwnerName);
                if (!String.IsNullOrEmpty(state.PreviousOwner)) {
                    string[] owner = state.PreviousOwner.Split(':');
                    int pid; long started;
                    if (owner.Length == 3 && owner[0] == identity && Int32.TryParse(owner[1],out pid) && Int64.TryParse(owner[2],out started)) {
                        try { if (Process.GetProcessById(pid).StartTime.ToUniversalTime().Ticks == started) { return; } } catch {}
                    }
                }
                state.Foreground = Console.ForegroundColor; state.Background = Console.BackgroundColor;
                if ((state.OutputMode & 4) == 0) {
                    if (!SetConsoleMode(state.Output,state.OutputMode | 4)) { Plain(state); return; }
                    state.ModeChanged = true;
                }
                state.Original = Query(state);
                if (state.Original == null) { Restore(state); Plain(state); return; }
                state.Applied = new Dictionary<string,string>();
                state.Applied["10"] = "rgb:ff/ff/ff"; state.Applied["11"] = "rgb:00/00/00";
                for (int n=0; n<16; n++) { state.Applied["4;"+n] = Rgb(Hex[n]); }
                StringBuilder restore = new StringBuilder();
                foreach (string key in Keys) { restore.Append(Escape(key,state.Original[key])); }
                string encoded = Convert.ToBase64String(Encoding.UTF8.GetBytes(restore.ToString()));
                state.Recovery = Path.Combine(Path.GetTempPath(),"JobsTerminalStyle-"+Process.GetCurrentProcess().Id+"-"+Guid.NewGuid().ToString("N")+".ps1");
                string manual = "# Restore only the session colors saved by this Jobs script.\r\n"+
                    "if ([Console]::IsOutputRedirected) { throw 'Run in the original console.' }\r\n"+
                    "Add-Type -Namespace Jobs -Name RecoveryConsole -MemberDefinition '[System.Runtime.InteropServices.DllImport(\"kernel32.dll\")] public static extern System.IntPtr GetStdHandle(int n); [System.Runtime.InteropServices.DllImport(\"kernel32.dll\")] public static extern bool GetConsoleMode(System.IntPtr h, out uint m); [System.Runtime.InteropServices.DllImport(\"kernel32.dll\")] public static extern bool SetConsoleMode(System.IntPtr h, uint m);'\r\n"+
                    "$h = [Jobs.RecoveryConsole]::GetStdHandle(-11); [uint32]$m = 0\r\n"+
                    "if (-not [Jobs.RecoveryConsole]::GetConsoleMode($h, [ref]$m)) { throw 'Run in the original console.' }\r\n"+
                    "try {\r\nif (-not [Jobs.RecoveryConsole]::SetConsoleMode($h, ($m -bor 4))) { throw 'Cannot enable terminal recovery.' }\r\n"+
                    "[Console]::Write([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('"+encoded+"')))\r\n"+
                    "[Console]::ForegroundColor = [ConsoleColor]"+((int)state.Foreground)+"\r\n"+
                    "[Console]::BackgroundColor = [ConsoleColor]"+((int)state.Background)+"\r\n"+
                    "[Console]::Write([string][char]27 + '[39;49m')\r\n"+
                    "} finally { [void][Jobs.RecoveryConsole]::SetConsoleMode($h, $m) }\r\n";
                File.WriteAllText(state.Recovery,manual,new UTF8Encoding(false));
                state.Owner = identity+":"+Process.GetCurrentProcess().Id+":"+Process.GetCurrentProcess().StartTime.ToUniversalTime().Ticks;
                Environment.SetEnvironmentVariable(OwnerName,state.Owner);
                state.Active = true;
                foreach (string key in Keys) { Console.Write(Escape(key,state.Applied[key])); }
                Console.ForegroundColor = ConsoleColor.White; Console.BackgroundColor = ConsoleColor.Black;
                Dictionary<string,string> check = Query(state);
                foreach (string key in Keys) {
                    if (check == null || Normal(check[key]) != Normal(state.Applied[key])) { Restore(state); Plain(state); return; }
                }
            } catch (Exception error) {
                Restore(state); Plain(state);
                Console.Error.WriteLine("[Jobs] Terminal style unavailable: " + error.Message);
            }
        }
        public static void Restore(State state) {
            if (state == null) { return; }
            try {
                if (state.Active) {
                    Dictionary<string,string> current = Query(state);
                    bool complete = current != null;
                    if (current != null) {
                        bool restoreForeground = Console.ForegroundColor == ConsoleColor.White && Normal(current["10"]) == Normal(state.Applied["10"]) && Normal(current["4;15"]) == Normal(state.Applied["4;15"]);
                        bool restoreBackground = Console.BackgroundColor == ConsoleColor.Black && Normal(current["11"]) == Normal(state.Applied["11"]) && Normal(current["4;0"]) == Normal(state.Applied["4;0"]);
                        foreach (string key in Keys) {
                            if (Normal(current[key]) == Normal(state.Applied[key])) { Console.Write(Escape(key,state.Original[key])); }
                            else if (Normal(current[key]) != Normal(state.Original[key])) {
                                complete = false; Console.Error.WriteLine("[Jobs] Kept a concurrent color change: " + key);
                            }
                        }
                        if (restoreForeground) { Console.ForegroundColor = state.Foreground; Console.Write("\x1b[39m"); }
                        if (restoreBackground) { Console.BackgroundColor = state.Background; Console.Write("\x1b[49m"); }
                    }
                    if (complete) {
                        Dictionary<string,string> check = Query(state);
                        foreach (string key in Keys) { if (check == null || Normal(check[key]) != Normal(state.Original[key])) { complete = false; } }
                    }
                    if (complete) { File.Delete(state.Recovery); }
                    else { Console.Error.WriteLine("[Jobs] Color restore needs review. Manual recovery: powershell -NoProfile -File \""+state.Recovery+"\""); }
                }
            } catch (Exception error) {
                Console.Error.WriteLine("[Jobs] Color restore failed: "+error.Message+"; recovery: "+state.Recovery);
            } finally {
                if (state.Owner != null && Environment.GetEnvironmentVariable(OwnerName) == state.Owner) { Environment.SetEnvironmentVariable(OwnerName,state.PreviousOwner); }
                state.Active = false;
                uint currentMode;
                if (state.ModeChanged && GetConsoleMode(state.Output,out currentMode) && currentMode == (state.OutputMode | 4)) { SetConsoleMode(state.Output,state.OutputMode); }
                state.ModeChanged = false;
                if (state.Fallback) {
                    foreach (KeyValuePair<string,string> pair in state.EnvironmentBefore) {
                        string applied = pair.Key == "FORCE_COLOR" || pair.Key == "CLICOLOR" ? "0" : "1";
                        if (Environment.GetEnvironmentVariable(pair.Key) == applied) { Environment.SetEnvironmentVariable(pair.Key,pair.Value); }
                    }
                    state.Fallback = false;
                }
            }
        }
    }
}
'@
        } catch {
            [Console]::Error.WriteLine('[Jobs] Terminal style setup failed; using plain output: ' + $_.Exception.Message)
            return @{ JobsTerminalPlainFallback = $true; Before = @{} }
        }
    }
    return New-Object Jobs.TerminalStyleV1.Native+State
}
# Guard setup is optional; failure keeps business behavior and the user's original terminal settings.
function Start-JobsTerminalStyle {
    param($State)
    if ($State -is [Collections.IDictionary] -and $State.Contains('JobsTerminalPlainFallback')) {
        foreach ($key in @('NO_COLOR', 'PLAIN_OUTPUT', 'FORCE_COLOR', 'CLICOLOR', 'ANSI_COLORS_DISABLED')) {
            $State.Before[$key] = [Environment]::GetEnvironmentVariable($key)
            [Environment]::SetEnvironmentVariable($key, $(if (@('FORCE_COLOR', 'CLICOLOR') -contains $key) { '0' } else { '1' }))
        }
        return
    }
    if ($null -ne $State) { [Jobs.TerminalStyleV1.Native]::Enter($State) }
}
# A finally block also runs for script exit and Ctrl+C; direct .NET calls avoid stopped pipelines.
function Stop-JobsTerminalStyle {
    param($State)
    if ($State -is [Collections.IDictionary] -and $State.Contains('JobsTerminalPlainFallback')) {
        foreach ($key in $State.Before.Keys) {
            $applied = if (@('FORCE_COLOR', 'CLICOLOR') -contains $key) { '0' } else { '1' }
            if ([Environment]::GetEnvironmentVariable($key) -ceq $applied) { [Environment]::SetEnvironmentVariable($key, $State.Before[$key]) }
        }
        return
    }
    if ($null -ne $State) { [Jobs.TerminalStyleV1.Native]::Restore($State) }
}
# END JOBS_TERMINAL_STYLE_V1

$__jobsTerminalStyleState = $null
try {
    if ($MyInvocation.InvocationName -ne '.') {
        $__jobsTerminalStyleState = New-JobsTerminalStyleState
        Start-JobsTerminalStyle $__jobsTerminalStyleState
    }
# BEGIN JOBS_TERMINAL_STYLE_ORIGINAL_BODY
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('Jobs Gits 中文 (fixture) '+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$keys=@('GIT_CONFIG_NOSYSTEM','GIT_CONFIG_GLOBAL','GIT_CONFIG_COUNT','GIT_CONFIG_KEY_0','GIT_CONFIG_VALUE_0','GIT_ALLOW_PROTOCOL','GIT_TERMINAL_PROMPT','GIT_AUTHOR_NAME','GIT_AUTHOR_EMAIL','GIT_COMMITTER_NAME','GIT_COMMITTER_EMAIL')
$saved=@{}
foreach ($key in $keys) { $saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process') }
$env:GIT_CONFIG_NOSYSTEM='1';$env:GIT_CONFIG_GLOBAL=Join-Path $root 'empty-config'
$env:GIT_CONFIG_COUNT='1';$env:GIT_CONFIG_KEY_0='core.hooksPath';$env:GIT_CONFIG_VALUE_0=Join-Path $root 'no-hooks'
$env:GIT_ALLOW_PROTOCOL='file';$env:GIT_TERMINAL_PROMPT='0'
$env:GIT_AUTHOR_NAME='Isolated Test';$env:GIT_COMMITTER_NAME='Isolated Test';$env:GIT_AUTHOR_EMAIL='test@example.invalid';$env:GIT_COMMITTER_EMAIL='test@example.invalid'
$script:assertions=0
# 比较夹具结果，失败保留临时目录供排查。
function Assert-Equal {
    param($Expected,$Actual,[string]$Message)
    $script:assertions++
    if ($Expected -cne $Actual) { throw "$Message；期望=$Expected；实际=$Actual" }
}
# 错误分支必须明确抛错，不能静默继续。
function Assert-Throws {
    param([scriptblock]$Body,[string]$Message)
    $script:assertions++
    try { & $Body; throw '未抛出预期错误' } catch { if ($_.Exception.Message -eq '未抛出预期错误') { throw $Message } }
}
# 创建只有测试身份和测试提交的隔离工作树。
function New-FixtureRepository {
    param([string]$Path,[string]$Remote)
    [void][IO.Directory]::CreateDirectory($Path)
    [void](Invoke-JobsGit $Path @('init','-b','main') -Quiet)
    [IO.File]::WriteAllText((Join-Path $Path 'seed.txt'),'seed')
    [void](Invoke-JobsGit $Path @('add','--','seed.txt') -Quiet)
    [void](Invoke-JobsGit $Path @('commit','-m','fixture seed') -Quiet)
    if ($Remote) { [void](Invoke-JobsGit $Path @('remote','add','origin',$Remote) -Quiet) }
    return (Invoke-JobsGit $Path @('rev-parse','--show-toplevel') -Quiet).Text
}
try {
    $module=Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'GitTools.psm1') -Force -PassThru -DisableNameChecking
    & $module {
        function script:Confirm-JobsYes { param([string]$Message) }
        function script:Select-JobsItem { param([string]$Title,[object[]]$Items) return $Items[0] }
    }
    Assert-Equal 'https://code.example/team/Child.git' (Resolve-JobsGitUrl 'https://code.example/team/Parent.git' '../Child.git') 'HTTPS 相对地址'
    Assert-Equal 'ssh://git@code.example:2222/a/b/Child.git' (Resolve-JobsGitUrl 'ssh://git@code.example:2222/a/b/Parent.git' '../Child.git') 'SSH 端口与 namespace'
    Assert-Equal 'git@code.example:team/Child.git' (Resolve-JobsGitUrl 'git@code.example:team/Parent.git' '../Child.git') 'SCP 地址'
    foreach ($path in @('../escape','a/../escape','a//b','/absolute','.git/config','a>z','CON','folder.')) { Assert-Throws { Resolve-JobsChildPath $root $path } ('应拒绝 '+$path) }
    Assert-Throws { Invoke-JobsNative 'jobs-command-that-does-not-exist-fixture' @('--version') -Quiet } '缺少命令不能复用上次成功退出码'
    $parent=New-FixtureRepository (Join-Path $root '父仓 空格') 'https://code.example/team/Parent.git'
    $consoleEncoding=[Console]::OutputEncoding
    $pipelineEncoding=$OutputEncoding
    try {
        [Console]::OutputEncoding=[Text.Encoding]::ASCII
        $OutputEncoding=[Text.Encoding]::Unicode
        Assert-Equal $parent (Invoke-JobsGit $parent @('rev-parse','--show-toplevel') -Quiet).Text '非 UTF8 终端仍能读取中文 Git 根目录'
        Assert-Equal 20127 ([Console]::OutputEncoding.CodePage) '成功后恢复终端原编码'
        Assert-Equal 1200 $OutputEncoding.CodePage '原生命令保留管道输入编码'
        Assert-Throws { Invoke-JobsGit $parent @('jobs-missing-fixture-command') -Quiet } '原生命令非零退出必须停止'
        Assert-Equal 20127 ([Console]::OutputEncoding.CodePage) '非零退出后恢复终端原编码'
        Assert-Throws { Invoke-JobsNative 'jobs-command-that-does-not-exist-fixture' @('--version') -Quiet } '查找命令失败必须停止'
        Assert-Equal 20127 ([Console]::OutputEncoding.CodePage) '查找命令失败保留终端编码'
    } finally {
        [Console]::OutputEncoding=$consoleEncoding
        $OutputEncoding=$pipelineEncoding
    }
    $child=New-FixtureRepository (Join-Path $parent '子仓 (一)') 'https://code.example/team/Child.git'
    $head=(Invoke-JobsGit $child @('rev-parse','HEAD') -Quiet).Text
    $before=Get-JobsAssociationFingerprint $parent
    & $module { $script:DryRun=$true }
    Invoke-JobsAssociate $parent
    Assert-Equal $before (Get-JobsAssociationFingerprint $parent) '只读关联不得改索引/配置'
    & $module { $script:DryRun=$false }
    Invoke-JobsAssociate $parent
    Assert-Equal '../Child.git' (Get-JobsConfig $parent 'submodule.子仓 (一).url' (Join-Path $parent '.gitmodules')) '登记共享相对地址'
    Assert-Equal $head (Invoke-JobsGit $child @('rev-parse','HEAD') -Quiet).Text '归集保留子仓 HEAD'
    Assert-Equal $true (Test-Path -LiteralPath (Join-Path $child '.git') -PathType Leaf) '归集使用 gitdir 指针'
    [void](Invoke-JobsGit $parent @('commit','-m','register fixture child') -Quiet)
    [IO.File]::WriteAllText((Join-Path $child 'later.txt'),'later')
    [void](Invoke-JobsGit $child @('add','--','later.txt') -Quiet);[void](Invoke-JobsGit $child @('commit','-m','later fixture') -Quiet)
    [void](Invoke-JobsGit $parent @('config','--file',(Join-Path $parent '.gitmodules'),'submodule.子仓 (一).custom','keep-me') -Quiet)
    [void](Invoke-JobsGit $parent @('add','--','.gitmodules') -Quiet)
    Invoke-JobsAssociate $parent
    Assert-Equal $head (((Invoke-JobsGit $parent @('ls-files','--stage','--','子仓 (一)') -Quiet).Text -split ' ')[1]) '增量关联保留已有 gitlink'
    Assert-Equal 'keep-me' (Get-JobsConfig $parent 'submodule.子仓 (一).custom' (Join-Path $parent '.gitmodules')) '保留扩展字段'
    Assert-Equal 'https://code.example/team/Child.git' (Get-JobsConfig $child 'remote.origin.url') '真实 origin 不改为相对地址'
    Invoke-JobsAssociate $parent -Align
    Assert-Equal ((Invoke-JobsGit $child @('rev-parse','HEAD') -Quiet).Text) (((Invoke-JobsGit $parent @('ls-files','--stage','--','子仓 (一)') -Quiet).Text -split ' ')[1]) '对齐采用当前 gitlink'
    $bare=Join-Path $root '远端仓.git'; [void](Invoke-JobsGit '' @('init','--bare','--initial-branch=main',$bare) -Quiet)
    $seed=New-FixtureRepository (Join-Path $root '远端种子') $bare
    [void](Invoke-JobsGit $seed @('push','-u','origin','main') -Quiet)
    $sync=New-FixtureRepository (Join-Path $root '同步父仓') 'https://code.example/team/Sync.git'
    [void](Invoke-JobsGit $sync @('submodule','add','--',$bare,'分类/子仓') -Quiet)
    [void](Invoke-JobsGit $sync @('commit','-m','register local fixture') -Quiet)
    [IO.File]::WriteAllText((Join-Path $seed 'remote-later.txt'),'new')
    [void](Invoke-JobsGit $seed @('add','--','remote-later.txt') -Quiet);[void](Invoke-JobsGit $seed @('commit','-m','remote advance') -Quiet)
    [void](Invoke-JobsGit $seed @('push','origin','main') -Quiet)
    $sub=Join-Path $sync '分类/子仓'
    [void](Invoke-JobsGit $sub @('checkout','--detach') -Quiet)
    Sync-JobsModules $sync 'https://code.example/team/Sync.git' $true
    Assert-Equal 'main' (Invoke-JobsGit $sub @('symbolic-ref','--short','HEAD') -Quiet).Text '同步恢复本地分支'
    Assert-Equal ((Invoke-JobsGit $seed @('rev-parse','HEAD') -Quiet).Text) (Invoke-JobsGit $sub @('rev-parse','HEAD') -Quiet).Text '同步跟随远端最新'
    [IO.File]::WriteAllText((Join-Path $sub 'local-only.txt'),'local')
    [void](Invoke-JobsGit $sub @('add','--','local-only.txt') -Quiet);[void](Invoke-JobsGit $sub @('commit','-m','local only fixture') -Quiet)
    $localHead=(Invoke-JobsGit $sub @('rev-parse','HEAD') -Quiet).Text
    Assert-Throws { Update-JobsBranch $sub $bare 'main' } '独有提交必须阻断'
    Assert-Equal $localHead (Invoke-JobsGit $sub @('rev-parse','HEAD') -Quiet).Text '独有提交保留'
    $moduleText=[IO.File]::ReadAllText((Join-Path $sync '.gitmodules'))
    & $module { $script:DryRun=$true }
    Sync-JobsModules $sync 'https://code.example/team/Sync.git' $true
    Assert-Equal $moduleText ([IO.File]::ReadAllText((Join-Path $sync '.gitmodules'))) '下载预览保留清单'
    & $module { $script:DryRun=$false }
    $fresh=New-FixtureRepository (Join-Path $root '首次下载父仓') 'https://code.example/team/Fresh.git'
    [void](Invoke-JobsGit $fresh @('config','--file',(Join-Path $fresh '.gitmodules'),'submodule.新子仓.path','新子仓') -Quiet)
    [void](Invoke-JobsGit $fresh @('config','--file',(Join-Path $fresh '.gitmodules'),'submodule.新子仓.url',$bare) -Quiet)
    [void](Invoke-JobsGit $fresh @('update-index','--add','--cacheinfo',('160000,'+(Invoke-JobsGit $seed @('rev-parse','HEAD') -Quiet).Text+',新子仓')) -Quiet)
    [void](Invoke-JobsGit $fresh @('add','--','.gitmodules') -Quiet);[void](Invoke-JobsGit $fresh @('commit','-m','fixture manifest') -Quiet)
    Sync-JobsModules $fresh 'https://code.example/team/Fresh.git' $true
    $freshChild=Join-Path $fresh '新子仓'
    Assert-Equal 'main' (Invoke-JobsGit $freshChild @('symbolic-ref','--short','HEAD') -Quiet).Text '首次克隆保持本地分支'
    Assert-Equal ((Invoke-JobsGit $seed @('rev-parse','HEAD') -Quiet).Text) (Invoke-JobsGit $freshChild @('rev-parse','HEAD') -Quiet).Text '首次克隆取得分支最新'
    Assert-Equal $true (Test-Path -LiteralPath (Join-Path $freshChild '.git') -PathType Leaf) '首次克隆归集元数据'
    $badParent=New-FixtureRepository (Join-Path $root '普通文件冲突') 'https://code.example/team/Bad.git'
    $badChild=New-FixtureRepository (Join-Path $badParent 'Child') 'https://code.example/team/Child.git'
    [void](Invoke-JobsGit $badParent @('update-index','--add','--cacheinfo',('100644,'+(Invoke-JobsGit $badParent @('hash-object','seed.txt') -Quiet).Text+',Child/seed.txt')) -Quiet)
    $badBefore=Get-JobsAssociationFingerprint $badParent
    Assert-Throws { Invoke-JobsAssociate $badParent } '普通文件跟踪冲突应停止'
    Assert-Equal $badBefore (Get-JobsAssociationFingerprint $badParent) '关联预检失败不改索引'
    [void](Invoke-JobsGit $fresh @('config','--file',(Join-Path $fresh '.gitmodules'),'submodule.新子仓.branch','branch-does-not-exist') -Quiet)
    $freshHead=(Invoke-JobsGit $freshChild @('rev-parse','HEAD') -Quiet).Text
    Assert-Throws { Sync-JobsModules $fresh 'https://code.example/team/Fresh.git' $true } '不存在的显式分支应停止'
    Assert-Equal $freshHead (Invoke-JobsGit $freshChild @('rev-parse','HEAD') -Quiet).Text '分支失败保留已有 HEAD'
    $remoteFolder=Join-Path $root '重建远端';[void][IO.Directory]::CreateDirectory($remoteFolder)
    foreach ($name in @('JobsCommand-Flutter','JobsCommand-iOS','JobsCommand-Gits','JobsCommand-Others','JobsSh')) {
        [void](Invoke-JobsGit '' @('clone','--bare','--',$seed,(Join-Path $remoteFolder ($name+'.git'))) -Quiet)
    }
    $rebuild=New-FixtureRepository (Join-Path $root '重建父仓') (Join-Path $remoteFolder 'Parent.git')
    [void](Invoke-JobsGit $rebuild @('submodule','add','--',(Join-Path $remoteFolder 'JobsCommand-Flutter.git'),'JobsGenesis@JobsCommand.Flutter') -Quiet)
    [void](Invoke-JobsGit $rebuild @('commit','-m','old fixture module') -Quiet)
    $originalMetadata=(Invoke-JobsGit (Join-Path $rebuild 'JobsGenesis@JobsCommand.Flutter') @('rev-parse','--absolute-git-dir') -Quiet).Text
    $originalMetadataHead=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $originalMetadata 'HEAD')))
    $originalMetadataConfig=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $originalMetadata 'config')))
    Invoke-JobsRebuildModules $rebuild
    Assert-Equal 5 @(Get-JobsModules $rebuild).Count '重建五仓关联完整'
    Assert-Equal 'main' (Invoke-JobsGit (Join-Path $rebuild 'JobsGenesis@JobsCommand.Flutter') @('symbolic-ref','--short','HEAD') -Quiet).Text '重建后保持分支'
    $rebuildGit=(Invoke-JobsGit $rebuild @('rev-parse','--absolute-git-dir') -Quiet).Text
    # 映射只位于每次备份的顶层，不遍历旧 Git 对象和 refs 深层目录。
    $maps=@(foreach ($directory in Get-ChildItem -LiteralPath (Join-Path $rebuildGit 'jobs-submodule-backups') -Directory) {
        $map=Join-Path $directory.FullName 'worktree-metadata-map.json'
        if (Test-Path -LiteralPath $map -PathType Leaf) { Get-Item -LiteralPath $map }
    })
    Assert-Equal 1 $maps.Count '重建保留原路径映射'
    $records=Get-Content -LiteralPath $maps[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Equal $true (Test-Path -LiteralPath $records.MetadataBackup) '重建保留完整旧元数据'
    Assert-Equal $originalMetadata $records.GitDirectory '备份映射保持原始 Git 元数据位置'
    Assert-Equal $originalMetadataHead ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $records.MetadataBackup 'HEAD')))) '备份保留旧 HEAD 原始字节'
    Assert-Equal $originalMetadataConfig ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $records.MetadataBackup 'config')))) '备份保留旧 config 原始字节'
    [void](Invoke-JobsGit $seed @('branch','feature') -Quiet)
    [void](Invoke-JobsGit $seed @('push','origin','feature') -Quiet)
    [void](Invoke-JobsGit $fresh @('config','--file',(Join-Path $fresh '.gitmodules'),'submodule.新子仓.branch','feature') -Quiet)
    [void](Invoke-JobsGit $freshChild @('checkout','--detach') -Quiet)
    Invoke-JobsDownload $freshChild $true
    Assert-Equal 'feature' (Invoke-JobsGit $freshChild @('symbolic-ref','--short','HEAD') -Quiet).Text '游离入口尊重直接父仓显式分支'
    Assert-Equal 'refs/heads/feature' (Get-JobsConfig $freshChild 'branch.feature.merge') '游离入口恢复对应跟踪分支'
    Write-Host "PASS：$script:assertions 项断言；隔离夹具：$root"
} catch { Write-Host "FAIL：隔离夹具保留在 $root"; throw }
finally { foreach ($key in $keys) { [Environment]::SetEnvironmentVariable($key,$saved[$key],'Process') } }

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}
