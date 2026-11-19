#!/usr/bin/env python3
# Created by Jobs on 2026年10月27日，星期二.
"""Exercise persistent download objects and bounded retries without network access."""

from __future__ import annotations

# JOBS_TERMINAL_STYLE_GUARD_V1_BEGIN
# 保存与恢复由监督进程负责；导入本模块时不接管终端。
def _jobs_terminal_style_bootstrap_v1():
    import os as _os
    import base64 as _base64
    import json as _json
    import shutil as _shutil
    import subprocess as _subprocess
    import sys as _sys
    import tempfile as _tempfile

    _entry = _os.path.abspath(__file__)
    if _os.environ.get("JOBS_TERMINAL_STYLE_REEXEC") == _entry:
        _os.environ.pop("JOBS_TERMINAL_STYLE_REEXEC", None)
        return
    if (getattr(_sys, "frozen", False) or not _sys.stdin or not _sys.stdout
            or not _sys.stdin.isatty() or not _sys.stdout.isatty()
            or "NO_COLOR" in _os.environ
            or _os.environ.get("PLAIN_OUTPUT") == "1"
            or _os.environ.get("IS_SOURCETREE_RUNTIME") == "1"
            or any(_key.upper().startswith(("SOURCETREE", "SOURCE_TREE"))
                   for _key in _os.environ)):
        return
    if _os.name != "nt" and (_os.environ.get("TERM", "") in ("", "dumb")
                             or _os.environ.get("TMUX") or _os.environ.get("STY")):
        return
    _original = getattr(_sys, "orig_argv", None)
    _module_start = False
    for _argument in list(_original[1:]) if _original else []:
        if _argument == "--" or _os.path.abspath(_argument) == _entry:
            break
        if _argument in ("-c", "-m"):
            _module_start = True
            break
    if _module_start:
        _os.environ.update(NO_COLOR="1", PLAIN_OUTPUT="1", FORCE_COLOR="0", CLICOLOR="0")
        return
    _command = [_sys.executable] + (list(_original[1:]) if _original else list(_sys.argv))
    _environment = _os.environ.copy()
    _environment["JOBS_TERMINAL_STYLE_REEXEC"] = _entry
    _shell_core = r"""# 临时保护当前终端配色，业务进程自行管理原有退出清理。
jobs_terminal_style_run() {
    # 无法可靠保存原色时，沿用脚本已有的纯文本约定。
    jobs_terminal_style_plain() {
        PLAIN_OUTPUT=1
        NO_COLOR=1
        FORCE_COLOR=0
        CLICOLOR=0
        ANSI_COLORS_DISABLED=1
        npm_config_color=false
        export PLAIN_OUTPUT NO_COLOR FORCE_COLOR CLICOLOR ANSI_COLORS_DISABLED npm_config_color
        if "$@"; then
            jobs_style_exit_status=0
        else
            jobs_style_exit_status=$?
        fi
        exit "$jobs_style_exit_status"
    }
    if [ ! -t 0 ] || [ ! -t 1 ] || [ -z "${TERM:-}" ] ||
       [ "${TERM:-}" = dumb ] || [ "${NO_COLOR+x}" = x ] ||
       [ "${PLAIN_OUTPUT:-0}" = 1 ] || [ "${IS_SOURCETREE_RUNTIME:-0}" = 1 ] ||
       env | LC_ALL=C grep -qiE '^(SOURCETREE|SOURCE_TREE)'; then
        if "$@"; then
            jobs_style_exit_status=0
        else
            jobs_style_exit_status=$?
        fi
        exit "$jobs_style_exit_status"
    fi
    if [ -n "${TMUX:-}${STY:-}" ]; then
        jobs_terminal_style_plain "$@"
    fi
    jobs_style_tty=$(tty 2>/dev/null) || jobs_terminal_style_plain "$@"
    if ! ps -o pgid= -o tpgid= -p "$$" 2>/dev/null |
         LC_ALL=C awk 'NF == 2 && $1 == $2 && $1 > 0 { foreground = 1 } END { exit !foreground }'; then
        jobs_terminal_style_plain "$@"
    fi
    case ${JOBS_TERMINAL_STYLE_OWNER:-} in
        ''|*[!0-9]*) ;;
        *)
            if [ "${JOBS_TERMINAL_STYLE_TTY:-}" = "$jobs_style_tty" ] &&
               kill -0 "$JOBS_TERMINAL_STYLE_OWNER" 2>/dev/null; then
                if "$@"; then
                    jobs_style_exit_status=0
                else
                    jobs_style_exit_status=$?
                fi
                exit "$jobs_style_exit_status"
            fi
            ;;
    esac
    jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_terminal_style_plain "$@"
    jobs_style_saved=''
    jobs_style_saved_rows=''
    jobs_style_applied_rows=''
    jobs_style_changed=0
    jobs_style_applied_complete=0
    jobs_style_query_active=0
    jobs_style_recovery=''
    jobs_style_exit_status=0
    jobs_style_esc=$(printf '\033')
    jobs_style_bel=$(printf '\007')
    # 只接受本次请求对应的 RGB 响应；非协议输入使本次探测失败。
    jobs_terminal_style_query() {
        jobs_style_query_key=$1
        printf '\033]%s;?\007' "$jobs_style_query_key" > /dev/tty || return 1
        jobs_style_reply=''
        for jobs_style_attempt in 1 2 3; do
            jobs_style_piece=$(dd bs=256 count=1 2>/dev/null < /dev/tty)
            jobs_style_reply=$jobs_style_reply$jobs_style_piece
            case $jobs_style_reply in
                *"$jobs_style_bel"|*"$jobs_style_esc\\") break ;;
                '') ;;
                "$jobs_style_esc"*) ;;
                *) break ;;
            esac
        done
        case $jobs_style_reply in
            "$jobs_style_esc]$jobs_style_query_key;rgb:"*"$jobs_style_bel")
                jobs_style_rgb=${jobs_style_reply#"$jobs_style_esc]$jobs_style_query_key;rgb:"}
                jobs_style_rgb=${jobs_style_rgb%"$jobs_style_bel"}
                ;;
            "$jobs_style_esc]$jobs_style_query_key;rgb:"*"$jobs_style_esc\\")
                jobs_style_rgb=${jobs_style_reply#"$jobs_style_esc]$jobs_style_query_key;rgb:"}
                jobs_style_rgb=${jobs_style_rgb%"$jobs_style_esc\\"}
                ;;
            *) return 1 ;;
        esac
        jobs_style_normalized=$(printf '%s\n' "$jobs_style_rgb" | LC_ALL=C awk -F/ '
            NF != 3 { exit 1 }
            {
                for (i = 1; i <= 3; i++) {
                    h = tolower($i)
                    if (length(h) < 1 || length(h) > 4 || h ~ /[^0-9a-f]/) exit 1
                    n = 0
                    for (j = 1; j <= length(h); j++) n = n * 16 + index("0123456789abcdef", substr(h, j, 1)) - 1
                    value[i] = int(n * 65535 / (16 ^ length(h) - 1) + 0.5)
                }
                printf "%d/%d/%d", value[1], value[2], value[3]
            }
        ') || return 1
        [ -n "$jobs_style_normalized" ]
    }
    # 查询可用不代表终端允许改色，按目标值核对实际生效结果。
    jobs_terminal_style_accepts_target() {
        jobs_style_requested_hex=''
        case $1 in
            10|12) jobs_style_requested_hex=ffffff ;;
            11) jobs_style_requested_hex=000000 ;;
            '4;'*)
                jobs_style_requested_index=0
                for jobs_style_requested_color in 000000 ff5f56 5fd787 ffd75f 5fafff d787ff 5fd7ff eeeeee 9e9e9e ff8787 87ffaf ffff87 87bfff ffafff afffff ffffff; do
                    if [ "4;$jobs_style_requested_index" = "$1" ]; then
                        jobs_style_requested_hex=$jobs_style_requested_color
                        break
                    fi
                    jobs_style_requested_index=$((jobs_style_requested_index + 1))
                done
                ;;
        esac
        [ -n "$jobs_style_requested_hex" ] || return 1
        printf '%s|%s\n' "$jobs_style_normalized" "$jobs_style_requested_hex" | LC_ALL=C awk -F'|' '
            function hexbyte(h) {
                return (index("0123456789abcdef", substr(h, 1, 1)) - 1) * 16 + index("0123456789abcdef", substr(h, 2, 1)) - 1
            }
            {
                if (split($1, actual, "/") != 3 || length($2) != 6) exit 1
                for (i = 1; i <= 3; i++) {
                    difference = actual[i] - hexbyte(substr($2, i * 2 - 1, 2)) * 257
                    if (difference < -255 || difference > 255) exit 1
                }
            }
        '
    }
    # 检测到后续改色时只恢复仍由本次保护持有的项，保留独立恢复入口。
    jobs_terminal_style_cleanup() {
        jobs_style_result=$1
        trap '' HUP INT TERM
        if [ "$jobs_style_query_active" = 1 ]; then
            stty "$jobs_style_stty" 2>/dev/null < /dev/tty || :
            jobs_style_query_active=0
        fi
        if [ "$jobs_style_changed" = 1 ]; then
            jobs_style_cleanup_ok=0
            jobs_style_conflicts=''
            jobs_style_restore_safe=''
            if [ "$jobs_style_applied_complete" = 1 ]; then
                jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_style_stty=''
                if [ -n "$jobs_style_stty" ] && stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then
                    jobs_style_query_active=1
                    jobs_style_cleanup_ok=1
                    while IFS='|' read -r jobs_style_key jobs_style_expected jobs_style_original; do
                        [ -n "$jobs_style_key" ] || continue
                        if ! jobs_terminal_style_query "$jobs_style_key"; then
                            jobs_style_cleanup_ok=0
                            break
                        fi
                        if [ "$jobs_style_normalized" = "$jobs_style_expected" ]; then
                            jobs_style_restore_safe=$jobs_style_restore_safe$jobs_style_original
                        else
                            jobs_style_conflicts="$jobs_style_conflicts $jobs_style_key"
                        fi
                    done <<JOBS_STYLE_APPLIED
$jobs_style_applied_rows
JOBS_STYLE_APPLIED
                    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || jobs_style_cleanup_ok=0
                    jobs_style_query_active=0
                fi
            fi
            if [ "$jobs_style_cleanup_ok" = 1 ] && printf '%s\033[0m' "$jobs_style_restore_safe" > /dev/tty; then
                if [ -z "$jobs_style_conflicts" ]; then
                    rm -f "$jobs_style_recovery"
                    rmdir "${jobs_style_recovery%/*}" 2>/dev/null || :
                else
                    printf '检测到运行期间的配色变更，已保留这些项：%s\n' "$jobs_style_conflicts" >&2
                    printf '确认要覆盖后续改色时才使用恢复入口：sh "%s"\n' "$jobs_style_recovery" >&2
                    [ "$jobs_style_result" -ne 0 ] || jobs_style_result=1
                fi
            else
                printf '终端配色未能安全自动恢复；确认覆盖当前配色后可运行：sh "%s"\n' "$jobs_style_recovery" >&2
                [ "$jobs_style_result" -ne 0 ] || jobs_style_result=1
            fi
        fi
        if [ "${2:-}" = continue ]; then
            jobs_style_cleanup_status=$jobs_style_result
            return 0
        fi
        exit "$jobs_style_result"
    }
    trap 'jobs_terminal_style_cleanup "$jobs_style_exit_status"' 0
    trap 'jobs_style_exit_status=129; exit 129' HUP
    trap 'jobs_style_exit_status=130; exit 130' INT
    trap 'jobs_style_exit_status=143; exit 143' TERM
    if ! stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then
        jobs_terminal_style_plain "$@"
    fi
    jobs_style_query_active=1
    jobs_style_probe_ok=1
    for jobs_style_key in 10 11 12 '4;0' '4;1' '4;2' '4;3' '4;4' '4;5' '4;6' '4;7' '4;8' '4;9' '4;10' '4;11' '4;12' '4;13' '4;14' '4;15'; do
        if ! jobs_terminal_style_query "$jobs_style_key"; then
            jobs_style_probe_ok=0
            break
        fi
        jobs_style_saved=$jobs_style_saved$jobs_style_reply
        jobs_style_saved_rows="$jobs_style_saved_rows$jobs_style_key|$jobs_style_reply
"
    done
    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || { jobs_style_exit_status=1; exit 1; }
    jobs_style_query_active=0
    if [ "$jobs_style_probe_ok" != 1 ]; then
        printf '%s\n' '终端不支持完整配色保存，或启动时收到其它输入；保留原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
    jobs_style_recovery_dir=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/jobs-terminal-style.XXXXXX") || jobs_terminal_style_plain "$@"
    jobs_style_recovery=$jobs_style_recovery_dir/restore.sh
    if ! (umask 077; {
        printf '#!/bin/sh\n'
        printf '[ -t 0 ] && [ "$(tty)" = '\''%s'\'' ] || { printf '\''请在原终端运行恢复入口。\\n'\'' >&2; exit 1; }\n' "$jobs_style_tty"
        printf 'printf '\''本操作会覆盖此终端当前配色。确认恢复脚本启动前的配色，请输入 YES：'\'' >&2\n'
        printf 'IFS= read -r jobs_restore_choice\n[ "$jobs_restore_choice" = YES ] || exit 1\n'
        printf 'printf '\''%%s\\033[0m'\'' '\''%s'\'' > /dev/tty\n' "$jobs_style_saved"
    } > "$jobs_style_recovery"); then
        printf '%s\n' '无法保存终端配色恢复入口；保留原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
    printf '正在准备本次终端临时配色；强退后恢复入口：sh "%s"\n' "$jobs_style_recovery" >&2
    jobs_style_changed=1
    printf '\033]10;#ffffff\007\033]11;#000000\007\033]12;#ffffff\007' > /dev/tty
    jobs_style_index=0
    for jobs_style_color in 000000 ff5f56 5fd787 ffd75f 5fafff d787ff 5fd7ff eeeeee 9e9e9e ff8787 87ffaf ffff87 87bfff ffafff afffff ffffff; do
        printf '\033]4;%s;#%s\007' "$jobs_style_index" "$jobs_style_color" > /dev/tty
        jobs_style_index=$((jobs_style_index + 1))
    done
    printf '\033[0m' > /dev/tty
    jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || { jobs_style_exit_status=1; exit 1; }
    stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty || { jobs_style_exit_status=1; exit 1; }
    jobs_style_query_active=1
    jobs_style_probe_ok=1
    jobs_style_targets_ok=1
    while IFS='|' read -r jobs_style_key jobs_style_original; do
        [ -n "$jobs_style_key" ] || continue
        if ! jobs_terminal_style_query "$jobs_style_key"; then
            jobs_style_probe_ok=0
            break
        fi
        jobs_style_applied_rows="$jobs_style_applied_rows$jobs_style_key|$jobs_style_normalized|$jobs_style_original
"
        if ! jobs_terminal_style_accepts_target "$jobs_style_key"; then
            jobs_style_targets_ok=0
        fi
    done <<JOBS_STYLE_ORIGINAL
$jobs_style_saved_rows
JOBS_STYLE_ORIGINAL
    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || { jobs_style_exit_status=1; exit 1; }
    jobs_style_query_active=0
    if [ "$jobs_style_probe_ok" != 1 ]; then
        printf '%s\n' '无法核实本次临时配色，已停止启动业务。' >&2
        jobs_style_exit_status=1
        exit 1
    fi
    jobs_style_applied_complete=1
    if [ "$jobs_style_targets_ok" != 1 ]; then
        jobs_terminal_style_cleanup 0 continue
        jobs_style_changed=0
        if [ "$jobs_style_cleanup_status" != 0 ]; then
            jobs_style_exit_status=1
            exit 1
        fi
        trap 'jobs_style_exit_status=129; exit 129' HUP
        trap 'jobs_style_exit_status=130; exit 130' INT
        trap 'jobs_style_exit_status=143; exit 143' TERM
        printf '%s\n' '终端未接受本次配色，已恢复原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
    printf '%s\n' '本次终端已临时使用黑底白字。' >&2
    JOBS_TERMINAL_STYLE_TTY=$jobs_style_tty
    JOBS_TERMINAL_STYLE_OWNER=$$
    export JOBS_TERMINAL_STYLE_TTY JOBS_TERMINAL_STYLE_OWNER
    if "$@"; then
        jobs_style_exit_status=0
    else
        jobs_style_exit_status=$?
    fi
    exit "$jobs_style_exit_status"
}
"""
    _powershell_core = r"""$__jobsTerminalCommand = @($args)
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
$__jobsTerminalExitCode = 0
try {
    $__jobsTerminalStyleState = New-JobsTerminalStyleState
    Start-JobsTerminalStyle $__jobsTerminalStyleState
    if ($null -eq $__jobsTerminalCommand -or $__jobsTerminalCommand.Count -eq 0) { throw 'A program is required.' }
    $__jobsTerminalProgram = $__jobsTerminalCommand[0]
    $__jobsTerminalArguments = @()
    if ($__jobsTerminalCommand.Count -gt 1) { $__jobsTerminalArguments = @($__jobsTerminalCommand[1..($__jobsTerminalCommand.Count-1)]) }
    $LASTEXITCODE = 0
    & $__jobsTerminalProgram @__jobsTerminalArguments
    $__jobsTerminalCommandSucceeded = $?
    $__jobsTerminalExitCode = $LASTEXITCODE
    if (-not $__jobsTerminalCommandSucceeded -and $__jobsTerminalExitCode -eq 0) { $__jobsTerminalExitCode = 1 }
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}
exit $__jobsTerminalExitCode
"""
    _interrupted = False
    # 等监督进程完成恢复后再退出，避免 Ctrl+C 提前关闭控制终端。
    def _wait(_arguments):
        nonlocal _interrupted
        _process = _subprocess.Popen(_arguments, env=_environment)
        while True:
            try:
                return _process.wait()
            except KeyboardInterrupt:
                _interrupted = True
                continue
    try:
        if _os.name == "nt":
            _powershell = _shutil.which("powershell.exe") or _shutil.which("pwsh.exe")
            if not _powershell:
                _os.environ.update(NO_COLOR="1", PLAIN_OUTPUT="1", FORCE_COLOR="0", CLICOLOR="0")
                return
            with _tempfile.TemporaryDirectory(prefix="jobs-terminal-style-") as _directory:
                _wrapper = _os.path.join(_directory, "guard.ps1")
                with open(_wrapper, "w", encoding="utf-8-sig", newline="\n") as _file:
                    _file.write(_powershell_core)
                # 原参数经 JSON 交给原生 Python 数组，避开旧 Windows PowerShell 的参数重解析。
                _environment["JOBS_TERMINAL_STYLE_PYTHON_COMMAND"] = _json.dumps(_command, ensure_ascii=False)
                _receipt = _os.path.join(_directory, "started")
                _environment["JOBS_TERMINAL_STYLE_PYTHON_RECEIPT"] = _receipt
                _bridge_source = """import json, os, subprocess, sys
command = json.loads(os.environ.pop('JOBS_TERMINAL_STYLE_PYTHON_COMMAND'))
with open(os.environ.pop('JOBS_TERMINAL_STYLE_PYTHON_RECEIPT'), 'wb') as receipt:
    receipt.write(b'started')
process = subprocess.Popen(command)
while True:
    try:
        result = process.wait()
        break
    except KeyboardInterrupt:
        continue
sys.exit(result if result >= 0 else 128 - result)
"""
                _bridge = "exec(__import__('base64').b64decode('" + _base64.b64encode(_bridge_source.encode()).decode() + "'))"
                _result = _wait([_powershell, "-NoProfile", "-ExecutionPolicy", "Bypass",
                                 "-File", _wrapper, _sys.executable, "-c", _bridge])
                if not _os.path.exists(_receipt) and not _interrupted and _result not in (129, 130, 143, -1073741510, 0xC000013A):
                    _os.environ.update(NO_COLOR="1", PLAIN_OUTPUT="1", FORCE_COLOR="0", CLICOLOR="0")
                    print("终端配色保护未能启动，保持原配色并使用纯文本。", file=_sys.stderr)
                    return
        else:
            _result = _wait(["/bin/sh", "-c", _shell_core + '\njobs_terminal_style_run "$@"\n',
                             "jobs-terminal-style", *_command])
    except KeyboardInterrupt:
        raise SystemExit(130) from None
    except OSError:
        _os.environ.update(NO_COLOR="1", PLAIN_OUTPUT="1", FORCE_COLOR="0", CLICOLOR="0")
        print("终端配色保护未能启动，保持原配色并使用纯文本。", file=_sys.stderr)
        return
    if _result in (-1073741510, 0xC000013A):
        raise SystemExit(130)
    raise SystemExit(_result if _result >= 0 else 128 - _result)


