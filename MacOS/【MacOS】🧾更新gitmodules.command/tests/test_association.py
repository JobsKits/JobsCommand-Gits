#!/usr/bin/env python3
# Created by Jobs on 2026年10月15日，星期四.
"""Exercise only disposable Git repositories against a copied updater script."""

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

import argparse
import errno
import hashlib
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


SCRIPT_SOURCE: Path
ARTIFACT_ROOT = Path(tempfile.mkdtemp(prefix="jobs-gitmodules-integration-"))
SCRIPT_NAME = "【MacOS】🧾更新gitmodules.command"


def tree_fingerprint(root: Path) -> dict[str, str]:
    """Record contents and symlink targets without treating access times as changes."""
    result: dict[str, str] = {}
    if not root.exists():
        return result
    for path in sorted(root.rglob("*")):
        relative = str(path.relative_to(root))
        if path.is_symlink():
            result[relative] = f"symlink:{os.readlink(path)}"
        elif path.is_file():
            result[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


class AssociationTests(unittest.TestCase):
    """Verify repository linkage and preservation using the actual Git executable."""

    def setUp(self) -> None:
        self.sandbox = Path(tempfile.mkdtemp(prefix=f"{self._testMethodName}-", dir=ARTIFACT_ROOT))
        self.parent = self.sandbox / "父 仓库"
        self.home = self.sandbox / "home"
        self.home.mkdir()
        self.tmp = self.sandbox / "logs"
        self.tmp.mkdir()
        self.env = dict(os.environ)
        for key in list(self.env):
            if key.startswith("GIT_"):
                del self.env[key]
        self.env.update(
            HOME=str(self.home),
            XDG_CONFIG_HOME=str(self.home / "xdg"),
            GIT_CONFIG_NOSYSTEM="1",
            GIT_CONFIG_GLOBAL=str(self.home / "empty-gitconfig"),
            GIT_TERMINAL_PROMPT="0",
            GIT_AUTHOR_NAME="Isolated Integration Test",
            GIT_AUTHOR_EMAIL="isolated@example.invalid",
            GIT_COMMITTER_NAME="Isolated Integration Test",
            GIT_COMMITTER_EMAIL="isolated@example.invalid",
            GIT_ALLOW_PROTOCOL="file",
            TMPDIR=str(self.tmp) + "/",
            TERM="dumb",
            NO_COLOR="1",
        )
        self.init_repo(self.parent)
        self.install_script(self.parent)

    def tearDown(self) -> None:
        """Successful, refused, and interrupted runs must release their owned resources."""
        self.assertFalse((self.gitdir(self.parent) / "jobs-gitmodules.lock").exists(), "script lock leaked")
        self.assertEqual([], list(self.tmp.glob("jobs-gitmodules.*")), "temporary plan directory leaked")

    def git(self, repo: Path, *args: str, check: bool = True) -> str:
        """Run Git with isolated identity, configuration, hooks, and protocols."""
        process = subprocess.run(
            ["git", "-c", "core.hooksPath=/dev/null", "-C", str(repo), *args],
            env=self.env,
            capture_output=True,
            text=True,
            check=False,
        )
        if check and process.returncode:
            self.fail(f"git {args} failed ({process.returncode}): {process.stdout}{process.stderr}")
        return process.stdout.rstrip("\n")

    def init_repo(self, path: Path, *, commit: bool = True, origin: bool = True) -> Path:
        """Create a disposable repository with an optional initial commit and remote."""
        path.mkdir(parents=True, exist_ok=True)
        self.git(path, "init", "-b", "main")
        self.git(path, "config", "core.logAllRefUpdates", "true")
        self.git(path, "config", "core.quotePath", "false")
        if origin:
            self.git(path, "remote", "add", "origin", f"https://example.invalid/Jobs/{path.name}.git")
        if commit:
            (path / "seed.txt").write_text("initial content\n", encoding="utf-8")
            self.git(path, "add", "seed.txt")
            self.git(path, "commit", "-m", "test fixture initial commit")
        return path

    def install_script(self, parent: Path) -> Path:
        """Place the candidate in the repository root, as the deployed entrypoint is used."""
        script = parent / SCRIPT_NAME
        shutil.copyfile(SCRIPT_SOURCE, script)
        return script

    def child(self, name: str = "子 仓库", **kwargs: bool) -> Path:
        """Create a direct child repository with a path requiring robust quoting."""
        return self.init_repo(self.parent / name, **kwargs)

    def gitdir(self, repo: Path) -> Path:
        """Resolve .git indirection for parents that are themselves absorbed submodules."""
        return Path(self.git(repo, "rev-parse", "--absolute-git-dir"))

    def index(self, repo: Path | None = None) -> bytes:
        """Capture the exact staged entries rather than the worktree's porcelain summary."""
        target = repo or self.parent
        return subprocess.check_output(
            ["git", "-C", str(target), "ls-files", "--stage", "-z"], env=self.env
        )

    def head(self, repo: Path) -> str:
        """Return the currently checked out commit without changing it."""
        return self.git(repo, "rev-parse", "HEAD")

    def run_script(
        self, *args: str, parent: Path | None = None,
        confirmation: bytes = b"\ny\n\n", entrypoint: Path | None = None,
    ) -> tuple[int, str]:
        """Use a pseudo-terminal for the ordinary confirmation, never a bypass flag."""
        target = parent or self.parent
        script = entrypoint or target / SCRIPT_NAME
        master, slave = pty.openpty()
        process = subprocess.Popen(
            ["/bin/zsh", str(script), *args],
            cwd=self.sandbox,
            env=self.env,
            stdin=slave,
            stdout=slave,
            stderr=slave,
            start_new_session=True,
        )
        os.close(slave)
        output = bytearray()
        started = time.monotonic()
        confirmed = False
        while True:
            if not confirmed and time.monotonic() - started > 0.15:
                os.write(master, confirmation)
                confirmed = True
            ready, _, _ = select.select([master], [], [], 0.1)
            if ready:
                try:
                    chunk = os.read(master, 65536)
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    break
                if not chunk:
                    break
                output.extend(chunk)
            elif process.poll() is not None:
                break
            if time.monotonic() - started > 25:
                process.kill()
                process.wait()
                self.fail(f"Script timed out: {output.decode(errors='replace')}")
        os.close(master)
        code = process.wait(timeout=5)
        decoded = output.decode("utf-8", errors="replace")
        (self.sandbox / f"run-{len(list(self.sandbox.glob('run-*.log'))) + 1}.log").write_text(decoded)
        if code == 0:
            self.assertNotIn("\nfatal:", decoded, "Git reported a fatal error despite a successful script exit")
        return code, decoded

    def register(self, child: Path, *, section: str | None = None, url: str | None = None) -> None:
        """Construct a real submodule registration without cloning or network access."""
        relative = str(child.relative_to(self.parent))
        section = section or relative
        url = url or self.git(child, "remote", "get-url", "origin")
        self.git(self.parent, "config", "-f", ".gitmodules", f"submodule.{section}.path", relative)
        self.git(self.parent, "config", "-f", ".gitmodules", f"submodule.{section}.url", url)
        self.git(self.parent, "add", ".gitmodules")
        self.git(self.parent, "update-index", "--add", "--cacheinfo", f"160000,{self.head(child)},{relative}")
        self.git(self.parent, "submodule", "init", "--", relative)
        self.git(self.parent, "submodule", "absorbgitdirs", "--", relative)

    def assert_linked(self, child: Path, *, section: str | None = None) -> None:
        """Check gitlink, absorbed metadata, and Git's actual parent relationship."""
        relative = str(child.relative_to(self.parent))
        stage = self.git(self.parent, "--literal-pathspecs", "ls-files", "--stage", "--", relative)
        self.assertEqual(f"160000 {self.head(child)} 0\t{relative}", stage)
        self.assertTrue((child / ".git").is_file(), "child metadata was not absorbed")
        self.assertEqual((self.gitdir(self.parent) / "modules" / (section or relative)).resolve(), self.gitdir(child).resolve())
        superproject = self.git(child, "rev-parse", "--show-superproject-working-tree")
        self.assertEqual(self.parent.resolve(), Path(superproject).resolve())
        self.git(self.parent, "--literal-pathspecs", "submodule", "status", "--", relative)

    def test_new_child_preserves_dirty_source_index_history_and_remotes(self) -> None:
        child = self.child()
        (child / "seed.txt").write_text("staged change\n")
        self.git(child, "add", "seed.txt")
        (child / "seed.txt").write_text("staged change\nplus unstaged change\n")
        (child / "未跟踪文件.txt").write_text("keep me\n")
        before = (self.head(child), self.index(child), self.git(child, "diff"), self.git(child, "remote", "-v"))
        before_parent_head = self.head(self.parent)
        code, output = self.run_script()
        self.assertEqual(0, code, output)
        self.assert_linked(child)
        self.assertEqual(before, (self.head(child), self.index(child), self.git(child, "diff"), self.git(child, "remote", "-v")))
        self.assertEqual("keep me\n", (child / "未跟踪文件.txt").read_text())
        self.assertEqual(before_parent_head, self.head(self.parent))

    def check_new_url(self, parent_urls: list[str], child_urls: list[str], expected: str) -> str:
        """Exercise URL selection through a real association without any network access."""
        child = self.child("URL child")
        for repo, urls in [(self.parent, parent_urls), (child, child_urls)]:
            self.git(repo, "remote", "remove", "origin")
            for number, url in enumerate(urls):
                self.git(repo, "remote", "add", "origin" if number == 0 else f"mirror{number}", url)
        original_remotes = self.git(child, "remote", "-v")
        code, output = self.run_script()
        self.assertEqual(0, code, output)
        self.assertEqual(expected, self.git(self.parent, "config", "-f", ".gitmodules", "submodule.URL child.url"))
        self.assertEqual(original_remotes, self.git(child, "remote", "-v"))
        self.assert_linked(child)
        return output

    def test_new_url_follows_all_configured_platforms(self) -> None:
        self.check_new_url(
            ["https://github.example/Team/Parent.git", "git@gitee.example:Mirror/Parent.git", "ssh://git@code.example:2222/group/subgroup/Parent.git"],
            ["git@github.example:Team/Child.git", "https://gitee.example/Mirror/Child", "ssh://git@code.example:2222/group/subgroup/Child.git"],
            "../Child.git",
        )

    def test_new_url_supports_nested_namespace_and_explicit_ssh_port(self) -> None:
        self.check_new_url(
            ["ssh://git@code.example:2222/group/subgroup/Parent.git"],
            ["ssh://git@code.example:2222/group/subgroup/Child.git"], "../Child.git",
        )

    def test_new_url_preserves_repository_name_difference_between_platforms(self) -> None:
        origin = "https://github.example/Team/Child.git"
        output = self.check_new_url(
            ["https://github.example/Team/Parent.git", "git@gitee.example:Mirror/Parent.git"],
            [origin, "git@gitee.example:Mirror/renamed-child.git"], origin,
        )
        self.assertIn("保留明确原地址", output)

    def test_new_url_preserves_cross_namespace_source(self) -> None:
        origin = "https://github.example/Upstream/Child.git"
        self.check_new_url(["https://github.example/Team/Parent.git"], [origin], origin)

    def test_new_url_preserves_source_when_a_parent_platform_has_no_child_mapping(self) -> None:
        origin = "https://github.example/Team/Child.git"
        self.check_new_url(
            ["https://github.example/Team/Parent.git", "git@gitee.example:Mirror/Parent.git"], [origin], origin,
        )

    def test_new_url_preserves_explicit_local_path(self) -> None:
        origin = str(self.sandbox / "local Child.git")
        self.check_new_url([str(self.sandbox / "local Parent.git")], [origin], origin)

    def test_new_url_preserves_unknown_protocol(self) -> None:
        origin = "git://code.example/Team/Child.git"
        self.check_new_url(["git://code.example/Team/Parent.git"], [origin], origin)

    def test_new_url_preserves_different_ssh_endpoints(self) -> None:
        origin = "ssh://git@code.example:2223/Team/Child.git"
        self.check_new_url(["ssh://git@code.example:2222/Team/Parent.git"], [origin], origin)

    def test_existing_absolute_url_is_preserved_when_relative_would_be_possible(self) -> None:
        child = self.child()
        origin = self.git(child, "remote", "get-url", "origin")
        self.register(child, section="custom absolute", url=origin)
        self.git(self.parent, "config", "-f", ".gitmodules", "submodule.custom absolute.branch", "release")
        self.git(self.parent, "config", "-f", ".gitmodules", "submodule.custom absolute.update", "none")
        self.git(self.parent, "add", ".gitmodules")
        before = (self.parent / ".gitmodules").read_bytes()
        code, output = self.run_script()
        self.assertEqual(0, code, output)
        self.assertEqual(before, (self.parent / ".gitmodules").read_bytes())

    def test_existing_gitmodules_without_gitlink_is_repaired(self) -> None:
        child = self.child()
        self.git(self.parent, "config", "-f", ".gitmodules", "submodule.existing name.path", child.name)
        self.git(self.parent, "config", "-f", ".gitmodules", "submodule.existing name.url", "../relative.git")
        self.git(self.parent, "add", ".gitmodules")
        self.git(self.parent, "commit", "-m", "register metadata only")
        code, output = self.run_script()
        self.assertEqual(0, code, output)
        self.assert_linked(child, section="existing name")
        self.assertEqual("../relative.git", self.git(self.parent, "config", "-f", ".gitmodules", "submodule.existing name.url"))

    def test_untracked_gitmodules_without_gitlink_is_staged_and_repaired(self) -> None:
        child = self.child()
        self.git(self.parent, "config", "-f", ".gitmodules", "submodule.untracked metadata.path", child.name)
        self.git(self.parent, "config", "-f", ".gitmodules", "submodule.untracked metadata.url", "../relative.git")
        with (self.parent / ".gitmodules").open("a") as stream:
            stream.write("# custom comment survives association\n")
        before = (self.parent / ".gitmodules").read_bytes()
        code, output = self.run_script()
        self.assertEqual(0, code, output)
        self.assert_linked(child, section="untracked metadata")
        self.assertEqual(before, (self.parent / ".gitmodules").read_bytes())
        staged = subprocess.check_output(["git", "-C", str(self.parent), "show", ":.gitmodules"], env=self.env)
        self.assertEqual(before, staged)

    def test_untracked_gitmodules_is_staged_when_every_other_association_is_complete(self) -> None:
        child = self.child()
        self.register(child, section="complete association", url="../relative.git")
        self.git(self.parent, "rm", "--cached", "--", ".gitmodules")
        before_metadata = (self.parent / ".gitmodules").read_bytes()
        before_child_gitdir = self.gitdir(child)
        before_config = (self.gitdir(self.parent) / "config").read_bytes()
        code, output = self.run_script()
        self.assertEqual(0, code, output)
        self.assert_linked(child, section="complete association")
        staged = subprocess.check_output(["git", "-C", str(self.parent), "show", ":.gitmodules"], env=self.env)
        self.assertEqual(before_metadata, staged)
        self.assertEqual(before_child_gitdir, self.gitdir(child))
        self.assertEqual(before_config, (self.gitdir(self.parent) / "config").read_bytes())

    def test_second_new_child_registers_after_successful_first_run(self) -> None:
        first = self.child("first child")
        code, output = self.run_script()
        self.assertEqual(0, code, output)
        self.assert_linked(first)
        self.assertFalse((self.gitdir(self.parent) / "jobs-gitmodules.lock").exists())
        second = self.child("second child")
        code, output = self.run_script()
        self.assertEqual(0, code, output)
        self.assert_linked(first)
        self.assert_linked(second)

    def test_same_named_wrapper_directory_resolves_parent_repository(self) -> None:
        child = self.child()
        original = self.parent / SCRIPT_NAME
        script_bytes = original.read_bytes()
        original.unlink()
        original.mkdir()
        wrapped_script = original / SCRIPT_NAME
        wrapped_script.write_bytes(script_bytes)
        code, output = self.run_script(entrypoint=wrapped_script)
        self.assertEqual(0, code, output)
        self.assert_linked(child)

    def test_unknown_argument_fails_before_runtime_initialization_or_git_changes(self) -> None:
        child = self.child()
        before_parent = tree_fingerprint(self.gitdir(self.parent))
        before_child = tree_fingerprint(child / ".git")
        before_tmp = tree_fingerprint(self.tmp)
        process = subprocess.run(
            ["/bin/zsh", str(self.parent / SCRIPT_NAME), "--unknown-option"],
            cwd=self.sandbox, env=self.env, input="y\n", capture_output=True,
            text=True, timeout=25,
        )
        self.assertNotEqual(0, process.returncode, process.stdout + process.stderr)
        self.assertEqual(before_parent, tree_fingerprint(self.gitdir(self.parent)))
        self.assertEqual(before_child, tree_fingerprint(child / ".git"))
        self.assertEqual(before_tmp, tree_fingerprint(self.tmp))
        self.assertFalse((self.parent / ".gitmodules").exists())

    def test_staged_gitmodules_deletion_is_preserved_and_run_refused(self) -> None:
        child = self.child()
        self.register(child)
        self.git(self.parent, "commit", "-m", "registered baseline")
        self.git(self.parent, "rm", "--cached", "--", ".gitmodules")
        before_index = self.index()
        before_metadata = (self.parent / ".gitmodules").read_bytes()
        before_parent_git = tree_fingerprint(self.gitdir(self.parent))
        code, output = self.run_script()
        self.assertNotEqual(0, code, output)
        self.assertEqual(before_index, self.index())
        self.assertEqual(before_metadata, (self.parent / ".gitmodules").read_bytes())
        self.assertEqual(before_parent_git, tree_fingerprint(self.gitdir(self.parent)))

    def test_staged_child_gitlink_deletion_is_preserved_and_run_refused(self) -> None:
        child = self.child()
        self.register(child)
        self.git(self.parent, "commit", "-m", "registered baseline")
        self.git(self.parent, "update-index", "--force-remove", "--", child.name)
        before_index = self.index()
        before_metadata = (self.parent / ".gitmodules").read_bytes()
        before_parent_git = tree_fingerprint(self.gitdir(self.parent))
        code, output = self.run_script()
        self.assertNotEqual(0, code, output)
        self.assertEqual(before_index, self.index())
        self.assertEqual(before_metadata, (self.parent / ".gitmodules").read_bytes())
        self.assertEqual(before_parent_git, tree_fingerprint(self.gitdir(self.parent)))

    def test_section_metadata_prefix_conflict_is_refused_before_any_git_change(self) -> None:
        first = self.child("alpha")
        second = self.child("beta")
        for child, section in [(first, "first"), (second, "first/two")]:
            self.git(self.parent, "config", "-f", ".gitmodules", f"submodule.{section}.path", child.name)
            self.git(self.parent, "config", "-f", ".gitmodules", f"submodule.{section}.url", "../relative.git")
        self.git(self.parent, "add", ".gitmodules")
        before_parent = tree_fingerprint(self.gitdir(self.parent))
        before_first = tree_fingerprint(first / ".git")
        before_second = tree_fingerprint(second / ".git")
        before_metadata = (self.parent / ".gitmodules").read_bytes()
        code, output = self.run_script()
        self.assertNotEqual(0, code, output)
        self.assertEqual(before_parent, tree_fingerprint(self.gitdir(self.parent)))
        self.assertEqual(before_first, tree_fingerprint(first / ".git"))
        self.assertEqual(before_second, tree_fingerprint(second / ".git"))
        self.assertEqual(before_metadata, (self.parent / ".gitmodules").read_bytes())

    def test_symlink_backup_root_is_refused_without_external_writes(self) -> None:
        child = self.child()
        outside = self.sandbox / "external backup target"
        outside.mkdir()
        (self.gitdir(self.parent) / "jobs-submodule-backups").symlink_to(outside, target_is_directory=True)
        before_parent = tree_fingerprint(self.gitdir(self.parent))
        before_child = tree_fingerprint(child / ".git")
        code, output = self.run_script()
        self.assertNotEqual(0, code, output)
        self.assertEqual([], list(outside.iterdir()))
        self.assertEqual(before_parent, tree_fingerprint(self.gitdir(self.parent)))
        self.assertEqual(before_child, tree_fingerprint(child / ".git"))

    def test_failed_git_absorption_releases_lock_and_temporary_plan(self) -> None:
        child = self.child()
        shim_dir = self.sandbox / "failure shims"
        shim_dir.mkdir()
        git_shim = shim_dir / "git"
        git_shim.write_text(
            "#!/bin/sh\n"
            "for argument in \"$@\"; do\n"
            "  if [ \"$argument\" = absorbgitdirs ]; then\n"
            "    echo 'Injected absorption failure' >&2\n"
            "    exit 42\n"
            "  fi\n"
            "done\n"
            "exec /usr/bin/git \"$@\"\n"
        )
        git_shim.chmod(0o755)
        self.env["PATH"] = str(shim_dir) + os.pathsep + self.env["PATH"]
        code, output = self.run_script()
        self.assertNotEqual(0, code, output)
        self.assertIn("Injected absorption failure", output)
        self.assertTrue((child / ".git").is_dir())
        self.assertFalse((self.gitdir(self.parent) / "jobs-gitmodules.lock").exists())
        self.assertEqual([], list(self.tmp.glob("jobs-gitmodules.*")))
        self.assertTrue(list((self.gitdir(self.parent) / "jobs-submodule-backups").iterdir()))

    def test_ignored_new_child_is_refused_without_registration(self) -> None:
        child = self.child("ignored child")
        (self.parent / ".gitignore").write_text("ignored child/\n")
        self.git(self.parent, "add", ".gitignore")
        self.git(self.parent, "commit", "-m", "ignore child fixture")
        before = self.index()
        child_before = tree_fingerprint(child / ".git")
        code, output = self.run_script()
        self.assertNotEqual(0, code, output)
        self.assertEqual(before, self.index())
        self.assertEqual(child_before, tree_fingerprint(child / ".git"))
        self.assertTrue((child / ".git").is_dir())
        self.assertFalse((self.parent / ".gitmodules").exists())

    def test_glob_metacharacters_in_child_path_are_treated_literally(self) -> None:
        child = self.child("子[仓]*?库")
        self.git(child, "remote", "set-url", "origin", "https://example.invalid/Jobs/safe-url.git")
        code, output = self.run_script()
        self.assertEqual(0, code, output)
        self.assert_linked(child)
        self.assertEqual(child.name, self.git(self.parent, "config", "-f", ".gitmodules", f"submodule.{child.name}.path"))

    def test_existing_association_is_idempotent_and_preserves_gitmodules_options(self) -> None:
        child = self.child()
        self.register(child, section="custom section 中文", url="../relative-url.git")
        for key, value in {"branch": "custom-branch", "update": "none", "ignore": "dirty"}.items():
            self.git(self.parent, "config", "-f", ".gitmodules", f"submodule.custom section 中文.{key}", value)
        self.git(self.parent, "add", ".gitmodules")
        self.git(self.parent, "commit", "-m", "existing association")
        before_gm = (self.parent / ".gitmodules").read_bytes()
        before_index = self.index()
        before_config = (self.gitdir(self.parent) / "config").read_bytes()
        for _ in range(2):
            code, output = self.run_script()
            self.assertEqual(0, code, output)
        self.assert_linked(child, section="custom section 中文")
        self.assertEqual(before_gm, (self.parent / ".gitmodules").read_bytes())
        self.assertEqual(before_index, self.index())
        self.assertEqual(before_config, (self.gitdir(self.parent) / "config").read_bytes())

    def test_stale_gitmodules_entries_are_preserved(self) -> None:
        self.git(self.parent, "config", "-f", ".gitmodules", "submodule.stale.path", "missing checkout")
        self.git(self.parent, "config", "-f", ".gitmodules", "submodule.stale.url", "../missing.git")
        self.git(self.parent, "config", "-f", ".gitmodules", "submodule.stale.branch", "release")
        self.git(self.parent, "add", ".gitmodules")
        self.git(self.parent, "commit", "-m", "stale entry fixture")
        child = self.child()
        code, output = self.run_script()
        self.assertEqual(0, code, output)
        self.assert_linked(child)
        self.assertEqual("missing checkout", self.git(self.parent, "config", "-f", ".gitmodules", "submodule.stale.path"))
        self.assertEqual("../missing.git", self.git(self.parent, "config", "-f", ".gitmodules", "submodule.stale.url"))
        self.assertEqual("release", self.git(self.parent, "config", "-f", ".gitmodules", "submodule.stale.branch"))

    def test_unrelated_staged_content_is_preserved(self) -> None:
        (self.parent / "seed.txt").write_text("parent staged edit\n")
        self.git(self.parent, "add", "seed.txt")
        staged = self.git(self.parent, "show", ":seed.txt")
        child = self.child()
        code, output = self.run_script()
        self.assertEqual(0, code, output)
        self.assert_linked(child)
        self.assertEqual(staged, self.git(self.parent, "show", ":seed.txt"))

    def test_parent_staged_gitlink_is_not_overwritten_by_later_child_head(self) -> None:
        child = self.child()
        self.register(child)
        self.git(self.parent, "commit", "-m", "baseline registered child")
        (child / "seed.txt").write_text("child commit B\n")
        self.git(child, "add", "seed.txt")
        self.git(child, "commit", "-m", "child B")
        self.git(self.parent, "add", "--", child.name)
        staged_before = self.index()
        (child / "seed.txt").write_text("child commit C\n")
        self.git(child, "add", "seed.txt")
        self.git(child, "commit", "-m", "child C")
        self.run_script()
        self.assertEqual(staged_before, self.index())

    def test_no_origin_is_refused_without_fake_url_or_metadata_move(self) -> None:
        child = self.child(origin=False)
        before = self.index()
        code, output = self.run_script()
        self.assertNotEqual(0, code, output)
        self.assertEqual(before, self.index())
        self.assertTrue((child / ".git").is_dir())
        self.assertFalse((self.parent / ".gitmodules").exists())

    def test_unborn_child_is_refused_without_partial_registration(self) -> None:
        child = self.child(commit=False)
        before = self.index()
        code, output = self.run_script()
        self.assertNotEqual(0, code, output)
        self.assertEqual(before, self.index())
        self.assertTrue((child / ".git").is_dir())
        self.assertFalse((self.parent / ".gitmodules").exists())

    def test_invalid_child_preflight_prevents_mutations_of_valid_child(self) -> None:
        valid = self.child("a valid child")
        invalid = self.child("z invalid child", origin=False)
        before_index = self.index()
        valid_before = tree_fingerprint(valid / ".git")
        invalid_before = tree_fingerprint(invalid / ".git")
        code, output = self.run_script()
        self.assertNotEqual(0, code, output)
        self.assertEqual(before_index, self.index())
        self.assertEqual(valid_before, tree_fingerprint(valid / ".git"))
        self.assertEqual(invalid_before, tree_fingerprint(invalid / ".git"))
        self.assertFalse((self.parent / ".gitmodules").exists())

    def test_gitmodules_matching_staged_content_is_allowed(self) -> None:
        self.git(self.parent, "config", "-f", ".gitmodules", "submodule.stale.path", "missing")
        self.git(self.parent, "config", "-f", ".gitmodules", "submodule.stale.url", "../initial.git")
        self.git(self.parent, "add", ".gitmodules")
        child = self.child()
        code, output = self.run_script()
        self.assertEqual(0, code, output)
        self.assert_linked(child)
        self.assertEqual("../initial.git", self.git(self.parent, "config", "-f", ".gitmodules", "submodule.stale.url"))

    def test_tracked_regular_child_files_are_not_replaced_by_gitlink(self) -> None:
        directory = self.parent / "tracked child"
        directory.mkdir()
        (directory / "seed.txt").write_text("parent tracked source\n")
        self.git(self.parent, "add", "--", "tracked child/seed.txt")
        self.git(self.parent, "commit", "-m", "parent owns child file")
        child = self.init_repo(directory)
        before = self.index()
        code, output = self.run_script()
        self.assertNotEqual(0, code, output)
        self.assertEqual(before, self.index())
        self.assertTrue((child / ".git").is_dir())

    def test_gitmodules_partial_stage_is_protected(self) -> None:
        self.git(self.parent, "config", "-f", ".gitmodules", "submodule.stale.path", "missing")
        self.git(self.parent, "config", "-f", ".gitmodules", "submodule.stale.url", "../initial.git")
        self.git(self.parent, "add", ".gitmodules")
        self.git(self.parent, "commit", "-m", "initial metadata")
        self.git(self.parent, "config", "-f", ".gitmodules", "submodule.stale.url", "../staged.git")
        self.git(self.parent, "add", ".gitmodules")
        self.git(self.parent, "config", "-f", ".gitmodules", "submodule.stale.url", "../unstaged.git")
        child = self.child()
        before = self.index(), (self.parent / ".gitmodules").read_bytes()
        code, output = self.run_script()
        self.assertNotEqual(0, code, output)
        self.assertEqual(before, (self.index(), (self.parent / ".gitmodules").read_bytes()))
        self.assertTrue((child / ".git").is_dir())

    def test_linked_worktree_is_refused_without_relocating_metadata(self) -> None:
        source = self.init_repo(self.sandbox / "external worktree source")
        child = self.parent / "linked child"
        self.git(source, "worktree", "add", "-b", "linked-branch", str(child))
        before_index = self.index()
        before_pointer = (child / ".git").read_bytes()
        before_source = tree_fingerprint(source / ".git")
        code, output = self.run_script()
        self.assertNotEqual(0, code, output)
        self.assertEqual(before_index, self.index())
        self.assertEqual(before_pointer, (child / ".git").read_bytes())
        self.assertEqual(before_source, tree_fingerprint(source / ".git"))
        self.assertFalse((self.parent / ".gitmodules").exists())

    def test_modules_target_collision_preserves_both_git_histories(self) -> None:
        child = self.child("conflicting-child")
        collision = self.init_repo(self.gitdir(self.parent) / "modules" / child.name)
        collision_before = tree_fingerprint(collision)
        child_before = tree_fingerprint(child / ".git")
        before_index = self.index()
        code, output = self.run_script()
        self.assertNotEqual(0, code, output)
        self.assertEqual(before_index, self.index())
        self.assertEqual(collision_before, tree_fingerprint(collision))
        self.assertEqual(child_before, tree_fingerprint(child / ".git"))
        self.assertTrue((child / ".git").is_dir())

    def test_dry_run_leaves_index_gitmodules_config_and_metadata_unchanged(self) -> None:
        child = self.child()
        before_index = self.index()
        before_parent_git = tree_fingerprint(self.gitdir(self.parent))
        before_child_git = tree_fingerprint(child / ".git")
        code, output = self.run_script("--dry-run")
        self.assertEqual(0, code, output)
        self.assertEqual(before_index, self.index())
        self.assertEqual(before_parent_git, tree_fingerprint(self.gitdir(self.parent)))
        self.assertEqual(before_child_git, tree_fingerprint(child / ".git"))
        self.assertFalse((self.parent / ".gitmodules").exists())

    def test_enter_skips_actual_update_without_mutations(self) -> None:
        child = self.child()
        before_index = self.index()
        before_parent = tree_fingerprint(self.gitdir(self.parent))
        before_child = tree_fingerprint(child / ".git")
        self.run_script(confirmation=b"\n\n")
        self.assertEqual(before_index, self.index())
        self.assertEqual(before_parent, tree_fingerprint(self.gitdir(self.parent)))
        self.assertEqual(before_child, tree_fingerprint(child / ".git"))
        self.assertFalse((self.parent / ".gitmodules").exists())

    def test_non_tty_write_run_is_refused_without_mutations(self) -> None:
        child = self.child()
        before_parent = tree_fingerprint(self.gitdir(self.parent))
        before_child = tree_fingerprint(child / ".git")
        process = subprocess.run(
            ["/bin/zsh", str(self.parent / SCRIPT_NAME)], cwd=self.sandbox,
            env=self.env, input="y\n", capture_output=True, text=True, timeout=25,
        )
        self.assertNotEqual(0, process.returncode, process.stdout + process.stderr)
        self.assertEqual(before_parent, tree_fingerprint(self.gitdir(self.parent)))
        self.assertEqual(before_child, tree_fingerprint(child / ".git"))
        self.assertFalse((self.parent / ".gitmodules").exists())
        self.assertNotIn("\x1b[", process.stdout + process.stderr)

    def test_help_and_env_dryrun_work_without_tty_or_mutations(self) -> None:
        child = self.child()
        before_parent = tree_fingerprint(self.gitdir(self.parent))
        before_child = tree_fingerprint(child / ".git")
        for args, extra_env in [(["--help"], {}), ([], {"DRY_RUN": "1"})]:
            process = subprocess.run(
                ["/bin/zsh", str(self.parent / SCRIPT_NAME), *args], cwd=self.sandbox,
                env=dict(self.env, **extra_env), input="", capture_output=True, text=True, timeout=25,
            )
            self.assertEqual(0, process.returncode, process.stdout + process.stderr)
            self.assertEqual(before_parent, tree_fingerprint(self.gitdir(self.parent)))
            self.assertEqual(before_child, tree_fingerprint(child / ".git"))
            self.assertFalse((self.parent / ".gitmodules").exists())
            self.assertNotIn("\x1b[", process.stdout + process.stderr)

    def test_symlink_gitmodules_is_refused_without_writing_external_target(self) -> None:
        child = self.child()
        target = self.sandbox / "outside gitmodules"
        target.write_text("# keep external content\n")
        (self.parent / ".gitmodules").symlink_to(target)
        before_index = self.index()
        code, output = self.run_script()
        self.assertNotEqual(0, code, output)
        self.assertEqual("# keep external content\n", target.read_text())
        self.assertEqual(before_index, self.index())
        self.assertTrue((child / ".git").is_dir())
        self.assertTrue((self.parent / ".gitmodules").is_symlink())

    def test_duplicate_registered_path_is_refused_without_mutation(self) -> None:
        child = self.child()
        for section in ["first", "second"]:
            self.git(self.parent, "config", "-f", ".gitmodules", f"submodule.{section}.path", child.name)
            self.git(self.parent, "config", "-f", ".gitmodules", f"submodule.{section}.url", "../relative.git")
        self.git(self.parent, "add", ".gitmodules")
        before_index = self.index()
        before_metadata = (self.parent / ".gitmodules").read_bytes()
        code, output = self.run_script()
        self.assertNotEqual(0, code, output)
        self.assertEqual(before_index, self.index())
        self.assertEqual(before_metadata, (self.parent / ".gitmodules").read_bytes())
        self.assertTrue((child / ".git").is_dir())

    def test_invalid_gitmodules_config_is_refused_without_mutation(self) -> None:
        child = self.child()
        (self.parent / ".gitmodules").write_text("[submodule \"unterminated\n")
        self.git(self.parent, "add", ".gitmodules")
        before_index = self.index()
        before_metadata = (self.parent / ".gitmodules").read_bytes()
        code, output = self.run_script()
        self.assertNotEqual(0, code, output)
        self.assertEqual(before_index, self.index())
        self.assertEqual(before_metadata, (self.parent / ".gitmodules").read_bytes())
        self.assertTrue((child / ".git").is_dir())

    def test_nested_parent_uses_actual_gitdir_for_absorption(self) -> None:
        outer = self.init_repo(self.sandbox / "outer repo")
        nested = outer / "nested parent"
        shutil.move(str(self.parent), nested)
        self.parent = nested
        self.git(outer, "config", "-f", ".gitmodules", "submodule.nested parent.path", "nested parent")
        self.git(outer, "config", "-f", ".gitmodules", "submodule.nested parent.url", "../nested.git")
        self.git(outer, "add", ".gitmodules")
        self.git(outer, "update-index", "--add", "--cacheinfo", f"160000,{self.head(nested)},nested parent")
        self.git(outer, "submodule", "absorbgitdirs", "--", "nested parent")
        child = self.child()
        code, output = self.run_script()
        self.assertEqual(0, code, output)
        self.assert_linked(child)
        self.assertTrue((nested / ".git").is_file())
        self.assertIn("modules/nested parent/modules", str(self.gitdir(child)))

    def test_only_direct_child_git_is_discovered(self) -> None:
        direct = self.child("direct")
        grandchild = self.init_repo(direct / "grandchild")
        loose_nested = self.init_repo(self.parent / "ordinary folder" / "nested git")
        code, output = self.run_script()
        self.assertEqual(0, code, output)
        self.assert_linked(direct)
        self.assertTrue((grandchild / ".git").is_dir())
        self.assertTrue((loose_nested / ".git").is_dir())
        paths = self.git(self.parent, "config", "-f", ".gitmodules", "--get-regexp", r"\.path$")
        self.assertEqual("submodule.direct.path direct", paths)


def main() -> None:
    """Select the candidate and run tests while retaining logs and fixtures for review."""
    global SCRIPT_SOURCE
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "script", type=Path, nargs="?", default=Path(__file__).resolve().parents[1] / SCRIPT_NAME,
        help="Candidate updater; defaults to the entrypoint beside tests/ and only runs as a disposable copy",
    )
    parser.add_argument("tests", nargs="*", help="Optional unittest case names")
    options = parser.parse_args()
    SCRIPT_SOURCE = options.script.resolve(strict=True)
    print(f"Candidate: {SCRIPT_SOURCE}\nDisposable fixtures: {ARTIFACT_ROOT}", flush=True)
    names = options.tests or ["AssociationTests"]
    suite = unittest.TestLoader().loadTestsFromNames(names, module=sys.modules[__name__])
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(not result.wasSuccessful())


if __name__ == "__main__":
    main()
