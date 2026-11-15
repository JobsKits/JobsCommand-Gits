#!/usr/bin/env python3
# Created by Jobs on 2026年10月18日，星期日.
"""Verify standalone downloaders with disposable repositories and file-only transport."""

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

import hashlib
import os
from pathlib import Path
import pty
import re
import shlex
import subprocess
import tempfile
import unittest

SCRIPT_NAME = "【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command"
GENESIS = Path(__file__).resolve().parents[4]
CANDIDATES = [Path(__file__).resolve().parents[1] / SCRIPT_NAME]
CANDIDATES += [GENESIS / folder / SCRIPT_NAME for folder in (
    "", "JobsConfigOS", "JobsPythonTools.py", "OS@Extension/MacOS@Extension", "JobsConfigOS/💻JobsCodexConfigs",
)]
CANDIDATES += [
    GENESIS.parent / "JobsBaseConfig" / SCRIPT_NAME,
    GENESIS / "JobsConfigOS/⚙️VScodeConfigs" / SCRIPT_NAME / SCRIPT_NAME,
]
SOURCES = list(dict.fromkeys(path for path in CANDIDATES if path.is_file()))
CONFIG_PATTERN = r"(?ms)^[ \t]*SUBMODULE_REPO_URLS=\(\n.*?^[ \t]*\)"
_READONLY_ENGINE_CACHE: dict[tuple[str, str], str] = {}


def render_readonly_engine(source: Path) -> str:
    """Render the shipped engine, including its current shared-function bootstrap."""
    content = source.read_text(encoding="utf-8")
    cache_key = (str(source.resolve()), hashlib.sha256(content.encode()).hexdigest())
    if cache_key in _READONLY_ENGINE_CACHE:
        return _READONLY_ENGINE_CACHE[cache_key]
    if not re.search(r"(?m)^render_readonly_pull_engine\s*\(\s*\)", content):
        engine = content.split("<<'JOBS_READONLY_PULL_ENGINE'\n", 1)[1].split("\nJOBS_READONLY_PULL_ENGINE", 1)[0]
    else:
        library, removed = re.subn(r'(?m)^main "\$@"[ \t]*\Z', "", content.rstrip("\r\n"), count=1)
        if removed != 1:
            raise AssertionError(f"Downloader has no unique final entrypoint: {source}")
        with tempfile.TemporaryDirectory(prefix="jobs-render-readonly-") as temporary:
            root = Path(temporary)
            script = root / "library.zsh"
            script.write_text(library, encoding="utf-8")
            environment = {
                "HOME": temporary, "ZDOTDIR": temporary, "TMPDIR": temporary,
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "C", "NO_COLOR": "1",
                "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
                "GIT_ALLOW_PROTOCOL": "file", "GIT_TERMINAL_PROMPT": "0",
                "GIT_ASKPASS": "/usr/bin/false", "GIT_SSH_COMMAND": "/usr/bin/false",
                "SSH_ASKPASS": "/usr/bin/false",
            }
            result = subprocess.run(
                ["/bin/zsh", "-f", "-c", 'source "$1"\nrender_readonly_pull_engine',
                 "render-readonly", str(script)],
                cwd=root, env=environment, capture_output=True, text=True, timeout=10,
            )
            if result.returncode:
                raise AssertionError(f"Cannot render {source}: {result.stderr}")
            engine = result.stdout
    syntax = subprocess.run(
        ["/bin/zsh", "-f", "-n"], input=engine, capture_output=True, text=True, timeout=10,
    )
    if syntax.returncode:
        raise AssertionError(f"Rendered engine is not valid zsh for {source}: {syntax.stderr}")
    _READONLY_ENGINE_CACHE[cache_key] = engine
    return engine


