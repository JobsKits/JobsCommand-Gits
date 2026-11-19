#!/usr/bin/env python3
# Created by Jobs on 2026年10月21日，星期三.
"""Keep configured Markdown filters active at a prepared recursive first checkout."""

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
import shutil
import subprocess
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
from test_downloaders_latest import SOURCES, GENESIS, SCRIPT_NAME, resolve_script_entry, render_readonly_engine

INVENTORY_SOURCES = tuple(SOURCES)


class MarkdownTocCheckoutTests(unittest.TestCase):
    """Use real Git and the embedded engine; all remotes and config are disposable."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="jobs-markdown-checkout-")
        self.root = Path(self.tmp.name).resolve()
        self.node = shutil.which("node")
        if not self.node:
            self.tmp.cleanup()
            self.skipTest("Node.js is required by the real Markdown TOC converter")
        self.converter = Path(__file__).resolve().parents[4] / ".jobs-markdown-toc/MarkdownToc.mjs"
        self.assertTrue(self.converter.is_file(), str(self.converter))
        self.original_converter = self.converter.read_text(encoding="utf-8")
        self.global_config = self.root / "isolated.gitconfig"
        self.global_config.write_text("[user]\n\tname = Offline Test\n\temail = offline@example.invalid\n", encoding="utf-8")
        self.journal = self.root / "filter-events.jsonl"
        self.env = {
            key: value for key, value in os.environ.items()
            if not key.startswith("GIT_") and key != "JOBS_GITEE_HTTPS_CONFIGURED"
        }
        # Keep the real HOME unchanged; only Git's configuration sources are isolated.
        self.env.update(
            TMPDIR=str(self.root), GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=str(self.global_config),
            GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="core.hooksPath", GIT_CONFIG_VALUE_0="/dev/null",
            GIT_ALLOW_PROTOCOL="file", GIT_TERMINAL_PROMPT="0", GIT_ASKPASS="/usr/bin/false",
            GIT_SSH_COMMAND="/usr/bin/false", SSH_ASKPASS="/usr/bin/false",
            GIT_AUTHOR_NAME="Offline Test", GIT_AUTHOR_EMAIL="offline@example.invalid",
            GIT_COMMITTER_NAME="Offline Test", GIT_COMMITTER_EMAIL="offline@example.invalid",
            PATH=f"{Path(self.node).parent}:/usr/bin:/bin:/usr/sbin:/sbin", TERM="dumb", NO_COLOR="1",
            JOBS_TOC_TEST_JOURNAL=str(self.journal),
        )
        self.trusted = self.root / "trusted-runtime/MarkdownToc.mjs"
        self.trusted.parent.mkdir()
        self.trusted.write_text(self.instrumented_converter("trusted"), encoding="utf-8")
        self.driver_config = self.root / "trusted-driver.gitconfig"
        for mode in ("clean", "smudge"):
            self.git(self.root, "config", "--file", str(self.driver_config),
                     f"filter.jobs-markdown-toc.{mode}",
                     f"{shlex.quote(self.node)} {shlex.quote(str(self.trusted))} {mode}")
        self.git(self.root, "config", "--file", str(self.driver_config), "filter.jobs-markdown-toc.required", "true")
        self.protected: dict[Path, bytes] = {}

    def tearDown(self) -> None:
        try:
            for path, before in self.protected.items():
                self.assertEqual(before, path.read_bytes(), f"external configuration changed: {path}")
        finally:
            self.tmp.cleanup()

    def instrumented_converter(self, role: str) -> str:
        """Log which trusted/checkout tool runs without changing its conversion logic."""
        prelude = r"""import * as tocTestFS from 'node:fs';
