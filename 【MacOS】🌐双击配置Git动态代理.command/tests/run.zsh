#!/bin/zsh
# 脚本自述：
# - 脚本名称：Jobs Git 动态代理安装入口隔离验证。
# - 核心用途：验证安装、精确备份、重复运行、升级与恢复冲突边界。
# - 影响范围：只在专属临时 HOME 中操作；SourceTree 偏好与应用检测全部替换为夹具。
# - 运行提示：不运行本机真实安装，不写真实 defaults、Git 配置或系统代理；Ctrl+C 取消。
# shell: zsh

typeset -g TEST_ROOT='' TEST_INSTALLER='' TEST_TEMP='' TEST_LIBRARY='' TEST_CANONICAL=''
typeset -g TEST_CASE_DIR='' TEST_CASE_HOME='' TEST_RESULT=0 TEST_PASSED=0 TEST_FAILED=0
typeset -g TEST_ACTION='' TEST_PAYLOAD_MODE='' TEST_APP_INSTALLED=1 TEST_APP_RUNNING=0
typeset -g TEST_RUNTIME='' TEST_STATE='' TEST_PREFS='' TEST_PATH_BLOCK_BEGIN='' TEST_PATH_BLOCK_END=''
typeset -g TEST_OLD_PREF_TYPE='' TEST_OLD_PREF_PATH='' TEST_EXPECTED_PAYLOAD=''

