#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】🧾更新gitmodules.command
# - 核心用途：发现直属子 Git，一次完成 .gitmodules、gitlink、本地登记与元数据归集。
# - 影响范围：增量暂存关联配置与新 gitlink；保留源码、既有指针、远端和其它暂存内容，不提交、不推送。
# - 运行提示：先回车查看计划；计划后回车跳过、输入任意字符执行；--dry-run 仅预览。
# shell: zsh

# >>> Jobs terminal style protection v1 >>>
# 临时保护当前终端配色，业务进程自行管理原有退出清理。
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
    # 完整颜色帧有界重发；仅退出恢复容忍帧外回车和明确方向键。
    jobs_terminal_style_query() {
        jobs_style_query_key=$1
        jobs_style_reply=''
        jobs_style_query_buffer=''
        jobs_style_query_target_reply=''
        jobs_style_query_target_normalized=''
        jobs_style_query_target_rgb=''
        jobs_style_query_st="${jobs_style_esc}\\"
        jobs_style_query_stale_count=0
        jobs_style_query_phase=${2:-strict}
        jobs_style_query_cr=$(printf '\r')
        jobs_style_query_lf=$(printf '\n.')
        jobs_style_query_lf=${jobs_style_query_lf%.}
        jobs_style_query_failure='未收到目标颜色的完整答复（最多 3 次查询，每次约 2 秒）'
        for jobs_style_query_round in 1 2 3; do
            printf '\033]%s;?\007' "$jobs_style_query_key" > /dev/tty || {
                jobs_style_query_failure='无法向原终端发送配色查询'
                return 1
            }
            for jobs_style_attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
                # 哨兵保留末尾换行，不能把只有回车的键盘输入误当成无答复。
                jobs_style_piece=$(dd bs=256 count=1 2>/dev/null < /dev/tty; printf '.')
                jobs_style_piece=${jobs_style_piece%.}
                jobs_style_query_buffer=$jobs_style_query_buffer$jobs_style_piece
                while [ -n "$jobs_style_query_buffer" ]; do
                    # 仅退出恢复阶段允许帧外的明确控制键，普通文字仍然失败。
                    if [ "$jobs_style_query_phase" = cleanup ]; then
                        jobs_style_query_control_sequence=''
                        jobs_style_query_control_partial=0
                        case $jobs_style_query_buffer in
                            "$jobs_style_query_cr"*) jobs_style_query_control_sequence=$jobs_style_query_cr ;;
                            "$jobs_style_query_lf"*) jobs_style_query_control_sequence=$jobs_style_query_lf ;;
                        esac
                        if [ -z "$jobs_style_query_control_sequence" ]; then
                            for jobs_style_query_direction in A B C D; do
                                for jobs_style_query_control_candidate in \
                                    "${jobs_style_esc}[${jobs_style_query_direction}" \
                                    "${jobs_style_esc}O${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;2${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;3${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;4${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;5${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;6${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;7${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;8${jobs_style_query_direction}"; do
                                    case $jobs_style_query_buffer in
                                        "$jobs_style_query_control_candidate"*)
                                            jobs_style_query_control_sequence=$jobs_style_query_control_candidate
                                            break 2
                                            ;;
                                    esac
                                    case $jobs_style_query_control_candidate in
                                        "$jobs_style_query_buffer"*) jobs_style_query_control_partial=1 ;;
                                    esac
                                done
                            done
                        fi
                        if [ -n "$jobs_style_query_control_sequence" ]; then
                            jobs_style_cleanup_control_keys=$(( ${jobs_style_cleanup_control_keys:-0} + 1 ))
                            if [ "$jobs_style_cleanup_control_keys" -gt 64 ]; then
                                jobs_style_query_failure='退出恢复期间已识别控制键超过 64 个，已停止自动恢复'
                                return 1
                            fi
                            jobs_style_query_buffer=${jobs_style_query_buffer#"$jobs_style_query_control_sequence"}
                            continue
                        fi
                        if [ "$jobs_style_query_control_partial" = 1 ]; then
                            break
                        fi
                    fi
                    case $jobs_style_query_buffer in
                        "$jobs_style_esc"|"$jobs_style_esc]") break ;;
                        "$jobs_style_esc]"*) ;;
                        *) jobs_style_query_failure='收到非配色查询输入，已停止读取'; return 1 ;;
                    esac
                    jobs_style_query_head=''
                    jobs_style_query_terminator=''
                    case $jobs_style_query_buffer in
                        *"$jobs_style_bel"*)
                            jobs_style_query_head=${jobs_style_query_buffer%%"$jobs_style_bel"*}
                            jobs_style_query_terminator=$jobs_style_bel
                            ;;
                    esac
                    case $jobs_style_query_buffer in
                        *"$jobs_style_query_st"*)
                            jobs_style_query_st_head=${jobs_style_query_buffer%%"$jobs_style_query_st"*}
                            if [ -z "$jobs_style_query_terminator" ] ||
                               [ "${#jobs_style_query_st_head}" -lt "${#jobs_style_query_head}" ]; then
                                jobs_style_query_head=$jobs_style_query_st_head
                                jobs_style_query_terminator=$jobs_style_query_st
                            fi
                            ;;
                    esac
                    [ -n "$jobs_style_query_terminator" ] || break
                    jobs_style_query_frame=$jobs_style_query_head$jobs_style_query_terminator
                    jobs_style_query_buffer=${jobs_style_query_buffer#"$jobs_style_query_frame"}
                    jobs_style_query_body=${jobs_style_query_head#"$jobs_style_esc]"}
                    case $jobs_style_query_body in
                        *';rgb:'*) ;;
                        *) jobs_style_query_failure='配色答复格式或 RGB 数据无效'; return 1 ;;
                    esac
                    jobs_style_query_frame_key=${jobs_style_query_body%%';rgb:'*}
                    case $jobs_style_query_frame_key in
                        10|11|12|'4;'[0-9]|'4;1'[0-5]) ;;
                        *) jobs_style_query_failure='收到不属于本次颜色协议的答复'; return 1 ;;
                    esac
                    jobs_style_query_frame_rgb=${jobs_style_query_body#"$jobs_style_query_frame_key;rgb:"}
                    jobs_style_query_frame_normalized=$(printf '%s\n' "$jobs_style_query_frame_rgb" | LC_ALL=C awk -F/ '
                        BEGIN { valid = 1 }
                        NR != 1 || NF != 3 { valid = 0; exit }
                        {
                            for (i = 1; i <= 3; i++) {
                                h = tolower($i)
                                if (length(h) < 1 || length(h) > 4 || h ~ /[^0-9a-f]/) {
                                    valid = 0
                                    exit
                                }
                                n = 0
                                for (j = 1; j <= length(h); j++) n = n * 16 + index("0123456789abcdef", substr(h, j, 1)) - 1
                                value[i] = int(n * 65535 / (16 ^ length(h) - 1) + 0.5)
                            }
                        }
                        END {
                            if (!valid || NR != 1) exit 1
                            printf "%d/%d/%d", value[1], value[2], value[3]
                        }
                    ')
                    if [ -z "$jobs_style_query_frame_normalized" ]; then
                        jobs_style_query_failure='配色答复格式或 RGB 数据无效'
                        return 1
                    fi
                    if [ "$jobs_style_query_frame_key" = "$jobs_style_query_key" ]; then
                        if [ -n "$jobs_style_query_target_reply" ] &&
                           [ "$jobs_style_query_target_normalized" != "$jobs_style_query_frame_normalized" ]; then
                            jobs_style_query_failure='同一颜色的重复答复不一致，已停止自动恢复'
                            return 1
                        fi
                        jobs_style_query_target_reply=$jobs_style_query_frame
                        jobs_style_query_target_normalized=$jobs_style_query_frame_normalized
                        jobs_style_query_target_rgb=$jobs_style_query_frame_rgb
                    else
                        jobs_style_query_stale_count=$((jobs_style_query_stale_count + 1))
                        if [ "$jobs_style_query_stale_count" -gt 128 ]; then
                            jobs_style_query_failure='收到过多旧颜色答复，已停止读取'
                            return 1
                        fi
                    fi
                done
                if [ -n "$jobs_style_query_target_reply" ] && [ -z "$jobs_style_query_buffer" ]; then
                    jobs_style_reply=$jobs_style_query_target_reply
                    jobs_style_normalized=$jobs_style_query_target_normalized
                    jobs_style_rgb=$jobs_style_query_target_rgb
                    return 0
                fi
            done
            # 残缺帧不能通过重发拼成另一个答复，更不能被当成键盘空输入。
            if [ -n "$jobs_style_query_buffer" ]; then
                jobs_style_query_failure='配色答复帧不完整，已停止自动恢复'
                return 1
            fi
        done
        return 1
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
            jobs_style_cleanup_issue='无法读取或设置原终端输入模式，或临时配色未完成核验'
            jobs_style_conflicts=''
            jobs_style_restore_safe=''
            jobs_style_cleanup_control_keys=0
            if [ "$jobs_style_applied_complete" = 1 ]; then
                jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_style_stty=''
                if [ -n "$jobs_style_stty" ] && stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then
                    jobs_style_query_active=1
                    jobs_style_cleanup_ok=1
                    while IFS='|' read -r jobs_style_key jobs_style_expected jobs_style_original; do
                        [ -n "$jobs_style_key" ] || continue
                        if ! jobs_terminal_style_query "$jobs_style_key" cleanup; then
                            jobs_style_cleanup_ok=0
                            jobs_style_cleanup_issue="颜色项 $jobs_style_key：$jobs_style_query_failure"
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
                    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || { jobs_style_cleanup_ok=0; jobs_style_cleanup_issue='无法恢复原终端输入模式'; }
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
                printf '终端配色未能安全自动恢复（%s）；确认覆盖当前配色后可运行：sh "%s"\n' "$jobs_style_cleanup_issue" "$jobs_style_recovery" >&2
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
    trap 'jobs_style_exit_status=129; jobs_terminal_style_cleanup 129 continue; jobs_style_changed=0; exit 129' HUP
    trap 'jobs_style_exit_status=130; jobs_terminal_style_cleanup 130 continue; jobs_style_changed=0; exit 130' INT
    trap 'jobs_style_exit_status=143; jobs_terminal_style_cleanup 143 continue; jobs_style_changed=0; exit 143' TERM
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
        trap 'jobs_style_exit_status=129; jobs_terminal_style_cleanup 129 continue; jobs_style_changed=0; exit 129' HUP
        trap 'jobs_style_exit_status=130; jobs_terminal_style_cleanup 130 continue; jobs_style_changed=0; exit 130' INT
        trap 'jobs_style_exit_status=143; jobs_terminal_style_cleanup 143 continue; jobs_style_changed=0; exit 143' TERM
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
# 仅监督直接执行的入口；被 source 时不切换配色、不重新执行业务。
jobs_terminal_style_bootstrap() {
    jobs_style_bootstrap_script=$1
    shift
    if [ -n "${ZSH_VERSION:-}" ]; then
        case ${ZSH_EVAL_CONTEXT:-} in
            *:file|*:file:*) return 0 ;;
        esac
    elif [ -n "${BASH_VERSION:-}" ] && [ "${BASH_SOURCE:-$jobs_style_bootstrap_script}" != "$jobs_style_bootstrap_script" ]; then
        return 0
    fi
    if [ "${JOBS_TERMINAL_STYLE_REEXEC:-}" = "$jobs_style_bootstrap_script" ]; then
        unset JOBS_TERMINAL_STYLE_REEXEC
        return 0
    fi
    if [ ! -t 0 ] || [ ! -t 1 ] || [ -z "${TERM:-}" ] ||
       [ "${TERM:-}" = dumb ] || [ "${NO_COLOR+x}" = x ] ||
       [ "${PLAIN_OUTPUT:-0}" = 1 ] || [ "${IS_SOURCETREE_RUNTIME:-0}" = 1 ] ||
       [ -n "${TMUX:-}${STY:-}" ] ||
       env | LC_ALL=C grep -qiE '^(SOURCETREE|SOURCE_TREE)'; then
        return 0
    fi
    case ${JOBS_TERMINAL_STYLE_OWNER:-} in
        ''|*[!0-9]*) ;;
        *)
            if kill -0 "$JOBS_TERMINAL_STYLE_OWNER" 2>/dev/null &&
               [ "${JOBS_TERMINAL_STYLE_TTY:-}" = "$(tty 2>/dev/null)" ]; then
                return 0
            fi
            ;;
    esac
    JOBS_TERMINAL_STYLE_REEXEC=$jobs_style_bootstrap_script
    export JOBS_TERMINAL_STYLE_REEXEC
    jobs_terminal_style_run /bin/zsh "$jobs_style_bootstrap_script" "$@"
    jobs_style_bootstrap_result=$?
    exit "$jobs_style_bootstrap_result"
}
jobs_terminal_style_bootstrap "$0" "$@"
# <<< Jobs terminal style protection v1 <<<