if __name__ == "__main__":
    _jobs_terminal_style_bootstrap_v1()
# JOBS_TERMINAL_STYLE_GUARD_V1_END

import errno
import json
import os
from pathlib import Path
import pty
import re
import select
import shlex
import signal
import subprocess
import sys
import tempfile
import time
import unittest

# 同名包装保留原模块名；仅为当前回归进程登记相邻测试包。
def configure_test_module_paths():
    import sys as jobs_test_sys
    from pathlib import Path as JobsTestPath
    tests_root = JobsTestPath(__file__).resolve().parent.parent
    for package in sorted(tests_root.glob("*.py")):
        if package.is_dir() and (package / package.name).is_file():
            jobs_test_sys.path.insert(0, str(package))
configure_test_module_paths()
from test_downloaders_latest import GENESIS, SCRIPT_NAME, SOURCES as DOWNLOADER_SOURCES, render_readonly_engine


# 全部同名入口共享下载蓝本，包含JobsBaseConfig的独立配置。
SOURCES = list(DOWNLOADER_SOURCES)


class DownloadResumeTests(unittest.TestCase):
    """All Git repositories, credentials, transport failures and settings are disposable."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="jobs-download-resume-")
        self.root = Path(self.tmp.name).resolve()
        self.home = self.root / "home"
        self.home.mkdir()
        self.global_config = self.home / "gitconfig"
        self.global_config.write_text("[test]\n\tpreserved = true\n", encoding="utf-8")
        self.global_before = self.global_config.read_bytes()
        self.source = GENESIS / SCRIPT_NAME / SCRIPT_NAME
        self.env = {
            key: value for key, value in os.environ.items()
            if not key.startswith(("GIT_", "JOBS_DOWNLOAD_", "JOBS_TEST_"))
        }
        self.env.update(
            HOME=str(self.home), TMPDIR=str(self.root),
            XDG_CONFIG_HOME=str(self.home / "xdg"),
            GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=str(self.global_config),
            GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="core.hooksPath",
            GIT_CONFIG_VALUE_0="/dev/null", GIT_ALLOW_PROTOCOL="file",
            GIT_TERMINAL_PROMPT="0", GIT_ASKPASS="/usr/bin/false",
            GIT_SSH_COMMAND="/usr/bin/false", SSH_ASKPASS="/usr/bin/false",
            GIT_AUTHOR_NAME="Offline Test", GIT_AUTHOR_EMAIL="offline@example.invalid",
            GIT_COMMITTER_NAME="Offline Test", GIT_COMMITTER_EMAIL="offline@example.invalid",
            PATH="/usr/bin:/bin:/usr/sbin:/sbin", NO_COLOR="1", TERM="dumb",
            JOBS_DOWNLOAD_TIMEOUT="20", JOBS_DOWNLOAD_ATTEMPTS="1",
            JOBS_DOWNLOAD_RETRY_DELAY="0", JOBS_DOWNLOAD_LOW_SPEED_LIMIT="1",
            JOBS_DOWNLOAD_LOW_SPEED_TIME="2",
        )
        self.serial = 0

    def tearDown(self) -> None:
        self.assertEqual(self.global_before, self.global_config.read_bytes())
        self.tmp.cleanup()

    def git(self, repo: Path, *args: str) -> str:
        result = subprocess.run(
            ["/usr/bin/git", "-c", "core.hooksPath=/dev/null", "-c", "submodule.recurse=false",
             "-c", "fetch.recurseSubmodules=false", "-C", str(repo), *args],
            env=self.env, capture_output=True, text=True, timeout=20,
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        return result.stdout.strip()

    def repository(self, name: str) -> Path:
        repo = self.root / name
        repo.mkdir(parents=True)
        self.git(repo, "init", "-q", "-b", "main")
        self.commit(repo, "initial")
        return repo

    def commit(self, repo: Path, label: str) -> str:
        (repo / "seed").write_text(label + "\n", encoding="utf-8")
        self.git(repo, "add", "seed")
        self.git(repo, "commit", "-qm", label)
        return self.git(repo, "rev-parse", "HEAD")

    def shell(self, body: str, *, source: Path | None = None, cwd: Path | None = None,
              env: dict[str, str] | None = None, expected: int = 0) -> str:
        self.serial += 1
        library = self.root / f"library-{self.serial}.zsh"
        library.write_text(
            re.sub(r'(?m)^main "\$@"\s*$', "", (source or self.source).read_text()),
            encoding="utf-8",
        )
        setup = r'''setopt ERR_EXIT PIPE_FAIL NO_NOMATCH
source "$1"
shift
CASE_ROOT="$1"
LOG_FILE="$CASE_ROOT/output.log"
REPO_ROOT="$PWD"
'''
        process = subprocess.Popen(
            ["/bin/zsh", "-f", "-c", setup + body, "offline-resume", str(library), str(self.root)],
            cwd=cwd or self.root, env=env or self.env, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, start_new_session=True,
        )
        try:
            stdout, stderr = process.communicate(timeout=90)
        except subprocess.TimeoutExpired:
            process.terminate()
            try:
                stdout, stderr = process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                stdout, stderr = process.communicate(timeout=5)
            self.fail("fixture shell timed out: " + stdout + stderr)
        self.assertEqual(expected, process.returncode, stdout + stderr)
        return stdout + stderr

    def engine(self, repo: Path, env: dict[str, str] | None = None) -> tuple[int, str]:
        engine = render_readonly_engine(self.source)
        script = self.root / "engine.zsh"
        script.write_text(engine, encoding="utf-8")
        master, slave = pty.openpty()
        process = subprocess.Popen(
            ["/bin/zsh", str(script), "--terminal-run", str(repo)],
            cwd=self.root, env=env or self.env, stdin=slave, stdout=slave, stderr=slave,
            start_new_session=True,
        )
        os.close(slave)
        output = bytearray()
        deadline = time.monotonic() + 90
        try:
            os.write(master, b"\n")
            while time.monotonic() < deadline:
                ready, _, _ = select.select([master], [], [], 0.1)
                if ready:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError as error:
                        if error.errno == errno.EIO:
                            break
                        raise
                    if not chunk:
                        break
                    output.extend(chunk)
                if process.poll() is not None and not ready:
                    break
            else:
                self.fail("download engine timed out: " + output.decode(errors="replace"))
            process.wait(timeout=5)
            return process.returncode, output.decode(errors="replace")
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=5)
            os.close(master)

    def shim(self) -> dict[str, str]:
        """A Git shim injects failures before delegating every real operation to file-only Git."""
        binary_dir = self.root / "bin"
        binary_dir.mkdir(exist_ok=True)
        shim = binary_dir / "git"
        handler = binary_dir / "git-transport.py"
        handler.write_text(r'''
import json
import os
from pathlib import Path
import subprocess
import sys
import time

args = sys.argv[1:]
trace_args = list(args)
working_directory = Path.cwd()
for index, argument in enumerate(args[:-1]):
    if argument == "-C":
        working_directory = (working_directory / args[index + 1]).resolve()
        trace_args[index + 1] = str(working_directory)
mode = os.environ.get("JOBS_TEST_MODE", "")
is_fetch = "fetch" in args
if any(operation in args for operation in ("fetch", "checkout", "ls-remote")):
    with open(os.environ["JOBS_TEST_OPERATION_TRACE"], "a", encoding="utf-8") as trace:
        trace.write(json.dumps({"args": trace_args}) + "\n")
if is_fetch:
    record = {"args": trace_args}
    expected = os.environ.get("JOBS_TEST_EXPECT_REUSE_OID", "")
    source = os.environ.get("JOBS_TEST_EXPECT_REUSE_URL", "")
    if expected and source in args:
        index = args.index("-C")
        found = subprocess.run(["/usr/bin/git", "-C", args[index + 1], "cat-file", "-e", expected],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        record["reused_object"] = found.returncode == 0
    with open(os.environ["JOBS_TEST_TRACE"], "a", encoding="utf-8") as trace:
        trace.write(json.dumps(record) + "\n")
    fail_url = os.environ.get("JOBS_TEST_FAIL_URL", "")
    marker = Path(os.environ["JOBS_TEST_MARKER"])
    if mode == "persistent" and fail_url in args and marker.exists():
        print("fatal: unable to access file fixture: Connection reset by peer", file=sys.stderr)
        sys.exit(128)
    if mode == "transient" and not marker.exists():
        marker.write_text("failed once")
        print("fatal: unable to access file fixture: Connection reset by peer", file=sys.stderr)
        sys.exit(128)
    if mode == "auth":
        print("fatal: Authentication failed for 'https://fixture.invalid/repo'", file=sys.stderr)
        sys.exit(128)
    if mode == "sensitive":
        print("PASSTHROUGH-STDOUT", flush=True)
        for chunk in (b"fatal: Authentication failed for '\x1b[31mhttps://user-secret:",
                      b"password-secret@fixture.invalid/repo?access_token=", b"query-secret'\x1b[0m\r",
                      b"https://another-secret:final-password@fixture.invalid/repo?key=", b"eof-secret"):
            os.write(2, chunk)
            time.sleep(0.1)
        sys.exit(128)
    if mode == "sleep":
        child = subprocess.Popen(["/bin/sleep", "300"])
        Path(os.environ["JOBS_TEST_CHILD_PID"]).write_text(str(child.pid))
        time.sleep(300)
os.execv("/usr/bin/git", ["/usr/bin/git", *args])
''', encoding="utf-8")
        shim.write_text(
            '#!/bin/sh\nfor argument in "$@"; do\n'
            '  case "$argument" in --get-url) exec /usr/bin/git "$@" ;; esac\n'
            'done\nfor argument in "$@"; do\n'
            '  case "$argument" in\n'
            f'    fetch|checkout|ls-remote) exec {shlex.quote(sys.executable)} {shlex.quote(str(handler))} "$@" ;;\n'
            '  esac\ndone\nexec /usr/bin/git "$@"\n',
            encoding="utf-8",
        )
        shim.chmod(0o755)
        env = dict(self.env)
        env.update(
            PATH=f"{binary_dir}:{self.env['PATH']}", JOBS_TEST_TRACE=str(self.root / "trace.jsonl"),
            JOBS_TEST_MARKER=str(self.root / "fail.marker"),
            JOBS_TEST_CHILD_PID=str(self.root / "child.pid"),
            JOBS_TEST_OPERATION_TRACE=str(self.root / "operations.jsonl"),
        )
        return env

    def events(self) -> list[dict]:
        trace = self.root / "trace.jsonl"
        return [json.loads(line) for line in trace.read_text().splitlines()] if trace.exists() else []

    def operations(self) -> list[list[str]]:
        trace = self.root / "operations.jsonl"
        return [json.loads(line)["args"] for line in trace.read_text().splitlines()] if trace.exists() else []

    def recursive_fixture(self) -> tuple[Path, Path, Path]:
        leaf = self.repository("leaf")
        child = self.repository("child")
        seed = self.repository("parent-source")
        self.git(child, "submodule", "add", "-q", leaf.as_uri(), "叶 child")
        self.git(child, "commit", "-qam", "nested leaf")
        self.git(seed, "submodule", "add", "-q", child.as_uri(), "A child")
        self.git(seed, "config", "-f", ".gitmodules", "submodule.A child.branch", "main")
        self.git(seed, "commit", "-qam", "child")
        parent = self.root / "parent"
        self.git(self.root, "clone", "-q", "--no-recurse-submodules", seed.as_uri(), str(parent))
        return parent, child, leaf

    def test_readonly_markers_skip_transfer_revalidate_and_keep_descendants_current(self) -> None:
        parent, child_remote, leaf_remote = self.recursive_fixture()
        env = self.shim()
        code, output = self.engine(parent, env)
        self.assertEqual(0, code, output)
        child = parent / "A child"
        leaf = child / "叶 child"
        marker_paths = [Path(self.git(repo, "rev-parse", "--absolute-git-dir")) / "jobs-download-complete"
                        for repo in (parent, child, leaf)]
        self.assertTrue(all(marker.is_file() for marker in marker_paths), output)

        cursor = len(self.operations())
        code, output = self.engine(parent, env)
        self.assertEqual(0, code, output)
        operations = self.operations()[cursor:]
        self.assertFalse(any("fetch" in args or "checkout" in args for args in operations), operations)
        self.assertGreaterEqual(sum("ls-remote" in args and "--get-url" not in args for args in operations), 3)

        cursor = len(self.operations())
        leaf_latest = self.commit(leaf_remote, "leaf remote advances")
        code, output = self.engine(parent, env)
        self.assertEqual(0, code, output)
        self.assertEqual(leaf_latest, self.git(leaf, "rev-parse", "HEAD"))
        transfers = [args for args in self.operations()[cursor:] if "fetch" in args]
        self.assertTrue(transfers, output)
        self.assertTrue(all(str(leaf) in args for args in transfers), transfers)

        cursor = len(self.operations())
        child_latest = self.commit(child_remote, "child remote advances")
        code, output = self.engine(parent, env)
        self.assertEqual(0, code, output)
        self.assertEqual(child_latest, self.git(child, "rev-parse", "HEAD"))
        self.assertTrue(any("fetch" in args and str(child) in args for args in self.operations()[cursor:]))

        marker_paths[1].unlink()
        cursor = len(self.operations())
        code, output = self.engine(parent, env)
        self.assertEqual(0, code, output)
        self.assertTrue(marker_paths[1].is_file())
        self.assertTrue(any("fetch" in args and str(child) in args for args in self.operations()[cursor:]))

        (leaf / "seed").write_text("uncommitted user work\n", encoding="utf-8")
        cursor = len(self.operations())
        code, output = self.engine(parent, env)
        self.assertNotEqual(0, code, output)
        self.assertEqual("uncommitted user work\n", (leaf / "seed").read_text())
        self.assertFalse(any("checkout" in args for args in self.operations()[cursor:]), output)

    def test_management_markers_skip_current_child_and_recurse_into_updated_leaf(self) -> None:
        parent, child_remote, leaf_remote = self.recursive_fixture()
        env = self.shim()
        body = f'''
SUBMODULE_RECURSIVE=1
SUBMODULE_SHALLOW_CLONE=1
SUBMODULE_DEPTH=1
SUBMODULE_FETCH_TAGS=0
GIT_URL_STYLE=auto
REMOTE_NAME=origin
ensure_submodule_worktree_present 'A child' {shlex.quote(child_remote.as_uri())} main 0
sync_one_submodule_to_latest 'A child' {shlex.quote(child_remote.as_uri())} main
'''
        self.shell(body, cwd=parent, env=env)
        child = parent / "A child"
        leaf = child / "叶 child"
        cursor = len(self.operations())
        self.shell(body, cwd=parent, env=env)
        operations = self.operations()[cursor:]
        self.assertFalse(any("fetch" in args or "checkout" in args for args in operations), operations)
        self.assertTrue(any("ls-remote" in args and "--get-url" not in args for args in operations))
        cursor = len(self.operations())
        leaf_latest = self.commit(leaf_remote, "leaf latest through parent marker")
        self.shell(body, cwd=parent, env=env)
        self.assertEqual(leaf_latest, self.git(leaf, "rev-parse", "HEAD"))
        transfers = [args for args in self.operations()[cursor:] if "fetch" in args]
        self.assertTrue(transfers)
        self.assertTrue(all(str(leaf) in args for args in transfers), transfers)

    def test_cache_identity_survives_reorder_and_separates_sources(self) -> None:
        parent = self.repository("parent 中文")
        first = self.repository("first")
        second = self.repository("second")
        for source in SOURCES:
            with self.subTest(source=source):
                self.shell(f'''
first="$(jobs_download_cache_repository "$PWD" "$PWD/child 中文" {shlex.quote(first.as_uri())})"
other="$(jobs_download_cache_repository "$PWD" "$PWD/other" {shlex.quote(first.as_uri())})"
again="$(jobs_download_cache_repository "$PWD" "$PWD/child 中文" {shlex.quote(first.as_uri())})"
changed="$(jobs_download_cache_repository "$PWD" "$PWD/child 中文" {shlex.quote(second.as_uri())})"
[[ "$first" == "$again" && "$first" != "$other" && "$first" != "$changed" ]]
[[ "$(git -C "$first" rev-parse --is-bare-repository)" == true ]]
''', source=source, cwd=parent)

    def test_each_copy_revalidates_marker_source_branch_head_and_dirty_files(self) -> None:
        remote = self.repository("remote")
        target = self.root / "target"
        self.git(self.root, "clone", "-q", remote.as_uri(), str(target))
        original = self.git(remote, "rev-parse", "HEAD")
        latest = self.commit(remote, "new remote version")
        for source in SOURCES:
            with self.subTest(source=source):
                self.shell(f'''
url={shlex.quote(remote.as_uri())}
old={shlex.quote(original)}
latest={shlex.quote(latest)}
jobs_download_write_marker "$PWD" "$url" main "$old"
jobs_download_marker_matches "$PWD" "$url" main "$old"
[[ "$(jobs_download_remote_tip "$PWD" "$url" main)" == "$latest" ]]
if jobs_download_marker_matches "$PWD" "$url" main "$latest"; then exit 91; fi
if jobs_download_marker_matches "$PWD" "$url/" main "$old"; then exit 92; fi
if jobs_download_marker_matches "$PWD" "$url" feature "$old"; then exit 93; fi
print -r -- 'uncommitted user content' > seed
if jobs_download_marker_matches "$PWD" "$url" main "$old"; then exit 94; fi
git checkout -- seed
marker="$(git rev-parse --absolute-git-dir)/jobs-download-complete"
rm -- "$marker"
if jobs_download_marker_matches "$PWD" "$url" main "$old"; then exit 95; fi
jobs_download_write_marker "$PWD" "$url" main "$old"
jobs_download_marker_matches "$PWD" "$url" main "$old"
''', source=source, cwd=target)

    def test_management_lock_lasts_until_exit_and_preserves_cache(self) -> None:
        remote = self.repository("remote")
        for termination in ("normal", "term"):
            with self.subTest(termination=termination):
                parent = self.repository(f"parent-{termination}")
                library = self.root / f"lock-library-{termination}.zsh"
                library.write_text(re.sub(r'(?m)^main "\$@"\s*$', "", self.source.read_text()), encoding="utf-8")
                ready = self.root / f"ready-{termination}"
                finish = self.root / f"finish-{termination}"
                body = r'''setopt ERR_EXIT PIPE_FAIL NO_NOMATCH
source "$1"
REPO_ROOT="$PWD"
LOG_FILE="$2"
SCRIPT_BASENAME=lock-fixture
acquire_download_lock
[[ -d "$DOWNLOAD_LOCK_DIRECTORY" ]]
jobs_download_git -C "$PWD" ls-remote --heads "$5" main > /dev/null
jobs_download_git -C "$PWD" status --porcelain > /dev/null
[[ -d "$DOWNLOAD_LOCK_DIRECTORY" ]]
prepare_preview_runtime
cache="$(jobs_download_cache_repository "$PWD" "$PWD/child" "$5")"
print -rl -- "$DOWNLOAD_LOCK_DIRECTORY" "$PREVIEW_FILE" "$cache" > "$3"
while [[ ! -e "$4" ]]; do /bin/sleep 0.05; done
'''
                process = subprocess.Popen(
                    ["/bin/zsh", "-f", "-c", body, "offline-lock", str(library), str(self.root / "lock.log"),
                     str(ready), str(finish), remote.as_uri()],
                    cwd=parent, env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    text=True, start_new_session=True,
                )
                try:
                    deadline = time.monotonic() + 10
                    while not ready.exists() and process.poll() is None and time.monotonic() < deadline:
                        time.sleep(0.05)
                    self.assertTrue(ready.is_file(), "lock holder did not become ready")
                    lock, preview, cache = [Path(line) for line in ready.read_text().splitlines()]
                    self.assertTrue(lock.is_dir())
                    self.assertTrue(preview.is_file())
                    sentinel = cache / "retained.marker"
                    sentinel.write_text("persistent objects stay", encoding="utf-8")
                    self.shell('if acquire_download_lock; then exit 91; fi\n', cwd=parent)
                    self.assertTrue(lock.is_dir(), "competing process released the holder's lock")
                    if termination == "term":
                        process.terminate()
                    else:
                        finish.touch()
                    stdout, stderr = process.communicate(timeout=8)
                    self.assertEqual(143 if termination == "term" else 0, process.returncode, stdout + stderr)
                    self.assertFalse(lock.exists())
                    self.assertFalse(preview.exists())
                    self.assertTrue(sentinel.is_file())
                finally:
                    if process.poll() is None:
                        process.terminate()
                        try:
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            os.killpg(process.pid, signal.SIGKILL)
                            process.wait(timeout=5)
                    process.stdout.close()
                    process.stderr.close()

    def test_failed_later_child_keeps_completed_objects_for_next_run(self) -> None:
        leaf = self.repository("leaf")
        first = self.repository("first")
        second = self.repository("second")
        seed = self.repository("parent-source")
        self.git(first, "submodule", "add", "-q", leaf.as_uri(), "叶 child")
        self.git(first, "commit", "-qam", "nested leaf")
        for section, remote, path in (("first", first, "A first"), ("second", second, "Z second")):
            self.git(seed, "submodule", "add", "-q", "--name", section, remote.as_uri(), path)
            self.git(seed, "config", "-f", ".gitmodules", f"submodule.{section}.branch", "main")
        self.git(seed, "commit", "-qam", "children")
        parent = self.root / "parent"
        self.git(self.root, "clone", "-q", "--no-recurse-submodules", seed.as_uri(), str(parent))
        target = self.git(first, "rev-parse", "HEAD")
        env = self.shim()
        env.update(JOBS_TEST_MODE="persistent", JOBS_TEST_FAIL_URL=second.as_uri())
        marker = Path(env["JOBS_TEST_MARKER"])
        marker.touch()
        before_head = self.git(parent, "rev-parse", "HEAD")
        before_index = self.git(parent, "diff", "--cached", "--raw")
        code, output = self.engine(parent, env)
        self.assertNotEqual(0, code, output)
        self.assertFalse((parent / "A first/.git").exists(), output)
        cache_output = self.shell(
            f'jobs_download_cache_repository "$PWD" "$PWD/A first" {shlex.quote(first.as_uri())}\n', cwd=parent,
        )
        cache = Path(cache_output.strip().splitlines()[-1])
        self.assertTrue(cache.is_dir(), output + cache_output)
        self.git(cache, "cat-file", "-e", target)
        kept = cache / "retained.marker"
        kept.write_text("keep complete objects", encoding="utf-8")
        marker.unlink()
        env.update(JOBS_TEST_EXPECT_REUSE_OID=target, JOBS_TEST_EXPECT_REUSE_URL=first.as_uri())
        code, output = self.engine(parent, env)
        self.assertEqual(0, code, output)
        self.assertTrue(kept.exists())
        self.assertTrue(any(event.get("reused_object") for event in self.events()))
        for repo, remote in ((parent / "A first", first), (parent / "A first/叶 child", leaf), (parent / "Z second", second)):
            self.assertEqual(self.git(remote, "rev-parse", "HEAD"), self.git(repo, "rev-parse", "HEAD"))
            self.assertEqual("main", self.git(repo, "branch", "--show-current"))
            self.assertTrue((repo / ".git").is_file())
        self.assertEqual(before_head, self.git(parent, "rev-parse", "HEAD"))
        self.assertEqual(before_index, self.git(parent, "diff", "--cached", "--raw"))
        self.assertFalse((parent / ".git/jobs-readonly-pull.lock").exists())

    def test_existing_full_and_shallow_children_keep_ancestor_history(self) -> None:
        for shallow in (False, True):
            with self.subTest(shallow=shallow):
                remote = self.repository(f"remote-{shallow}")
                seed = self.repository(f"source-{shallow}")
                self.git(seed, "submodule", "add", "-q", remote.as_uri(), "child")
                self.git(seed, "commit", "-qam", "child")
                parent = self.root / f"parent-{shallow}"
                self.git(self.root, "clone", "-q", "--no-recurse-submodules", seed.as_uri(), str(parent))
                self.git(parent, "submodule", "update", "--init")
                child = parent / "child"
                old = self.git(child, "rev-parse", "HEAD")
                self.git(child, "checkout", "-q", "main")
                if shallow:
                    self.git(child, "fetch", "--depth=1", "origin", old)
                for number in range(4):
                    latest = self.commit(remote, f"remote update {number}")
                code, output = self.engine(parent)
                self.assertEqual(0, code, output)
                self.assertEqual(latest, self.git(child, "rev-parse", "HEAD"))
                self.git(child, "merge-base", "--is-ancestor", old, latest)
                self.assertEqual("4", self.git(child, "rev-list", "--count", f"{old}..{latest}"))
                if not shallow:
                    self.assertEqual("false", self.git(child, "rev-parse", "--is-shallow-repository"))

    def test_transport_retries_transient_failure_and_preserves_result(self) -> None:
        remote = self.repository("remote")
        target = self.repository("target")
        env = self.shim()
        env.update(JOBS_TEST_MODE="transient", JOBS_DOWNLOAD_ATTEMPTS="3")
        self.shell(f'jobs_download_git -C "$PWD" fetch --no-tags -- {shlex.quote(remote.as_uri())} refs/heads/main:refs/remotes/test/main\n', cwd=target, env=env)
        self.assertEqual(2, len(self.events()))
        self.assertEqual(self.git(remote, "rev-parse", "HEAD"), self.git(target, "rev-parse", "refs/remotes/test/main"))

    def test_authentication_failure_is_not_retried(self) -> None:
        repo = self.repository("repo")
        env = self.shim()
        env.update(JOBS_TEST_MODE="auth", JOBS_DOWNLOAD_ATTEMPTS="3")
        output = self.shell('jobs_download_git -C "$PWD" fetch --no-tags file:///unused refs/heads/main\n', cwd=repo, env=env, expected=128)
        self.assertEqual(1, len(self.events()), output)

    def test_chunked_stderr_redacts_credentials_and_cleans_private_diagnostics(self) -> None:
        repo = self.repository("repo")
        env = self.shim()
        env.update(JOBS_TEST_MODE="sensitive", JOBS_DOWNLOAD_ATTEMPTS="3")
        output = self.shell('jobs_download_git -C "$PWD" fetch --no-tags file:///unused refs/heads/main\n', cwd=repo, env=env, expected=128)
        self.assertIn("PASSTHROUGH-STDOUT", output)
        for secret in ("user-secret", "password-secret", "query-secret", "another-secret", "final-password", "eof-secret", "\x1b"):
            self.assertNotIn(secret, output)
        self.assertEqual(1, len(self.events()), output)
        self.assertFalse(list(self.root.glob("jobs-git-transfer.*")))

    def test_timeout_stops_git_descendants_and_returns_failure(self) -> None:
        repo = self.repository("repo")
        env = self.shim()
        env.update(JOBS_TEST_MODE="sleep", JOBS_DOWNLOAD_TIMEOUT="1")
        started = time.monotonic()
        output = self.shell('jobs_download_git -C "$PWD" fetch --no-tags file:///unused refs/heads/main\n', cwd=repo, env=env, expected=124)
        self.assertLess(time.monotonic() - started, 12, output)
        self.assert_mock_child_stopped(env, output)

    def assert_mock_child_stopped(self, env: dict[str, str], output: str) -> None:
        pid = int(Path(env["JOBS_TEST_CHILD_PID"]).read_text())
        try:
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline:
                try:
                    os.kill(pid, 0)
                except ProcessLookupError:
                    break
                time.sleep(0.05)
            else:
                self.fail(f"timeout left Git child {pid} running: {output}")
        finally:
            try:
                os.kill(pid, 9)
            except ProcessLookupError:
                pass

    def test_termination_cancels_once_and_stops_git_descendants(self) -> None:
        repo = self.repository("repo")
        env = self.shim()
        env.update(JOBS_TEST_MODE="sleep", JOBS_DOWNLOAD_ATTEMPTS="3")
        output = self.shell(r'''
jobs_download_git -C "$PWD" fetch --no-tags file:///unused refs/heads/main &
transfer_pid=$!
for attempt in {1..100}; do
  [[ -f "$JOBS_TEST_CHILD_PID" ]] && break
  /bin/sleep 0.05
done
[[ -f "$JOBS_TEST_CHILD_PID" ]]
kill -TERM "$transfer_pid"
if wait "$transfer_pid"; then exit 91; else transfer_result=$?; fi
[[ "$transfer_result" == 143 ]]
''', cwd=repo, env=env)
        self.assertEqual(1, len(self.events()), output)
        self.assert_mock_child_stopped(env, output)

    def test_invalid_transfer_settings_stop_before_transport(self) -> None:
        for key, values in {
            "JOBS_DOWNLOAD_TIMEOUT": ("0", "-1", "abc", "86401"),
            "JOBS_DOWNLOAD_ATTEMPTS": ("0", "11"),
            "JOBS_DOWNLOAD_RETRY_DELAY": ("-1", "61"),
            "JOBS_DOWNLOAD_LOW_SPEED_LIMIT": ("0", "1000000001"),
            "JOBS_DOWNLOAD_LOW_SPEED_TIME": ("0", "3601"),
        }.items():
            for value in values:
                with self.subTest(setting=key, value=value):
                    env = dict(self.env, **{key: value})
                    self.shell('if jobs_download_validate_settings; then exit 91; fi\n', env=env)
        self.shell('jobs_download_validate_settings\n', env=dict(self.env, JOBS_DOWNLOAD_TIMEOUT="0001", JOBS_DOWNLOAD_RETRY_DELAY="0"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
