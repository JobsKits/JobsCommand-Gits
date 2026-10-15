#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】⬆️Git添加子模块.command
# - 核心用途：执行“⬆️Git添加子模块”对应的 Git / Sourcetree 自动化操作。
# - 影响范围：可能修改当前仓库、工作区、分支、菜单配置或 Git 索引。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。
# =====================================================================
# Jobs 标准化脚本外壳
# 说明：保留原脚本业务逻辑，补齐 README 防误触、彩色日志、zsh 入口、Homebrew 健康自检标准。
# =====================================================================

# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
# >>> Jobs Homebrew install choice >>>
# 输出安装诊断，避免混入返回的命令路径。
jobs_brew_note() {
  print -u2 -r -- "ℹ $*"
}
# 验证候选能够执行；共享安装只读不代表未安装。
jobs_brew_candidate_ok() {
  local candidate="$1" prefix
  [[ -n "$candidate" && -x "$candidate" ]] || return 1
  HOMEBREW_NO_AUTO_UPDATE=1 "$candidate" --version >/dev/null 2>&1 || return 1
  prefix="$("$candidate" --prefix 2>/dev/null)" || return 1
  [[ "$prefix" == /* && -d "$prefix" ]]
}
# 发现既有健康安装，不以目录可写性决定是否重新安装。
jobs_brew_find() {
  local candidate
  local -a candidates
  candidates=("${JOBS_HOMEBREW_BIN:-}" "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew
    "${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}/bin/brew" "$HOME/.homebrew/bin/brew")
  for candidate in "${candidates[@]}"; do
    if jobs_brew_candidate_ok "$candidate"; then
      print -r -- "$candidate"
      return 0
    fi
  done
  return 1
}
# 计算官方系统目录；实际支持范围和授权交由官方安装器处理。
jobs_brew_system_prefix() {
  case "$(/usr/bin/uname -m)" in
    arm64) print -r -- /opt/homebrew ;;
    *) print -r -- /usr/local ;;
  esac
}
# 缺失时强提示选择安装路径；YES 只表示选择系统目录，不验证密码或权限。
jobs_brew_choose_installation() {
  local answer="" system_prefix="$(jobs_brew_system_prefix)"
  if [[ ! -t 0 || ! -t 2 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 ]]; then
    jobs_brew_note "缺少 Homebrew，需要人工选择安装路径；请在可交互终端重新运行，未执行安装。"
    return 1
  fi
  print -u2 -r -- "⚠ Homebrew 尚未就绪，必须先选择安装路径："
  print -u2 -r -- "1、输入精确大写 YES：选择系统标准目录 $system_prefix（Apple Silicon：/opt/homebrew；Intel：/usr/local）。"
  print -u2 -r -- "   这表示你准备向系统目录安装；官方安装器可能随后要求管理员密码，并自行验证权限。"
  print -u2 -r -- "2、其它输入或直接回车：选择用户目录 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}，不使用 sudo；有管理员权限也可选此路径。"
  print -u2 -r -- "本步骤只选择路径，不收集或验证密码；选定路径失败就停止，不自动切换。按 Ctrl+C 取消整个任务。"
  print -u2 -n -r -- "➤ 安装路径选择："
  if ! IFS= read -r answer; then
    jobs_brew_note "输入已取消或结束，停止安装。"
    return 1
  fi
  if [[ "$answer" == YES ]]; then
    typeset -g JOBS_HOMEBREW_INSTALL_MODE=system
  else
    typeset -g JOBS_HOMEBREW_INSTALL_MODE=user
  fi
}
# 将官方系统安装器下载到临时文件后执行，失败不自动改装到用户目录。
jobs_brew_install_system() {
  local installer system_prefix="$(jobs_brew_system_prefix)" installer_result=0
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方安装器。"; return 1; }
  installer="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-install.XXXXXX")" || return 1
  if curl -fsSL --connect-timeout 10 --max-time 120 https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer"; then
    /bin/bash "$installer" || installer_result=$?
  else
    installer_result=1
  fi
  rm -- "$installer"
  if (( installer_result != 0 )); then
    jobs_brew_note "系统目录安装失败（退出码 $installer_result）；停止，不自动切换安装路径。"
    return 1
  fi
  typeset -g JOBS_HOMEBREW_BIN="$system_prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "官方安装器结束后未找到健康 Homebrew：$JOBS_HOMEBREW_BIN"; return 1; }
}
# 克隆官方稳定版本到用户目录；不覆盖非空目录，不调用 sudo。
jobs_brew_install_user() {
  local prefix="${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}" stage release_tag git_bin
  [[ "$prefix" == /* && "$prefix" != / && "$prefix" != *[[:space:]:]* ]] || {
    jobs_brew_note "Homebrew 用户前缀须为不含空白或冒号的绝对目录：$prefix"
    return 1
  }
  if [[ -L "$prefix" || ( -e "$prefix" && ! -d "$prefix" ) || ( -d "$prefix" && -n "$(ls -A "$prefix" 2>/dev/null)" ) ]]; then
    jobs_brew_note "用户安装目标非空或不是普通目录，不覆盖：$prefix"
    return 1
  fi
  git_bin="$(command -v git 2>/dev/null)"
  [[ -n "$git_bin" ]] && "$git_bin" --version >/dev/null 2>&1 || { jobs_brew_note "用户目录安装需要可用 Git；请先准备 Git / Command Line Tools。"; return 1; }
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方稳定版本。"; return 1; }
  export HOMEBREW_NO_SUDO=1
  mkdir -p "${prefix:h}" || return 1
  stage="$(mktemp -d "${prefix:h}/.jobs-homebrew.XXXXXX")" || return 1
  if ! curl -fsSL --connect-timeout 10 --max-time 60 https://api.github.com/repos/Homebrew/brew/releases/latest -o "$stage/release.json"; then
    rm -r -- "$stage"
    jobs_brew_note "获取官方稳定版本失败，停止安装。"
    return 1
  fi
  release_tag="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p' "$stage/release.json" | head -n 1)"
  if [[ ! "$release_tag" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] ||
     ! GIT_TERMINAL_PROMPT=0 "$git_bin" -c http.lowSpeedLimit=1 -c http.lowSpeedTime=60 clone --depth 1 --branch "$release_tag" --single-branch https://github.com/Homebrew/brew.git "$stage/brew" ||
     ! "$git_bin" -C "$stage/brew" checkout -b stable ||
     ! "$git_bin" -C "$stage/brew" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*' ||
     ! mkdir -p "$stage/brew/Cellar" "$stage/brew/Caskroom" "$stage/brew/etc" "$stage/brew/var"; then
    rm -r -- "$stage"
    jobs_brew_note "Homebrew 用户目录初始化失败，停止安装。"
    return 1
  fi
  # 空目录也只在下载成功后移除，避免提前改动用户的目标目录。
  if [[ -d "$prefix" ]] && ! rmdir -- "$prefix"; then
    rm -r -- "$stage"
    return 1
  fi
  if ! mv "$stage/brew" "$prefix"; then
    rm -r -- "$stage"
    return 1
  fi
  rm -r -- "$stage"
  typeset -g JOBS_HOMEBREW_BIN="$prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "用户目录安装后复检失败：$prefix"; return 1; }
}
# 只更新本模块的 shellenv 配置块，并保留配置文件的符号链接和权限。
jobs_brew_save_shellenv() {
  local profile_file="$HOME/.zprofile" profile_stage shellenv_line current_shell="${SHELL:-/bin/zsh}"
  [[ "${current_shell##*/}" != bash ]] || profile_file="$HOME/.bash_profile"
  shellenv_line='eval "$('"${(q)JOBS_HOMEBREW_BIN}"' shellenv)"'
  profile_stage="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-profile.XXXXXX")" || return 1
  if [[ -e "$profile_file" || -L "$profile_file" ]]; then
    awk '
      $0 == "# >>> Jobs Homebrew shellenv >>>" { inside = 1; block = $0 ORS; next }
      inside {
        block = block $0 ORS
        if ($0 == "# <<< Jobs Homebrew shellenv <<<") { inside = 0; block = "" }
        next
      }
      { print }
      END { if (inside) printf "%s", block }
    ' "$profile_file" > "$profile_stage" || { rm -- "$profile_stage"; return 1; }
  fi
  {
    print -r -- '# >>> Jobs Homebrew shellenv >>>'
    print -rl -- "$shellenv_line" '# <<< Jobs Homebrew shellenv <<<'
  } >> "$profile_stage"
  if ! cmp -s "$profile_stage" "$profile_file"; then
    cat "$profile_stage" > "$profile_file" || { rm -- "$profile_stage"; jobs_brew_note "无法写入用户配置：$profile_file"; return 1; }
  fi
  rm -- "$profile_stage"
}
# 激活当前进程并验证 Ruby 命令层；只有新安装才持久化 shellenv。
jobs_brew_activate() {
  local brew_env
  brew_env="$("$JOBS_HOMEBREW_BIN" shellenv)" || return 1
  eval "$brew_env" || return 1
  typeset -g JOBS_HOMEBREW_PREFIX="$("$JOBS_HOMEBREW_BIN" --prefix)"
  export PATH="$JOBS_HOMEBREW_PREFIX/bin:$JOBS_HOMEBREW_PREFIX/sbin:$PATH"
  rehash
  HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" config >/dev/null || { jobs_brew_note "Homebrew 命令层复检失败，停止后续业务。"; return 1; }
  if [[ "${1:-}" == installed ]]; then
    if [[ "${JOBS_HOMEBREW_INSTALL_MODE:-}" == user && -z "${HOMEBREW_CASK_OPTS:-}" ]]; then
      export HOMEBREW_CASK_OPTS="--appdir=$HOME/Applications"
    fi
    jobs_brew_save_shellenv || return 1
  fi
}
# 在原版安装位置复用或安装 Homebrew，安装失败必须终止外层业务。
jobs_brew_install_or_exit() {
  local installed=""
  if [[ "${DRY_RUN:-0}" == 1 ]]; then
    jobs_brew_note "演练：Homebrew 系统路径 $(jobs_brew_system_prefix)；用户路径 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}；未询问或执行安装。"
    return 0
  fi
  if ! JOBS_HOMEBREW_BIN="$(jobs_brew_find)"; then
    jobs_brew_choose_installation || exit 1
    case "$JOBS_HOMEBREW_INSTALL_MODE" in
      system) jobs_brew_install_system || exit 1 ;;
      user) jobs_brew_install_user || exit 1 ;;
      *) jobs_brew_note "安装路径选择无效，停止。"; exit 1 ;;
    esac
    installed=installed
  fi
  jobs_brew_activate "$installed" || exit 1
}
# <<< Jobs Homebrew install choice <<<
jobs_intro_style() {
  local intro_color=0
  if [ -t 1 ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
     [ -z "${NO_COLOR+x}" ] && [ "${PLAIN_OUTPUT:-0}" != 1 ] &&
     [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]; then
    intro_color=1
  fi
  /usr/bin/awk -v color="$intro_color" -v role="${1:-body}" '
    BEGIN { esc = sprintf("%c", 27) }
    {
      gsub(esc "\\[[0-9;]*m", "")
      gsub(/\\(033|e|x1[bB])\[[0-9;]*m/, "")
      if (!color || $0 ~ /^[[:space:]]*$/) { print; next }
      numbered = ($0 ~ /^[[:space:]➤ℹ🔹✔⚠]*([0-9]+[、.)）]|[0-9]+️⃣|[-•])/)
      heading = ($0 ~ /^[[:space:]]*#{1,6}[[:space:]]/ || $0 ~ /[：:][[:space:]]*$/ || $0 ~ /^[[:space:]]*[=━─-]{3}/)
      title = (!numbered && (role == "title" || heading))
      if (role == "auto" && !seen && !numbered) title = 1
      if ($0 !~ /^[[:space:]]*[=━─-]+[[:space:]]*$/) seen = 1
      printf "%s%s%s\n", esc (title ? "[1;31m" : "[0;34m"), $0, esc "[0m"
    }
  '
}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
SCRIPT_BASENAME="$(basename "$0" | sed 's/\.[^.]*$//')"
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
# 统一输出终端信息并同步记录日志。
log()            { echo -e "$1" | tee -a "$LOG_FILE"; }
# 输出 color echo 对应级别的日志信息。
color_echo()     { log "\033[1;32m$1\033[0m"; }
# 输出 info echo 对应级别的日志信息。
info_echo()      { log "\033[1;34mℹ $1\033[0m"; }
# 输出 success echo 对应级别的日志信息。
success_echo()   { log "\033[1;32m✔ $1\033[0m"; }
# 输出 warn echo 对应级别的日志信息。
warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }
# 输出 warm echo 对应级别的日志信息。
warm_echo()      { log "\033[1;33m$1\033[0m"; }
# 输出 note echo 对应级别的日志信息。
note_echo()      { log "\033[1;35m➤ $1\033[0m"; }
# 输出 error echo 对应级别的日志信息。
error_echo()     { log "\033[1;31m✖ $1\033[0m"; }
# 输出 err echo 对应级别的日志信息。
err_echo()       { log "\033[1;31m$1\033[0m"; }
# 输出 debug echo 对应级别的日志信息。
debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }
# 输出 highlight echo 对应级别的日志信息。
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }
# 输出 gray echo 对应级别的日志信息。
gray_echo()      { log "\033[0;90m$1\033[0m"; }
# 输出 bold echo 对应级别的日志信息。
bold_echo()      { log "\033[1m$1\033[0m"; }
# 输出 underline echo 对应级别的日志信息。
underline_echo() { log "\033[4m$1\033[0m"; }
# ============================= 标准工具函数 =============================
get_cpu_arch() {
  [[ "$(uname -m)" == "arm64" ]] && echo "arm64" || echo "x86_64"
}
# 封装 abs path 对应的独立处理逻辑。
abs_path() {
  local p="$1"
  [[ -z "$p" ]] && return 1
  p="${p//\"/}"
  [[ "$p" != "/" ]] && p="${p%/}"
  if [[ -d "$p" ]]; then
    (cd "$p" 2>/dev/null && pwd -P)
  elif [[ -f "$p" ]]; then
    (cd "${p:h}" 2>/dev/null && printf "%s/%s\n" "$(pwd -P)" "${p:t}")
  else
    return 1
  fi
}
# 收集并校验 ask run 对应的用户确认。
ask_run() {
  echo ""
  note_echo "👉 $1"
  gray_echo "【回车=跳过，输入任意字符后回车=执行】"
  local input=""
  IFS= read -r "input?➤ "
  [[ -n "$input" ]]
}
# 收集并校验 confirm yes 对应的用户确认。
confirm_yes() {
  echo ""
  warn_echo "⚠ $1"
  gray_echo "危险操作必须输入 YES 后回车；其它输入一律取消。"
  local input=""
  IFS= read -r "input?➤ "
  [[ "$input" == "YES" ]]
}
# 封装 inject shellenv block 对应的独立处理逻辑。
inject_shellenv_block() {
  local profile_file="$1"
  local shellenv_cmd="$2"
  local header="# >>> Homebrew 环境变量 >>>"
  [[ -z "$profile_file" || -z "$shellenv_cmd" ]] && { error_echo "缺少参数：inject_shellenv_block <profile_file> <shellenv_cmd>"; return 1; }
  mkdir -p "$(dirname "$profile_file")"
  touch "$profile_file"
  if grep -Fq "$shellenv_cmd" "$profile_file" 2>/dev/null; then
    info_echo "已存在 Homebrew shellenv：$profile_file"
  elif grep -Fq "$header" "$profile_file" 2>/dev/null; then
    info_echo "已存在 Homebrew 环境变量块：$profile_file"
  else
    {
      echo ""
      echo "$header"
      echo "$shellenv_cmd"
    } >> "$profile_file"
    success_echo "已写入 Homebrew shellenv：$profile_file"
  fi
  eval "$shellenv_cmd" || true
}
# 封装 activate homebrew shellenv 对应的独立处理逻辑。
activate_homebrew_shellenv() {
  local arch="$(get_cpu_arch)"
  local brew_bin=""
  brew_bin="$(jobs_brew_find)" || { error_echo "没有健康 Homebrew，停止激活。"; return 1; }
  JOBS_HOMEBREW_BIN="$brew_bin"
  jobs_brew_activate || { error_echo "Homebrew 激活或命令层复检失败。"; return 1; }

  local shell_name="${SHELL##*/}"
  local profile_file=""
  case "$shell_name" in
    zsh)  profile_file="$HOME/.zprofile" ;;
    bash) profile_file="$HOME/.bash_profile" ;;
    *)    profile_file="$HOME/.profile" ;;
  esac
  inject_shellenv_block "$profile_file" "eval \"\$(${brew_bin} shellenv)\"" || return 1
  eval "$(${brew_bin} shellenv)"
}
# 执行 run brew health update 对应的独立业务步骤。
run_brew_health_update() {
  info_echo "正在执行 Homebrew 健康更新..."
  brew update  || { error_echo "brew update 失败"; return 1; }
  brew upgrade || { error_echo "brew upgrade 失败"; return 1; }
  brew cleanup || { error_echo "brew cleanup 失败"; return 1; }
  brew doctor  || warn_echo "brew doctor 有警告，请按输出处理"
  brew -v      || warn_echo "打印 brew 版本失败，可忽略"
  success_echo "Homebrew 健康更新完成"
}
# 准备并配置 install homebrew 对应的运行条件。
install_homebrew() {
  local arch="$(get_cpu_arch)"
  local brew_bin=""

  if ! brew_bin="$(jobs_brew_find)"; then
    warn_echo "未检测到 Homebrew，准备按架构安装：$arch"
    if [[ "$arch" == "arm64" ]]; then
      jobs_brew_install_or_exit || { error_echo "Homebrew 安装失败（arm64）"; return 1; }
      brew_bin="${JOBS_HOMEBREW_BIN:-$(jobs_brew_find 2>/dev/null || true)}"
    else
      jobs_brew_install_or_exit || { error_echo "Homebrew 安装失败（x86_64）"; return 1; }
      brew_bin="${JOBS_HOMEBREW_BIN:-$(jobs_brew_find 2>/dev/null || true)}"
    fi
    success_echo "Homebrew 安装完成"
    activate_homebrew_shellenv || exit 1
    return 0
  fi

  activate_homebrew_shellenv || exit 1
  info_echo "Homebrew 已安装。"
  if ask_run "是否执行 Homebrew 更新 / 升级 / 清理 / doctor？"; then
    run_brew_health_update || exit 1
  else
    note_echo "已跳过 Homebrew 更新"
  fi
}
# 封装 brew install or upgrade 对应的独立处理逻辑。
brew_install_or_upgrade() {
  local formula="$1"
  [[ -z "$formula" ]] && return 1
  install_homebrew || return 1
  if ! brew list --formula "$formula" >/dev/null 2>&1 && ! command -v "$formula" >/dev/null 2>&1; then
    note_echo "未检测到 $formula，正在安装..."
    brew install "$formula" || { error_echo "$formula 安装失败"; return 1; }
    success_echo "$formula 安装完成"
  else
    info_echo "$formula 已安装。"
    if ask_run "是否升级 $formula？"; then
      brew upgrade "$formula" || warn_echo "$formula 可能已是最新或升级失败，请检查输出"
      brew cleanup || true
    else
      note_echo "已跳过 $formula 升级"
    fi
  fi
}
# 输出 show readme and wait 对应的说明与结果。
show_script_intro_and_wait() {
  clear
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：【MacOS】⬆️Git添加子模块.command' | jobs_intro_style title
  print -r -- '核心用途：执行“⬆️Git添加子模块”对应的 Git 自动化操作。' | jobs_intro_style body
  print -r -- '影响范围：可能修改当前仓库、工作区、分支或 Git 索引。' | jobs_intro_style body
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。' | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title
  echo "" | jobs_intro_style body
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _ || exit 1
}
# 执行 run original logic 对应的独立业务步骤。
run_original_logic() {
  # ============================= 原脚本业务逻辑区 =============================
  set -euo pipefail
  # ============================ Git 子模块批量管理（模块化调用） ============================
  # —— 自述 & 用户确认 ——
  show_intro_and_wait() {
    cat <<'EOF' | jobs_intro_style auto
  📘 脚本说明
  ------------------------------------------------------------
  本脚本用于批量管理 Git 子模块，包含以下流程：
    1. 切换到脚本所在目录，并确保这是 Git 仓库根目录
    2. 删除当前仓库下所有已存在的子模块（包括 .gitmodules 配置）
    3. 重新添加预定义的子模块
    4. 同步子模块配置并首次拉取
    5. 将子模块前移到远端分支最新，并【固化到父仓】记录最新 SHA
    6. 配置远程仓库（交互式输入）

  ⚠️ 注意：
  运行后将会：彻底清空现有的子模块，并提交一笔清理记录。
  请确保你已经备份或不再需要原有子模块的数据。

  ------------------------------------------------------------
  按下 [回车] 键继续，或 Ctrl+C 取消。
EOF
    read -r
  }
  # —— 简易语义输出（避免外部依赖） ——
  info_echo()    { echo "ℹ️  $*"; }
  # 输出 success echo 对应级别的日志信息。
  success_echo() { echo "✅ $*"; }
  # 输出 warn echo 对应级别的日志信息。
  warn_echo()    { echo "⚠️  $*"; }
  # 输出 error echo 对应级别的日志信息。
  error_echo()   { echo "❌ $*" >&2; }
  # 1) 切到脚本所在目录
  cd_to_script_dir() {
    local script_path
    script_path="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
    cd "$script_path"
  }
  # 2) 初始化父仓（幂等）
  ensure_repo_initialized() {
    git init
    # 先把现状纳入暂存，避免后续操作依赖失败（无变更时不报错）
    git add . || true
    git status
  }
  # 3) 仅删除子模块目录，并清理索引中的 gitlink（mode=160000）
  # - 打印将删除的目录清单 + 每条执行结果
  # - 清空 .gitmodules 内容（不存在就新建）
  # - 删除 .git/modules/<path>（确保后续 submodule add 不报本地仓库已存在）
  # - 清理完成后自动提交一笔 "chore: reset submodules"
  purge_all_submodules() {
    info_echo "清理子模块目录 + 索引 gitlink + .gitmodules + .git/modules"

    # --- 收集子模块路径 ---
    local paths=()
    if [[ -f .gitmodules ]]; then
      while IFS= read -r p; do
        [[ -n "$p" ]] && paths+=("$p")
      done < <(git config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}')
    fi
    while IFS= read -r p; do
      [[ -n "$p" ]] && paths+=("$p")
    done < <(git ls-files -s 2>/dev/null | awk '$1==160000 {print $4}')

    # --- 去重 ---
    local uniq_paths=()
    typeset -A __seen
    local _p
    for _p in "${paths[@]:-}"; do
      [[ -z "${__seen[$_p]:-}" ]] && uniq_paths+=("$_p") && __seen[$_p]=1
    done

    # --- 预览将要删除的目录 ---
    if [[ ${#uniq_paths[@]} -eq 0 ]]; then
      info_echo "未发现任何子模块路径，跳过清理。"
    else
      info_echo "将删除以下 ${#uniq_paths[@]} 个子模块目录："
      local i=1
      for _p in "${uniq_paths[@]}"; do
        echo "   $i) $_p"
        ((i++))
      done
    fi

    # --- 逐条执行并打印结果（不中断） ---
    set +e
    local removed=0 skipped=0 failed=0 cleared=0 modules_removed=0
    local removed_list=()

    for _p in "${uniq_paths[@]:-}"; do
      # 1) 删除工作区目录
      if [[ -e "$_p" ]]; then
        rm -rf -- "$_p"
        if [[ -e "$_p" ]]; then
          echo "❌ 删除失败：$_p"; ((failed++))
        else
          echo "✅ 已删除：$_p"; ((removed++)); removed_list+=("$_p")
        fi
      else
        echo "ℹ️  不存在（跳过）：$_p"; ((skipped++))
      fi

      # 2) 清理索引 gitlink（若存在）
      if git ls-files -s -- "$_p" | awk '$1==160000 {exit 0} {exit 1}'; then
        git rm -f --cached -- "$_p" >/dev/null 2>&1
        # 这里不再二次校验，交由最终 commit 生效
        ((cleared++))
        echo "🧹 已清理索引 gitlink：$_p"
      fi

      # 3) 删除 .git/modules/<path>（避免 re-add 冲突）
      local modpath=".git/modules/$_p"
      if [[ -d "$modpath" ]]; then
        rm -rf -- "$modpath"
        if [[ ! -d "$modpath" ]]; then
          ((modules_removed++))
          echo "🗂️  已删除子模块仓库：$modpath"
        else
          echo "❌ 删除子模块仓库失败：$modpath"
        fi
      fi
    done
    set -e

    # --- 重置 .gitmodules（确保存在且为空） ---
    printf "# Reset by purge_all_submodules on %s\n" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" > .gitmodules
    git add .gitmodules 2>/dev/null || true

    # --- 提交一次快照 ---
    git add -A || true
    if ! git diff --cached --quiet; then
      git commit -m "chore: reset submodules" >/dev/null 2>&1 || true
      success_echo "已提交：chore: reset submodules"
    else
      info_echo "无变更可提交，跳过 commit"
    fi

    # --- 汇总（竖向打印已删除目录） ---
    if (( removed > 0 )); then
      success_echo "✅ 清理完成：删除目录 $removed 项："
      for d in "${removed_list[@]}"; do
        echo "   - $d"
      done
    else
      info_echo "没有目录被删除"
    fi
    info_echo "索引 gitlink 清理 $cleared 项；.git/modules 清理 $modules_removed 项；跳过 $skipped 项；失败 $failed 项。"
  }
  # 4) 确保 .gitmodules 在“当前脚本运行目录”（且该目录就是仓库根）
  ensure_gitmodules_here() {
    # 已是 Git 仓库时，校验顶层目录
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      local top
      top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
      if [[ -n "${top:-}" && "$top" != "$PWD" ]]; then
        error_echo "当前目录不是仓库根目录：top-level = $top （.gitmodules 必须在仓库根）"
        exit 1
      fi
    fi

    if [[ ! -e .gitmodules ]]; then
      printf "# Auto-created by script on %s\n" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" > .gitmodules
      info_echo "已创建空的 .gitmodules 于：$PWD"
    elif [[ -L .gitmodules || -d .gitmodules ]]; then
      local bak=".gitmodules.bak.$(date +%s)"
      mv .gitmodules "$bak"
      printf "# Auto-recreated by script on %s (backup: %s)\n" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$bak" > .gitmodules
      warn_echo "检测到异常的 .gitmodules（目录/符号链接），已备份为 $bak 并重建为常规文件"
    fi

    git add .gitmodules 2>/dev/null || true
  }
  # 5) 添加子模块（此时就在拉取远端）
  add_submodules() {
    git submodule add -b main https://github.com/JobsKits/JobsCommand-Flutter.git  ./JobsGenesis@JobsCommand.Flutter
    git submodule add -b main https://github.com/JobsKits/JobsCommand-iOS.git      ./JobsGenesis@JobsCommand.iOS
    git submodule add -b main https://github.com/JobsKits/JobsCommand-Gits.git     ./JobsGenesis@JobsCommand.Gits
    git submodule add -b main https://github.com/JobsKits/JobsCommand-Others.git   ./JobsGenesis@JobsCommand.Others
    git submodule add -b main https://github.com/JobsKits/JobsSh.git               ./JobsGenesis@JobsSh
  }
  # 6) 同步子模块记录
  sync_submodules() {
    git submodule sync
  }
  # 7) 提交 .gitmodules 及目录占位
  commit_gitmodules_and_dirs() {
    git add .gitmodules */ 2>/dev/null || true
    git commit -m "同步文件" || info_echo "无变更可提交，跳过 commit"
  }
  # 8) 获取并发数（macOS 优先，用于 submodule --jobs）
  get_ncpu() {
    if command -v sysctl >/dev/null 2>&1; then
      sysctl -n hw.ncpu
    else
      echo 1
    fi
  }
  # 9) 首次拉取子模块内容（并发）
  submodule_init_update() {
    git submodule update --init --recursive --jobs="$(get_ncpu)"
  }
  # 10) 让全部子模块按“各自的 branch”前移到远端最新
  submodule_ff_remote_merge() {
    git submodule update --remote --merge --recursive --jobs="$(get_ncpu)"
  }
  # 11) 配置当前 Git 仓库的 remote（交互式，兼容 zsh）
  ensure_git_remote() {
    local remote_name="${1:-origin}"
    local remote_url=""

    # 如果已经存在远程仓库，直接提示并返回
    if git remote get-url "$remote_name" >/dev/null 2>&1; then
      info_echo "已存在 git remote [$remote_name] -> $(git remote get-url "$remote_name")"
      return 0
    fi

    while true; do
      # ✅ 在 zsh 里用 read '?prompt:'，在 bash 里用 read -p
      if [ -n "${ZSH_VERSION:-}" ]; then
        read "?请输入Git远程仓库地址: " remote_url
      else
        read "?请输入Git远程仓库地址: " remote_url
      fi

      if [[ -z "${remote_url:-}" ]]; then
        warn_echo "输入为空，请重新输入"
        continue
      fi

      # 验证远程是否可访问
      if git ls-remote "$remote_url" >/dev/null 2>&1; then
        git remote add "$remote_name" "$remote_url"
        success_echo "已成功配置 git remote [$remote_name] -> $remote_url"
        break
      else
        error_echo "无法访问 $remote_url，请检查地址是否正确"
      fi
    done
  }
  # 12) 记录子模块新的 SHA 到父仓，并尽量让子模块处于分支 HEAD（避免 detached HEAD）
  record_and_normalize_submodules() {
    info_echo "标准化子模块分支并固化 gitlink 到父仓……"

    # 尽量让每个子模块处于 main 分支（若存在）
    git submodule foreach '
      set -e
      # 有 main 分支就切过去并同步
      if git show-ref --verify --quiet refs/heads/main; then
        git checkout main >/dev/null 2>&1 || true
        git pull --ff-only || true
      else
        # 尝试创建 main 跟踪 origin/main
        if git ls-remote --exit-code --heads origin main >/dev/null 2>&1; then
          git checkout -B main --track origin/main || true
          git pull --ff-only || true
        fi
      fi
    '

    # 取出所有子模块路径，提交到父仓，使父仓记录最新 gitlink
    local paths
    paths=($(git config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}'))
    if [[ ${#paths[@]} -gt 0 ]]; then
      git add "${paths[@]}" 2>/dev/null || true
    fi

    git commit -m "chore: bump submodules to latest remote" || info_echo "无子模块前移需要固化，跳过 commit"
    success_echo "子模块最新提交已固化到父仓（若有变更）"
  }
  # ================================== main（只调用函数） ==================================
  main() {
    show_intro_and_wait              # 自述信息 + 等待用户确认
    cd_to_script_dir                 # 切到脚本所在目录
    ensure_repo_initialized          # 初始化父仓（幂等）
    purge_all_submodules             # ✅ 运行前：先删除本文件夹下所有子模块（含索引与 .git/modules）
    ensure_gitmodules_here           # 确保 .gitmodules 在当前目录（且为仓库根），必要时创建/修复
    add_submodules                   # 添加子模块（立即拉取）
    sync_submodules                  # 同步子模块记录
    commit_gitmodules_and_dirs       # 提交 .gitmodules 及目录占位
    submodule_init_update            # 首次拉取子模块内容（并发）
    submodule_ff_remote_merge        # 让全部子模块按“各自的 branch”前移到远端最新
    record_and_normalize_submodules  # ✅ 固化子模块 SHA 到父仓，并尽量在 main 分支上
    ensure_git_remote                # 配置 remote（可交互）
  }

  main "$@"

  # =========================== 原脚本业务逻辑区结束 ===========================
}
# 编排脚本的高层业务流程。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_runtime() {
  : > "$LOG_FILE"
}
# 编排脚本的高层业务流程。
main() {
  show_script_intro_and_wait # 展示脚本内置自述，并按运行入口完成防误触确认。
  initialize_script_runtime # 初始化 Shell 选项、日志、依赖和入口运行状态。
  run_original_logic "$@" # 执行 run_original_logic 对应的核心业务步骤。
  success_echo "脚本执行结束。日志：$LOG_FILE" # 输出脚本执行结果、摘要和日志位置。
}

main "$@"