# 只删除本测试 mktemp 生成的专属临时文件和空目录。
cleanup_tests() {
    [[ -n "$TEST_TEMP" && -d "$TEST_TEMP" ]] || return 0
    /usr/bin/find "$TEST_TEMP" -type f -delete
    /usr/bin/find "$TEST_TEMP" -type l -delete
    /usr/bin/find "$TEST_TEMP" -depth -type d -empty -delete
}
# 正常退出时回收全部隔离夹具。
TRAPEXIT() {
    cleanup_tests
}
# 取消后不进入后续安装用例。
TRAPINT() {
    exit 130
}
# 受控终止同样回收测试临时目录。
TRAPTERM() {
    exit 143
}
# 先说明无真实安装的验证边界。
show_test_intro() {
    print -r -- 'Jobs Git 安装入口隔离验证：临时 HOME + 真实文件 + mock SourceTree 偏好和应用检测。'
    print -r -- '运行策略：无交互验证；Ctrl+C 取消；不修改本机真实配置，临时记录退出时清理。'
}
# 从同包安装器提取可 source 的函数库，内嵌 payload 保留原文。
prepare_tests() {
    setopt NO_NOMATCH
    TEST_ROOT="${${(%):-%x}:A:h}"
    TEST_INSTALLER="${TEST_ROOT:h}/${TEST_ROOT:h:t}"
    TEST_TEMP="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/jobs-git-installer-tests.XXXXXXXX")" || exit 1
    TEST_LIBRARY="${TEST_TEMP}/installer-library.zsh"
    TEST_CANONICAL="${TEST_ROOT:h:h:h}/JobsConfigOS/🌍JobsMacEnvVarConfigs/scripts/_lib/jobs_git_network_strategy/bin/git"
    [[ -f "$TEST_INSTALLER" ]] || exit 1
    /usr/bin/sed '$d' "$TEST_INSTALLER" > "$TEST_LIBRARY"
}
# 为每项验证分配带空格路径，防止测试遗漏路径引用。
reset_case() {
    TEST_CASE_DIR="${TEST_TEMP}/$1 with spaces"
    TEST_CASE_HOME="${TEST_CASE_DIR}/home with spaces"
    TEST_STATE="${TEST_CASE_HOME}/Library/Application Support/JobsGitNetworkStrategy"
    TEST_RUNTIME="${TEST_STATE}/runtime/bin/git"
    TEST_PREFS="${TEST_CASE_DIR}/mock preferences"
    TEST_PAYLOAD_MODE=''
    TEST_APP_INSTALLED=1
    TEST_APP_RUNNING=0
    /bin/mkdir -p "$TEST_CASE_HOME" "$TEST_PREFS" "${TEST_CASE_DIR}/tmp"
    print -r -- '# fixture Git config must remain unchanged' > "${TEST_CASE_HOME}/.gitconfig"
    /bin/cp -p "${TEST_CASE_HOME}/.gitconfig" "${TEST_CASE_DIR}/gitconfig.before"
}
# mock 偏好区分原来缺失、空字符串与具体值，不接触 defaults。
write_fixture_preference() {
    print -rn -- "$2" > "${TEST_PREFS}/$1"
    print -rn -- "${3:-string}" > "${TEST_PREFS}/$1.type"
}
# 每次调用重新加载生产函数，文件状态则在同一隔离 HOME 内保留。
invoke_installer() {
    TEST_ACTION="$1"
    shift
    (
        unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY no_proxy NO_PROXY
        unset GIT_CONFIG GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
        export HOME="$TEST_CASE_HOME" TMPDIR="${TEST_CASE_DIR}/tmp/" PATH=/usr/bin:/bin:/usr/sbin:/sbin
        source "$TEST_LIBRARY" || exit 99
        # 夹具只模拟应用是否存在，不启动或退出任何实际应用。
        sourcetree_installed() {
            (( TEST_APP_INSTALLED == 1 ))
        }
        # 运行态也来自夹具，避免查询或影响真实 SourceTree 进程。
        sourcetree_running() {
            (( TEST_APP_RUNNING == 1 ))
        }
        # 缺失返回非零，存在但为空仍返回零。
        preference_read() {
            [[ -f "${TEST_PREFS}/$1" ]] || return 1
            /bin/cat "${TEST_PREFS}/$1"
        }
        # 类型也只读取夹具，避免触发实际 defaults read-type。
        preference_type() {
            [[ -f "${TEST_PREFS}/$1.type" ]] || return 1
            /bin/cat "${TEST_PREFS}/$1.type"
        }
        # 只向夹具文件写偏好值。
        preference_write() {
            print -r -- "write:$1" >> "${TEST_CASE_DIR}/preference-mutations"
            print -rn -- "$2" > "${TEST_PREFS}/$1"
            print -rn -- "${3:-string}" > "${TEST_PREFS}/$1.type"
        }
        # 只删除属于夹具的一个偏好键。
        preference_delete() {
            print -r -- "delete:$1" >> "${TEST_CASE_DIR}/preference-mutations"
            /bin/rm -f "${TEST_PREFS}/$1"
            /bin/rm -f "${TEST_PREFS}/$1.type"
        }
        initialize_paths || exit 98
        case "$TEST_PAYLOAD_MODE" in
            upgrade)
                # 使用测试生成的合法新版本，不改生产安装器或 canonical 源。
                embedded_wrapper() {
                    /bin/cat "${TEST_CASE_DIR}/payload-upgrade"
                }
                ;;
            missing)
                # 缺失 payload 必须在任何持久写入前被拒绝。
                embedded_wrapper() {
                    return 1
                }
                ;;
            invalid)
                # 非法 Shell 不能被安装成可用 Git 入口。
                embedded_wrapper() {
                    print -r -- '}'
                }
                ;;
            dependency)
                # 模拟必需命令不可用，不触碰当前机器实际依赖。
                check_dependencies() {
                    return 1
                }
                ;;
        esac
        case "$TEST_ACTION" in
            install) install_configuration ;;
            check) main --check ;;
            restore) restore_configuration ;;
            non-tty) main </dev/null ;;
            explicit-install) main --install </dev/null ;;
            payload) embedded_wrapper ;;
            mount) embedded_mount ;;
            *) return 97 ;;
        esac
    ) > "${TEST_CASE_DIR}/${TEST_ACTION}.stdout" 2> "${TEST_CASE_DIR}/${TEST_ACTION}.stderr"
    TEST_RESULT=$?
}
# 断言只输出隔离夹具中的值。
assert_equal() {
    if [[ "$1" == "$2" ]]; then
        (( TEST_PASSED++ ))
        return 0
    fi
    (( TEST_FAILED++ ))
    print -u2 -r -- "FAIL $3: expected=[$2] actual=[$1]"
    return 1
}
# 比较完整字节内容，不把末尾换行差异吞掉。
assert_same_file() {
    if [[ -f "$1" && -f "$2" ]] && /usr/bin/cmp -s "$1" "$2"; then
        (( TEST_PASSED++ ))
        return 0
    fi
    (( TEST_FAILED++ ))
    print -u2 -r -- "FAIL $3: file bytes differ or missing"
    return 1
}
# 文件缺失也有独立语义，避免以空值替代不存在。
file_exists() {
    [[ -e "$1" || -L "$1" ]] && print yes || print no
}
# 读取测试文件；缺失返回空，不产生无关错误。
read_fixture() {
    [[ -f "$1" ]] && print -rn -- "$(<"$1")"
    return 0
}
# 只读检查前后记录 HOME 路径、权限和内容，不依赖用户状态。
home_snapshot() {
    /usr/bin/find "$TEST_CASE_HOME" -print | /usr/bin/sort | while IFS= read -r fixture; do
        /usr/bin/stat -f '%N %HT %Lp' "$fixture"
        [[ ! -f "$fixture" ]] || /usr/bin/shasum -a 256 "$fixture"
    done
}
# 安装器不能写全局 Git 配置。
assert_gitconfig_unchanged() {
    assert_same_file "${TEST_CASE_HOME}/.gitconfig" "${TEST_CASE_DIR}/gitconfig.before" "$1-gitconfig-unchanged"
}
# --check 在未安装状态下也不能创建日志、快照或启动文件。
test_check_read_only() {
    reset_case check-read-only
    home_snapshot > "${TEST_CASE_DIR}/home.before"
    invoke_installer check
    assert_equal "$(( TEST_RESULT == 0 || TEST_RESULT == 1 ))" 1 check-valid-status
    home_snapshot > "${TEST_CASE_DIR}/home.after"
    assert_same_file "${TEST_CASE_DIR}/home.before" "${TEST_CASE_DIR}/home.after" check-home-read-only
    assert_equal "$(file_exists "$TEST_STATE")" no check-no-state-directory
    assert_equal "$(file_exists "${TEST_CASE_DIR}/preference-mutations")" no check-no-preference-mutation
    assert_gitconfig_unchanged check
}
# 精确提取内嵌 payload，并在完整工作树中与 canonical 源逐字节比较。
test_embedded_payload() {
    reset_case payload-source
    invoke_installer payload
    assert_equal "$TEST_RESULT" 0 embedded-payload-exit
    /bin/zsh -n "${TEST_CASE_DIR}/payload.stdout"
    assert_equal "$?" 0 embedded-payload-syntax
    if [[ -f "$TEST_CANONICAL" ]]; then
        assert_same_file "${TEST_CASE_DIR}/payload.stdout" "$TEST_CANONICAL" embedded-canonical-equality
    fi
}
# 首次安装保留启动文件原文和权限，将 payload 精确部署到运行态。
test_first_install() {
    reset_case first-install
    print -rn -- "export JOBS_FIXTURE_SETTING='unchanged'" > "${TEST_CASE_HOME}/.zshrc"
    /bin/chmod 640 "${TEST_CASE_HOME}/.zshrc"
    /bin/cp -p "${TEST_CASE_HOME}/.zshrc" "${TEST_CASE_DIR}/zshrc.before"
    invoke_installer install
    assert_equal "$TEST_RESULT" 0 first-install-exit
    assert_same_file "$TEST_RUNTIME" "$TEST_CANONICAL" installed-payload-canonical
    local original_size="$(/usr/bin/stat -f '%z' "${TEST_CASE_DIR}/zshrc.before")"
    /usr/bin/head -c "$original_size" "${TEST_CASE_HOME}/.zshrc" > "${TEST_CASE_DIR}/zshrc.prefix"
    assert_same_file "${TEST_CASE_DIR}/zshrc.before" "${TEST_CASE_DIR}/zshrc.prefix" zshrc-original-prefix
    assert_equal "$(/usr/bin/stat -f '%Lp' "${TEST_CASE_HOME}/.zshrc")" 640 zshrc-permission-preserved
    assert_equal "$(/usr/bin/stat -f '%Lp' "$TEST_RUNTIME")" 755 runtime-executable-permission
    invoke_installer mount
    /bin/cat "${TEST_CASE_DIR}/zshrc.before" "${TEST_CASE_DIR}/mount.stdout" > "${TEST_CASE_DIR}/zshrc.expected"
    assert_same_file "${TEST_CASE_HOME}/.zshrc" "${TEST_CASE_DIR}/zshrc.expected" zshrc-only-appended-managed-mount
    home_snapshot > "${TEST_CASE_DIR}/installed-home.before"
    invoke_installer check
    assert_equal "$TEST_RESULT" 0 installed-check-exit
    home_snapshot > "${TEST_CASE_DIR}/installed-home.after"
    assert_same_file "${TEST_CASE_DIR}/installed-home.before" "${TEST_CASE_DIR}/installed-home.after" installed-check-home-read-only
    assert_gitconfig_unchanged first-install
}
# 偏好缺失、空字符串和已有值都按存在状态与原类型精确恢复。
test_preference_snapshots() {
    local state='' key='' expected_exists=0
    for state in absent empty populated; do
        reset_case "preferences-${state}"
        if [[ "$state" == empty ]]; then
            write_fixture_preference gitCustomPath '' string
            write_fixture_preference gitWhichOne '' string
        elif [[ "$state" == populated ]]; then
            write_fixture_preference gitCustomPath '/tmp/original Git with spaces/git' string
            write_fixture_preference gitWhichOne 0 integer
        fi
        /bin/mkdir "${TEST_CASE_DIR}/preferences.before"
        for key in gitCustomPath gitWhichOne; do
            [[ ! -f "${TEST_PREFS}/$key" ]] || /bin/cp -p "${TEST_PREFS}/$key" "${TEST_CASE_DIR}/preferences.before/$key"
            [[ ! -f "${TEST_PREFS}/$key.type" ]] || /bin/cp -p "${TEST_PREFS}/$key.type" "${TEST_CASE_DIR}/preferences.before/$key.type"
        done
        invoke_installer install
        assert_equal "$TEST_RESULT" 0 "${state}-preferences-install-exit"
        assert_equal "$(read_fixture "${TEST_PREFS}/gitCustomPath")" "$TEST_RUNTIME" "${state}-preferences-managed-path"
        assert_equal "$(read_fixture "${TEST_PREFS}/gitWhichOne")" 1 "${state}-preferences-managed-selection"
        assert_equal "$(read_fixture "${TEST_PREFS}/gitWhichOne.type")" integer "${state}-preferences-managed-selection-type"
        local snapshot="${TEST_STATE}/installer/snapshots/$(active_snapshot)"
        expected_exists=1
        [[ "$state" != absent ]] || expected_exists=0
        for key in gitCustomPath gitWhichOne; do
            assert_equal "$(read_fixture "${snapshot}/${key}.before.exists")" "$expected_exists" "${state}-${key}-snapshot-existence"
            if (( expected_exists )); then
                assert_same_file "${snapshot}/${key}.before.value" "${TEST_CASE_DIR}/preferences.before/$key" "${state}-${key}-snapshot-value"
                assert_equal "$(read_fixture "${snapshot}/${key}.before.type")" "$(read_fixture "${TEST_CASE_DIR}/preferences.before/$key.type")" "${state}-${key}-snapshot-type"
            fi
        done
        invoke_installer restore
        assert_equal "$TEST_RESULT" 0 "${state}-preferences-restore-exit"
        for key in gitCustomPath gitWhichOne; do
            if (( expected_exists )); then
                assert_same_file "${TEST_PREFS}/$key" "${TEST_CASE_DIR}/preferences.before/$key" "${state}-${key}-restored-value"
                assert_same_file "${TEST_PREFS}/$key.type" "${TEST_CASE_DIR}/preferences.before/$key.type" "${state}-${key}-restored-type"
            else
                assert_equal "$(file_exists "${TEST_PREFS}/$key")" no "${state}-${key}-restored-to-missing"
            fi
        done
        assert_gitconfig_unchanged "preferences-${state}"
    done
}
# 当前快照标识只读记录，用于验证重复安装不会悄悄创建新恢复层。
active_snapshot() {
    read_fixture "${TEST_STATE}/installer/active"
}
# 已存在的启动文件恢复为原字节，之后的无关编辑仍被保留。
test_restore_existing_shell() {
    reset_case restore-existing-shell
    print -r -- '# original user configuration' > "${TEST_CASE_HOME}/.zshrc"
    /bin/chmod 640 "${TEST_CASE_HOME}/.zshrc"
    /bin/cp -p "${TEST_CASE_HOME}/.zshrc" "${TEST_CASE_DIR}/zshrc.before"
    invoke_installer install
    assert_equal "$TEST_RESULT" 0 existing-shell-install-exit
    print -r -- '# unrelated edit after installation' >> "${TEST_CASE_HOME}/.zshrc"
    /bin/cp -p "${TEST_CASE_DIR}/zshrc.before" "${TEST_CASE_DIR}/zshrc.expected"
    print -r -- '# unrelated edit after installation' >> "${TEST_CASE_DIR}/zshrc.expected"
    invoke_installer restore
    assert_equal "$TEST_RESULT" 0 existing-shell-restore-exit
    assert_same_file "${TEST_CASE_HOME}/.zshrc" "${TEST_CASE_DIR}/zshrc.expected" restore-retains-unrelated-shell-edit
    assert_equal "$(/usr/bin/stat -f '%Lp' "${TEST_CASE_HOME}/.zshrc")" 640 restore-shell-permission-preserved
    assert_equal "$(file_exists "$TEST_RUNTIME")" no restore-originally-missing-runtime
    assert_gitconfig_unchanged restore-existing-shell
}
# 原文没有末尾换行且没有新增内容时，安装再恢复必须逐字节回到原文。
test_restore_no_final_newline() {
    reset_case restore-no-final-newline
    print -rn -- "export JOBS_FIXTURE_SETTING='without-final-newline'" > "${TEST_CASE_HOME}/.zshrc"
    /bin/chmod 640 "${TEST_CASE_HOME}/.zshrc"
    /bin/cp -p "${TEST_CASE_HOME}/.zshrc" "${TEST_CASE_DIR}/zshrc.before"
    invoke_installer install
    assert_equal "$TEST_RESULT" 0 no-final-newline-install-exit
    invoke_installer restore
    assert_equal "$TEST_RESULT" 0 no-final-newline-restore-exit
    assert_same_file "${TEST_CASE_HOME}/.zshrc" "${TEST_CASE_DIR}/zshrc.before" no-final-newline-byte-exact-roundtrip
    assert_equal "$(/usr/bin/stat -f '%Lp' "${TEST_CASE_HOME}/.zshrc")" 640 no-final-newline-permission-roundtrip
    assert_gitconfig_unchanged no-final-newline
}
# 原来没有启动文件和运行态时，首次恢复回到缺失状态且可重复执行。
test_restore_absent_files() {
    reset_case restore-absent-files
    invoke_installer install
    assert_equal "$TEST_RESULT" 0 absent-files-install-exit
    invoke_installer restore
    assert_equal "$TEST_RESULT" 0 absent-files-restore-exit
    assert_equal "$(file_exists "${TEST_CASE_HOME}/.zshrc")" no absent-shell-restored-to-absent
    assert_equal "$(file_exists "$TEST_RUNTIME")" no absent-runtime-restored-to-absent
    local active_before="$(active_snapshot)"
    invoke_installer restore
    assert_equal "$TEST_RESULT" 0 repeated-restore-exit
    assert_equal "$(active_snapshot)" "$active_before" repeated-restore-same-snapshot
    assert_equal "$(file_exists "${TEST_CASE_HOME}/.zshrc")" no repeated-restore-shell-still-absent
    assert_equal "$(file_exists "$TEST_RUNTIME")" no repeated-restore-runtime-still-absent
    assert_gitconfig_unchanged restore-absent
}
# 同一 payload 重装幂等，升级后恢复恰好回到上一版而不继续卸载。
test_idempotent_install_and_upgrade() {
    reset_case install-upgrade
    print -r -- '# original shell' > "${TEST_CASE_HOME}/.zshrc"
    invoke_installer install
    assert_equal "$TEST_RESULT" 0 version-one-install-exit
    /bin/cp -p "$TEST_RUNTIME" "${TEST_CASE_DIR}/payload-version-one"
    /bin/cp -p "${TEST_CASE_HOME}/.zshrc" "${TEST_CASE_DIR}/shell-version-one"
    local first_active="$(active_snapshot)"
    invoke_installer install
    assert_equal "$TEST_RESULT" 0 duplicate-install-exit
    assert_equal "$(active_snapshot)" "$first_active" duplicate-install-same-active
    assert_same_file "$TEST_RUNTIME" "${TEST_CASE_DIR}/payload-version-one" duplicate-install-same-runtime
    assert_same_file "${TEST_CASE_HOME}/.zshrc" "${TEST_CASE_DIR}/shell-version-one" duplicate-install-no-extra-path-block
    /bin/cp -p "$TEST_RUNTIME" "${TEST_CASE_DIR}/payload-upgrade"
    print -r -- '# isolated test payload version two' >> "${TEST_CASE_DIR}/payload-upgrade"
    TEST_PAYLOAD_MODE=upgrade
    invoke_installer install
    assert_equal "$TEST_RESULT" 0 version-two-install-exit
    assert_same_file "$TEST_RUNTIME" "${TEST_CASE_DIR}/payload-upgrade" version-two-deployed
    assert_equal "$([[ "$(active_snapshot)" != "$first_active" ]] && print yes || print no)" yes upgrade-new-snapshot
    TEST_PAYLOAD_MODE=''
    invoke_installer restore
    assert_equal "$TEST_RESULT" 0 upgrade-restore-exit
    assert_same_file "$TEST_RUNTIME" "${TEST_CASE_DIR}/payload-version-one" upgrade-restored-version-one
    assert_same_file "${TEST_CASE_HOME}/.zshrc" "${TEST_CASE_DIR}/shell-version-one" upgrade-restored-shell-state
    local restored_active="$(active_snapshot)"
    invoke_installer restore
    assert_equal "$TEST_RESULT" 0 upgrade-repeated-restore-exit
    assert_equal "$(active_snapshot)" "$restored_active" upgrade-repeated-restore-same-snapshot
    assert_same_file "$TEST_RUNTIME" "${TEST_CASE_DIR}/payload-version-one" upgrade-repeated-restore-preserves-version-one
    assert_gitconfig_unchanged upgrade
}
# 运行态被用户后改时停止恢复，不覆盖用户改动或继续恢复其它文件。
test_wrapper_conflict() {
    reset_case wrapper-conflict
    invoke_installer install
    assert_equal "$TEST_RESULT" 0 wrapper-conflict-install-exit
    print -r -- '# user changed runtime after installation' >> "$TEST_RUNTIME"
    /bin/cp -p "$TEST_RUNTIME" "${TEST_CASE_DIR}/runtime.user"
    /bin/cp -p "${TEST_CASE_HOME}/.zshrc" "${TEST_CASE_DIR}/shell.installed"
    local active_before="$(active_snapshot)"
    invoke_installer restore
    assert_equal "$(( TEST_RESULT != 0 ))" 1 wrapper-conflict-restore-rejected
    assert_same_file "$TEST_RUNTIME" "${TEST_CASE_DIR}/runtime.user" wrapper-conflict-user-change-preserved
    assert_same_file "${TEST_CASE_HOME}/.zshrc" "${TEST_CASE_DIR}/shell.installed" wrapper-conflict-shell-not-partly-restored
    assert_equal "$(active_snapshot)" "$active_before" wrapper-conflict-active-unchanged
    assert_gitconfig_unchanged wrapper-conflict
}
# 偏好被用户后改时整次恢复先停止，不部分还原其它受控项。
test_preference_conflict() {
    reset_case preference-conflict
    invoke_installer install
    assert_equal "$TEST_RESULT" 0 preference-conflict-install-exit
    write_fixture_preference gitCustomPath '/tmp/user-selected Git/git' string
    /bin/cp -p "$TEST_RUNTIME" "${TEST_CASE_DIR}/runtime.installed"
    /bin/cp -p "${TEST_CASE_HOME}/.zshrc" "${TEST_CASE_DIR}/shell.installed"
    local active_before="$(active_snapshot)"
    invoke_installer restore
    assert_equal "$(( TEST_RESULT != 0 ))" 1 preference-conflict-restore-rejected
    assert_equal "$(read_fixture "${TEST_PREFS}/gitCustomPath")" '/tmp/user-selected Git/git' preference-conflict-user-value-preserved
    assert_equal "$(read_fixture "${TEST_PREFS}/gitWhichOne")" 1 preference-conflict-other-key-not-partly-restored
    assert_same_file "$TEST_RUNTIME" "${TEST_CASE_DIR}/runtime.installed" preference-conflict-runtime-not-partly-restored
    assert_same_file "${TEST_CASE_HOME}/.zshrc" "${TEST_CASE_DIR}/shell.installed" preference-conflict-shell-not-partly-restored
    assert_equal "$(active_snapshot)" "$active_before" preference-conflict-active-unchanged
    assert_gitconfig_unchanged preference-conflict
}
# 运行入口失去执行权限时检查必须失败，并保持当前文件与权限不变。
test_runtime_execution_permission() {
    reset_case runtime-execution-permission
    invoke_installer install
    assert_equal "$TEST_RESULT" 0 runtime-permission-install-exit
    /bin/chmod 644 "$TEST_RUNTIME"
    home_snapshot > "${TEST_CASE_DIR}/home.before"
    /bin/cp -p "${TEST_CASE_DIR}/preference-mutations" "${TEST_CASE_DIR}/preference-mutations.before"
    invoke_installer check
    assert_equal "$(( TEST_RESULT != 0 ))" 1 nonexecutable-runtime-check-rejected
    home_snapshot > "${TEST_CASE_DIR}/home.after"
    assert_same_file "${TEST_CASE_DIR}/home.before" "${TEST_CASE_DIR}/home.after" nonexecutable-runtime-check-read-only
    assert_same_file "${TEST_CASE_DIR}/preference-mutations" "${TEST_CASE_DIR}/preference-mutations.before" nonexecutable-runtime-no-preference-write
    assert_equal "$(/usr/bin/stat -f '%Lp' "$TEST_RUNTIME")" 644 nonexecutable-runtime-permission-retained
}
# 偏好值相同但类型被用户改动也属于冲突，检查与恢复都不能继续写入。
test_preference_type_conflict() {
    reset_case preference-type-conflict
    invoke_installer install
    assert_equal "$TEST_RESULT" 0 preference-type-conflict-install-exit
    write_fixture_preference gitWhichOne 1 string
    home_snapshot > "${TEST_CASE_DIR}/home.before"
    /bin/cp -p "${TEST_CASE_DIR}/preference-mutations" "${TEST_CASE_DIR}/preference-mutations.before"
    invoke_installer check
    assert_equal "$(( TEST_RESULT != 0 ))" 1 preference-type-conflict-check-rejected
    home_snapshot > "${TEST_CASE_DIR}/home.after-check"
    assert_same_file "${TEST_CASE_DIR}/home.before" "${TEST_CASE_DIR}/home.after-check" preference-type-conflict-check-read-only
    assert_equal "$(read_fixture "${TEST_PREFS}/gitWhichOne")" 1 preference-type-conflict-check-value-preserved
    assert_equal "$(read_fixture "${TEST_PREFS}/gitWhichOne.type")" string preference-type-conflict-check-type-preserved
    invoke_installer restore
    assert_equal "$(( TEST_RESULT != 0 ))" 1 preference-type-conflict-restore-rejected
    home_snapshot > "${TEST_CASE_DIR}/home.after-restore"
    assert_same_file "${TEST_CASE_DIR}/home.before" "${TEST_CASE_DIR}/home.after-restore" preference-type-conflict-no-partial-restore
    assert_same_file "${TEST_CASE_DIR}/preference-mutations" "${TEST_CASE_DIR}/preference-mutations.before" preference-type-conflict-no-preference-write
    assert_equal "$(read_fixture "${TEST_PREFS}/gitWhichOne")" 1 preference-type-conflict-restore-value-preserved
    assert_equal "$(read_fixture "${TEST_PREFS}/gitWhichOne.type")" string preference-type-conflict-restore-type-preserved
}
# 未安装 SourceTree 时照常安装终端入口，但不创建任何 SourceTree 偏好。
test_sourcetree_absent() {
    reset_case sourcetree-absent
    TEST_APP_INSTALLED=0
    invoke_installer explicit-install
    assert_equal "$TEST_RESULT" 0 no-sourcetree-cli-install-exit
    assert_same_file "$TEST_RUNTIME" "$TEST_CANONICAL" no-sourcetree-runtime-installed
    assert_equal "$(file_exists "${TEST_CASE_DIR}/preference-mutations")" no no-sourcetree-no-preference-mutations
    invoke_installer restore
    assert_equal "$TEST_RESULT" 0 no-sourcetree-restore-exit
    assert_equal "$(file_exists "${TEST_CASE_DIR}/preference-mutations")" no no-sourcetree-restore-no-preference-mutations
    assert_gitconfig_unchanged no-sourcetree
}
# 默认双击入口没有 TTY 时拒绝安装，缺失或无效 payload 也不能写入运行态。
test_invalid_inputs() {
    reset_case non-tty
    invoke_installer non-tty
    assert_equal "$(( TEST_RESULT != 0 ))" 1 non-tty-default-install-rejected
    assert_equal "$(file_exists "$TEST_RUNTIME")" no non-tty-no-runtime
    assert_equal "$(file_exists "${TEST_CASE_HOME}/.zshrc")" no non-tty-no-shell-write
    assert_equal "$(file_exists "${TEST_CASE_DIR}/preference-mutations")" no non-tty-no-preference-write
    local mode=''
    for mode in missing invalid dependency; do
        reset_case "invalid-${mode}"
        TEST_PAYLOAD_MODE="$mode"
        if [[ "$mode" == dependency ]]; then
            invoke_installer explicit-install
        else
            invoke_installer install
        fi
        assert_equal "$(( TEST_RESULT != 0 ))" 1 "${mode}-install-rejected"
        assert_equal "$(file_exists "$TEST_RUNTIME")" no "${mode}-no-runtime"
        assert_equal "$(file_exists "${TEST_CASE_HOME}/.zshrc")" no "${mode}-no-shell-write"
        assert_equal "$(file_exists "${TEST_CASE_DIR}/preference-mutations")" no "${mode}-no-preference-write"
        assert_gitconfig_unchanged "$mode"
    done
}
# 汇总结果并向调用者传播任何验证失败。
finish_tests() {
    print -r -- "Jobs Git 安装入口隔离验证：${TEST_PASSED} 项通过，${TEST_FAILED} 项失败。"
    (( TEST_FAILED == 0 ))
}
# 编排说明、隔离环境和完整安装恢复验证。
main() {
    show_test_intro # 先说明 mock 边界与取消方式。
    prepare_tests # 只读加载同包单文件安装器。
    test_check_read_only # 确认检查模式不产生任何用户目录写入。
    test_embedded_payload # 确认内嵌脚本与 canonical 源完整一致。
    test_first_install # 验证首次安装和原启动文件保留。
    test_preference_snapshots # 验证偏好缺失、空值和已有值的精确快照。
    test_restore_existing_shell # 验证只撤回自身块并保留后续用户编辑。
    test_restore_no_final_newline # 验证无末尾换行的原文可逐字节恢复。
    test_restore_absent_files # 验证原来不存在的文件精确恢复且可重复撤回。
    test_idempotent_install_and_upgrade # 验证重复安装与上一版升级恢复。
    test_wrapper_conflict # 验证运行态后改时停止恢复。
    test_preference_conflict # 验证偏好后改时整次恢复停止。
    test_runtime_execution_permission # 验证运行入口失去执行权限时检查失败且只读。
    test_preference_type_conflict # 验证值相同而类型后改的偏好冲突也会停止。
    test_sourcetree_absent # 验证没有 SourceTree 时只安装终端入口。
    test_invalid_inputs # 验证非 TTY、缺 payload 和坏依赖安全退出。
    finish_tests # 汇总断言并返回最终状态。
}

main "$@"
