#!/usr/bin/env python3
# Created by Jobs on 2026年10月18日，星期日.
"""Exercise complete reference-repair entries in isolated, offline Git fixtures."""

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

import os
from pathlib import Path
import pty
import select
import shutil
import subprocess
import sys
import tempfile
import time
import unittest


SCRIPT_NAME = "【MacOS】🧭更新引用Git父仓=＞子仓.command"
SCRIPTS = [Path(item).resolve() for item in sys.argv[1:]] or [Path(__file__).resolve().parents[2] / SCRIPT_NAME]
REAL_GIT = shutil.which("git")


class ReferenceRepairTests(unittest.TestCase):
    """Check repository state, metadata ownership and failure boundaries."""

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="jobs-reference-repair-tests-")
        self.root = Path(self.temp.name).resolve()
        self.env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        self.env.update(
            HOME=str(self.root), GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=str(self.root / "empty-config"),
            GIT_ALLOW_PROTOCOL="file", GIT_TERMINAL_PROMPT="0", GIT_AUTHOR_NAME="Jobs Isolated Test",
            GIT_AUTHOR_EMAIL="test@example.invalid", GIT_COMMITTER_NAME="Jobs Isolated Test",
            GIT_COMMITTER_EMAIL="test@example.invalid", TERM="dumb", NO_COLOR="1", TMPDIR=str(self.root),
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    def git(self, repo: Path, *arguments: str, check: bool = True) -> str:
        result = subprocess.run(
            [str(REAL_GIT), "-c", "core.hooksPath=/dev/null", "-C", str(repo), *arguments],
            env=self.env, text=True, capture_output=True, timeout=15,
        )
        if check:
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        return result.stdout.strip()

    def repo(self, location: Path, name: str) -> Path:
        location.mkdir(parents=True)
        self.git(location, "init", "-b", "main")
        self.git(location, "remote", "add", "origin", f"https://code.example/team/{name}.git")
        (location / "seed").write_text("seed\n")
        self.git(location, "add", "seed")
        self.git(location, "commit", "-m", "offline fixture")
        return location

    def fixture(self, number: int, child_name: str = "Child") -> tuple[Path, Path]:
        parent = self.repo(self.root / str(number) / "Parent", "Parent")
        return parent, self.repo(parent / child_name, "Child")

    def entry(self, source: Path, parent: Path, packaged: bool = False) -> Path:
        folder = parent / SCRIPT_NAME if packaged else parent
        folder.mkdir(exist_ok=True)
        target = folder / SCRIPT_NAME
        shutil.copy2(source, target)
        return target

    def run_entry(
        self, entry: Path, *, dry_run: bool = False, skip: bool = False, extra_env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        env = self.env | (extra_env or {})
        command = ["/bin/zsh", str(entry)] + (["--dry-run"] if dry_run else [])
        if dry_run:
            return subprocess.run(command, env=env, capture_output=True, text=True, timeout=20)
        master, slave = pty.openpty()
        process = None
        output = bytearray()
        try:
            process = subprocess.Popen(command, stdin=slave, stdout=slave, stderr=slave, env=env, start_new_session=True)
            os.close(slave)
            slave = -1
            deadline = time.monotonic() + 20
            sent_intro = sent_plan = False
            while True:
                ready, _, _ = select.select([master], [], [], 0.05)
                if ready:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError:
                        break
                    if not chunk:
                        break
                    output.extend(chunk)
                elif process.poll() is not None:
                    break
                decoded = output.decode(errors="replace")
                if not sent_intro and "按回车查看计划；Ctrl+C 取消：" in decoded:
                    os.write(master, b"\n")
                    sent_intro = True
                if not sent_plan and "输入任意字符后回车执行：" in decoded:
                    os.write(master, b"\n" if skip else b"run\n")
                    sent_plan = True
                if time.monotonic() > deadline:
                    self.fail(f"Script timed out: {decoded}")
            code = process.wait(timeout=5)
            return subprocess.CompletedProcess(command, code, output.decode(errors="replace"), "")
        finally:
            if process is not None and process.poll() is None:
                process.kill()
                process.wait()
            if slave >= 0:
                os.close(slave)
            os.close(master)

    def assert_success(self, result: subprocess.CompletedProcess[str]) -> None:
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn("✔ 已完成", result.stdout)

    def assert_stopped(self, result: subprocess.CompletedProcess[str]) -> None:
        self.assertNotEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertNotIn("✔ 已完成", result.stdout)

    def parent_files(self, parent: Path) -> dict[str, bytes | None]:
        return {item: (parent / item).read_bytes() if (parent / item).exists() else None for item in [".git/config", ".git/index", ".gitmodules"]}

    def test_entries_are_identical_and_parse(self) -> None:
        expected = SCRIPTS[0].read_bytes()
        for source in SCRIPTS:
            with self.subTest(source=source):
                self.assertEqual(expected, source.read_bytes())
                subprocess.run(["/bin/zsh", "-n", str(source)], check=True, capture_output=True)

    def test_root_and_package_locate_target_parent_and_backup(self) -> None:
        for number, source in enumerate(SCRIPTS):
            for packaged in [False, True]:
                with self.subTest(source=source, packaged=packaged):
                    parent, child = self.fixture(number * 2 + int(packaged))
                    entry = self.entry(source, parent, packaged)
                    before_head = self.git(parent, "rev-parse", "HEAD")
                    result = self.run_entry(entry)
                    self.assert_success(result)
                    self.assertTrue((child / ".git").is_file())
                    self.assertEqual(parent, Path(self.git(child, "rev-parse", "--show-superproject-working-tree")))
                    self.assertEqual(before_head, self.git(parent, "rev-parse", "HEAD"))
                    backups = list((parent / ".git/jobs-submodule-backups").glob("reference.*"))
                    self.assertEqual(1, len(backups))
                    self.assertTrue((backups[0] / "config").is_file())
                    self.assertFalse((parent / ".git/jobs-reference-repair.lock").exists())

    def test_rename_preserves_original_section_metadata_and_fields(self) -> None:
        for number, source in enumerate(SCRIPTS):
            with self.subTest(source=source):
                parent, child = self.fixture(number, "Old Name")
                for key, value in {"path": child.name, "url": "../preserved.git", "ignore": "dirty", "update": "none"}.items():
                    self.git(parent, "config", "-f", ".gitmodules", f"submodule.custom section.{key}", value)
                entry = self.entry(source, parent)
                self.assert_success(self.run_entry(entry))
                self.git(parent, "commit", "-m", "record original relation")
                metadata = self.git(child, "rev-parse", "--absolute-git-dir")
                origin = self.git(child, "remote", "get-url", "origin")
                renamed = parent / "New 名称 (2)"
                child.rename(renamed)
                self.assert_success(self.run_entry(entry))
                self.assertEqual(metadata, self.git(renamed, "rev-parse", "--absolute-git-dir"))
                self.assertEqual(renamed.name, self.git(parent, "config", "-f", ".gitmodules", "submodule.custom section.path"))
                self.assertEqual("../preserved.git", self.git(parent, "config", "-f", ".gitmodules", "submodule.custom section.url"))
                self.assertEqual("dirty", self.git(parent, "config", "-f", ".gitmodules", "submodule.custom section.ignore"))
                self.assertEqual("none", self.git(parent, "config", "-f", ".gitmodules", "submodule.custom section.update"))
                self.assertEqual("", self.git(parent, "config", "-f", ".gitmodules", "submodule.custom section.branch", check=False))
                self.assertEqual(origin, self.git(renamed, "remote", "get-url", "origin"))

    def test_spaces_and_local_commits_branches_indexes_and_sources_survive(self) -> None:
        for number, source in enumerate(SCRIPTS):
            with self.subTest(source=source):
                parent, child = self.fixture(number, "有 空格(子仓)")
                self.git(child, "checkout", "-b", "topic/local-only")
                (child / "seed").write_text("local commit\n")
                self.git(child, "commit", "-am", "not pushed")
                (child / "seed").write_text("staged source\n")
                self.git(child, "add", "seed")
                (child / "untracked").write_text("keep me\n")
                (parent / "unrelated").write_text("already staged\n")
                self.git(parent, "add", "unrelated")
                before = {"head": self.git(child, "rev-parse", "HEAD"), "branch": self.git(child, "symbolic-ref", "HEAD"), "status": self.git(child, "status", "--porcelain"), "refs": self.git(child, "show-ref"), "origin": self.git(child, "remote", "get-url", "origin")}
                self.assert_success(self.run_entry(self.entry(source, parent)))
                self.assertEqual(before["head"], self.git(child, "rev-parse", "HEAD"))
                self.assertEqual(before["branch"], self.git(child, "symbolic-ref", "HEAD"))
                self.assertEqual(before["status"], self.git(child, "status", "--porcelain"))
                self.assertEqual(before["refs"], self.git(child, "show-ref"))
                self.assertEqual(before["origin"], self.git(child, "remote", "get-url", "origin"))
                self.assertEqual("already staged", self.git(parent, "show", ":unrelated"))
                self.assertEqual(before["head"], self.git(parent, "rev-parse", f":{child.name}"))

    def test_registered_nested_path_preserves_section_without_adopting_siblings(self) -> None:
        for number, source in enumerate(SCRIPTS):
            with self.subTest(source=source):
                child_path = "OS@Extension/平台 分类/Child 名称"
                parent, child = self.fixture(number, child_path)
                sibling = self.repo(child.parent / "Unregistered", "Unregistered")
                section = "existing custom section"
                for key, value in {"path": child_path, "url": "../preserved.git", "ignore": "dirty", "update": "none"}.items():
                    self.git(parent, "config", "-f", ".gitmodules", f"submodule.{section}.{key}", value)
                self.git(parent, "add", ".gitmodules")
                self.git(parent, "update-index", "--add", "--cacheinfo", "160000", self.git(child, "rev-parse", "HEAD"), child_path)
                self.git(parent, "commit", "-m", "record nested relation")
                entry = self.entry(source, parent)
                sibling_before = {"head": self.git(sibling, "rev-parse", "HEAD"), "status": self.git(sibling, "status", "--porcelain"), "config": (sibling / ".git/config").read_bytes()}
                for _ in range(2):
                    self.assert_success(self.run_entry(entry))
                    self.assertEqual(child_path, self.git(parent, "config", "-f", ".gitmodules", f"submodule.{section}.path"))
                    self.assertEqual("../preserved.git", self.git(parent, "config", "-f", ".gitmodules", f"submodule.{section}.url"))
                    self.assertEqual("dirty", self.git(parent, "config", "-f", ".gitmodules", f"submodule.{section}.ignore"))
                    self.assertEqual("none", self.git(parent, "config", "-f", ".gitmodules", f"submodule.{section}.update"))
                    self.assertEqual("", self.git(parent, "config", "-f", ".gitmodules", f"submodule.{section}.branch", check=False))
                    self.assertEqual(child_path + "\0", self.git(parent, "ls-files", "-z", "--", "OS@Extension"))
                    self.assertEqual(parent, Path(self.git(child, "rev-parse", "--show-superproject-working-tree")))
                self.assertTrue((sibling / ".git").is_dir())
                self.assertEqual(sibling_before["head"], self.git(sibling, "rev-parse", "HEAD"))
                self.assertEqual(sibling_before["status"], self.git(sibling, "status", "--porcelain"))
                self.assertEqual(sibling_before["config"], (sibling / ".git/config").read_bytes())

    def test_registered_nested_symlinks_and_intermediate_git_are_blocked(self) -> None:
        for number, source in enumerate(SCRIPTS):
            for variant in ["container-link", "child-link", "intermediate-git"]:
                with self.subTest(source=source, variant=variant):
                    base = self.root / str(number) / variant
                    parent = self.repo(base / "Parent", "Parent")
                    external = self.repo(base / "External/Child", "Child")
                    container = parent / "OS@Extension"
                    if variant == "container-link":
                        container.symlink_to(external.parent, target_is_directory=True)
                    elif variant == "child-link":
                        container.mkdir()
                        (container / "Child").symlink_to(external, target_is_directory=True)
                    else:
                        self.repo(container, "Intermediate")
                        self.repo(container / "Child", "Child")
                    self.git(parent, "config", "-f", ".gitmodules", "submodule.custom.path", "OS@Extension/Child")
                    self.git(parent, "config", "-f", ".gitmodules", "submodule.custom.url", "../Child.git")
                    entry = self.entry(source, parent)
                    before = self.parent_files(parent)
                    self.assert_stopped(self.run_entry(entry))
                    self.assertEqual(before, self.parent_files(parent))
                    self.assertTrue((external / ".git").is_dir())
                    self.assertFalse((parent / ".git/jobs-submodule-backups").exists())

    def test_missing_nested_registration_is_removed_without_recursing(self) -> None:
        for number, source in enumerate(SCRIPTS):
            with self.subTest(source=source):
                parent, child = self.fixture(number)
                missing = parent / "OS@Extension/Missing"
                missing.mkdir(parents=True)
                (missing / "notes").write_text("retain source\n")
                self.git(parent, "config", "-f", ".gitmodules", "submodule.stale.path", "OS@Extension/Missing")
                self.git(parent, "config", "-f", ".gitmodules", "submodule.stale.url", "../Missing.git")
                self.git(parent, "update-index", "--add", "--cacheinfo", "160000", self.git(child, "rev-parse", "HEAD"), "OS@Extension/Missing")
                self.assert_success(self.run_entry(self.entry(source, parent)))
                self.assertEqual("", self.git(parent, "config", "-f", ".gitmodules", "submodule.stale.path", check=False))
                self.assertEqual("", self.git(parent, "ls-files", "--", "OS@Extension/Missing"))
                self.assertEqual("retain source\n", (missing / "notes").read_text())

    def test_missing_registration_is_removed_but_disk_content_is_kept(self) -> None:
        for number, source in enumerate(SCRIPTS):
            with self.subTest(source=source):
                parent, child = self.fixture(number)
                missing = parent / "Missing Folder"
                missing.mkdir()
                (missing / "notes").write_text("retain source\n")
                self.git(parent, "config", "-f", ".gitmodules", "submodule.stale.path", missing.name)
                self.git(parent, "config", "-f", ".gitmodules", "submodule.stale.url", "../Missing.git")
                self.git(parent, "update-index", "--add", "--cacheinfo", "160000", self.git(child, "rev-parse", "HEAD"), missing.name)
                self.assert_success(self.run_entry(self.entry(source, parent)))
                self.assertEqual("", self.git(parent, "config", "-f", ".gitmodules", "submodule.stale.path", check=False))
                self.assertEqual("", self.git(parent, "ls-files", "--", missing.name))
                self.assertEqual("retain source\n", (missing / "notes").read_text())

    def test_preview_and_skip_do_not_change_association(self) -> None:
        for number, source in enumerate(SCRIPTS):
            for dry_run in [False, True]:
                with self.subTest(source=source, dry_run=dry_run):
                    parent, child = self.fixture(number * 2 + int(dry_run))
                    entry = self.entry(source, parent)
                    before = self.parent_files(parent)
                    result = self.run_entry(entry, dry_run=dry_run, skip=True)
                    self.assertEqual(0, result.returncode, result.stdout + result.stderr)
                    self.assertEqual(before, self.parent_files(parent))
                    self.assertTrue((child / ".git").is_dir())
                    self.assertFalse((parent / ".git/jobs-submodule-backups").exists())

    def test_conflicting_metadata_stops_before_write(self) -> None:
        for number, source in enumerate(SCRIPTS):
            with self.subTest(source=source):
                parent, child = self.fixture(number)
                conflict = parent / ".git/modules/Child"
                conflict.mkdir(parents=True)
                (conflict / "sentinel").write_text("other history\n")
                entry = self.entry(source, parent)
                before = self.parent_files(parent)
                self.assert_stopped(self.run_entry(entry))
                self.assertEqual(before, self.parent_files(parent))
                self.assertEqual("other history\n", (conflict / "sentinel").read_text())
                self.assertTrue((child / ".git").is_dir())

    def test_linked_child_and_linked_parent_are_blocked(self) -> None:
        for number, source in enumerate(SCRIPTS):
            with self.subTest(source=source):
                parent = self.repo(self.root / str(number) / "Parent", "Parent")
                external = self.repo(self.root / str(number) / "External", "External")
                self.git(external, "worktree", "add", "-b", "linked", str(parent / "Linked"))
                entry = self.entry(source, parent)
                before = self.parent_files(parent)
                self.assert_stopped(self.run_entry(entry))
                self.assertEqual(before, self.parent_files(parent))
                linked_parent = self.root / str(number) / "Parent Linked"
                self.git(parent, "worktree", "add", "-b", "linked-parent", str(linked_parent))
                self.repo(linked_parent / "Child", "Child")
                self.assert_stopped(self.run_entry(self.entry(source, linked_parent)))

    def test_broken_pointer_is_not_replaced_with_unproven_metadata(self) -> None:
        for number, source in enumerate(SCRIPTS):
            with self.subTest(source=source):
                parent = self.repo(self.root / str(number) / "Parent", "Parent")
                child = parent / "Broken"
                child.mkdir()
                marker = "gitdir: ../missing-metadata\n"
                (child / ".git").write_text(marker)
                entry = self.entry(source, parent)
                before = self.parent_files(parent)
                self.assert_stopped(self.run_entry(entry))
                self.assertEqual(before, self.parent_files(parent))
                self.assertEqual(marker, (child / ".git").read_text())

    def test_absorb_failure_keeps_backup_and_does_not_report_success(self) -> None:
        for number, source in enumerate(SCRIPTS):
            with self.subTest(source=source):
                parent, child = self.fixture(number)
                expected_head = self.git(child, "rev-parse", "HEAD")
                tools = self.root / str(number) / "tools"
                tools.mkdir()
                wrapper = tools / "git"
                wrapper.write_text('#!/bin/zsh\nif [[ "$1" == -C && "$3" == submodule && "$4" == absorbgitdirs ]]; then print -u2 -- "isolated absorb failure"; exit 42; fi\nexec "$TEST_REAL_GIT" "$@"\n')
                wrapper.chmod(0o755)
                result = self.run_entry(self.entry(source, parent), extra_env={"PATH": f"{tools}:{self.env.get('PATH', '')}", "TEST_REAL_GIT": str(REAL_GIT)})
                self.assert_stopped(result)
                self.assertIn("isolated absorb failure", result.stdout + result.stderr)
                self.assertEqual(expected_head, self.git(child, "rev-parse", "HEAD"))
                self.assertEqual(1, len(list((parent / ".git/jobs-submodule-backups").glob("reference.*"))))
                self.assertFalse((parent / ".git/jobs-reference-repair.lock").exists())


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]], verbosity=2)
