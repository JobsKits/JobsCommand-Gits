#!/bin/zsh
# shell: zsh
# 脚本自述：终端管理个人 GitHub SSH 密钥；fzf 选择算法，只需填写绑定邮箱（默认 295060456@qq.com）。
# 影响范围：创建或复用个人密钥，仅在未占用时新建 .ssh/README.md，备份并更新 SSH 配置，加载 agent，复制公钥；认证通过后添加 Sourcetree 相对链接。
# 远端：仅在 gh 已授权且绑定邮箱匹配时登记公钥；否则打开官方页面并明确提示未完成。
# 不覆盖已有密钥，不读取或记录私钥正文，不修改其它账户密钥和仓库地址。

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
    jobs_style_original_rows=''
    jobs_style_applied_rows=''
    jobs_style_changed=0
    jobs_style_applied_complete=0
    jobs_style_query_active=0
    jobs_style_recovery=''
    jobs_style_exit_status=0
    jobs_style_esc=$(printf '\033')
    jobs_style_bel=$(printf '\007')
    # 完整颜色帧有界重发；设置核验与退出恢复容忍帧外回车和明确方向键。
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
                    # 设置核验与退出恢复阶段允许帧外的明确控制键，普通文字仍然失败。
                    if [ "$jobs_style_query_phase" = cleanup ] || [ "$jobs_style_query_phase" = applied ]; then
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
                            jobs_style_phase_control_keys=$(( ${jobs_style_phase_control_keys:-0} + 1 ))
                            if [ "$jobs_style_phase_control_keys" -gt 64 ]; then
                                jobs_style_query_failure='本阶段已识别控制键超过 64 个，已停止自动恢复'
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
    # 核验中断时重新读取当前值，只撤回仍等于本轮目标值的颜色。
    jobs_terminal_style_rollback() {
        jobs_style_rollback_issue='无法读取或设置原终端输入模式'
        jobs_style_rollback_safe=''
        jobs_style_rollback_conflicts=''
        jobs_style_phase_control_keys=0
        jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_style_stty=''
        if [ -n "$jobs_style_stty" ] && stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then
            jobs_style_query_active=1
            jobs_style_rollback_ok=1
            while IFS='|' read -r jobs_style_key jobs_style_original_normalized jobs_style_original; do
                [ -n "$jobs_style_key" ] || continue
                if ! jobs_terminal_style_query "$jobs_style_key" cleanup; then
                    jobs_style_rollback_ok=0
                    jobs_style_rollback_issue="回退颜色项 $jobs_style_key：$jobs_style_query_failure"
                    break
                fi
                if [ "$jobs_style_normalized" = "$jobs_style_original_normalized" ]; then
                    continue
                elif jobs_terminal_style_accepts_target "$jobs_style_key"; then
                    jobs_style_rollback_safe=$jobs_style_rollback_safe$jobs_style_original
                else
                    jobs_style_rollback_conflicts="$jobs_style_rollback_conflicts $jobs_style_key"
                fi
            done <<JOBS_STYLE_ROLLBACK
$jobs_style_original_rows
JOBS_STYLE_ROLLBACK
            stty "$jobs_style_stty" 2>/dev/null < /dev/tty || { jobs_style_rollback_ok=0; jobs_style_rollback_issue='无法恢复原终端输入模式'; }
            jobs_style_query_active=0
            if [ "$jobs_style_rollback_ok" = 1 ] && printf '%s\033[0m' "$jobs_style_rollback_safe" > /dev/tty; then
                if [ -z "$jobs_style_rollback_conflicts" ]; then
                    rm -f "$jobs_style_recovery"
                    rmdir "${jobs_style_recovery%/*}" 2>/dev/null || :
                    return 0
                fi
                printf '检测到运行期间的配色变更，已保留这些项：%s\n' "$jobs_style_rollback_conflicts" >&2
                jobs_style_rollback_issue="核验中断后检测到其它配色变更：$jobs_style_rollback_conflicts"
            fi
        fi
        printf '终端配色未能安全自动恢复（%s）；确认覆盖当前配色后可运行：sh "%s"\n' "$jobs_style_rollback_issue" "$jobs_style_recovery" >&2
        return 1
    }
    # 检测到后续改色时只恢复仍由本次保护持有的项，保留独立恢复入口。
    jobs_terminal_style_cleanup() {
        jobs_style_result=$1
        trap '' HUP INT TERM
        if [ "$jobs_style_query_active" = 1 ]; then
            stty "$jobs_style_stty" 2>/dev/null < /dev/tty || :
            jobs_style_query_active=0
        fi
        if [ "$jobs_style_changed" = 1 ] && [ "$jobs_style_applied_complete" != 1 ]; then
            if jobs_terminal_style_rollback; then
                jobs_style_changed=0
            else
                [ "$jobs_style_result" -ne 0 ] || jobs_style_result=1
            fi
            if [ "${2:-}" = continue ]; then
                jobs_style_cleanup_status=$jobs_style_result
                return 0
            fi
            exit "$jobs_style_result"
        fi
        if [ "$jobs_style_changed" = 1 ]; then
            jobs_style_cleanup_ok=0
            jobs_style_cleanup_issue='无法读取或设置原终端输入模式，或临时配色未完成核验'
            jobs_style_conflicts=''
            jobs_style_restore_safe=''
            jobs_style_phase_control_keys=0
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
        jobs_style_original_rows="$jobs_style_original_rows$jobs_style_key|$jobs_style_normalized|$jobs_style_reply
"
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
    jobs_style_phase_control_keys=0
    while IFS='|' read -r jobs_style_key jobs_style_original; do
        [ -n "$jobs_style_key" ] || continue
        if ! jobs_terminal_style_query "$jobs_style_key" applied; then
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
        printf '临时配色核验失败（颜色项 %s：%s），正在核对原色恢复。\n' "$jobs_style_key" "$jobs_style_query_failure" >&2
        jobs_terminal_style_cleanup 0 continue
        jobs_style_changed=0
        if [ "$jobs_style_cleanup_status" != 0 ]; then
            jobs_style_exit_status=1
            exit 1
        fi
        trap 'jobs_style_exit_status=129; jobs_terminal_style_cleanup 129 continue; jobs_style_changed=0; exit 129' HUP
        trap 'jobs_style_exit_status=130; jobs_terminal_style_cleanup 130 continue; jobs_style_changed=0; exit 130' INT
        trap 'jobs_style_exit_status=143; jobs_terminal_style_cleanup 143 continue; jobs_style_changed=0; exit 143' TERM
        printf '%s\n' '已恢复原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
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
    jobs_style_applied_complete=1
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
# URL仅供显示；纯文本日志传color=0。
jobs_url_format() {
  LC_ALL=en_US.UTF-8 /usr/bin/awk -v color="${1:-0}" -v lines="${2:-1}" '
    # URL 范围只在展示文本上识别；不会改写真实请求或输出数据。
    function urlInit() {
      urlPattern = "[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]<>\"" sprintf("%c", 39) esc "]+"
      urlPunctuationCount = split("，|。|；|：|！|？|、|（|）|【|】|《|》|「|」|『|』|“|”|‘|’", urlPunctuation, "\\|")
    }
    function urlCount(value, token, total, idx) {
      total = 0
      for (idx = 1; idx <= length(value); idx++) if (substr(value, idx, 1) == token) total++
      return total
    }
    function urlTrim(value, idx, at, last) {
      for (idx = 1; idx <= urlPunctuationCount; idx++) {
        at = index(value, urlPunctuation[idx])
        if (at) value = substr(value, 1, at - 1)
      }
      while (length(value)) {
        last = substr(value, length(value), 1)
        if (index(".,;:!?", last) > 0 || (last == ")" && urlCount(value, ")") > urlCount(value, "(")) ||
            (last == "]" && urlCount(value, "]") > urlCount(value, "[")) || (last == "}" && urlCount(value, "}") > urlCount(value, "{"))) {
          value = substr(value, 1, length(value) - 1)
        } else break
      }
      return value
    }
    function urlClean(value, preserve, output, token, start, size) {
      gsub(esc "\\][^" esc sprintf("%c", 7) "]*(" sprintf("%c", 7) "|" esc "\\\\)", "", value)
      output = ""
      while (match(value, esc "\\[[0-?]*[ -/]*[@-~]")) {
        start = RSTART; size = RLENGTH; token = substr(value, start, size)
        output = output substr(value, 1, start - 1)
        if (preserve && token ~ /m$/) output = output token
        value = substr(value, start + size)
      }
      return output value
    }
    # 题干分段前临时遮蔽地址，地址里的 Enter、/、?、= 不参与选项识别。
    function urlProtect(value, output, at, size, token, marker, number, original) {
      urlProtectedCount = 0; output = ""; original = value; number = 0
      while (match(value, urlPattern)) {
        at = RSTART; size = RLENGTH; token = urlTrim(substr(value, at, size))
        do { marker = sprintf("%c", 2) "U" ++number sprintf("%c", 3) } while (index(original, marker))
        urlProtected[++urlProtectedCount] = token; urlMarkers[urlProtectedCount] = marker
        output = output substr(value, 1, at - 1) marker
        value = substr(value, at + length(token))
      }
      return output value
    }
    function urlRestore(value, idx, token, at) {
      for (idx = urlProtectedCount; idx > 0; idx--) {
        token = urlMarkers[idx]
        while ((at = index(value, token))) value = substr(value, 1, at - 1) urlProtected[idx] substr(value, at + length(token))
      }
      return value
    }
    # 保存原 SGR 的有效序列；RGB 中的零值不能误认为整体复位。
    function urlTrack(tokens, token, code, idx, total, reset, fields) {
      while (match(tokens, esc "\\[[0-9;:]*m")) {
        token = substr(tokens, RSTART, RLENGTH)
        tokens = substr(tokens, RSTART + RLENGTH)
        code = substr(token, 3, length(token) - 3); reset = (code == "")
        total = split(code, fields, ";")
        for (idx = 1; idx <= total; idx++) {
          if (fields[idx] == "0") reset = 1
          if ((fields[idx] == "38" || fields[idx] == "48" || fields[idx] == "58") && idx < total) {
            if (fields[idx + 1] == "2") idx += 4
            else if (fields[idx + 1] == "5") idx += 2
          }
        }
        if (reset) urlActive = ""
        urlActive = urlActive token
      }
    }
    # 用可见字符位置映射原 SGR，URL 内已有样式也会重新覆为绿下划线。
    function urlRender(value, output, visible, rest, key, at, size, token, idx, offset, url, inURL) {
      value = urlClean(value, color)
      if (!color) return value
      for (key in urlStyles) delete urlStyles[key]
      for (key in urlStarts) delete urlStarts[key]
      for (key in urlEnds) delete urlEnds[key]
      visible = ""; rest = value
      while (match(rest, esc "\\[[0-9;:]*m")) {
        at = RSTART; size = RLENGTH; token = substr(rest, at, size)
        visible = visible substr(rest, 1, at - 1)
        urlStyles[length(visible) + 1] = urlStyles[length(visible) + 1] token
        rest = substr(rest, at + size)
      }
      visible = visible rest; rest = visible; offset = 0
      while (match(rest, urlPattern)) {
        at = RSTART; size = RLENGTH; url = urlTrim(substr(rest, at, size))
        urlStarts[offset + at] = 1; urlEnds[offset + at + length(url) - 1] = 1
        offset += at + length(url) - 1; rest = substr(visible, offset + 1)
      }
      output = ""; inURL = 0
      for (idx = 1; idx <= length(visible) + 1; idx++) {
        if (idx in urlStyles) {
          token = urlStyles[idx]; output = output token; urlTrack(token)
          if (inURL) output = output esc "[32;4m"
        }
        if (idx > length(visible)) break
        if (idx in urlStarts) { output = output esc "[32;4m"; inURL = 1 }
        output = output substr(visible, idx, 1)
        if (idx in urlEnds) { output = output esc "[0m" urlActive; inURL = 0 }
      }
      return output
    }
    BEGIN { esc = sprintf("%c", 27); first = 1; urlInit() }
    {
      if (lines == 2) {
        if (!first) printf "%s\n", urlRender(pending)
        pending = $0; first = 0
      } else {
        if (!lines && !first) printf "\n"
        printf "%s", urlRender($0)
        if (lines) printf "\n"
        first = 0
      }
    }
    END {
      if (lines == 2 && !first) {
        sub(sprintf("%c", 1) "$", "", pending)
        printf "%s", urlRender(pending)
      }
    }
  '
}
# URL仅供显示；纯文本日志传color=0。
jobs_url_stream() {
  local url_color=0
  if [ -t 1 ] && jobs_prompt_color_ready; then url_color=1; fi
  jobs_url_format "$url_color" "${1:-1}"
}
# 检查当前终端与调用环境，决定是否允许提示样式。
jobs_prompt_color_ready() {
  env | LC_ALL=C /usr/bin/grep -qiE '^(SOURCETREE|SOURCE_TREE)' && return 1
  [ -z "${NO_COLOR+x}" ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
    [ "${PLAIN_OUTPUT:-0}" != 1 ] && [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]
}
# 原生 awk 分段着色；任意/非空输入优先，括号内外沿用同一个选项。
jobs_prompt_format() {
  # 中文字符类按UTF-8字符处理，仅约束此awk进程，保留调用者locale。
  LC_ALL=en_US.UTF-8 /usr/bin/awk -v color="${1:-0}" -v lines="${2:-0}" -v keep="${3:-0}" -v question="${4:-0}" '
    # URL 范围只在展示文本上识别；不会改写真实请求或输出数据。
    function urlInit() {
      urlPattern = "[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]<>\"" sprintf("%c", 39) esc "]+"
      urlPunctuationCount = split("，|。|；|：|！|？|、|（|）|【|】|《|》|「|」|『|』|“|”|‘|’", urlPunctuation, "\\|")
    }
    function urlCount(value, token, total, idx) {
      total = 0
      for (idx = 1; idx <= length(value); idx++) if (substr(value, idx, 1) == token) total++
      return total
    }
    function urlTrim(value, idx, at, last) {
      for (idx = 1; idx <= urlPunctuationCount; idx++) {
        at = index(value, urlPunctuation[idx])
        if (at) value = substr(value, 1, at - 1)
      }
      while (length(value)) {
        last = substr(value, length(value), 1)
        if (index(".,;:!?", last) > 0 || (last == ")" && urlCount(value, ")") > urlCount(value, "(")) ||
            (last == "]" && urlCount(value, "]") > urlCount(value, "[")) || (last == "}" && urlCount(value, "}") > urlCount(value, "{"))) {
          value = substr(value, 1, length(value) - 1)
        } else break
      }
      return value
    }
    function urlClean(value, preserve, output, token, start, size) {
      gsub(esc "\\][^" esc sprintf("%c", 7) "]*(" sprintf("%c", 7) "|" esc "\\\\)", "", value)
      output = ""
      while (match(value, esc "\\[[0-?]*[ -/]*[@-~]")) {
        start = RSTART; size = RLENGTH; token = substr(value, start, size)
        output = output substr(value, 1, start - 1)
        if (preserve && token ~ /m$/) output = output token
        value = substr(value, start + size)
      }
      return output value
    }
    # 题干分段前临时遮蔽地址，地址里的 Enter、/、?、= 不参与选项识别。
    function urlProtect(value, output, at, size, token, marker, number, original) {
      urlProtectedCount = 0; output = ""; original = value; number = 0
      while (match(value, urlPattern)) {
        at = RSTART; size = RLENGTH; token = urlTrim(substr(value, at, size))
        do { marker = sprintf("%c", 2) "U" ++number sprintf("%c", 3) } while (index(original, marker))
        urlProtected[++urlProtectedCount] = token; urlMarkers[urlProtectedCount] = marker
        output = output substr(value, 1, at - 1) marker
        value = substr(value, at + length(token))
      }
      return output value
    }
    function urlRestore(value, idx, token, at) {
      for (idx = urlProtectedCount; idx > 0; idx--) {
        token = urlMarkers[idx]
        while ((at = index(value, token))) value = substr(value, 1, at - 1) urlProtected[idx] substr(value, at + length(token))
      }
      return value
    }
    # 保存原 SGR 的有效序列；RGB 中的零值不能误认为整体复位。
    function urlTrack(tokens, token, code, idx, total, reset, fields) {
      while (match(tokens, esc "\\[[0-9;:]*m")) {
        token = substr(tokens, RSTART, RLENGTH)
        tokens = substr(tokens, RSTART + RLENGTH)
        code = substr(token, 3, length(token) - 3); reset = (code == "")
        total = split(code, fields, ";")
        for (idx = 1; idx <= total; idx++) {
          if (fields[idx] == "0") reset = 1
          if ((fields[idx] == "38" || fields[idx] == "48" || fields[idx] == "58") && idx < total) {
            if (fields[idx + 1] == "2") idx += 4
            else if (fields[idx + 1] == "5") idx += 2
          }
        }
        if (reset) urlActive = ""
        urlActive = urlActive token
      }
    }
    # 用可见字符位置映射原 SGR，URL 内已有样式也会重新覆为绿下划线。
    function urlRender(value, output, visible, rest, key, at, size, token, idx, offset, url, inURL) {
      value = urlClean(value, color)
      if (!color) return value
      for (key in urlStyles) delete urlStyles[key]
      for (key in urlStarts) delete urlStarts[key]
      for (key in urlEnds) delete urlEnds[key]
      visible = ""; rest = value
      while (match(rest, esc "\\[[0-9;:]*m")) {
        at = RSTART; size = RLENGTH; token = substr(rest, at, size)
        visible = visible substr(rest, 1, at - 1)
        urlStyles[length(visible) + 1] = urlStyles[length(visible) + 1] token
        rest = substr(rest, at + size)
      }
      visible = visible rest; rest = visible; offset = 0
      while (match(rest, urlPattern)) {
        at = RSTART; size = RLENGTH; url = urlTrim(substr(rest, at, size))
        urlStarts[offset + at] = 1; urlEnds[offset + at + length(url) - 1] = 1
        offset += at + length(url) - 1; rest = substr(visible, offset + 1)
      }
      output = ""; inURL = 0
      for (idx = 1; idx <= length(visible) + 1; idx++) {
        if (idx in urlStyles) {
          token = urlStyles[idx]; output = output token; urlTrack(token)
          if (inURL) output = output esc "[32;4m"
        }
        if (idx > length(visible)) break
        if (idx in urlStarts) { output = output esc "[32;4m"; inURL = 1 }
        output = output substr(visible, idx, 1)
        if (idx in urlEnds) { output = output esc "[0m" urlActive; inURL = 0 }
      }
      return output
    }
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
    function segment(value, inherited, is_question, start, kind, prefix, body, red, green, connector, left, right, splitAt) {
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
          return segment(left, 0, is_question) connector segment(right, 31, 0)
        }
        if (red && green && red < green && match(value, /或[[:space:]]*(直接|仅|只需|只|按下|按)?(回车|回車)/)) {
          splitAt = RSTART
          return segment(substr(value, 1, splitAt - 1), 31, is_question) "或" segment(substr(value, splitAt + length("或")), 0, 0)
        }
        if (red) {
          kind = 31
          start = red
        } else if (green) {
          kind = 32
          start = green
        }
      }
      if (!color) return value
      if (!kind) return is_question && value !~ /^[[:space:]]*$/ ? esc "[1;36m" value esc "[0m" : value
      prefix = substr(value, 1, start - 1)
      body = substr(value, start)
      if (is_question && prefix !~ /^[[:space:]]*$/) prefix = esc "[1;36m" prefix esc "[0m"
      return prefix esc "[1;" kind "m" body esc "[0m"
    }
    function render(value, output, part, boundary, inherited, kind, consumed, depth, original, question_body) {
      original = value
      value = urlProtect(urlClean(value, 0))
      if (color && keep && !greenPosition(value) && value !~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) return urlRender(original)
      output = ""
      inherited = 0
      depth = 0
      question_body = question
      while (match(value, /[；;\/|，,、？?：:=＝（）()\[\]【】]/)) {
        part = substr(value, 1, RSTART - 1)
        boundary = substr(value, RSTART, RLENGTH)
        consumed = RSTART + RLENGTH
        output = output segment(part, inherited, question_body) boundary
        if (inherited || greenPosition(part) || part ~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) question_body = 0
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
      return urlRender(urlRestore(output segment(value, inherited, question_body) (question && color ? esc "[0m" : "")))
    }
    BEGIN { esc = sprintf("%c", 27); first = 1; urlInit() }
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
  printf "%s" "$1" | jobs_prompt_format "$jobs_prompt_color" 0 0 1
}
# 仅放在显示链末端；tee 在此函数之前接收纯文本，不把 ANSI 写入日志。
jobs_prompt_stream() {
  local jobs_prompt_color=0
  if [ -t 1 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  jobs_prompt_format "$jobs_prompt_color" 1 1
}
# 显示管道保留原末尾换行；只删除本轮追加的最后一个结束标记。
jobs_prompt_filter() {
  local jobs_prompt_color=0 jobs_prompt_question=0
  case "${1:-0}" in 1|--question) jobs_prompt_question=1 ;; esac
  if [ -t 1 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  { /bin/cat; printf '\001'; } | jobs_prompt_format "$jobs_prompt_color" 2 "$((1 - jobs_prompt_question))" "$jobs_prompt_question"
}
# 仅包装原 printf/echo/print 展示，原参数、尾换行与显示命令退出码保持不变。
jobs_prompt_output() {
  local jobs_prompt_status=0 jobs_prompt_stderr=0 jobs_prompt_arg="" jobs_prompt_previous="" jobs_prompt_question=0
  if [ "${1:-}" = --question ]; then jobs_prompt_question=1; shift; fi
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
      "$@" 2>&1 | jobs_prompt_filter "$jobs_prompt_question" >&2
      jobs_prompt_status=$(( ${pipestatus[1]} != 0 ? ${pipestatus[1]} : ${pipestatus[2]} ))
    else
      "$@" | jobs_prompt_filter "$jobs_prompt_question"
      jobs_prompt_status=$(( ${pipestatus[1]} != 0 ? ${pipestatus[1]} : ${pipestatus[2]} ))
    fi
  elif [ -n "${BASH_VERSION:-}" ]; then
    "$@" | jobs_prompt_filter "$jobs_prompt_question"
    jobs_prompt_status=$(( ${PIPESTATUS[0]} != 0 ? ${PIPESTATUS[0]} : ${PIPESTATUS[1]} ))
  else
    "$@" | jobs_prompt_filter "$jobs_prompt_question"
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

SCRIPT_PATH=""
SCRIPT_DIR=""
LOG_FILE=""
SSH_EMAIL=""
SSH_ALGORITHM=""
SSH_KEY_PATH=""
SSH_GITHUB_LOGIN=""
SSH_AUTHENTICATED_LOGIN=""
SSH_REMOTE_REGISTERED=0
SSH_CONNECTION_OK=0
# 从真实脚本文件定位资源，不使用函数中的 $0。
initialize_paths() {
  SCRIPT_PATH="${${(%):-%x}:A}"
  SCRIPT_DIR="${SCRIPT_PATH:h}"
  LOG_FILE="${TMPDIR:-/tmp}/【MacOS】⚙️双击为私人账户生成 SSH 密钥.log"
}
# 向终端与临时日志同步输出，不记录私钥和认证令牌。
log() {
  print -r -- "$*" | jobs_prompt_tee "$LOG_FILE"
}
# 验证邮箱、算法与业务依赖，未通过时不写入密钥目录。
check_environment() {
  [[ "$SSH_EMAIL" =~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' ]] || {
    log "✖ 邮箱格式无效，请修改邮箱后重试。"
    return 1
  }
  [[ "$SSH_ALGORITHM" == ed25519 || "$SSH_ALGORITHM" == rsa ]] || return 1
  local required
  for required in ssh-keygen ssh-add ssh-agent ssh curl pbcopy; do
    command -v "$required" >/dev/null 2>&1 || {
      log "✖ 缺少系统命令：$required。请先准备 macOS OpenSSH / Command Line Tools。"
      return 1
    }
  done
}
# 只复用算法、邮箱和公私钥配对均可验证的空口令个人密钥。
key_matches_request() {
  local candidate="$1" public_data private_public key_fingerprint
  [[ -f "$candidate" && ! -L "$candidate" && -f "$candidate.pub" && ! -L "$candidate.pub" ]] || return 1
  public_data="$(awk -v email="$SSH_EMAIL" '{ if ($3 == email) print $1 " " $2 }' "$candidate.pub")"
  [[ -n "$public_data" ]] || return 1
  if [[ "$SSH_ALGORITHM" == ed25519 ]]; then
    [[ "$public_data" == ssh-ed25519\ * ]] || return 1
  else
    [[ "$public_data" == ssh-rsa\ * ]] || return 1
    key_fingerprint="$(ssh-keygen -lf "$candidate.pub" 2>/dev/null)" || return 1
    [[ "$key_fingerprint" == 4096\ * ]] || return 1
  fi
  private_public="$(ssh-keygen -y -P '' -f "$candidate" 2>/dev/null)" || return 1
  [[ "$(print -r -- "$private_public" | awk '{print $1 " " $2}')" == "$public_data" ]]
}
# 选择可复用路径或未占用的新文件名，永远不触发覆盖询问。
prepare_personal_key() {
  local ssh_dir="$HOME/.ssh" candidate base suffix index=0
  if [[ -L "$ssh_dir" || ( -e "$ssh_dir" && ! -d "$ssh_dir" ) ]]; then
    log "✖ .ssh 是符号链接或非目录，未创建密钥或修改目标权限，请检查后重试。"
    return 1
  fi
  umask 077
  mkdir -p "$ssh_dir" || return 1
  chmod 700 "$ssh_dir" || return 1
  base="$ssh_dir/id_${SSH_ALGORITHM}_personal"
  for candidate in "$base" "$ssh_dir/id_rsa_personal"; do
    if key_matches_request "$candidate"; then
      SSH_KEY_PATH="$candidate"
      log "✔ 已复用匹配邮箱与算法的密钥：$SSH_KEY_PATH"
      return 0
    fi
  done
  candidate="$base"
  suffix="$(print -rn -- "$SSH_EMAIL" | cksum | awk '{print $1}')"
  while [[ -e "$candidate" || -L "$candidate" || -e "$candidate.pub" || -L "$candidate.pub" ]]; do
    if key_matches_request "$candidate"; then
      SSH_KEY_PATH="$candidate"
      log "✔ 已复用匹配邮箱与算法的密钥：$SSH_KEY_PATH"
      return 0
    fi
    (( index += 1 ))
    candidate="${base}_${suffix}_${index}"
    (( index <= 100 )) || return 1
  done
  SSH_KEY_PATH="$candidate"
  local -a key_options
  key_options=(-t "$SSH_ALGORITHM" -C "$SSH_EMAIL" -f "$SSH_KEY_PATH" -N '')
  [[ "$SSH_ALGORITHM" != rsa ]] || key_options+=(-b 4096)
  if ! ssh-keygen "${key_options[@]}" >> "$LOG_FILE" 2>&1; then
    log "✖ 密钥生成失败；已有密钥未覆盖。详见日志。"
    return 1
  fi
  log "✔ 已生成个人密钥：$SSH_KEY_PATH"
}
# 说明跟随密钥目录；独占创建，已有任意同名项都保留，失败不阻断 SSH 配置。
write_ssh_readme() {
  local readme_path="${SSH_KEY_PATH:h}/README.md" key_name="${SSH_KEY_PATH:t}" readme_text readme_fd
  if [[ -e "$readme_path" || -L "$readme_path" ]]; then
    log "ℹ 密钥目录 README.md 已被占用，原内容保持不变，跳过生成。"
    return 0
  fi
  if ! zmodload -F zsh/system b:sysopen 2>/dev/null; then
    log "⚠ 无法准备 README.md 独占创建；密钥与 SSH 配置流程继续。"
    return 0
  fi
  readme_text="$(cat <<'JOBS_SSH_README'
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
JOBS_SSH_README
)"
  readme_text="${readme_text//__JOBS_SSH_KEY__/$key_name}"
  # O_EXCL 对并发到达的链接、目录和特殊文件同样拒绝，不跟随目标写入。
  if sysopen -o creat,excl,cloexec -m 600 -w -u readme_fd "$readme_path" 2>/dev/null; then
    if print -r -- "$readme_text" >&$readme_fd 2>/dev/null; then
      log "✔ 已在密钥目录生成 README.md 文件用途说明。"
    else
      log "⚠ 无法写入密钥目录 README.md；密钥与 SSH 配置流程继续。"
    fi
    exec {readme_fd}>&-
  elif [[ -e "$readme_path" || -L "$readme_path" ]]; then
    log "ℹ 密钥目录 README.md 已被占用，保留先到的文件，跳过生成。"
  else
    log "⚠ 无法生成密钥目录 README.md；密钥与 SSH 配置流程继续。"
  fi
  return 0
}
# 只替换本脚本托管块，备份旧配置并保留其它 Host 和 IdentityFile。
configure_ssh() {
  local config="$HOME/.ssh/config" stage original backup
  [[ ! -L "$config" ]] || { log "✖ SSH config 是符号链接，未自动改写，请检查后重试。"; return 1; }
  stage="$(mktemp "${TMPDIR:-/tmp}/jobs-ssh-config.XXXXXX")" || return 1
  original="$(mktemp "${TMPDIR:-/tmp}/jobs-ssh-original.XXXXXX")" || { rm -- "$stage"; return 1; }
  if [[ -f "$config" ]]; then
    awk '
      $0 == "# >>> Jobs personal GitHub SSH >>>" { if (inside || seen) exit 2; inside=1; seen=1; next }
      $0 == "# <<< Jobs personal GitHub SSH <<<" { if (!inside) exit 2; inside=0; next }
      !inside {print}
      END {if (inside) exit 2}
    ' "$config" > "$original" || { rm -- "$stage" "$original"; log "✖ SSH 托管块不完整，未修改配置。"; return 1; }
  fi
  {
    print -r -- '# >>> Jobs personal GitHub SSH >>>'
    print -r -- 'Host github.com github-personal'
    print -rl -- '  HostName github.com' '  User git'
    print -r -- "  IdentityFile \"~/.ssh/${SSH_KEY_PATH:t}\""
    print -rl -- '  IdentitiesOnly yes' '  AddKeysToAgent yes' '  UseKeychain yes'
    print -rl -- 'Host *' '' '# <<< Jobs personal GitHub SSH <<<'
    cat "$original"
  } > "$stage"
  if ! ssh -G -F "$stage" git@github.com >/dev/null 2>> "$LOG_FILE"; then
    rm -- "$stage" "$original"
    log "✖ 新 SSH 配置校验失败，原配置未修改。"
    return 1
  fi
  if ! cmp -s "$stage" "$config"; then
    if [[ -e "$config" ]]; then
      backup="${config}.jobs-backup-$(date +%Y%m%d-%H%M%S)-$$"
      cp -p "$config" "$backup" || { rm -- "$stage" "$original"; return 1; }
      log "ℹ 原 SSH 配置备份：$backup"
    fi
    cat "$stage" > "$config" || { rm -- "$stage" "$original"; return 1; }
    chmod 600 "$config" || return 1
  fi
  rm -- "$stage" "$original"
  log "✔ github.com / github-personal 已指向本次个人密钥；其它账户配置保留。"
}
# 优先复用当前 agent；必要时启动当前会话 agent，不反复追加 Shell 启动配置。
load_ssh_agent() {
  local agent_result=0 agent_environment
  ssh-add -l >/dev/null 2>&1 || agent_result=$?
  if (( agent_result > 1 )); then
    agent_environment="$(ssh-agent -s)" || { log "⚠ agent 启动失败；SSH 仍可通过 IdentityFile 使用私钥。"; return 0; }
    eval "$agent_environment" >/dev/null
  fi
  if ssh-add "$SSH_KEY_PATH" >> "$LOG_FILE" 2>&1; then
    log "✔ 已将本次密钥加载到 ssh-agent。"
  else
    log "⚠ agent 加载失败；SSH 仍可通过 IdentityFile 使用私钥。"
  fi
}
# 仅通过 GitHub 官方 HTTPS 元数据补齐首次信任，已有主机记录保持原样。
prepare_github_host_keys() {
  local known_hosts="$HOME/.ssh/known_hosts" metadata keys key_line
  if [[ -f "$known_hosts" ]] && ssh-keygen -F github.com -f "$known_hosts" >/dev/null 2>&1; then
    return 0
  fi
  metadata="$(mktemp "${TMPDIR:-/tmp}/jobs-github-meta.XXXXXX")" || return 1
  log "ℹ GitHub 主机公钥来源：https://api.github.com/meta → 当前用户 .ssh/known_hosts"
  if ! curl -fsSL --connect-timeout 8 --max-time 20 https://api.github.com/meta -o "$metadata" 2>> "$LOG_FILE"; then
    rm -- "$metadata"
    log "⚠ 无法取得官方主机公钥，暂不进行 SSH 认证；请检查网络后重试。"
    return 1
  fi
  keys="$(/usr/bin/plutil -extract ssh_keys xml1 -o - "$metadata" 2>> "$LOG_FILE" | sed -n 's:.*<string>\(.*\)</string>.*:\1:p')"
  rm -- "$metadata"
  [[ -n "$keys" ]] || { log "⚠ 官方主机公钥解析失败，未写入 known_hosts。"; return 1; }
  for key_line in "${(@f)keys}"; do
    [[ "$key_line" =~ '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256) [A-Za-z0-9+/]+={0,3}$' ]] || return 1
  done
  [[ ! -L "$known_hosts" ]] || { log "⚠ known_hosts 是符号链接，未自动追加。"; return 1; }
  # 先分隔最后一行，避免与原文件无换行的记录粘连。
  [[ ! -s "$known_hosts" ]] || print >> "$known_hosts"
  for key_line in "${(@f)keys}"; do
    print -r -- "github.com $key_line" >> "$known_hosts" || return 1
  done
  chmod 600 "$known_hosts"
}
# 限时运行 GitHub CLI，不让网络或授权请求无限阻塞当前流程。
run_github_cli() {
  setopt LOCAL_OPTIONS LOCAL_TRAPS
  local timeout_seconds="${JOBS_SSH_GH_TIMEOUT_SECONDS:-20}" command_pid command_result=0 output_file
  local ticks=0 timeout_ticks
  [[ "$timeout_seconds" =~ '^[1-9][0-9]{0,2}$' ]] || timeout_seconds=20
  timeout_ticks=$(( timeout_seconds * 5 ))
  output_file="$(mktemp "${TMPDIR:-/tmp}/jobs-ssh-gh.XXXXXX")" || return 1
  trap 'if [[ -n "$command_pid" ]]; then kill -TERM "$command_pid" 2>/dev/null; kill -KILL "$command_pid" 2>/dev/null; wait "$command_pid" 2>/dev/null; fi; rm -f -- "$output_file"' EXIT
  # auth status 显式给出 --hostname；移除 GH_HOST，避免 gh 把无登录合成为空账户 401。
  if [[ "${2:-}" == auth && "${3:-}" == status ]]; then
    /usr/bin/env -u GH_HOST GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1 "$@" </dev/null > "$output_file" &
  else
    GH_HOST=github.com GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1 "$@" </dev/null > "$output_file" &
  fi
  command_pid=$!
  while kill -0 "$command_pid" 2>/dev/null; do
    if (( ticks >= timeout_ticks )); then
      kill -TERM "$command_pid" 2>/dev/null
      sleep 0.2
      kill -KILL "$command_pid" 2>/dev/null
      wait "$command_pid" 2>/dev/null
      command_pid=""
      print -u2 -r -- "⚠ GitHub CLI 请求超过 ${timeout_seconds} 秒，已终止本次请求；可稍后重试。"
      return 124
    fi
    sleep 0.2
    (( ticks += 1 ))
  done
  wait "$command_pid" || command_result=$?
  command_pid=""
  cat "$output_file"
  return "$command_result"
}
# 只输出可展示的状态；原始授权响应和令牌都不进入终端或日志。
github_auth_state() {
  local gh_bin="$1" auth_state auth_result=0
  local auth_filter='
    if (.hosts | type) != "object" then "check_failed"
    elif .hosts["github.com"] == null then
      if (.hosts | length) == 0 then "not_logged_in" else "check_failed" end
    elif (.hosts["github.com"] | type) != "array" then "check_failed"
    elif (.hosts["github.com"] | length) == 0 then "not_logged_in"
    else
      [.hosts["github.com"][] | select(.active == true)] |
      if length != 1 then "check_failed"
      elif .[0].state == "success" then "ready"
      elif .[0].state == "timeout" then "timeout"
      elif .[0].state != "error" or (.[0].error | type) != "string" then "check_failed"
      elif (.[0].error | test("(?i)HTTP[ :]+401\\b")) then "invalid"
      elif (.[0].error | test("(?i)HTTP[ :]+403\\b")) then "forbidden"
      elif (.[0].error | test("(?i)timeout|timed out|connection|resolve|network|certificate|tls|dial tcp|no such host")) then "network"
      else "check_failed" end
    end'
  auth_state="$(run_github_cli "$gh_bin" auth status --active --hostname github.com --json hosts --jq "$auth_filter" 2>/dev/null)" || auth_result=$?
  if (( auth_result == 124 )); then
    print -r -- timeout
  elif (( auth_result != 0 )) && [[ ! ( "$auth_result" == 1 && "$auth_state" == not_logged_in ) ]]; then
    print -r -- check_failed
  else
    case "$auth_state" in
      ready|not_logged_in|invalid|forbidden|network|timeout) print -r -- "$auth_state" ;;
      *) print -r -- check_failed ;;
    esac
  fi
}
# 验证 gh 活跃账户的绑定邮箱后才自动登记，避免上传到其它账号。
register_github_key() {
  local emails public_identity existing_keys gh_bin auth_state
  gh_bin="$(command -v gh 2>/dev/null)"
  if [[ -z "$gh_bin" ]]; then
    log "⚠ 未检测到 GitHub CLI（gh），公钥尚未自动登记。可安装 gh 后授权，或在 GitHub 公钥网页添加。"
    return 0
  fi
  auth_state="$(github_auth_state "$gh_bin")"
  case "$auth_state" in
    ready) ;;
    not_logged_in) log "⚠ gh 已安装，但尚未登录 github.com，公钥尚未自动登记。请运行 gh auth login --hostname github.com，或在公钥网页添加。"; return 0 ;;
    invalid) log "⚠ gh 已安装，但当前 GitHub 登录凭据被拒绝（HTTP 401），公钥尚未自动登记。请重新登录授权，或在公钥网页添加；无需重新生成本地密钥。"; return 0 ;;
    forbidden) log "⚠ gh 已安装，但 GitHub 拒绝授权检查请求（HTTP 403），公钥尚未自动登记。请检查授权与访问限制，或在公钥网页添加。"; return 0 ;;
    timeout) log "⚠ gh 已安装，但登录状态检测超时，未判断凭据是否有效，也未自动登记公钥。请检查网络后重试，或在公钥网页添加。"; return 0 ;;
    network) log "⚠ gh 已安装，但网络或证书问题导致登录状态检测失败，未判断凭据是否有效，也未自动登记公钥。请检查网络后重试。"; return 0 ;;
    *) log "⚠ gh 已安装，但无法确认登录状态，公钥尚未自动登记。请检查 gh 版本及网络后重试，或在公钥网页添加；未将检测失败判定为授权失效。"; return 0 ;;
  esac
  SSH_GITHUB_LOGIN="$(run_github_cli "$gh_bin" api --hostname github.com user --jq .login 2>> "$LOG_FILE")" || {
    log "⚠ 无法读取 GitHub 活跃账户，未自动上传公钥。"
    return 0
  }
  emails="$(run_github_cli "$gh_bin" api --hostname github.com user/emails --paginate --jq '.[] | select(.verified == true) | .email' 2>> "$LOG_FILE")" || {
    log "⚠ 无法核对 GitHub 已验证邮箱，未自动上传公钥。"
    return 0
  }
  if ! print -r -- "$emails" | grep -Fxiq -- "$SSH_EMAIL"; then
    log "⚠ gh 活跃账户没有匹配的已验证邮箱，未向该账号上传公钥。"
    SSH_GITHUB_LOGIN=""
    return 0
  fi
  public_identity="$(awk '{print $1 " " $2}' "$SSH_KEY_PATH.pub")"
  existing_keys="$(run_github_cli "$gh_bin" api --hostname github.com user/keys --paginate --jq '.[].key' 2>> "$LOG_FILE")" || {
    log "⚠ 无法读取 GitHub 公钥清单，请检查 gh 公钥权限。"
    return 0
  }
  if print -r -- "$existing_keys" | awk '{print $1 " " $2}' | grep -Fxq -- "$public_identity"; then
    SSH_REMOTE_REGISTERED=1
    log "✔ GitHub 账户 $SSH_GITHUB_LOGIN 已登记本次公钥。"
  elif run_github_cli "$gh_bin" ssh-key add "$SSH_KEY_PATH.pub" --title "Jobs $(hostname -s) $SSH_EMAIL" --type authentication >> "$LOG_FILE" 2>&1; then
    SSH_REMOTE_REGISTERED=1
    log "✔ 已自动向 GitHub 账户 $SSH_GITHUB_LOGIN 登记公钥。"
  else
    log "⚠ GitHub 公钥登记失败；请在官方页面添加公钥。"
  fi
}
# 强制本次私钥独立认证，不用 agent 的其它密钥冒充成功。
verify_github_connection() {
  local connection_output connection_result=0 response_line authenticated_login=""
  SSH_CONNECTION_OK=0
  SSH_AUTHENTICATED_LOGIN=""
  prepare_github_host_keys || return 0
  connection_output="$(ssh -F /dev/null -T -i "$SSH_KEY_PATH" -o IdentityAgent=none \
    -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 \
    -o StrictHostKeyChecking=yes -o UpdateHostKeys=no git@github.com 2>&1)" || connection_result=$?
  for response_line in "${(@f)connection_output}"; do
    response_line="${response_line%$'\r'}"
    if [[ "$response_line" =~ "^Hi ([A-Za-z0-9][A-Za-z0-9-]{0,38})! You've successfully authenticated, but GitHub does not provide shell access\\.$" ]]; then
      authenticated_login="$match[1]"
      break
    fi
  done
  if (( connection_result == 1 )) && [[ -n "$authenticated_login" ]]; then
    if [[ -n "$SSH_GITHUB_LOGIN" && "$authenticated_login" != "$SSH_GITHUB_LOGIN" ]]; then
      log "⚠ 认证账号与 gh 活跃账号不一致，请核对 GitHub 账号。"
      return 0
    fi
    SSH_CONNECTION_OK=1
    SSH_AUTHENTICATED_LOGIN="$authenticated_login"
    log "✔ $connection_output"
  else
    log "⚠ 本次密钥尚未通过 GitHub SSH 认证：$connection_output"
  fi
}
# Foundation 原子创建精确目标，存在目录或链接时也失败，不写进冲突目录。
create_sourcetree_symlink() {
  /usr/bin/osascript -l JavaScript -e '
ObjC.import("Foundation");
function run(args) {
  if (args.length !== 2 || !$.NSFileManager.defaultManager.createSymbolicLinkAtPathWithDestinationPathError(args[0], args[1], null)) {
    throw new Error("E_SOURCETREE_LINK_CREATE");
  }
}' "$1" "$2" >/dev/null 2>&1
}
# 只关联严格认证返回的实际账号；整对预检，任何冲突都不覆盖旧文件。
configure_sourcetree_aliases() {
  local account="$SSH_AUTHENTICATED_LOGIN" folder="${SSH_KEY_PATH:h}" source alias index
  local -a sources aliases
  (( SSH_CONNECTION_OK == 1 )) && [[ "$account" =~ '^[A-Za-z0-9][A-Za-z0-9-]{0,38}$' ]] || return 0
  if [[ ! -d "$folder" || -L "$folder" || ! -x /usr/bin/osascript ]]; then
    log "⚠ Sourcetree 密钥链接未完成；SSH 认证已通过，原始密钥与配置保留。"
    return 0
  fi
  sources=("$SSH_KEY_PATH" "$SSH_KEY_PATH.pub")
  aliases=("$folder/${account}-GitHub" "$folder/${account}-GitHub.pub")
  for source in "${sources[@]}"; do
    if [[ ! -f "$source" || -L "$source" ]]; then
      log "⚠ 原密钥不是普通文件，未建立 Sourcetree 链接；SSH 认证结果保持不变。"
      return 0
    fi
  done
  for index in 1 2; do
    source="$sources[$index]"
    alias="$aliases[$index]"
    if [[ -e "$alias" || -L "$alias" ]]; then
      if [[ ! -f "$alias" || ! "$alias" -ef "$source" ]]; then
        log "⚠ Sourcetree 链接名称与已有文件冲突，保留原文件：$alias。SSH 认证仍已通过；账户用户名应为 $account。"
        return 0
      fi
    fi
  done
  for index in 1 2; do
    source="$sources[$index]"
    alias="$aliases[$index]"
    [[ ( -e "$alias" || -L "$alias" ) && -f "$alias" && "$alias" -ef "$source" ]] && continue
    if ! create_sourcetree_symlink "$alias" "${source:t}"; then
      [[ -f "$alias" && "$alias" -ef "$source" ]] && continue
      log "⚠ Sourcetree 密钥链接未完成，已保留已有文件与原密钥；SSH 认证仍已通过。账户用户名应为 $account。"
      return 0
    fi
  done
  log "✔ 已为认证账号 $account 配置 Sourcetree 密钥链接；Sourcetree 账户用户名也应填写 $account。"
}
# 汇总已完成与待完成步骤，不把网页打开视为远端登记成功。
show_setup_result() {
  pbcopy < "$SSH_KEY_PATH.pub" && log "✔ 公钥已复制到剪贴板。"
  log "ℹ 私钥：$SSH_KEY_PATH"
  log "ℹ 公钥：$SSH_KEY_PATH.pub"
  if (( SSH_CONNECTION_OK )); then
    log "✔ 本机配置与 GitHub SSH 认证完成，可重新打开 Sourcetree 后执行拉取。"
  else
    log "⚠ 本机配置已完成，GitHub 认证尚未完成。"
    log "已打开 GitHub 公钥网页，请在目标账号粘贴公钥；若使用 gh，请重新登录并授予公钥权限后重试。"
    open https://github.com/settings/ssh/new >> "$LOG_FILE" 2>&1
  fi
  log "ℹ Sourcetree 账户页图标与实际 SSH 认证分开判断；不会覆盖其它密钥来消除图标。"
  log "ℹ 日志：$LOG_FILE"
}
# 接收邮箱与算法后连续完成本机配置和远端验证，不重复确认。
run_worker() {
  setopt NO_NOMATCH
  SSH_EMAIL="$1"
  SSH_ALGORITHM="$2"
  : > "$LOG_FILE"
  check_environment || return 1
  prepare_personal_key || return 1
  write_ssh_readme
  configure_ssh || return 1
  load_ssh_agent
  register_github_key
  verify_github_connection
  configure_sourcetree_aliases
  show_setup_result
}
# 展示用途与影响，未确认或无交互输入时不执行真实业务。
show_script_intro_and_wait() {
  print -r -- '==================== 个人 SSH 密钥 ===================='
  print -r -- '用途：fzf 选择算法，输入绑定邮箱后自动生成/复用、配置、加载及验证。'
  print -r -- '影响：写入当前用户 .ssh；密钥不覆盖，修改 SSH 配置前备份。'
  print -r -- '仅在未占用时新建 .ssh/README.md 用途说明；已有同名文件、链接或目录均保留。'
  print -r -- 'GitHub 严格认证通过后，以实际账号添加 Sourcetree 相对链接；原密钥不改名，冲突文件保留。'
  print -r -- '新密钥使用空口令；远端自动登记须 gh 已授权且邮箱匹配。'
  print -r -- '取消：确认前 Ctrl+C，算法菜单选择取消或按 Esc。'
  [[ -t 0 && -t 1 ]] || { print -u2 -r -- '✖ 请在可交互终端运行。'; return 1; }
  local answer=""
  IFS= read -r "answer?$(jobs_prompt_render '按回车继续；输入任意字符后回车取消：')" || return 1
  [[ -z "$answer" ]]
}
# 验证 fzf 的实际可执行文件和必需选项，不退回数字输入。
find_fzf() {
  local candidate help_text required_option
  for candidate in "$(command -v fzf 2>/dev/null)" /opt/homebrew/bin/fzf /usr/local/bin/fzf; do
    [[ -n "$candidate" && -x "$candidate" ]] || continue
    "$candidate" --version >/dev/null 2>&1 || continue
    help_text="$("$candidate" --help 2>/dev/null)" || continue
    for required_option in --height --layout --border --bind --header --no-sort; do
      [[ "$help_text" == *"$required_option"* ]] || break
    done
    [[ "$help_text" == *"$required_option"* ]] || continue
    SSH_FZF_BIN="$candidate"
    return 0
  done
  print -u2 -r -- '✖ fzf 缺失或不可用，请先运行 brew install fzf（损坏时 brew reinstall fzf），再重新启动。'
  return 1
}
# 在根菜单中选择算法或打开辅助入口，取消和失败都不生成密钥。
choose_key_type() {
  local selection selector_result
  print -r -- "ED25519（推荐）：密钥更短，签名通常更快，适合现代 GitHub / OpenSSH 环境。"
  print -r -- "RSA 4096：主要兼容不支持 ED25519 的旧系统；位数更大不等于一定更安全。"
  while true; do
    selector_result=0
    selection="$(printf '%s\n' 'ED25519（推荐）' 'RSA 4096' '打开 GitHub 公钥网页' '打开本机密钥文件夹' '打开 GitHub Token 网页' '取消本轮' |
      FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE='' "$SSH_FZF_BIN" --height=12 --layout=reverse --border --no-sort \
        --bind='tab:down,btab:up' --prompt='密钥算法 > ' --header='方向键 / Tab 选择，回车确认；Esc 取消')" || selector_result=$?
    case "$selector_result" in
      0) ;;
      1|130) print -r -- '已取消，未生成密钥。'; return 130 ;;
      *) print -u2 -r -- "✖ fzf 失败（$selector_result），未生成密钥。"; return 1 ;;
    esac
    case "$selection" in
      'ED25519（推荐）') SSH_ALGORITHM=ed25519; return 0 ;;
      'RSA 4096') SSH_ALGORITHM=rsa; return 0 ;;
      '打开 GitHub 公钥网页') open https://github.com/settings/ssh/new || return 1 ;;
      '打开本机密钥文件夹') mkdir -p "$HOME/.ssh" && open "$HOME/.ssh" || return 1 ;;
      '打开 GitHub Token 网页') open https://github.com/settings/tokens || return 1 ;;
      '取消本轮') print -r -- '已取消，未生成密钥。'; return 130 ;;
      *) print -u2 -r -- '✖ 选择为空或无效，未生成密钥。'; return 1 ;;
    esac
  done
}
# 邮箱是唯一必需文字输入，默认邮箱按用户指定提供，仍允许本轮替换。
get_email() {
  local default_email="295060456@qq.com"
  if [[ -n "$default_email" ]]; then
    IFS= read -r "SSH_EMAIL?$(jobs_prompt_render "绑定邮箱（回车使用 $default_email）：")" || return 1
    SSH_EMAIL="${SSH_EMAIL:-$default_email}"
  else
    IFS= read -r "SSH_EMAIL?$(jobs_prompt_render '绑定邮箱：')" || return 1
  fi
}
# 编排终端输入，完整收集成功后才调用写入步骤。
run_cli() {
  show_script_intro_and_wait || return $?
  find_fzf || return 1
  choose_key_type || return $?
  get_email || return 1
  run_worker "$SSH_EMAIL" "$SSH_ALGORITHM"
}
# 支持终端入口与供隔离验证使用的明确参数入口。
run_entry() {
  if [[ "${1:-}" == --worker && $# == 3 ]]; then
    run_worker "$2" "$3"
  elif (( $# == 0 )); then
    run_cli
  else
    print -u2 -r -- '用法：直接运行进入终端菜单；--worker <邮箱> <ed25519|rsa> 非交互执行。'
    return 1
  fi
}
# 编排路径初始化与终端业务入口。
main() {
  initialize_paths # 从当前脚本定位入口和日志。
  run_entry "$@" # 展示终端菜单或执行明确传入的任务。
}

main "$@"