import { spawnSync as tocTestSpawn } from 'node:child_process';
if (process.env.JOBS_TOC_TEST_JOURNAL) {
  const origin = tocTestSpawn('/usr/bin/git', ['config', '--get', 'remote.origin.url'], {encoding: 'utf8'});
  tocTestFS.appendFileSync(process.env.JOBS_TOC_TEST_JOURNAL, JSON.stringify({
    role: ROLE, mode: process.argv[2], cwd: process.cwd(), origin: origin.stdout.trim(),
    readmeExists: tocTestFS.existsSync('README.md'),
  }) + '\n');
}
""".replace("ROLE", json.dumps(role))
        return prelude + self.original_converter

    def git(self, repo: Path, *args: str) -> str:
        result = subprocess.run(
            ["/usr/bin/git", "-c", "core.hooksPath=/dev/null", "-c", "submodule.recurse=false",
             "-c", "fetch.recurseSubmodules=false", "-C", str(repo), *args],
            env=self.env, capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        return result.stdout.rstrip("\n")

    def convert(self, source: str, mode: str) -> str:
        result = subprocess.run([self.node, str(self.trusted), mode], env=self.env,
                                cwd=self.root, input=source, capture_output=True, text=True, timeout=20)
        self.assertEqual(0, result.returncode, result.stderr)
        return result.stdout

    def source_document(self, name: str, revision: str) -> str:
        return f"# {name}\n\n[toc]\n\n## 第一章\n\n{revision} 正文，保留本地编辑。\n\n### 第二级\n\n细节。\n"

    def seed(self, case: Path, name: str, branch: str) -> tuple[Path, Path, str]:
        repo = case / f"{name}-source"
        repo.mkdir()
        self.git(repo, "init", "-q", "-b", branch)
        tools = repo / ".jobs-markdown-toc"
        tools.mkdir()
        (tools / "MarkdownToc.mjs").write_text(self.instrumented_converter("repository"), encoding="utf-8")
        (tools / "manifest.json").write_text(json.dumps({"version": 1, "files": ["README.md"]}) + "\n", encoding="utf-8")
        (repo / ".gitattributes").write_text("README.md filter=jobs-markdown-toc\n", encoding="utf-8")
        source = self.source_document(name, "revision one")
        (repo / "README.md").write_text(self.convert(source, "clean"), encoding="utf-8")
        self.git(repo, "add", ".")
        self.git(repo, "commit", "-qm", "initial generated publication")
        bare = case / f"{name}.git"
        self.git(case, "clone", "-q", "--bare", repo.as_uri(), str(bare))
        return repo, bare, source

    def publish(self, repo: Path, bare: Path, branch: str) -> None:
        """Prepare a disposable remote by fetching locally, without invoking push."""
        self.git(bare, "fetch", "-q", repo.as_uri(), f"HEAD:refs/heads/{branch}")

    def link(self, repo: Path, path: str, section: str, url: str, branch: str, pin: str) -> None:
        for key, value in (("path", path), ("url", url), ("branch", branch)):
            self.git(repo, "config", "-f", ".gitmodules", f"submodule.{section}.{key}", value)
        self.git(repo, "add", ".gitmodules")
        self.git(repo, "update-index", "--add", "--cacheinfo", f"160000,{pin},{path}")
        self.git(repo, "commit", "-qm", "pin nested child")

    def register(self, urls: dict[str, str], bares: dict[str, Path]) -> None:
        for key, url in urls.items():
            self.git(self.root, "config", "--file", str(self.global_config),
                     f"url.{bares[key].as_uri()}.insteadOf", url)
            self.git(self.root, "config", "--file", str(self.global_config),
                     f"includeIf.hasconfig:remote.*.url:{url}.path", str(self.driver_config))
        self.protected = {path: path.read_bytes() for path in (self.global_config, self.driver_config, self.trusted)}

    def fixture(self, name: str) -> dict:
        case = self.root / name
        case.mkdir()
        branches = {"parent": "main", "child": "release", "leaf": "trunk"}
        seeds, bares, documents = {}, {}, {}
        for key, branch in branches.items():
            seeds[key], bares[key], documents[key] = self.seed(case, key, branch)
        urls = {key: f"https://github.com/JobsTocOffline/{name}-{key}.git" for key in branches}
        self.link(seeds["child"], "叶 child", "leaf section", urls["leaf"], branches["leaf"], self.git(seeds["leaf"], "rev-parse", "HEAD"))
        self.publish(seeds["child"], bares["child"], branches["child"])
        self.link(seeds["parent"], "Selected child", "child section", urls["child"], branches["child"], self.git(seeds["child"], "rev-parse", "HEAD"))
        self.publish(seeds["parent"], bares["parent"], branches["parent"])
        self.register(urls, bares)
        parent = case / "parent"
        self.git(case, "clone", "-q", "--no-recurse-submodules", urls["parent"], str(parent))
        self.journal.write_text("", encoding="utf-8")
        return {"case": case, "parent": parent, "seeds": seeds, "bares": bares,
                "urls": urls, "branches": branches, "documents": documents}

    def engine(self, source: Path) -> str:
        return render_readonly_engine(source)

    def run_engine(self, source: Path, fixture: dict) -> tuple[int, str]:
        script = fixture["case"] / "readonly-engine.zsh"
        script.write_text(self.engine(source), encoding="utf-8")
        master, slave = pty.openpty()
        process = subprocess.Popen(["/bin/zsh", str(script), "--terminal-run", str(fixture["parent"])],
                                   cwd=fixture["case"], env=self.env, stdin=slave, stdout=slave, stderr=slave)
        os.close(slave)
        output = bytearray()
        deadline = time.monotonic() + 60
        try:
            os.write(master, b"\n")
            while time.monotonic() < deadline:
                readable, _, _ = select.select([master], [], [], 0.1)
                if readable:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError as error:
                        if error.errno == errno.EIO:
                            break
                        raise
                    if not chunk:
                        break
                    output.extend(chunk)
                if process.poll() is not None and not readable:
                    break
            else:
                self.fail("readonly engine timed out: " + output.decode(errors="replace"))
            process.wait(timeout=5)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)
            os.close(master)
        for path, before in self.protected.items():
            self.assertEqual(before, path.read_bytes(), f"external configuration changed: {path}")
        return process.returncode, output.decode(errors="replace")

    def events(self) -> list[dict]:
        return [json.loads(line) for line in self.journal.read_text(encoding="utf-8").splitlines() if line]

    def run_restore(self, source: Path, repo: Path, *, embedded: bool, no_node: bool = False) -> tuple[int, str]:
        content = self.engine(source) if embedded else source.read_text(encoding="utf-8")
        library = repo.parent / "restore-library.zsh"
        library.write_text(re.sub(r'(?m)^main "\$@"\s*$', "", content), encoding="utf-8")
        env = dict(self.env)
        if no_node:
            env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        external_before = {path: path.read_bytes() for path in (self.global_config, self.driver_config, self.trusted)}
        result = subprocess.run(
            ["/bin/zsh", "-f", "-c", 'source "$1"; restore_configured_markdown_toc "$2"',
             "isolated-restore", str(library), str(repo)],
            cwd=repo, env=env, stdin=subprocess.DEVNULL,
            capture_output=True, text=True, timeout=25,
        )
        for path, before in external_before.items():
            self.assertEqual(before, path.read_bytes(), f"external configuration changed: {path}")
        return result.returncode, result.stdout + result.stderr

    def assert_publication_and_worktree(self, repo: Path, source: str, branch: str, url: str) -> None:
        self.assertEqual(source, (repo / "README.md").read_text(encoding="utf-8"))
        generated = self.convert(source, "clean")
        self.assertIn("<details>", generated)
        self.assertEqual(generated.rstrip("\n"), self.git(repo, "show", "HEAD:README.md"))
        self.assertEqual(generated.rstrip("\n"), self.git(repo, "show", ":README.md"))
        self.assertEqual(branch, self.git(repo, "branch", "--show-current"))
        self.assertEqual(f"origin/{branch}", self.git(repo, "rev-parse", "--abbrev-ref", "@{upstream}"))
        self.assertEqual(url, self.git(repo, "config", "--get", "remote.origin.url"))
        self.assertEqual("", self.git(repo, "status", "--porcelain=v1", "--untracked-files=all"))
        local_keys = self.git(repo, "config", "--local", "--name-only", "--list").splitlines()
        self.assertFalse(any(key.startswith("filter.") for key in local_keys), local_keys)

    def test_prepared_recursive_first_checkout_uses_real_remote_before_smudge_and_later_updates(self) -> None:
        # 按已确认维护入口逐一验证；旧总数7包含已不存在的候选，不能把遗漏路径静默当覆盖。
        maintained = [resolve_script_entry(GENESIS / folder / SCRIPT_NAME) for folder in (
            "", "JobsCommand@Gits/MacOS", "JobsConfigOS", "JobsConfigOS/💻JobsCodexConfigs", "JobsConfigOS/⚙️VScodeConfigs",
        )]
        external = GENESIS.parent / "JobsBaseConfig" / SCRIPT_NAME
        if external.is_file():
            maintained.append(external)  # 既有只读夹具来源，不修改范围外源码。
        for source in maintained:
            self.assertTrue(source.is_file(), str(source))
            self.assertIn(source, INVENTORY_SOURCES)
            self.assertIn("sync_selected_submodules_to_latest", source.read_text(encoding="utf-8"))
        for index, source in enumerate(SOURCES):
            with self.subTest(script=source):
                fixture = self.fixture(f"checkout-{index}")
                code, output = self.run_engine(source, fixture)
                self.assertEqual(0, code, output)
                repos = {"parent": fixture["parent"], "child": fixture["parent"] / "Selected child",
                         "leaf": fixture["parent"] / "Selected child/叶 child"}
                first_events = self.events()
                for key in ("child", "leaf"):
                    events = [event for event in first_events if event["origin"] == fixture["urls"][key]]
                    first_smudge = next((event for event in events if event["mode"] == "smudge"), None)
                    self.assertIsNotNone(first_smudge, f"{key}: initial checkout bypassed the configured smudge; {events}")
                    # 首次检出在直属父仓的受控暂存区完成，随后才原子移入最终路径。
                    parent_repo = repos["parent" if key == "child" else "child"]
                    stage_parent = Path(self.git(parent_repo, "rev-parse", "--absolute-git-dir")) / "jobs-download-cache/worktrees"
                    smudge_root = Path(first_smudge["cwd"])
                    self.assertEqual(stage_parent, smudge_root.parent.parent)
                    self.assertTrue(smudge_root.parent.name.startswith("checkout."))
                    self.assertEqual("worktree", smudge_root.name)
                    self.assertEqual("trusted", first_smudge["role"])
                    self.assertEqual(fixture["urls"][key], first_smudge["origin"])
                    self.assertFalse(first_smudge["readmeExists"], "first checkout must write [toc] directly")
                    self.assertNotIn("install", [event["mode"] for event in events])
                    self.assertNotIn("smudge", [event["mode"] for event in events if event["role"] == "repository"])
                for key, repo in repos.items():
                    self.assert_publication_and_worktree(repo, fixture["documents"][key], fixture["branches"][key], fixture["urls"][key])
                # Neither a no-op fetch nor checkout rewrites an old generated file.
                # The configured restore step must repair it before child readiness checks.
                indexes = {key: self.git(repo, "ls-files", "--stage") for key, repo in repos.items()}
                for key, repo in repos.items():
                    (repo / "README.md").write_text(self.convert(fixture["documents"][key], "clean"), encoding="utf-8")
                code, output = self.run_engine(source, fixture)
                self.assertEqual(0, code, output)
                for key, repo in repos.items():
                    self.assertEqual(indexes[key], self.git(repo, "ls-files", "--stage"))
                    self.assert_publication_and_worktree(repo, fixture["documents"][key], fixture["branches"][key], fixture["urls"][key])
                for key in ("leaf", "child", "parent"):
                    seed = fixture["seeds"][key]
                    fixture["documents"][key] = self.source_document(key, "revision two latest")
                    (seed / "README.md").write_text(self.convert(fixture["documents"][key], "clean"), encoding="utf-8")
                    self.git(seed, "add", "README.md")
                    if key != "leaf":
                        child_key, path = ("leaf", "叶 child") if key == "child" else ("child", "Selected child")
                        self.git(seed, "update-index", "--cacheinfo", f"160000,{self.git(fixture['seeds'][child_key], 'rev-parse', 'HEAD')},{path}")
                    self.git(seed, "commit", "-qm", "advance branch without reinstalling filters")
                    self.publish(seed, fixture["bares"][key], fixture["branches"][key])
                code, output = self.run_engine(source, fixture)
                self.assertEqual(0, code, output)
                for key, repo in repos.items():
                    self.assertEqual(self.git(fixture["seeds"][key], "rev-parse", "HEAD"), self.git(repo, "rev-parse", "HEAD"))
                    self.assert_publication_and_worktree(repo, fixture["documents"][key], fixture["branches"][key], fixture["urls"][key])
                self.assertNotIn("install", [event["mode"] for event in self.events()])

    def test_configured_restore_preserves_uncommitted_body_and_original_index(self) -> None:
        for index, source in enumerate(SOURCES):
            for embedded in (False, True):
                with self.subTest(script=source, embedded=embedded):
                    case = self.root / f"body-{index}-{embedded}"
                    case.mkdir()
                    repo, _, original = self.seed(case, "edited", "main")
                    url = f"https://github.com/JobsTocOffline/edited-{index}-{embedded}.git"
                    self.git(repo, "remote", "add", "origin", url)
                    self.git(self.root, "config", "--file", str(self.global_config),
                             f"includeIf.hasconfig:remote.*.url:{url}.path", str(self.driver_config))
                    self.protected = {path: path.read_bytes() for path in (self.global_config, self.driver_config, self.trusted)}
                    edited = original.replace("revision one", "用户尚未提交的新增内容")
                    (repo / "README.md").write_text(self.convert(edited, "clean"), encoding="utf-8")
                    (repo / "staged.txt").write_text("partial staging remains\n", encoding="utf-8")
                    self.git(repo, "add", "staged.txt")
                    (repo / "untracked.txt").write_text("untracked remains\n", encoding="utf-8")
                    before_head = self.git(repo, "rev-parse", "HEAD")
                    before_index = self.git(repo, "ls-files", "--stage")
                    before_config = (repo / ".git/config").read_bytes()
                    self.journal.write_text("", encoding="utf-8")
                    code, output = self.run_restore(source, repo, embedded=embedded)
                    self.assertEqual(0, code, output)
                    self.assertEqual(edited, (repo / "README.md").read_text(encoding="utf-8"))
                    self.assertEqual(before_head, self.git(repo, "rev-parse", "HEAD"))
                    self.assertEqual(before_index, self.git(repo, "ls-files", "--stage"))
                    self.assertEqual(before_config, (repo / ".git/config").read_bytes())
                    self.assertEqual("untracked remains\n", (repo / "untracked.txt").read_text(encoding="utf-8"))
                    modes = [event["mode"] for event in self.events() if event["role"] == "repository"]
                    self.assertEqual(["restore", "verify"], modes)

    def test_unconfigured_restore_skips_missing_runtime_and_never_executes_repository_tool(self) -> None:
        for index, source in enumerate(SOURCES):
            for embedded in (False, True):
                with self.subTest(script=source, embedded=embedded):
                    case = self.root / f"skip-{index}-{embedded}"
                    case.mkdir()
                    repo, _, _ = self.seed(case, "unconfigured", "main")
                    tool = repo / ".jobs-markdown-toc/MarkdownToc.mjs"
                    tool.write_text("throw new Error('unconfigured repository tool must never run');\n", encoding="utf-8")
                    before = {"readme": (repo / "README.md").read_bytes(),
                              "config": (repo / ".git/config").read_bytes(),
                              "head": self.git(repo, "rev-parse", "HEAD"),
                              "index": self.git(repo, "ls-files", "--stage")}
                    self.journal.write_text("", encoding="utf-8")
                    code, output = self.run_restore(source, repo, embedded=embedded, no_node=True)
                    self.assertEqual(0, code, output)
                    self.assertIn("跳过", output)
                    self.assertEqual(before["readme"], (repo / "README.md").read_bytes())
                    self.assertEqual(before["config"], (repo / ".git/config").read_bytes())
                    self.assertEqual(before["head"], self.git(repo, "rev-parse", "HEAD"))
                    self.assertEqual(before["index"], self.git(repo, "ls-files", "--stage"))
                    self.assertEqual([], self.events())

    def test_configured_missing_tool_process_conflict_and_unfinished_git_stop_without_installing(self) -> None:
        for index, source in enumerate(SOURCES):
            for embedded in (False, True):
                for failure in ("missing-tool", "missing-directory", "process-conflict", "process-only", "unfinished-git"):
                    with self.subTest(script=source, embedded=embedded, failure=failure):
                        case = self.root / f"reject-{index}-{embedded}-{failure}"
                        case.mkdir()
                        repo, _, _ = self.seed(case, "configured", "main")
                        self.git(repo, "config", "filter.jobs-markdown-toc.smudge",
                                 f"{shlex.quote(self.node)} {shlex.quote(str(self.trusted))} smudge")
                        tool = repo / ".jobs-markdown-toc/MarkdownToc.mjs"
                        if failure == "missing-tool":
                            tool.unlink()
                        elif failure == "missing-directory":
                            shutil.rmtree(tool.parent)
                        elif failure in ("process-conflict", "process-only"):
                            self.git(repo, "config", "filter.jobs-markdown-toc.process", "/usr/bin/false")
                            if failure == "process-only":
                                self.git(repo, "config", "--unset", "filter.jobs-markdown-toc.smudge")
                        else:
                            (repo / ".git/MERGE_HEAD").write_text(self.git(repo, "rev-parse", "HEAD") + "\n", encoding="utf-8")
                        before = ((repo / "README.md").read_bytes(), (repo / ".git/config").read_bytes(),
                                  self.git(repo, "rev-parse", "HEAD"), self.git(repo, "ls-files", "--stage"))
                        self.journal.write_text("", encoding="utf-8")
                        code, output = self.run_restore(source, repo, embedded=embedded)
                        self.assertNotEqual(0, code, output)
                        if failure == "process-only":
                            self.assertIn("process", output)
                            self.assertNotIn("跳过", output)
                        self.assertEqual(before, ((repo / "README.md").read_bytes(), (repo / ".git/config").read_bytes(),
                                                  self.git(repo, "rev-parse", "HEAD"), self.git(repo, "ls-files", "--stage")))
                        self.assertEqual([], self.events())

    def test_unconfigured_missing_directory_skips_without_runtime_or_writes(self) -> None:
        for index, source in enumerate(SOURCES):
            for embedded in (False, True):
                with self.subTest(script=source, embedded=embedded):
                    case = self.root / f"missing-directory-{index}-{embedded}"
                    case.mkdir()
                    repo, _, _ = self.seed(case, "unconfigured", "main")
                    shutil.rmtree(repo / ".jobs-markdown-toc")
                    before = ((repo / "README.md").read_bytes(), (repo / ".git/config").read_bytes(),
                              self.git(repo, "rev-parse", "HEAD"), self.git(repo, "ls-files", "--stage"))
                    self.journal.write_text("", encoding="utf-8")
                    code, output = self.run_restore(source, repo, embedded=embedded, no_node=True)
                    self.assertEqual(0, code, output)
                    self.assertIn("跳过", output)
                    self.assertFalse((repo / ".jobs-markdown-toc").exists())
                    self.assertEqual(before, ((repo / "README.md").read_bytes(), (repo / ".git/config").read_bytes(),
                                              self.git(repo, "rev-parse", "HEAD"), self.git(repo, "ls-files", "--stage")))
                    self.assertEqual([], self.events())


if __name__ == "__main__":
    unittest.main()