class DownloaderLatestTests(unittest.TestCase):
    """Load real functions after removing the entrypoint; refuse network and real hooks."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix='jobs-downloader-latest-')
        self.root = Path(self.tmp.name).resolve()
        (self.root / 'home').mkdir()
        self.env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
        self.env.update(
            HOME=str(self.root / 'home'), TMPDIR=str(self.root),
            XDG_CONFIG_HOME=str(self.root / 'home/xdg'),
            GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL='/dev/null',
            GIT_CONFIG_COUNT='1', GIT_CONFIG_KEY_0='core.hooksPath',
            GIT_CONFIG_VALUE_0='/dev/null', GIT_ALLOW_PROTOCOL='file',
            GIT_TERMINAL_PROMPT='0', GIT_ASKPASS='/usr/bin/false',
            GIT_SSH_COMMAND='/usr/bin/false', SSH_ASKPASS='/usr/bin/false',
            GIT_AUTHOR_NAME='Offline Test', GIT_AUTHOR_EMAIL='offline@example.invalid',
            GIT_COMMITTER_NAME='Offline Test', GIT_COMMITTER_EMAIL='offline@example.invalid',
            PATH='/usr/bin:/bin:/usr/sbin:/sbin', NO_COLOR='1', TERM='dumb',
        )

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def shell(
        self, source: Path, body: str, *, tty_input: str | None = None, expected: int = 0,
    ) -> str:
        """Load real functions after removing the entrypoint, without initial side effects."""
        lib = self.root / 'library.zsh'
        lib.write_text(re.sub('(?m)^main "\\$@"\\s*$', '', source.read_text()))
        prefix = r'''setopt ERR_EXIT PIPE_FAIL NO_NOMATCH
original_path="$PATH"
original_pwd="$PWD"
source "$1"
shift
CASE_ROOT="$1"
[[ "$PATH" == "$original_path" && "$PWD" == "$original_pwd" ]]
LOG_FILE="$CASE_ROOT/output.log"
'''
        args = ['/bin/zsh', '-f', '-c', prefix + body, 'offline-latest', str(lib), str(self.root)]
        if tty_input is not None:
            master, slave = pty.openpty()
            proc = subprocess.Popen(
                args, cwd=self.root, env=self.env, stdin=slave,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            )
            os.close(slave)
            try:
                os.write(master, tty_input.encode())
                out, err = proc.communicate(timeout=20)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.communicate()
                raise
            finally:
                os.close(master)
            code = proc.returncode
        else:
            r = subprocess.run(
                args, cwd=self.root, env=self.env, stdin=subprocess.DEVNULL,
                capture_output=True, text=True, timeout=20,
            )
            code = r.returncode
            out = r.stdout
            err = r.stderr
        self.assertEqual(expected, code, f'{source}: {out}{err}')
        return out + err

    def git(self, repo: Path, *args: str) -> str:
        """Run Git only in the disposable fixture, with real hooks disabled."""
        r = subprocess.run(
            ['/usr/bin/git', '-c', 'core.hooksPath=/dev/null', '-C', str(repo), *args],
            env=self.env, capture_output=True, text=True, timeout=20,
        )
        self.assertEqual(0, r.returncode, r.stdout + r.stderr)
        return r.stdout.strip()

    def fixture(self, key: str) -> tuple[Path, Path, Path, Path]:
        """Create a parent Git pointer file and children whose section names differ from paths."""
        root = (self.root / key).resolve()
        root.mkdir()
        leaf = root / 'leaf'
        seed = root / 'seed parent'
        outer = root / 'outer'
        for repo in (leaf, seed, outer):
            repo.mkdir()
            self.git(repo, 'init', '-q', '-b', 'main')
            self.git(repo, 'commit', '--allow-empty', '-qm', 'fixture')
        (leaf / 'seed').write_text('leaf\n')
        self.git(leaf, 'add', 'seed')
        self.git(leaf, 'commit', '-qm', 'leaf seed')
        self.git(seed, 'submodule', 'add', '-q', '--name', 'real-section', leaf.as_uri(), '目标 child')
        self.git(seed, 'submodule', 'add', '-q', '--name', 'bypass-section', leaf.as_uri(), '旁路 child')
        self.git(seed, 'commit', '-qam', 'children')
        self.git(outer, 'submodule', 'add', '-q', '--name', 'parent-section', seed.as_uri(), 'parent tree')
        parent = outer / 'parent tree'
        self.git(parent, 'submodule', 'update', '--init', '--recursive')
        parent_git = Path(self.git(parent, 'rev-parse', '--absolute-git-dir'))
        return (parent, parent_git / 'modules/real-section', parent_git / 'modules/bypass-section', leaf)

    def script_body(self, parent: Path) -> str:
        """Exercise real local Git without automatically publishing the parent."""
        return f"cd {shlex.quote(str(parent))}\n" + r'''CONFIG_PATHS=('目标 child')
SUBMODULE_BRANCH=main
SUBMODULE_SHALLOW_CLONE=0
SUBMODULE_FETCH_TAGS=0
PRUNE_STALE_GITMODULES=0
AUTO_PARENT_COMMIT=0
AUTO_PARENT_PUSH=0
GITMODULES_RECONCILED=0
REMOTE_NAME=origin
GIT_URL_STYLE=auto
repo_name_by_path() { print -r -- "$1"; }
'''

    def test_common_implementation_and_independent_configurations(self) -> None:
        configurations = set()
        self.assertTrue(SOURCES, 'the standalone downloader is missing')
        for source in SOURCES:
            with self.subTest(script=source):
                content = source.read_text(encoding='utf-8')
                config = re.search(CONFIG_PATTERN, content)
                self.assertIsNotNone(config, str(source))
                configurations.add(config.group())
                outer = re.sub(
                    r"(?ms)(<<'JOBS_READONLY_PULL_ENGINE'\r?\n).*?(^JOBS_READONLY_PULL_ENGINE[ \t]*$)",
                    r"\1\2", content, count=1,
                )
                self.assertEqual(1, len(re.findall('^main\\(\\)', outer, re.M)))
                self.assertEqual(1, outer.count('main "$@"'))
                self.assertNotIn('jobs_run_original_script', content)
                self.assertNotIn('run_original_logic', content)
                self.assertNotIn('collect_existing_child_git_dirs', content)
                # 各仓可有不同附加流程；校验取消选择时的行为，不能用逐行格式或
                # 整文件相等约束已支持的可选安装与真实退出码传播。
                output = self.shell(source, r'''
select_download_operation_mode() { print SELECT; return 19; }
run_selected_download_mode() { print UNEXPECTED_DOWNLOAD; }
offer_global_markdown_toc_setup() { print UNEXPECTED_SETUP; }
main
''', expected=19)
                self.assertIn('SELECT', output)
                self.assertNotIn('UNEXPECTED_', output)
        if len(SOURCES) > 1:
            self.assertGreater(len(configurations), 1)

    def test_declarations_do_not_execute_or_change_environment(self) -> None:
        for source in SOURCES:
            with self.subTest(source=source):
                self.shell(source, r'''[[ -z "$SCRIPT_DIR" && -z "$REPO_ROOT" ]]
[[ ! -e "$LOG_FILE" ]]
[[ ! -e "$CASE_ROOT/home/.zprofile" ]]
''')

    def test_root_and_package_paths_with_unicode_and_spaces(self) -> None:
        for i, source in enumerate(SOURCES):
            with self.subTest(source=source):
                target = self.root / f'case {i} 中文'
                target.mkdir()
                subprocess.run(['/usr/bin/git', 'init', '-q', str(target)], env=self.env, check=True)
                name = source.name
                (target / name).write_text('fixture')
                package = target / name
                package.unlink()
                package.mkdir()
                (package / name).write_text('fixture')
                self.shell(source, f'expected={str(target.resolve())!r}\nSCRIPT_FILE="$expected/{name}/{name}"\ninitialize_script_paths\n[[ "$SCRIPT_DIR" == "$expected/{name}" && "$REPO_ROOT" == "$expected" ]]\nLOG_FILE="$CASE_ROOT/output.log"\ncd_to_script_dir\nensure_repo_initialized\nSCRIPT_FILE="$expected/{name}"\ninitialize_script_paths\n[[ "$REPO_ROOT" == "$expected" ]]\n')

    def test_wrong_root_is_rejected_without_initializing_nested_repo(self) -> None:
        for i, source in enumerate(SOURCES):
            with self.subTest(source=source):
                target = self.root / f'parent-{i}'
                target.mkdir()
                (target / 'wrong-layer').mkdir()
                subprocess.run(['/usr/bin/git', 'init', '-q', str(target)], env=self.env, check=True)
                self.shell(source, f"cd {str(target / 'wrong-layer')!r}\nif ensure_repo_initialized; then print UNEXPECTED_SUCCESS; exit 92; fi\n[[ ! -e .git ]]\n")

    def test_full_sync_reuses_configured_paths_without_delete_or_global_confirmation(self) -> None:
        for source in SOURCES:
            with self.subTest(source=source):
                trace = self.root / 'trace'
                trace.unlink(missing_ok=True)
                self.shell(source, r'''CONFIG_PATHS=('Child with space' '第二个 child')
repo_name_by_path() { print UNEXPECTED_LEGACY_LOOKUP; return 1; }
reconcile_gitmodules_with_config_once() { print RECONCILE >> "$CASE_ROOT/trace"; }
sync_selected_submodules_to_latest() { printf 'SYNC %s\n' "$@" >> "$CASE_ROOT/trace"; }
stage_and_commit_parent_changes() { printf 'STAGE %s\n' "$@" >> "$CASE_ROOT/trace"; }
parent_push_if_needed() { print PUSH_POLICY >> "$CASE_ROOT/trace"; }
full_sync_to_latest
''')
                self.assertEqual([
                    'RECONCILE', 'SYNC Child with space', 'SYNC 第二个 child',
                    'STAGE Child with space', 'STAGE 第二个 child', 'PUSH_POLICY',
                ], trace.read_text().splitlines())
                content = source.read_text(encoding='utf-8')
                for obsolete in ('collect_full_delete_targets()', 'confirm_full_rebuild()', 'remove_worktree_dir_safely()'):
                    self.assertNotIn(obsolete, content)

    def test_full_failure_propagates_before_later_actions(self) -> None:
        for source in SOURCES:
            with self.subTest(source=source):
                output = self.shell(source, r'''reconcile_gitmodules_with_config_once() { print EXPECTED_FAILURE; return 37; }
sync_selected_submodules_to_latest() { print UNEXPECTED_SYNC; }
success_echo() { print UNEXPECTED_SUCCESS; }
if full_sync_to_latest; then print UNEXPECTED_ZERO; exit 93; fi
''')
                self.assertIn('EXPECTED_FAILURE', output)
                self.assertNotIn('UNEXPECTED_', output)

    def test_explicit_stale_prune_requires_its_own_terminal_yes(self) -> None:
        for source in SOURCES:
            with self.subTest(source=source):
                self.assertIn('未执行删除', self.shell(
                    source, "confirm_stale_submodule_removal 'Legacy child'\n", expected=1,
                ))
                for answer in ('\n', 'yes\n', 'YES \n'):
                    self.assertIn('停止旧登记裁剪', self.shell(
                        source, "confirm_stale_submodule_removal 'Legacy child'\n",
                        tty_input=answer, expected=1,
                    ))
                self.shell(source, "confirm_stale_submodule_removal 'Legacy child'\n", tty_input='YES\n')
                self.assertIn('仅展示旧登记裁剪', self.shell(
                    source, "DRY_RUN=1\nconfirm_stale_submodule_removal 'Legacy child'\n",
                ))

    def test_multiselect_back_returns_to_menu_with_err_exit(self) -> None:
        for source in SOURCES:
            with self.subTest(source=source):
                counter = self.root / 'counter'
                counter.unlink(missing_ok=True)
                output = self.shell(source, r'''build_intro_content() { print preview; }
select_menu_action() {
 if [[ -f "$CASE_ROOT/counter" ]]; then print 2 >> "$CASE_ROOT/counter"; print '退出'; else print 1 > "$CASE_ROOT/counter"; print '选择指定子模块同步（可多选）'; fi
}
select_configured_submodules_interactive() { return 2; }
menu_result=0
main_menu_loop "$CASE_ROOT/preview" || menu_result=$?
if (( $+functions[run_download_selection_loop] )); then
 [[ "$menu_result" == 130 ]]
else
 [[ "$menu_result" == 0 ]]
fi
[[ "$(cat "$CASE_ROOT/counter")" == $'1\n2' ]]
''')
                self.assertIn('已退出', output)

    def test_menu_action_failure_is_not_success(self) -> None:
        for source in SOURCES:
            for action, func in [('全量同步更新下载到最新', 'full_sync_to_latest'), ('只更新目前已有的', 'update_existing_to_latest'), ('添加并同步一个新的 Git 地址', 'add_new_git_url_interactive')]:
                with self.subTest(source=source, action=action):
                    self.shell(source, f'build_intro_content() {{ print preview; }}\nsynchronize_parent_repository() {{ return 0; }}\nselect_menu_action() {{ print -r -- {action!r}; }}\n{func}() {{ return 37; }}\nif main_menu_loop "$CASE_ROOT/preview"; then print UNEXPECTED_ZERO; exit 94; fi\n')

    def test_recursion_menu_choice_changes_mode_and_cancel_preserves_previous_mode(self) -> None:
        for source in SOURCES:
            with self.subTest(source=source):
                self.shell(source, r'''
[[ "$SUBMODULE_RECURSIVE" == 1 && "$(submodule_recursion_label)" == *向下递归* ]]
fzf() {
 cat >/dev/null
 (( $+functions[run_download_selection_loop] )) && print ''
 print -r -- '仅直属一层（不拉取下层）'
}
select_submodule_recursion_interactive
[[ "$SUBMODULE_RECURSIVE" == 0 && "$(submodule_recursion_label)" == *仅直属一层* ]]
fzf() { cat >/dev/null; return 130; }
picker_result=0
select_submodule_recursion_interactive || picker_result=$?
[[ "$SUBMODULE_RECURSIVE" == 0 ]]
if (( $+functions[run_download_selection_loop] )); then [[ "$picker_result" == 130 ]]; fi
fzf() {
 cat >/dev/null
 (( $+functions[run_download_selection_loop] )) && print ''
 print -r -- '向下递归（所选子树逐层最新）'
}
select_submodule_recursion_interactive
[[ "$SUBMODULE_RECURSIVE" == 1 ]]
fzf() { cat >/dev/null; return 130; }
picker_result=0
select_submodule_recursion_interactive || picker_result=$?
[[ "$SUBMODULE_RECURSIVE" == 1 ]]
''')

    def test_symlink_selection_is_rejected_before_remote_or_worktree_mutation(self) -> None:
        for index, source in enumerate(SOURCES):
            with self.subTest(source=source):
                target = self.root / f"outside-{index}"
                target.mkdir()
                self.git(target, "init", "-q")
                self.git(target, "commit", "--allow-empty", "-qm", "fixture")
                self.git(target, "remote", "add", "origin", "https://must-preserve.invalid/repo")
                pointer = self.root / f"symlink-{index}"
                pointer.symlink_to(target, target_is_directory=True)
                before = (target / ".git/config").read_bytes()
                output = self.shell(source, f"selected={shlex.quote(pointer.name)}\n" + r'''
clone_url_for_path() { print UNEXPECTED_URL_LOOKUP; return 1; }
if sync_selected_submodules_to_latest "$selected"; then print UNEXPECTED_SUCCESS; exit 98; fi
''')
                self.assertNotIn("UNEXPECTED_", output)
                self.assertIn("拒绝", output)
                self.assertEqual(before, (target / ".git/config").read_bytes())

    def test_nested_configured_paths_keep_the_classification_directory(self) -> None:
        for source in SOURCES:
            with self.subTest(source=source):
                self.shell(source, r'''
SUBMODULE_REPO_URLS=(
  'https://github.com/JobsKits/MacOS_Extension|OS@Extension/MacOS@Extension'
  'https://github.com/JobsKits/WindowsOS_Extension|OS@Extension/WindowsOS@Extension'
)
load_configured_submodules
[[ "${CONFIG_PATHS[1]}" == OS@Extension/MacOS@Extension ]]
[[ "${CONFIG_PATHS[2]}" == OS@Extension/WindowsOS@Extension ]]
[[ ! -e OS@Extension ]]
for invalid in '' /absolute 'OS@Extension/' 'OS@Extension//child' './child' '../child' 'OS@Extension/../child' 'OS@Extension/.GIT/child' 'OS@Extension/-child' 'OS@Extension/child|other' $'OS@Extension/child\t'; do
  if validate_local_path "$invalid"; then print -r -- "UNEXPECTED_ACCEPTED:$invalid"; exit 91; fi
done
''')

    def test_nested_clone_reuses_different_section_and_preserves_sibling(self) -> None:
        for index, source in enumerate(SOURCES):
            with self.subTest(source=source):
                case = self.root / f'nested-clone-{index}'
                parent, leaf = case / 'parent', case / 'leaf'
                for repo in (parent, leaf):
                    repo.mkdir(parents=True)
                    self.git(repo, 'init', '-q', '-b', 'main')
                    (repo / 'seed').write_text('fixture\n')
                    self.git(repo, 'add', 'seed')
                    self.git(repo, 'commit', '-qm', 'fixture')
                self.git(parent, 'remote', 'add', 'origin', 'https://code.example/team/Parent.git')
                nested = 'OS@Extension/WindowsOS@Extension'
                self.git(parent, 'config', '-f', '.gitmodules', 'submodule.Stable Windows section.path', nested)
                self.git(parent, 'config', '-f', '.gitmodules', 'submodule.Stable Windows section.url', leaf.as_uri())
                self.git(parent, 'config', '-f', '.gitmodules', 'submodule.Stable Windows section.update', 'checkout')
                body = self.script_body(parent) + f'leaf_url={shlex.quote(leaf.as_uri())}\n' + r'''
SUBMODULE_RECURSIVE=0
ensure_submodule_worktree_present 'OS@Extension/WindowsOS@Extension' "$leaf_url" main
ensure_gitmodules_entry 'OS@Extension/WindowsOS@Extension'
'''
                self.shell(source, body)
                child = parent / nested
                self.assertTrue((child / '.git').is_file())
                self.assertEqual(str(parent), self.git(child, 'rev-parse', '--show-superproject-working-tree'))
                self.assertEqual('OS@Extension/WindowsOS@Extension', self.git(parent, 'config', '-f', '.gitmodules', 'submodule.Stable Windows section.path'))
                self.assertEqual('checkout', self.git(parent, 'config', '-f', '.gitmodules', 'submodule.Stable Windows section.update'))
                self.assertTrue(self.git(parent, 'ls-files', '--stage', '--', nested).startswith('160000 '))
                sibling = parent / 'OS@Extension/MacOS@Extension'
                sibling.mkdir()
                (sibling / 'keep').write_bytes(b'keep sibling')
                self.git(parent, 'config', '-f', '.gitmodules', 'submodule.legacy.path', 'OS@Extension')
                self.git(parent, 'config', '-f', '.gitmodules', 'submodule.legacy.url', leaf.as_uri())
                before = (parent / '.gitmodules').read_bytes()
                output = self.shell(source, self.script_body(parent) + r'''
CONFIG_PATHS=('OS@Extension/WindowsOS@Extension')
PRUNE_STALE_GITMODULES=1
FORCE_DELETE=1
confirm_stale_submodule_removal() { print UNEXPECTED_CONFIRM; return 0; }
if prune_unconfigured_gitmodules; then print UNEXPECTED_PRUNE; exit 92; fi
''')
                self.assertNotIn('UNEXPECTED_', output)
                self.assertIn('保留分类目录', output)
                self.assertEqual(before, (parent / '.gitmodules').read_bytes())
                self.assertEqual(b'keep sibling', (sibling / 'keep').read_bytes())
                self.assertTrue((child / '.git').is_file())

    def test_nested_path_cannot_cross_an_independent_repository(self) -> None:
        for index, source in enumerate(SOURCES):
            with self.subTest(source=source):
                parent = self.root / f'nested-boundary-{index}'
                middle = parent / 'OS@Extension'
                middle.mkdir(parents=True)
                self.git(middle, 'init', '-q', '-b', 'main')
                before = (middle / '.git/config').read_bytes()
                output = self.shell(source, f'cd {shlex.quote(str(parent))}\n' + r'''
if validate_local_path 'OS@Extension/WindowsOS@Extension'; then print UNEXPECTED_ACCEPTED; exit 93; fi
if ensure_submodule_worktree_present 'OS@Extension/WindowsOS@Extension'; then print UNEXPECTED_CREATED; exit 94; fi
''')
                self.assertNotIn('UNEXPECTED_', output)
                self.assertEqual(before, (middle / '.git/config').read_bytes())
                self.assertFalse((middle / 'WindowsOS@Extension').exists())

    def test_nested_symlink_components_inside_parent_are_rejected_before_mutation(self) -> None:
        for index, source in enumerate(SOURCES):
            with self.subTest(source=source):
                parent = self.root / f'component-links-{index}'
                target = parent / 'existing/child'
                target.mkdir(parents=True)
                self.git(parent, 'init', '-q')
                self.git(target, 'init', '-q')
                self.git(target, 'commit', '--allow-empty', '-qm', 'fixture')
                self.git(target, 'remote', 'add', 'origin', 'https://must-preserve.invalid/repo')
                (parent / 'shortcut').symlink_to(parent / 'existing', target_is_directory=True)
                (parent / 'deep').mkdir()
                (parent / 'deep/link').symlink_to(target, target_is_directory=True)
                before = {name: (target / '.git' / name).read_bytes() for name in ('HEAD', 'config')}
                output = self.shell(source, f'cd {shlex.quote(str(parent))}\n' + r'''
clone_url_for_path() { print UNEXPECTED_URL_LOOKUP; return 1; }
for selected in 'shortcut/child' 'deep/link' '.git/child' 'deep/.git/child'; do
  if sync_selected_submodules_to_latest "$selected"; then print UNEXPECTED_SUCCESS; exit 99; fi
done
''')
                self.assertNotIn('UNEXPECTED_', output)
                self.assertEqual(before, {name: (target / '.git' / name).read_bytes() for name in before})

    def test_initialized_entry_stops_before_completion_on_failure(self) -> None:
        for source in SOURCES:
            with self.subTest(source=source):
                output = self.shell(source, r'''
SCRIPT_FILE="$CASE_ROOT/fixture.command"
TMPDIR="$CASE_ROOT"
show_script_intro_and_wait() { return 0; }
prepare_parent_repository() { print EXPECTED_PARENT_FAILURE; return 37; }
synchronize_parent_repository() { print UNEXPECTED_PARENT_UPDATE; }
ensure_fzf_healthy() { print UNEXPECTED_INSTALL; }
prepare_preview_runtime() { print UNEXPECTED_PREVIEW; }
main_menu_loop() { print UNEXPECTED_MENU; }
report_completion() { print UNEXPECTED_SUCCESS; }
run_management_download
''', expected=37)
                self.assertIn('EXPECTED_PARENT_FAILURE', output)
                self.assertNotIn('UNEXPECTED_', output)

    def test_intro_refuses_noninteractive_before_log_or_environment_writes(self) -> None:
        for source in SOURCES:
            with self.subTest(source=source):
                output = self.shell(source, r'''show_script_intro_and_wait
print UNEXPECTED_CONTINUED
''', expected=1)
                self.assertIn('当前没有可交互输入', output)
                self.assertNotIn('UNEXPECTED_', output)
                self.assertFalse((self.root / 'output.log').exists())

    def test_real_nested_parent_reuses_worktree_and_owned_cache_and_commits_only_association(self) -> None:
        for i, source in enumerate(SOURCES):
            with self.subTest(source=source):
                parent, cache, bypass, leaf = self.fixture(f'reuse-{i}')
                self.assertTrue((parent / '.git').is_file())
                self.assertTrue((parent / '目标 child/.git').is_file())
                (cache / 'old-target.marker').write_text('old target cache')
                (bypass / 'bypass.marker').write_text('must stay')
                before = {p: hashlib.sha256((bypass / p).read_bytes()).hexdigest() for p in ('config', 'HEAD', 'bypass.marker')}
                output = self.shell(source, self.script_body(parent) + r'''full_sync_to_latest
[[ -f '目标 child/.git' ]]
expected_cache="$(git rev-parse --absolute-git-dir)/modules/real-section"
[[ "$(git -C '目标 child' rev-parse --absolute-git-dir)" == "$expected_cache" ]]
[[ -f "$expected_cache/old-target.marker" ]]
[[ "$(git config -f .gitmodules submodule.real-section.path)" == '目标 child' ]]
# 关联提交只包含目标 gitlink，原有其它暂存仍留在索引中。
print unrelated > unrelated-staged.txt
git add -- unrelated-staged.txt
staged_before="$(git ls-files --stage -- unrelated-staged.txt)"
git -C '目标 child' commit --allow-empty -qm 'local fixture commit'
expected_head="$(git -C '目标 child' rev-parse HEAD)"
AUTO_PARENT_COMMIT=1
stage_and_commit_parent_changes '目标 child'
[[ "$(git ls-files --stage -- unrelated-staged.txt)" == "$staged_before" ]]
[[ "$(git rev-parse 'HEAD:目标 child')" == "$expected_head" ]]
if git cat-file -e HEAD:unrelated-staged.txt 2>/dev/null; then exit 94; fi
[[ "$(git -c core.quotepath=false diff-tree --no-commit-id --name-only -r HEAD)" == '目标 child' ]]
''')
                self.assertIn('全量同步完成', output)
                self.assertEqual(before, {p: hashlib.sha256((bypass / p).read_bytes()).hexdigest() for p in before})

    def test_cache_ownership_symlinks_and_overlapping_modules_are_rejected(self) -> None:
        source = SOURCES[0]
        for mode in ('wrong-owner', 'symlink', 'overlap', 'linked-worktree'):
            with self.subTest(mode=mode):
                parent, cache, bypass, leaf = self.fixture(mode)
                (cache / 'keep.marker').write_text('keep target')
                (bypass / 'keep.marker').write_text('keep bypass')
                before = (cache / 'keep.marker').read_bytes()
                if mode == 'wrong-owner':
                    self.git(parent, 'config', '--file', str(cache / 'config'), 'core.worktree', str(parent / '旁路 child'))
                if mode == 'symlink':
                    saved = cache.with_name('saved-cache')
                    cache.rename(saved)
                    cache.symlink_to(bypass, target_is_directory=True)
                if mode == 'overlap':
                    self.git(parent, 'config', '-f', '.gitmodules', 'submodule.real-section/other.path', 'other')
                    self.git(parent, 'config', '-f', '.gitmodules', 'submodule.real-section/other.url', leaf.as_uri())
                if mode == 'linked-worktree':
                    (cache / 'worktrees').mkdir()
                    (cache / 'worktrees/other').mkdir()
                output = self.shell(source, self.script_body(parent) + "if submodule_cache_for_removal '目标 child'; then print UNEXPECTED_ACCEPTED; exit 95; fi\n")
                self.assertIn('拒绝复用', output)
                self.assertNotIn('UNEXPECTED_', output)
                self.assertEqual(b'keep bypass', (bypass / 'keep.marker').read_bytes())
                if mode != 'symlink':
                    self.assertEqual(before, (cache / 'keep.marker').read_bytes())

    def test_real_absorb_collision_stops_registration_and_update_success(self) -> None:
        for i, source in enumerate(SOURCES):
            with self.subTest(source=source):
                parent, cache, bypass, leaf = self.fixture(f'collision-{i}')
                self.git(parent, 'submodule', 'deinit', '-f', '--', '目标 child')
                target = parent / '目标 child'
                target.rmdir()
                self.git(parent, 'clone', '-q', leaf.as_uri(), '目标 child')
                self.assertTrue((target / '.git').is_dir())
                self.assertTrue(cache.is_dir())
                output = self.shell(source, self.script_body(parent) + r'''if ensure_submodule_worktree_present '目标 child'; then print UNEXPECTED_REGISTERED; exit 96; fi
if sync_one_submodule_to_latest '目标 child'; then print UNEXPECTED_SYNCED; exit 97; fi
''')
                self.assertIn('子模块元数据归集失败', output)
                self.assertNotIn('UNEXPECTED_', output)
                self.assertNotIn('已登记标准子模块', output)
                self.assertNotIn('已浅同步', output)
                self.assertTrue((target / '.git').is_dir())
                self.assertTrue(cache.is_dir())


    def test_fzf_navigation_never_runs_business_on_back_empty_or_cancel(self) -> None:
        for source in SOURCES:
            if "run_download_selection_loop()" not in source.read_text():
                continue
            with self.subTest(source=source):
                output = self.shell(source, r'''
CONFIG_PATHS=('目标 child' 'second child')
build_submodule_picker_content() { print preview; }
synchronize_parent_repository() { print UNEXPECTED_PARENT; }
reconcile_gitmodules_with_config_once() { print UNEXPECTED_RECONCILE; }
sync_selected_submodules_to_latest() { print UNEXPECTED_SYNC; }
stage_and_commit_parent_changes() { print UNEXPECTED_COMMIT; }
parent_push_if_needed() { print UNEXPECTED_PUSH; }
fzf() { cat >/dev/null; print -r -- left; return 1; }
picker_result=0
select_configured_submodules_interactive "$CASE_ROOT/preview" || picker_result=$?
[[ "$picker_result" == 2 ]]
select_submodule_recursion_interactive
[[ "$SUBMODULE_RECURSIVE" == 1 ]]
[[ "$(select_menu_action "$CASE_ROOT/preview")" == __JOBS_BACK_MODE__ ]]
fzf() { cat >/dev/null; return 130; }
picker_result=0
select_configured_submodules_interactive "$CASE_ROOT/preview" || picker_result=$?
[[ "$picker_result" == 130 ]]
fzf() { cat >/dev/null; print ''; }
picker_result=0
select_configured_submodules_interactive "$CASE_ROOT/preview" || picker_result=$?
[[ "$picker_result" == 2 ]]
fzf() { cat >/dev/null; return 2; }
picker_result=0
select_configured_submodules_interactive "$CASE_ROOT/preview" || picker_result=$?
[[ "$picker_result" == 1 ]]
''')
                self.assertNotIn("UNEXPECTED_", output)

    def test_mode_back_reopens_chooser_and_only_success_runs_optional_setup(self) -> None:
        for source in SOURCES:
            if "run_download_selection_loop()" not in source.read_text():
                continue
            with self.subTest(source=source):
                (self.root / "mode-counter").unlink(missing_ok=True)
                output = self.shell(source, r'''
select_download_operation_mode() { print CHOOSE_MODE; DOWNLOAD_OPERATION_MODE=readonly; }
run_selected_download_mode() {
 if [[ ! -f "$CASE_ROOT/mode-counter" ]]; then
  print 1 > "$CASE_ROOT/mode-counter"
  return 20
 fi
 print COMPLETED_DOWNLOAD
}
offer_global_markdown_toc_setup() { print OPTIONAL_SETUP; }
run_download_selection_loop
''')
                self.assertEqual(2, output.count("CHOOSE_MODE"))
                self.assertEqual(1, output.count("COMPLETED_DOWNLOAD"))
                self.assertEqual(1, output.count("OPTIONAL_SETUP"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