# JOBS_INPUT_CHOICE_STYLE_BEGIN
# 只展示提示选项；不读取答案、不改变默认值、返回码或业务环境。
jobs_prompt_color_ready() {
  [ -z "${NO_COLOR+x}" ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
    [ "${PLAIN_OUTPUT:-0}" != 1 ] && [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]
}
# 原生 awk 分段着色；任意/非空输入优先，括号内外沿用同一个选项。
jobs_prompt_format() {
  /usr/bin/awk -v color="${1:-0}" -v lines="${2:-0}" -v keep="${3:-0}" '
    function typedEnter(value, start, prefix) {
      prefix = substr(value, 1, start - 1)
      gsub(/[“”‘’「」『』"]/, "", prefix)
      gsub(sprintf("%c", 39), "", prefix)
      if (prefix ~ /(空格|[Ss][Pp][Aa][Cc][Ee])[[:space:]]*(后|再|并|[Tt][Hh][Ee][Nn])?[[:space:]]*$/) return 1
      return prefix ~ /(输入|键入|填写|[Tt]ype)[^；;|]*[[:alnum:]_+-]+[[:space:]]*(后|再|并)?[[:space:]]*$/
    }
    function greenPosition(value, token, start) {
      if (match(value, /(直接|仅|只需|只|按下|按)?[[:space:]]*(回车|回車)/)) {
        start = RSTART
        return typedEnter(value, start) ? 0 : start
      }
      if (!match(value, /(^|[^[:alnum:]_])([Ee][Nn][Tt][Ee][Rr]|[Rr][Ee][Tt][Uu][Rr][Nn])([^[:alnum:]_]|$)/)) return 0
      start = RSTART
      token = substr(value, RSTART, RLENGTH)
      match(token, /[Ee][Nn][Tt][Ee][Rr]|[Rr][Ee][Tt][Uu][Rr][Nn]/)
      start += RSTART - 1
      return typedEnter(value, start) ? 0 : start
    }
    function segment(value, inherited, start, kind, prefix, body, red, green, connector, left, right, splitAt) {
      if (value == "") return value
      kind = inherited
      start = 1
      if (!kind) {
        if (match(value, /(输入)?(任意|任何)(非空)?(字符|内容|输入|键)|非空(字符|内容|输入)?|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key/)) {
          red = RSTART
        }
        green = greenPosition(value)
        if (red && green && green < red) {
          left = substr(value, 1, red - 1)
          right = substr(value, red)
          connector = ""
          if (match(left, /(或者|或)[[:space:]]*$/)) {
            connector = substr(left, RSTART)
            left = substr(left, 1, RSTART - 1)
          }
          return segment(left, 0) connector segment(right, 31)
        }
        if (red && green && red < green && match(value, /或[[:space:]]*(直接|仅|只需|只|按下|按)?(回车|回車)/)) {
          splitAt = RSTART
          return segment(substr(value, 1, splitAt - 1), 31) "或" segment(substr(value, splitAt + length("或")), 0)
        }
        if (red) {
          kind = 31
          start = red
        } else if (green) {
          kind = 32
          start = green
        }
      }
      if (!kind || !color) return value
      prefix = substr(value, 1, start - 1)
      body = substr(value, start)
      return prefix esc "[1;" kind "m" body esc "[0m"
    }
    function render(value, output, part, boundary, inherited, kind, consumed, depth, original) {
      original = value
      gsub(esc "\\[[0-9;]*m", "", value)
      if (color && keep && !greenPosition(value) && value !~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) return original
      output = ""
      inherited = 0
      depth = 0
      while (match(value, /[；;\/|，,、？?：:=＝（）()\[\]【】]/)) {
        part = substr(value, 1, RSTART - 1)
        boundary = substr(value, RSTART, RLENGTH)
        consumed = RSTART + RLENGTH
        output = output segment(part, inherited) boundary
        if (boundary ~ /[（(\[【]/) {
          depth++
          if (part ~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) inherited = 31
          else if (greenPosition(part)) inherited = 32
        } else if (boundary ~ /[）)\]】]/) {
          if (depth) depth--
        } else if (boundary ~ /[：:=＝]/) {
          if (!inherited) {
            if (part ~ /(任意|任何|非空|其它输入|其他输入)/) inherited = 31
            else if (greenPosition(part)) inherited = 32
          }
        } else if (!depth) inherited = 0
        value = substr(value, consumed)
      }
      return output segment(value, inherited)
    }
    BEGIN { esc = sprintf("%c", 27); first = 1 }
    {
      if (lines == 2) {
        if (!first) printf "%s\n", render(pending)
        pending = $0
        first = 0
        next
      }
      if (!lines && !first) printf "\n"
      printf "%s", render($0)
      if (lines) printf "\n"
      first = 0
    }
    END {
      if (lines == 2 && !first) {
        sub(sprintf("%c", 1) "$", "", pending)
        printf "%s", render(pending)
      }
    }
  '
}
# read 的命令替换会使 stdout 成为管道，按输入与提示所在 stderr 判断终端。
jobs_prompt_render() {
  local jobs_prompt_color=0
  if [ -t 0 ] && [ -t 2 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  printf "%s" "$1" | jobs_prompt_format "$jobs_prompt_color" 0
}
# 仅放在显示链末端；tee 在此函数之前接收纯文本，不把 ANSI 写入日志。
jobs_prompt_stream() {
  local jobs_prompt_color=0
  if [ -t 1 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  jobs_prompt_format "$jobs_prompt_color" 1 1
}
# 显示管道保留原末尾换行；只删除本轮追加的最后一个结束标记。
jobs_prompt_filter() {
  local jobs_prompt_color=0
  if [ -t 1 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  { /bin/cat; printf '\001'; } | jobs_prompt_format "$jobs_prompt_color" 2 1
}
# 仅包装原 printf/echo/print 展示，原参数、尾换行与显示命令退出码保持不变。
jobs_prompt_output() {
  local jobs_prompt_status=0 jobs_prompt_stderr=0 jobs_prompt_arg="" jobs_prompt_previous=""
  if [ "${1:-}" = print ]; then
    for jobs_prompt_arg in "$@"; do
      case "$jobs_prompt_arg" in -?*u2*|-u2) jobs_prompt_stderr=1 ;; esac
      if [ "$jobs_prompt_previous" = -u ] && [ "$jobs_prompt_arg" = 2 ]; then jobs_prompt_stderr=1; fi
      jobs_prompt_previous="$jobs_prompt_arg"
      [ "$jobs_prompt_arg" != -- ] || break
    done
  fi
  if [ -n "${ZSH_VERSION:-}" ]; then
    if [ "$jobs_prompt_stderr" = 1 ]; then
      "$@" 2>&1 | jobs_prompt_filter >&2
      jobs_prompt_status=$(( ${pipestatus[1]} != 0 ? ${pipestatus[1]} : ${pipestatus[2]} ))
    else
      "$@" | jobs_prompt_filter
      jobs_prompt_status=$(( ${pipestatus[1]} != 0 ? ${pipestatus[1]} : ${pipestatus[2]} ))
    fi
  elif [ -n "${BASH_VERSION:-}" ]; then
    "$@" | jobs_prompt_filter
    jobs_prompt_status=$(( ${PIPESTATUS[0]} != 0 ? ${PIPESTATUS[0]} : ${PIPESTATUS[1]} ))
  else
    "$@" | jobs_prompt_filter
    jobs_prompt_status=$?
  fi
  return "$jobs_prompt_status"
}
# 仅替换日志 primitive 的 tee：磁盘同步追加纯文，终端保留非选项原色。
jobs_prompt_tee() {
  local jobs_prompt_log="$1" jobs_prompt_line="" jobs_prompt_newline=0
  while :; do
    jobs_prompt_line=""
    if IFS= read -r jobs_prompt_line; then jobs_prompt_newline=1; else jobs_prompt_newline=0; [ -n "$jobs_prompt_line" ] || break; fi
    if [ "$jobs_prompt_newline" = 1 ]; then
      { printf '%s\n' "$jobs_prompt_line"; printf '\001'; } | jobs_prompt_format 0 2 >> "$jobs_prompt_log" || return $?
      printf '%s\n' "$jobs_prompt_line" | jobs_prompt_filter || return $?
    else
      { printf '%s' "$jobs_prompt_line"; printf '\001'; } | jobs_prompt_format 0 2 >> "$jobs_prompt_log" || return $?
      printf '%s' "$jobs_prompt_line" | jobs_prompt_filter || return $?
    fi
  done
}
# JOBS_INPUT_CHOICE_STYLE_END

SCRIPT_FILE="${(%):-%x}"
SCRIPT_DIR=""
SCRIPT_PATH=""
LOG_FILE=""
REPO_ROOT=""
PARENT_GIT_DIR=""
MODULES_FILE=""
PLAN_DIR=""
PLAN_FILE=""
BACKUP_DIR=""
LOCK_DIR=""
LOCK_OWNED=0
MUTATING=0
CLEANED=0
DRY_RUN="${DRY_RUN:-0}"
PHASE="初始化"
INDEX_BEFORE=""
CONFIG_BEFORE=""
MODULES_BEFORE=""
MODULES_INDEXED=0
typeset -ga CHILDREN WORK_ITEMS ISSUES
typeset -gA SECTION_NAMES SECTION_PATHS CHILD_HEADS CHILD_URLS CHILD_BRANCHES
typeset -gA CHILD_GIT_DIRS CHILD_MODES NEED_GITLINK NEED_ABSORB

# 渲染自述的红色标题与蓝色正文，非彩色终端保留纯文本。
intro_line() {
  local role="$1" message="$2" color="0;34"
  [[ "$role" == title ]] && color="1;31"
  if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != dumb && -z "${NO_COLOR+x}" &&
        "${PLAIN_OUTPUT:-0}" != 1 && "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]]; then
    printf '\033[%sm%s\033[0m\n' "$color" "$message"
  else
    print -r -- "$message"
  fi
}
# 在任何实际操作前展示固定说明，help / dry-run 可作为非交互只读入口。
show_script_intro_and_wait() {
  local argument="" answer=""
  SCRIPT_DIR="${SCRIPT_FILE:A:h}"
  SCRIPT_PATH="${SCRIPT_DIR}/${SCRIPT_FILE:t}"
  LOG_FILE="${TMPDIR:-/tmp}"
  LOG_FILE="${LOG_FILE%/}/【MacOS】🧾更新gitmodules.$$.log"
  intro_line title '【MacOS】🧾更新gitmodules.command · 父子 Git 一次关联'
  intro_line body '1、只扫描目标父仓第一层真实子 Git，补齐配置、gitlink、本地登记和 Git 元数据归集。'
  intro_line body '2、保留已有 URL 与分支；新增 URL 仅在各线路同站同命名空间且仓库同名时使用相对地址。'
  intro_line body '   映射不明时保留明确原地址；保留源码和指针，不联网、不提交、不推送。'
  jobs_prompt_output intro_line body '3、先预检并展示计划；回车跳过，输入任意字符后回车执行完整关联。'
  intro_line body '4、执行前在父仓实际 Git 目录内备份关联配置和索引；失败停止并显示阶段和恢复位置。'
  intro_line body "日志：${LOG_FILE}；--dry-run / DRY_RUN=1 只预览，Ctrl+C 取消。"
  for argument in "$@"; do
    case "$argument" in
      --help|-h) print -r -- '用法：脚本 [--dry-run]；脚本放在仓库根目录或其直属同名脚本目录。'; exit 0 ;;
      --dry-run) DRY_RUN=1 ;;
      *) print -u2 -r -- "未知参数：${argument}"; exit 1 ;;
    esac
  done
  [[ "$DRY_RUN" == 0 || "$DRY_RUN" == 1 ]] || { print -u2 -- 'DRY_RUN 只能为 0 或 1。'; exit 1; }
  [[ "$DRY_RUN" == 1 ]] && return 0
  [[ -t 0 ]] || { print -u2 -- '没有可交互输入，请在终端运行，或使用 --dry-run。'; exit 1; }
  IFS= read -r "answer?$(jobs_prompt_render '已了解影响范围，按回车查看计划；Ctrl+C 取消：')" || exit 1
}
# 统一输出到终端和日志，不把用户路径当作转义序列执行。
log() {
  print -r -- "$*" | jobs_prompt_tee "$LOG_FILE"
}
# 输出失败原因，让主流程在对应步骤立即停止。
fail() {
  log "✖ $*"
  return 1
}
# 只移除当前进程创建的临时文件和锁，不自动回滚其它 Git 操作。
cleanup() {
  local result="${1:-0}"
  if (( CLEANED )); then return 0; fi
  CLEANED=1
  if (( result != 0 )); then
    print -u2 -r -- "✖ 已停止，阶段：${PHASE}；日志：${LOG_FILE}"
    if (( MUTATING )); then
      print -u2 -r -- "部分关联操作可能已完成，请核对 git status；备份：${BACKUP_DIR}"
    fi
  fi
  if (( LOCK_OWNED )); then
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
  if [[ -n "$PLAN_DIR" && -d "$PLAN_DIR" ]]; then
    rm -f -- "$PLAN_DIR/gitmodules" "$PLAN_DIR/index-gitmodules" "$PLAN_DIR/index-entries"
    rmdir "$PLAN_DIR" 2>/dev/null || true
  fi
  return 0
}
# 在脚本整体退出时清理；zsh 函数内的 EXIT trap 会过早触发，不能在初始化函数中注册。
TRAPEXIT() {
  local exit_code=$?
  cleanup "$exit_code"
  return "$exit_code"
}
# zsh 的 ERR_EXIT 在函数返回失败时可能跳过 EXIT trap，错误分支显式完成清理。
TRAPZERR() {
  local failure_code=$?
  cleanup "$failure_code"
  exit "$failure_code"
}
# 中断保留非零状态，让统一退出处理报告已完成阶段。
TRAPINT() {
  cleanup 130
  exit 130
}
# 终止保留非零状态，避免留下本进程创建的脚本锁。
TRAPTERM() {
  cleanup 143
  exit 143
}
# 确认后集中初始化运行选项、日志、进程状态和退出清理。
initialize_runtime() {
  set -e
  set -o pipefail
  setopt NO_NOMATCH
  export GIT_OPTIONAL_LOCKS=0 GIT_LITERAL_PATHSPECS=1 GIT_TERMINAL_PROMPT=0
  CHILDREN=(); WORK_ITEMS=(); ISSUES=()
  SECTION_NAMES=(); SECTION_PATHS=(); CHILD_HEADS=(); CHILD_URLS=(); CHILD_BRANCHES=()
  CHILD_GIT_DIRS=(); CHILD_MODES=(); NEED_GITLINK=(); NEED_ABSORB=()
  umask 077
  LOG_FILE="$(mktemp "${LOG_FILE}.XXXXXXXX")" || return 1
  print -r -- "本次日志：$LOG_FILE"
}
# 为后续并发变更检测记录文件内容，不存在的文件使用独立标识。
file_checksum() {
  if [[ -f "$1" ]]; then
    cksum < "$1"
  else
    print -r -- absent
  fi
}
# 定位父仓并检查环境，拒绝继承外部 Git 定位变量或越界的配置文件。
check_environment() {
  local variable="" common="" candidate="" root=""
  PHASE="父仓预检"
  command -v git >/dev/null 2>&1 || { fail '未找到 Git。'; return 1; }
  git --version >/dev/null || return 1
  for variable in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR; do
    [[ -z "${(P)variable}" ]] || { fail "检测到 ${variable}，请在普通仓库终端运行。"; return 1; }
  done
  if [[ -e "$SCRIPT_DIR/.git" ]]; then
    candidate="$SCRIPT_DIR"
  elif [[ -e "${SCRIPT_DIR:h}/.git" ]]; then
    candidate="${SCRIPT_DIR:h}"
  elif [[ "${${SCRIPT_DIR:h}:t}" == MacOS && -e "${SCRIPT_DIR:h:h}/.git" ]]; then
    candidate="${SCRIPT_DIR:h:h}"
  else
    fail '脚本应位于父仓根目录，或其直属的同名脚本目录。'; return 1
  fi
  root="$(git -C "$candidate" rev-parse --show-toplevel)" || return 1
  REPO_ROOT="${root:A}"
  [[ "$REPO_ROOT" == "${candidate:A}" ]] || { fail '脚本目录不对应独立父仓根目录。'; return 1; }
  PARENT_GIT_DIR="$(git -C "$REPO_ROOT" rev-parse --absolute-git-dir)" || return 1
  PARENT_GIT_DIR="${PARENT_GIT_DIR:A}"
  common="$(git -C "$REPO_ROOT" rev-parse --git-common-dir)" || return 1
  [[ "$common" == /* ]] || common="$REPO_ROOT/$common"
  [[ "${common:A}" == "$PARENT_GIT_DIR" ]] || { fail '父仓是链接工作树，请在主工作树完成关联。'; return 1; }
  MODULES_FILE="$REPO_ROOT/.gitmodules"
  [[ ! -L "$MODULES_FILE" && ( ! -e "$MODULES_FILE" || -f "$MODULES_FILE" ) ]] || { fail '.gitmodules 必须是普通文件。'; return 1; }
  [[ ! -e "$PARENT_GIT_DIR/index.lock" ]] || { fail 'Git 索引正在被其它操作占用。'; return 1; }
  [[ ! -L "$PARENT_GIT_DIR/index" && ! -L "$PARENT_GIT_DIR/config" ]] || { fail '索引或 Git 配置是符号链接，停止写入。'; return 1; }
  [[ ! -L "$PARENT_GIT_DIR/jobs-submodule-backups" && ( ! -e "$PARENT_GIT_DIR/jobs-submodule-backups" || -d "$PARENT_GIT_DIR/jobs-submodule-backups" ) ]] || { fail '关联备份目录不是父仓 Git 目录内的真实目录。'; return 1; }
  [[ -z "$(git -C "$REPO_ROOT" ls-files --unmerged)" ]] || { fail '父仓存在未解决的索引冲突。'; return 1; }
  if git -C "$REPO_ROOT" ls-files --error-unmatch -- .gitmodules >/dev/null 2>&1; then
    MODULES_INDEXED=1
    git -C "$REPO_ROOT" diff --quiet -- .gitmodules || { fail '.gitmodules 存在未暂存差异；请先处理该文件的暂存边界。'; return 1; }
  elif git -C "$REPO_ROOT" cat-file -e HEAD:.gitmodules 2>/dev/null; then
    fail '.gitmodules 已被暂存删除，保留该选择，请先处理暂存边界。'; return 1
  fi
  if [[ -f "$MODULES_FILE" ]]; then
    git config --file "$MODULES_FILE" --list >/dev/null || { fail '.gitmodules 语法无效。'; return 1; }
  fi
  PLAN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/jobs-gitmodules.XXXXXXXX")" || return 1
  PLAN_FILE="$PLAN_DIR/gitmodules"
  if [[ -f "$MODULES_FILE" ]]; then cp -p "$MODULES_FILE" "$PLAN_FILE"; else : > "$PLAN_FILE"; fi
  INDEX_BEFORE="$(file_checksum "$PARENT_GIT_DIR/index")"
  CONFIG_BEFORE="$(file_checksum "$PARENT_GIT_DIR/config")"
  MODULES_BEFORE="$(file_checksum "$MODULES_FILE")"
  log "父仓：${REPO_ROOT}"
}
# 读取已有 section 与 path 映射，其它字段和暂时未检出的目录全部保留。
load_existing_modules() {
  local record="" key="" sub_path="" section=""
  PHASE="读取已有登记"
  [[ -f "$MODULES_FILE" ]] || return 0
  while IFS= read -r -d '' record; do
    key="${record%%$'\n'*}"; sub_path="${record#*$'\n'}"
    section="${key#submodule.}"; section="${section%.path}"
    [[ -n "$sub_path" && -n "$section" ]] || { fail '.gitmodules 的 path 或 section 为空。'; return 1; }
    if [[ -n "${SECTION_NAMES[$sub_path]:-}" || -n "${SECTION_PATHS[$section]:-}" ]]; then
      fail ".gitmodules 的 path 或 section 重复：${sub_path}"; return 1
    fi
    SECTION_NAMES[$sub_path]="$section"
    SECTION_PATHS[$section]="$sub_path"
  done < <(git config --null --file "$MODULES_FILE" --get-regexp '^submodule\..*\.path$' || true)
}
# 判断名称是否适合用作子模块名称，防止 Git 元数据路径穿越。
valid_name() {
  local value="$1"
  [[ -n "$value" && "$value" != /* && "$value" != *$'\n'* && "$value" != *$'\r'* && "$value" != *$'\t'* && "$value" != *\\* ]] || return 1
  [[ "/$value/" != */../* && "/$value/" != */./* && "$value" != -* ]]
}
# 只接受已配置的普通 Git 地址，不把带凭据 URL 写入共享配置和日志。
valid_url() {
  local value="$1" authority=""
  [[ -n "$value" && "$value" != -* && "$value" != *$'\n'* && "$value" != *$'\r'* && "$value" != *$'\t'* && "$value" != *'::'* ]] || return 1
  if [[ "$value" == http://* || "$value" == https://* ]]; then
    authority="${value#*://}"; authority="${authority%%/*}"
    [[ "$authority" != *@* && "$value" != *\?* && "$value" != *\#* ]] || return 1
  elif [[ "$value" == ssh://* ]]; then
    authority="${value#*://}"; authority="${authority%%/*}"
    if [[ "$authority" == *@* ]]; then [[ "${authority%%@*}" != *:* ]] || return 1; fi
  fi
  return 0
}
# 解析可证明仓库层级的托管地址；本地路径、未知协议和歧义路径不参与相对化。
hosted_url_parts() {
  local value="$1" rest="" authority="" repository_path="" namespace="" repository=""
  [[ -n "$value" && "$value" != *$'\n'* && "$value" != *$'\r'* && "$value" != *$'\t'* && "$value" != *\?* && "$value" != *\#* && "$value" != *\\* ]] || return 1
  case "$value" in
    http://*|https://*|ssh://*)
      rest="${value#*://}"
      [[ "$rest" == */* ]] || return 1
      authority="${rest%%/*}"; repository_path="${rest#*/}"
      if [[ "$value" == ssh://* ]]; then
        [[ "${authority%%@*}" != *:* || "$authority" != *@* ]] || return 1
      else
        [[ "$authority" != *@* ]] || return 1
      fi
      authority="${authority##*@}"
      ;;
    *://*) return 1 ;;
    *:*)
      authority="${value%%:*}"; repository_path="${value#*:}"
      [[ "$authority" != */* && "$authority" != -* && "$repository_path" != /* ]] || return 1
      authority="${authority##*@}"
      ;;
    *) return 1 ;;
  esac
  [[ -n "$authority" && "$authority" != *[[:space:]@/]* && "$repository_path" == */* && "$repository_path" != /* && "$repository_path" != */ && "$repository_path" != *//* ]] || return 1
  [[ "/$repository_path/" != */../* && "/$repository_path/" != */./* && "$repository_path" != '~'* ]] || return 1
  namespace="${repository_path%/*}"; repository="${repository_path##*/}"; repository="${repository%.git}"
  [[ -n "$repository" && "$repository" != . && "$repository" != .. && "$repository" != -* ]] || return 1
  if [[ "$authority" == *:* ]]; then
    authority="${value%%://*}://${authority}"
  fi
  print -rl -- "${(L)authority}" "$namespace" "$repository"
}
# 只有父子所有已配置托管线路逐一同站同命名空间、子仓名称一致时生成共享相对 URL。
relative_submodule_url() {
  local parent_repo="$1" child_repo="$2" selected_url="$3" record="" remote_url="" endpoint="" repository="" key="" repo=""
  local -a parts
  local -A parent_endpoints child_endpoints
  hosted_url_parts "$selected_url" >/dev/null || return 1
  for repo in "$parent_repo" "$child_repo"; do
    while IFS= read -r -d '' record; do
      remote_url="${record#*$'\n'}"
      parts=("${(@f)$(hosted_url_parts "$remote_url")}")
      (( ${#parts} == 3 )) || return 1
      endpoint="${parts[1]}/${parts[2]}"
      if [[ "$repo" == "$parent_repo" ]]; then
        parent_endpoints[$endpoint]=1
      else
        [[ -z "$repository" || "$repository" == "${parts[3]}" ]] || return 1
        repository="${parts[3]}"
        child_endpoints[$endpoint]=1
      fi
    done < <(git -C "$repo" config --local --null --get-regexp '^remote\..*\.url$' 2>/dev/null || true)
  done
  (( ${#parent_endpoints} && ${#parent_endpoints} == ${#child_endpoints} )) || return 1
  for key in "${(@k)parent_endpoints}"; do
    [[ -n "${child_endpoints[$key]:-}" ]] || return 1
  done
  [[ -n "$repository" ]] || return 1
  print -r -- "../${repository}.git"
}
# 预检单个子仓；任何冲突都在实际写入前收集并报告。
inspect_child() {
  local child="$1" sub_path="${1:t}" section="" top="" oid="" url="" stored_url="" branch=""
  local git_dir="" common="" target="" entry="" header="" mode="" entry_path=""
  local relative_url="" need_link=1 need_absorb=0 needs_work=0 ignored_result=0
  [[ ! -L "$child" && ! -L "$child/.git" ]] || { ISSUES+=("${sub_path}：工作目录或 .git 是符号链接"); return 0; }
  valid_name "$sub_path" || { ISSUES+=("${sub_path}：名称含不支持的控制字符或路径片段"); return 0; }
  top="$(git -C "$child" rev-parse --show-toplevel 2>/dev/null)" || { ISSUES+=("${sub_path}：无法读取独立仓库"); return 0; }
  [[ "${top:A}" == "${child:A}" ]] || { ISSUES+=("${sub_path}：不是独立子仓根目录"); return 0; }
  oid="$(git -C "$child" rev-parse --verify 'HEAD^{commit}' 2>/dev/null)" || { ISSUES+=("${sub_path}：没有可登记的 HEAD 提交"); return 0; }
  section="${SECTION_NAMES[$sub_path]:-$sub_path}"
  valid_name "$section" || { ISSUES+=("${sub_path}：section 不能安全映射到 modules 目录"); return 0; }
  if [[ -n "${SECTION_PATHS[$section]:-}" && "${SECTION_PATHS[$section]}" != "$sub_path" ]]; then
    ISSUES+=("${sub_path}：section 名已被其它路径占用"); return 0
  fi
  url="$(git config --file "$PLAN_FILE" --get "submodule.${section}.url" 2>/dev/null || true)"
  stored_url="$url"
  [[ -n "$url" ]] || url="$(git -C "$child" remote get-url origin 2>/dev/null || true)"
  valid_url "$url" || { ISSUES+=("${sub_path}：缺少可共享的 origin URL，或地址含凭据 / 不支持的协议"); return 0; }
  if [[ -z "$stored_url" ]]; then
    if relative_url="$(relative_submodule_url "$REPO_ROOT" "$child" "$url")"; then
      url="$relative_url"
    else
      log "⚠ ${sub_path}：远端线路、命名空间或仓库名称无法统一验证，保留明确原地址。"
    fi
  fi
  git_dir="$(git -C "$child" rev-parse --absolute-git-dir)" || return 1
  git_dir="${git_dir:A}"
  common="$(git -C "$child" rev-parse --git-common-dir)" || return 1
  [[ "$common" == /* ]] || common="$child/$common"
  [[ "${common:A}" == "$git_dir" ]] || { ISSUES+=("${sub_path}：链接工作树不作为普通子模块迁移"); return 0; }
  target="$PARENT_GIT_DIR/modules/$section"
  if [[ -L "$PARENT_GIT_DIR/modules" || "$target" != "${target:A}" ]]; then
    ISSUES+=("${sub_path}：目标 modules 路径含符号链接"); return 0
  fi
  if [[ "$git_dir" != "$target" ]]; then
    if [[ -e "$target" || -L "$target" ]]; then
      ISSUES+=("${sub_path}：目标 modules 元数据已存在，需先核对归属"); return 0
    fi
    if [[ ! -d "$child/.git" ]]; then
      ISSUES+=("${sub_path}：.git 指向外部元数据，需单独核对迁移边界"); return 0
    fi
    if [[ -d "$git_dir/worktrees" && -n "$(ls -A "$git_dir/worktrees")" ]]; then
      ISSUES+=("${sub_path}：元数据仍管理其它链接工作树"); return 0
    fi
    need_absorb=1
  fi
  git -C "$REPO_ROOT" ls-files --stage -z -- "$sub_path" > "$PLAN_DIR/index-entries" || return 1
  while IFS= read -r -d '' entry; do
    header="${entry%%$'\t'*}"; entry_path="${entry#*$'\t'}"; mode="${header%% *}"
    if [[ "$entry_path" != "$sub_path" || "$mode" != 160000 || "${header##* }" != 0 ]]; then
      ISSUES+=("${sub_path}：父仓已按普通文件跟踪该目录，或索引类型存在冲突"); return 0
    fi
    need_link=0
  done < "$PLAN_DIR/index-entries"
  if (( need_link )) && [[ -n "$(git -C "$REPO_ROOT" ls-tree HEAD -- "$sub_path" 2>/dev/null)" ]]; then
    ISSUES+=("${sub_path}：该路径已暂存删除，保留用户原有暂存选择"); return 0
  fi
  if (( need_link )); then
    if (unset GIT_LITERAL_PATHSPECS; git -C "$REPO_ROOT" check-ignore --quiet -- "$sub_path"); then
      ISSUES+=("${sub_path}：被父仓忽略规则排除，未强行登记"); return 0
    else
      ignored_result=$?
      (( ignored_result == 1 )) || { fail "${sub_path}：无法检查忽略规则"; return 1; }
    fi
  fi
  branch="$(git config --file "$PLAN_FILE" --get "submodule.${section}.branch" 2>/dev/null || true)"
  if [[ -z "$branch" && -z "${SECTION_NAMES[$sub_path]:-}" ]]; then
    branch="$(git -C "$child" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  fi
  if [[ -z "${SECTION_NAMES[$sub_path]:-}" ]]; then
    git config --file "$PLAN_FILE" "submodule.${section}.path" "$sub_path" || return 1
  fi
  if [[ -z "$stored_url" ]]; then
    git config --file "$PLAN_FILE" "submodule.${section}.url" "$url" || return 1
  fi
  if [[ -n "$branch" && -z "${SECTION_NAMES[$sub_path]:-}" ]]; then
    git config --file "$PLAN_FILE" "submodule.${section}.branch" "$branch" || return 1
  fi
  CHILDREN+=("$sub_path")
  SECTION_NAMES[$sub_path]="$section"; SECTION_PATHS[$section]="$sub_path"
  CHILD_HEADS[$sub_path]="$oid"; CHILD_URLS[$sub_path]="$url"; CHILD_BRANCHES[$sub_path]="$branch"
  CHILD_GIT_DIRS[$sub_path]="$git_dir"; NEED_GITLINK[$sub_path]=$need_link; NEED_ABSORB[$sub_path]=$need_absorb
  if (( need_link || need_absorb )); then needs_work=1; fi
  if ! git -C "$REPO_ROOT" config --get "submodule.${section}.url" >/dev/null; then needs_work=1; fi
  if (( needs_work )); then WORK_ITEMS+=("$sub_path"); fi
  return 0
}
# 仅扫描直属目录，跳过依赖、构建、供应商目录和软链接。
discover_and_plan() {
  local child="" name="" problem="" section="" other=""
  PHASE="子仓预检与计划"
  for child in "$REPO_ROOT"/*(DN/); do
    name="${child:t}"
    case "$name" in
      .git|node_modules|Pods|PodsManual|ManualBy*Pods@Pods|.dart_tool|build|DerivedData|dist|work|.venv|.venv-*|venv|vendor|third_party) continue ;;
    esac
    [[ -e "$child/.git" || -L "$child/.git" ]] || continue
    inspect_child "$child" || return 1
  done
  for name in "${CHILDREN[@]}"; do
    section="${SECTION_NAMES[$name]}"
    for other in "${(@k)SECTION_PATHS}"; do
      [[ "$section" == "$other" ]] && continue
      if [[ "$section/" == "$other/"* || "$other/" == "$section/"* ]]; then
        ISSUES+=("${name}：section ${section} 与 ${other} 的 modules 元数据路径重叠")
      fi
    done
  done
  if (( ${#ISSUES} )); then
    for problem in "${ISSUES[@]}"; do log "✖ ${problem}"; done
    fail '预检未通过，尚未修改父子仓配置、索引或元数据。'; return 1
  fi
}
# 展示完整计划；不删除旧登记，也不刷新已经存在的 gitlink 指针。
show_plan() {
  local sub_path=""
  PHASE="展示关联计划"
  log '========== 增量关联计划 =========='
  for sub_path in "${CHILDREN[@]}"; do
    log "${sub_path}：新增 gitlink=${NEED_GITLINK[$sub_path]}，归集元数据=${NEED_ABSORB[$sub_path]}；已有指针保留"
  done
  if [[ -f "$MODULES_FILE" ]]; then
    diff -u "$MODULES_FILE" "$PLAN_FILE" || [[ $? == 1 ]]
  else
    cat "$PLAN_FILE"
  fi
  log '旧 section、相对 URL、分支、扩展字段和暂未检出的子模块均保留。'
}
# 执行前确认计划仍对应当前状态，防止覆盖并行的 Git 操作。
recheck_plan() {
  local sub_path=""
  [[ "$INDEX_BEFORE" == "$(file_checksum "$PARENT_GIT_DIR/index")" && "$CONFIG_BEFORE" == "$(file_checksum "$PARENT_GIT_DIR/config")" && "$MODULES_BEFORE" == "$(file_checksum "$MODULES_FILE")" ]] || { fail '父仓配置或索引在预览后发生变化，请重新运行。'; return 1; }
  for sub_path in "${CHILDREN[@]}"; do
    [[ "${CHILD_HEADS[$sub_path]}" == "$(git -C "$REPO_ROOT/$sub_path" rev-parse HEAD)" ]] || { fail "${sub_path}：HEAD 在预览后变化，请重新运行。"; return 1; }
    [[ "${CHILD_GIT_DIRS[$sub_path]}" == "$(git -C "$REPO_ROOT/$sub_path" rev-parse --absolute-git-dir)" ]] || { fail "${sub_path}：Git 元数据位置在预览后变化。"; return 1; }
  done
}
# 在父仓 Git 目录内备份关联文件，失败时可核对，不复制源码和第三方目录。
backup_association_state() {
  local name=""
  PHASE="备份关联状态"
  LOCK_DIR="$PARENT_GIT_DIR/jobs-gitmodules.lock"
  mkdir "$LOCK_DIR" 2>/dev/null || { fail "已有脚本锁：${LOCK_DIR}"; return 1; }
  LOCK_OWNED=1
  recheck_plan || return 1
  mkdir -p "$PARENT_GIT_DIR/jobs-submodule-backups" || return 1
  BACKUP_DIR="$(mktemp -d "$PARENT_GIT_DIR/jobs-submodule-backups/$(date '+%Y.%m.%d %H-%M-%S').XXXXXXXX")" || return 1
  for name in index config; do
    if [[ -f "$PARENT_GIT_DIR/$name" ]]; then cp -p "$PARENT_GIT_DIR/$name" "$BACKUP_DIR/$name" || return 1; fi
  done
  if [[ -f "$MODULES_FILE" ]]; then cp -p "$MODULES_FILE" "$BACKUP_DIR/gitmodules" || return 1; fi
  print -r -- "$REPO_ROOT" > "$BACKUP_DIR/parent-path"
  log "关联配置与索引备份：${BACKUP_DIR}"
}
# 写入增量配置、只补缺失的 gitlink，并使用 Git 官方命令归集元数据。
apply_associations() {
  local sub_path="" section=""
  PHASE="写入关联配置"
  MUTATING=1
  if [[ ! -f "$MODULES_FILE" ]] || ! cmp -s "$MODULES_FILE" "$PLAN_FILE"; then
    cp -p "$PLAN_FILE" "$MODULES_FILE" || return 1
    git -C "$REPO_ROOT" add -- .gitmodules || return 1
  elif ! git -C "$REPO_ROOT" ls-files --error-unmatch -- .gitmodules >/dev/null 2>&1; then
    git -C "$REPO_ROOT" add -- .gitmodules || return 1
  fi
  for sub_path in "${CHILDREN[@]}"; do
    section="${SECTION_NAMES[$sub_path]}"
    if (( ${NEED_GITLINK[$sub_path]} )); then
      PHASE="登记 gitlink：${sub_path}"
      git -C "$REPO_ROOT" update-index --add --cacheinfo 160000 "${CHILD_HEADS[$sub_path]}" "$sub_path" || return 1
    fi
    PHASE="本地登记：${sub_path}"
    git -C "$REPO_ROOT" submodule init -- "$sub_path" || return 1
    if (( ${NEED_ABSORB[$sub_path]} )); then
      PHASE="归集 Git 元数据：${sub_path}"
      git -C "$REPO_ROOT" submodule absorbgitdirs -- "$sub_path" || return 1
    fi
  done
}
# 核验登记、160000 指针、父子关系和真实元数据目录，任一失败都不报完成。
verify_associations() {
  local sub_path="" section="" actual="" superproject="" entry=""
  PHASE="核验关联"
  git -C "$REPO_ROOT" ls-files --error-unmatch -- .gitmodules >/dev/null || { fail '.gitmodules 尚未登记到父仓索引。'; return 1; }
  for sub_path in "${CHILDREN[@]}"; do
    section="${SECTION_NAMES[$sub_path]}"
    [[ "$(git config --file "$MODULES_FILE" --get "submodule.${section}.path")" == "$sub_path" ]] || return 1
    [[ "$(git config --file "$MODULES_FILE" --get "submodule.${section}.url")" == "${CHILD_URLS[$sub_path]}" ]] || return 1
    entry="$(git -C "$REPO_ROOT" ls-files --stage -- "$sub_path")" || return 1
    [[ "$entry" == 160000\ * ]] || { fail "缺少 gitlink：${sub_path}"; return 1; }
    actual="$(git -C "$REPO_ROOT/$sub_path" rev-parse --absolute-git-dir)" || return 1
    [[ "${actual:A}" == "$PARENT_GIT_DIR/modules/$section" && -f "$REPO_ROOT/$sub_path/.git" ]] || { fail "元数据归集未完成：${sub_path}"; return 1; }
    superproject="$(git -C "$REPO_ROOT/$sub_path" rev-parse --show-superproject-working-tree)" || return 1
    [[ "${superproject:A}" == "$REPO_ROOT" ]] || { fail "父仓关系不一致：${sub_path}"; return 1; }
    [[ "$(git -C "$REPO_ROOT/$sub_path" rev-parse HEAD)" == "${CHILD_HEADS[$sub_path]}" ]] || { fail "子仓提交意外变化：${sub_path}"; return 1; }
    git -C "$REPO_ROOT" config --get "submodule.${section}.url" >/dev/null || return 1
  done
  log "✔ 已核验 ${#CHILDREN} 个直属子仓的完整关联；未提交、未推送。"
  git -C "$REPO_ROOT" status --short
}
# 单次运行完成确认、备份、登记、归集与核验；预览和重复运行不制造变更。
run_business() {
  local answer="" same=0
  if [[ -f "$MODULES_FILE" ]] && cmp -s "$MODULES_FILE" "$PLAN_FILE"; then same=1; fi
  if (( same && MODULES_INDEXED && ${#WORK_ITEMS} == 0 )); then
    log '✔ 已有登记完整，无需更新已有 gitlink 或元数据。'; return 0
  fi
  if (( ${#CHILDREN} == 0 )); then
    log '没有发现待关联的直属子仓；保留已有配置。'; return 0
  fi
  if [[ "$DRY_RUN" == 1 ]]; then
    log 'DRY_RUN=1：仅预检与预览，没有修改父子仓的配置、索引或元数据。'; return 0
  fi
  IFS= read -r "answer?$(jobs_prompt_render '确认按计划完成全部父子关联？直接回车跳过；输入任意字符后回车执行：')" || return 1
  if [[ -z "$answer" ]]; then log '已跳过，尚未修改父子仓。'; return 0; fi
  backup_association_state || return 1
  apply_associations || return 1
  verify_associations || return 1
}
# 编排自述、只读预检、增量计划和完整本地关联。
main() {
  show_script_intro_and_wait "$@" # 先说明影响范围，写入流程须有交互确认。
  initialize_runtime # 初始化日志、选项、数组与清理逻辑。
  check_environment # 定位当前父仓并保护索引和配置边界。
  load_existing_modules # 保留已有子模块映射和扩展配置。
  discover_and_plan # 扫描直属子仓并在写入前检查冲突。
  show_plan # 展示需要补齐的登记、gitlink 和元数据迁移。
  run_business # 一次完成备份、关联、归集及核验。
}
main "$@"
