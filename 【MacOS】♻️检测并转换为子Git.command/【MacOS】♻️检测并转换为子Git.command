#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】♻️检测并转换为子Git.command
# - 核心用途：执行“♻️检测并转换为子Git”对应的 Git / Sourcetree 自动化操作。
# - 影响范围：可能修改当前仓库、工作区、分支、菜单配置或 Git 索引。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。
# =====================================================================
# Jobs 标准化脚本外壳
# 说明：保留原脚本业务逻辑，补齐 README 防误触、彩色日志、zsh 入口、Homebrew 健康自检标准。
# =====================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
SCRIPT_BASENAME="$(basename "$0" | sed 's/\.[^.]*$//')"
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
# 按当前输出级别记录终端信息，并同步写入脚本日志。
log()            { echo -e "$1" | tee -a "$LOG_FILE"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
color_echo()     { log "\033[1;32m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
info_echo()      { log "\033[1;34mℹ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
success_echo()   { log "\033[1;32m✔ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warm_echo()      { log "\033[1;33m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
note_echo()      { log "\033[1;35m➤ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
error_echo()     { log "\033[1;31m✖ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
err_echo()       { log "\033[1;31m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
gray_echo()      { log "\033[0;90m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
bold_echo()      { log "\033[1m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
underline_echo() { log "\033[4m$1\033[0m"; }
# ============================= 标准工具函数 =============================
get_cpu_arch() {
  [[ "$(uname -m)" == "arm64" ]] && echo "arm64" || echo "x86_64"
}
# 封装 abs_path 对应的独立处理逻辑。
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
# 收集并校验用户输入，决定后续执行路径。
ask_run() {
  echo ""
  note_echo "👉 $1"
  gray_echo "【回车=跳过，输入任意字符后回车=执行】"
  local input=""
  IFS= read -r "input?➤ "
  [[ -n "$input" ]]
}
# 收集并校验用户输入，决定后续执行路径。
confirm_yes() {
  echo ""
  warn_echo "⚠ $1"
  gray_echo "危险操作必须输入 YES 后回车；其它输入一律取消。"
  local input=""
  IFS= read -r "input?➤ "
  [[ "$input" == "YES" ]]
}
# 封装 inject_shellenv_block 对应的独立处理逻辑。
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
# 封装 activate_homebrew_shellenv 对应的独立处理逻辑。
activate_homebrew_shellenv() {
  local arch="$(get_cpu_arch)"
  local brew_bin=""
  if command -v brew >/dev/null 2>&1; then
    brew_bin="$(command -v brew)"
  elif [[ "$arch" == "arm64" && -x "/opt/homebrew/bin/brew" ]]; then
    brew_bin="/opt/homebrew/bin/brew"
  elif [[ -x "/usr/local/bin/brew" ]]; then
    brew_bin="/usr/local/bin/brew"
  fi
  [[ -z "$brew_bin" ]] && return 1

  local shell_name="${SHELL##*/}"
  local profile_file=""
  case "$shell_name" in
    zsh)  profile_file="$HOME/.zprofile" ;;
    bash) profile_file="$HOME/.bash_profile" ;;
    *)    profile_file="$HOME/.profile" ;;
  esac
  inject_shellenv_block "$profile_file" "eval \"\$(${brew_bin} shellenv)\""
  eval "$(${brew_bin} shellenv)"
}
# 执行已经拆分完成的独立业务步骤。
run_brew_health_update() {
  info_echo "正在执行 Homebrew 健康更新..."
  brew update  || { error_echo "brew update 失败"; return 1; }
  brew upgrade || { error_echo "brew upgrade 失败"; return 1; }
  brew cleanup || { error_echo "brew cleanup 失败"; return 1; }
  brew doctor  || warn_echo "brew doctor 有警告，请按输出处理"
  brew -v      || warn_echo "打印 brew 版本失败，可忽略"
  success_echo "Homebrew 健康更新完成"
}
# 执行对应的环境配置或同步处理。
install_homebrew() {
  local arch="$(get_cpu_arch)"
  local brew_bin=""

  if ! command -v brew >/dev/null 2>&1 && [[ ! -x "/opt/homebrew/bin/brew" && ! -x "/usr/local/bin/brew" ]]; then
    warn_echo "未检测到 Homebrew，准备按架构安装：$arch"
    if [[ "$arch" == "arm64" ]]; then
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || { error_echo "Homebrew 安装失败（arm64）"; return 1; }
      brew_bin="/opt/homebrew/bin/brew"
    else
      arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || { error_echo "Homebrew 安装失败（x86_64）"; return 1; }
      brew_bin="/usr/local/bin/brew"
    fi
    success_echo "Homebrew 安装完成"
    activate_homebrew_shellenv || true
    return 0
  fi

  activate_homebrew_shellenv || true
  info_echo "Homebrew 已安装。"
  if ask_run "是否执行 Homebrew 更新 / 升级 / 清理 / doctor？"; then
    run_brew_health_update
  else
    note_echo "已跳过 Homebrew 更新"
  fi
}
# 封装 brew_install_or_upgrade 对应的独立处理逻辑。
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
# 展示脚本用途和影响范围，并在执行前等待用户确认。
show_readme_and_wait() {
  clear
  print -r -- '============================== 脚本内置自述 =============================='
  print -r -- '脚本名称：【MacOS】♻️检测并转换为子Git.command'
  print -r -- '核心用途：执行“♻️检测并转换为子Git”对应的 Git 自动化操作。'
  print -r -- '影响范围：可能修改当前仓库、工作区、分支或 Git 索引。'
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。'
  print -r -- '============================================================================'
  local readme_path="${SCRIPT_DIR}/README.md"
  if [[ -f "$readme_path" ]]; then
    highlight_echo "正在显示脚本自述文件：$readme_path"
    echo ""
    cat "$readme_path" | tee -a "$LOG_FILE"
  else
    warn_echo "未找到 README.md：$readme_path"
  fi
  echo ""
  read "?👉 请先阅读上面的自述文件，按回车继续执行，或按 Ctrl+C 取消..."
}
# 执行已经拆分完成的独立业务步骤。
run_original_logic() {
  # ============================= 原脚本业务逻辑区 =============================
  set -Eeuo pipefail

  # ================================== UTF-8 / 终端兼容 ==================================
  # 说明：
  # - .command 在某些终端/环境下可能出现中文/emoji 乱码
  # - 强制使用 UTF-8 locale，尽量避免输出乱码
  export LANG="${LANG:-en_US.UTF-8}"
  export LC_ALL="${LC_ALL:-en_US.UTF-8}"

  # ================================== 基础信息 ==================================
  SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
  SCRIPT_BASENAME="$(basename "$SCRIPT_PATH")"
  LOG_FILE="${LOG_FILE:-/tmp/${SCRIPT_BASENAME}.log}"

  # 运行脚本时的起始目录（用户在哪里运行/双击打开，就以哪里为起点）
  LAUNCH_DIR="$(pwd)"

  # 交互统一走 TTY，避免 .command / 管道环境 stdin 异常导致卡死
  TTY_IN="/dev/tty"
  TTY_OUT="/dev/tty"
  # ================================== 日志输出函数 ==================================
  # 说明：
  # - 所有“展示给用户”的输出走 TTY（不会污染 stdout）
  # - 日志落盘到 LOG_FILE
  # - 使用 printf（比 echo -e 更稳，避免反斜杠/乱码问题）
  _log_raw() {
    local msg="$1"
    printf "%b\n" "$msg" >>"$LOG_FILE"
    printf "%b\n" "$msg" >"$TTY_OUT"
  }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  info_echo()      { _log_raw "\033[1;34mℹ $1\033[0m"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  success_echo()   { _log_raw "\033[1;32m✔ $1\033[0m"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  warm_echo()      { _log_raw "\033[1;33m⚠ $1\033[0m"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  error_echo()     { _log_raw "\033[1;31m✖ $1\033[0m"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  debug_echo()     { _log_raw "\033[1;35m🐞 $1\033[0m"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  note_echo()      { _log_raw "\033[1;36m➤ $1\033[0m"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  highlight_echo() { _log_raw "\033[1;36m🔹 $1\033[0m"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  gray_echo()      { _log_raw "\033[0;90m$1\033[0m"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  bold_echo()      { _log_raw "\033[1m$1\033[0m"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  underline_echo() { _log_raw "\033[4m$1\033[0m"; }
  # 兼容你已有的命名习惯（向后兼容）
  log() { _log_raw "$1"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  info() { info_echo "$1"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  success() { success_echo "$1"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  warn() { warm_echo "$1"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  error() { error_echo "$1"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  debug() { debug_echo "$1"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  note() { note_echo "$1"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  highlight() { highlight_echo "$1"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  gray() { gray_echo "$1"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  bold() { bold_echo "$1"; }
  # 封装 underline 对应的独立处理逻辑。
  underline() { underline_echo "$1"; }
  # ================================== 异常捕获 ==================================
  # 说明：
  # - 仅用于“真正异常”。用户主动取消/返回不应触发 die。
  die() {
    error "${1:-发生错误}"
    error "请查看日志：$LOG_FILE"
    exit 1
  }
  # 封装 on_err 对应的独立处理逻辑。
  on_err() {
    local line="${1:-unknown}"
    error "脚本异常退出：line=$line"
    error "请查看日志：$LOG_FILE"
  }
  trap 'on_err $LINENO' ERR
  # ================================== TTY 交互工具 ==================================
  read_tty() {
    local __var="$1"
    local prompt="${2:-}"
    local input=""
    [[ -n "$prompt" ]] && printf "%b" "$prompt" >"$TTY_OUT"
    IFS= read -r input <"$TTY_IN" || true
    printf -v "$__var" "%s" "$input"
  }
  # 封装 press_enter_to_continue 对应的独立处理逻辑。
  press_enter_to_continue() {
    note "👉 按 [Enter] 继续..."
    local _x=""
    read_tty _x ""
  }
  # ================================== 路径处理 / Git 判断 ==================================
  trim_path() {
    # 去掉首尾空格、末尾 /
    # 去掉拖拽常见的包裹引号
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"   # ltrim
    s="${s%"${s##*[![:space:]]}"}"   # rtrim
    s="${s%/}"                       # 去掉末尾 /
    if [[ "$s" == \"*\" && "$s" == *\" ]]; then s="${s:1:${#s}-2}"; fi
    if [[ "$s" == \'*\' && "$s" == *\' ]]; then s="${s:1:${#s}-2}"; fi
    printf "%s" "$s"
  }
  # 封装 require_cmd 对应的独立处理逻辑。
  require_cmd() { command -v "$1" &>/dev/null; }
  # 检查当前运行条件是否满足后续流程要求。
  is_git_worktree() {
    local dir="$1"
    git -C "$dir" rev-parse --is-inside-work-tree &>/dev/null
  }
  # 解析并返回后续流程需要的目标信息。
  get_git_root() {
    local dir="$1"
    git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true
  }
  # 封装 abspath 对应的独立处理逻辑。
  abspath() {
    local p="$1"
    if command -v realpath &>/dev/null; then
      realpath "$p"
    else
      python3 - <<'PY' "$p" 2>/dev/null || perl -MCwd -e 'print Cwd::abs_path($ARGV[0])' "$p"
  import os,sys
  print(os.path.abspath(sys.argv[1]))
PY
    fi
  }
  # ================================== 自述 ==================================
  show_intro_and_wait() {
    cat >"$TTY_OUT" <<EOF
  【MacOS】♻️ 检测并转换嵌套 Git 为 submodule
  日志：$LOG_FILE

  它会做什么：
  1) 默认以【运行脚本时的当前目录】为起点（也就是你在哪个目录运行，就从哪个目录开始）
  2) 起点目录必须处于 Git 管理中：如果不是 Git 目录，会循环提示你输入/拖入一个 Git 目录
  3) 起点目录不要求一定是 Git 根目录：脚本会自动定位到该目录所属的 Git 根目录作为“父 Git 起点”
  4) 扫描父 Git 起点下的所有【嵌套 Git 仓库根目录】（只列 Git 目录，不列 .git 文件/文件夹；排除已是 submodule 的目录）
  5) 用 fzf 让你选择要转换的目录（多选；含 ALL；如果只有 1 个则不弹 fzf）
  6) 每个目录转换前会二次确认：会把原目录备份到 /tmp，再执行 git submodule add

  ⚠ 风险提示：转换会修改父仓库 .gitmodules / gitlink，并移动原目录到 /tmp 备份。
EOF

    printf "\n➤ 👉 按 [Enter] 继续...\n\n" >"$TTY_OUT"
    IFS= read -r _ <"$TTY_IN" || true
  }
  # ================================== 依赖自检 ==================================
  deps_homebrew() {
    debug "STEP -> deps_homebrew"

    if ! require_cmd brew; then
      warn "未检测到 Homebrew，准备安装..."
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
        || die "Homebrew 安装失败"

      # 尝试让 brew 在当前会话可用
      if [[ -x "/opt/homebrew/bin/brew" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      elif [[ -x "/usr/local/bin/brew" ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
      fi

      success "Homebrew 安装完成"
    else
      info "检测到 Homebrew，是否更新？"
      cat >"$TTY_OUT" <<'EOF'
  👉 直接回车：跳过更新
  👉 输入任意字符后回车：执行 ask_run "执行 Homebrew 更新 / 升级 / 清理？" && run_brew_health_update
EOF
      local c=""
      read_tty c ""
      if [[ -n "$c" ]]; then
        info "开始更新 Homebrew..."
        brew update || die "brew update 失败"
        brew upgrade || die "brew upgrade 失败"
        brew cleanup || true
        brew doctor  || true
        success "Homebrew 更新完成"
      else
        note "⏭️ 已选择跳过：Homebrew 更新"
      fi
    fi

    local bv
    bv="$(brew -v 2>/dev/null | head -n 1 || true)"
    [[ -n "$bv" ]] && info "brew 版本：$bv"
  }
  # 封装 deps_fzf 对应的独立处理逻辑。
  deps_fzf() {
    debug "STEP -> deps_fzf"

    if ! require_cmd fzf; then
      warn "未检测到 fzf，将通过 brew 安装..."
      brew install fzf || die "fzf 安装失败"
      success "fzf 安装完成"
    else
      info "检测到 fzf，是否升级？"
      cat >"$TTY_OUT" <<'EOF'
  👉 直接回车：跳过
  👉 输入任意字符后回车：执行 brew update && brew upgrade fzf && brew cleanup
EOF
      local c=""
      read_tty c ""
      if [[ -n "$c" ]]; then
        info "开始升级 fzf..."
        brew update || die "brew update 失败"
        brew upgrade fzf || die "brew upgrade fzf 失败"
        brew cleanup || true
        success "fzf 升级完成"
      else
        note "⏭️ 已选择跳过：fzf 升级"
      fi
    fi

    local fv
    fv="$(fzf --version 2>/dev/null | head -n 1 || true)"
    [[ -n "$fv" ]] && info "fzf 版本：$fv"
  }
  # 封装 deps_check 对应的独立处理逻辑。
  deps_check() {
    debug "STEP -> deps_check"
    deps_homebrew
    deps_fzf
  }
  # ================================== 起点选择 ==================================
  pick_start_dir() {
    debug "STEP -> pick_start_dir"

    local start_dir="$LAUNCH_DIR"

    # 若传参：用参数作为起点
    if [[ $# -ge 1 && -n "${1:-}" ]]; then
      start_dir="$(trim_path "$1")"
    fi

    while true; do
      if [[ -d "$start_dir" ]] && is_git_worktree "$start_dir"; then
        printf "%s" "$start_dir"
        return 0
      fi

      warn "当前目录不是 Git：$start_dir"
      read_tty start_dir "➤ 请输入一个 Git 目录作为起点（可拖拽目录进来后回车）："
      start_dir="$(trim_path "$start_dir")"

      if [[ -z "$start_dir" ]]; then
        warn "你没有输入路径"
        start_dir="$LAUNCH_DIR"
        continue
      fi

      if [[ ! -d "$start_dir" ]]; then
        warn "目录不存在：$start_dir"
        continue
      fi
    done
  }
  # 解析并返回后续流程需要的目标信息。
  resolve_parent_git_root() {
    debug "STEP -> resolve_parent_git_root"
    local start="$1"
    local root
    root="$(get_git_root "$start")"
    [[ -n "$root" && -d "$root" ]] || die "无法识别起点目录所属的 Git 根目录：$start"
    printf "%s" "$root"
  }

  # ================================== 扫描嵌套 Git ==================================
  # 扫描时排除的大目录（更快、更干净）
  EXCLUDE_DIRS=(
    "Pods"
    "build"
    "DerivedData"
    "Carthage"
    ".swiftpm"
    "node_modules"
    ".gradle"
    ".idea"
    ".vscode"
  )
  # 封装 list_existing_submodules 对应的独立处理逻辑。
  list_existing_submodules() {
    local parent="$1"
    local gm="$parent/.gitmodules"
    [[ -f "$gm" ]] || return 0
    sed -n 's/^[[:space:]]*path[[:space:]]*=[[:space:]]*//p' "$gm" 2>/dev/null || true
  }
  # 输出：每行一个候选 repo 根目录相对路径（相对 parent）
  list_nested_git_repos() {
    debug "STEP -> list_nested_git_repos"
    local parent="$1"

    local tmp_all tmp_filtered tmp_submods
    tmp_all="$(mktemp)"
    tmp_filtered="$(mktemp)"
    tmp_submods="$(mktemp)"

    list_existing_submodules "$parent" | sed '/^[[:space:]]*$/d' >"$tmp_submods" || true

    (
      cd "$parent" || exit 1

      # 组装 prune 条件：排除常见大目录
      local prune_expr=( )
      local d
      for d in "${EXCLUDE_DIRS[@]}"; do
        prune_expr+=( -path "./$d" -o -path "./$d/*" -o )
      done
      # 去掉最后一个 -o
      if [[ "${#prune_expr[@]}" -gt 0 ]]; then
        unset 'prune_expr[${#prune_expr[@]}-1]'
      fi

      # 只找 .git marker（目录或文件），再取其父目录作为候选 repo 根
      # 注意：这里一定要让 fzf 接收到“父目录列表”，而不是 .git 本身
      if [[ "${#prune_expr[@]}" -gt 0 ]]; then
        find . \( "${prune_expr[@]}" \) -prune -o \( -type d -name ".git" -o -type f -name ".git" \) -print 2>/dev/null \
          | sed 's|^\./||' \
          | while IFS= read -r git_marker; do
              local repo_root
              repo_root="$(dirname "$git_marker")"

              [[ "$repo_root" == "." ]] && continue
              [[ "$repo_root" == .git/* || "$repo_root" == .git/modules/* ]] && continue

              if git -C "$repo_root" rev-parse --is-inside-work-tree &>/dev/null; then
                printf "%s\n" "$repo_root"
              fi
            done
      else
        find . \( -type d -name ".git" -o -type f -name ".git" \) -print 2>/dev/null \
          | sed 's|^\./||' \
          | while IFS= read -r git_marker; do
              local repo_root
              repo_root="$(dirname "$git_marker")"

              [[ "$repo_root" == "." ]] && continue
              [[ "$repo_root" == .git/* || "$repo_root" == .git/modules/* ]] && continue

              if git -C "$repo_root" rev-parse --is-inside-work-tree &>/dev/null; then
                printf "%s\n" "$repo_root"
              fi
            done
      fi
    ) >"$tmp_all" || true

    sort -u "$tmp_all" >"$tmp_filtered" || true

    # 排除已在 .gitmodules 的 path（精确匹配相对路径）
    if [[ -s "$tmp_submods" ]]; then
      grep -vxFf "$tmp_submods" "$tmp_filtered" || true
    else
      cat "$tmp_filtered" || true
    fi

    rm -f "$tmp_all" "$tmp_filtered" "$tmp_submods"
  }
  # 封装 child_origin_url 对应的独立处理逻辑。
  child_origin_url() {
    local child_abs="$1"
    git -C "$child_abs" config --get remote.origin.url 2>/dev/null || true
  }
  # 封装 child_branch_name 对应的独立处理逻辑。
  child_branch_name() {
    local child_abs="$1"
    local b
    b="$(git -C "$child_abs" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    if [[ -z "$b" ]]; then
      printf "%s" "-"
      return 0
    fi
    if [[ "$b" == "HEAD" ]]; then
      local sha
      sha="$(git -C "$child_abs" rev-parse --short HEAD 2>/dev/null || true)"
      [[ -n "$sha" ]] && printf "%s" "detached@$sha" || printf "%s" "detached"
      return 0
    fi
    printf "%s" "$b"
  }
  # 输出：每行 TAB 分隔：rel<TAB>origin<TAB>branch
  list_repo_rows() {
    local parent="$1"
    local rel
    while IFS= read -r rel; do
      [[ -z "$rel" ]] && continue
      local abs="$parent/$rel"
      local url branch
      url="$(child_origin_url "$abs")"
      branch="$(child_branch_name "$abs")"
      [[ -z "$url" ]] && url="-"
      [[ -z "$branch" ]] && branch="-"
      printf "%s\t%s\t%s\n" "$rel" "$url" "$branch"
    done < <(list_nested_git_repos "$parent")
  }
  # ================================== fzf 选择目标 ==================================
  # 返回：多行 rel（相对路径）；空字符串表示“取消/返回”
  select_targets() {
    debug "STEP -> select_targets"
    local parent="$1"

    local rows=()
    local line
    while IFS= read -r line; do
      [[ -n "$line" ]] && rows+=("$line")
    done < <(list_repo_rows "$parent")

    if [[ "${#rows[@]}" -eq 0 ]]; then
      warn "未发现需要转换的嵌套 Git（已排除现有 submodule）"
      printf "%s" ""
      return 0
    fi

    if [[ "${#rows[@]}" -eq 1 ]]; then
      info "仅发现 1 个嵌套 Git（无需 fzf）："
      gray "${rows[0]//\t/ | }"
      note "是否继续处理该项？直接回车=继续；输入任意字符=返回上一步"
      local c=""
      read_tty c ""
      if [[ -n "$c" ]]; then
        printf "%s" ""
        return 0
      fi
      printf "%s" "$(printf "%s" "${rows[0]}" | cut -f1)"
      return 0
    fi

    # 多个：提供 ALL + 多选
    local selected
    selected="$(
      {
        printf "ALL\t-\t-\n"
        printf "%s\n" "${rows[@]}"
      } | fzf --multi \
              --prompt="选择要转换为 submodule 的目录（TAB 多选 / Enter 确认）： " \
              --height=70% --border --no-sort \
              --delimiter=$'\t' --with-nth=1,2,3 \
              --header=$'展示：相对路径 | origin url | branch\n提示：选 ALL 表示全部；ctrl-a 也可全选' \
              --bind "ctrl-a:select-all"
    )" || true

    if [[ -z "$selected" ]]; then
      warn "你没有选择任何项"
      printf "%s" ""
      return 0
    fi

    # 如果包含 ALL：返回全部 rel
    if printf "%s\n" "$selected" | cut -f1 | grep -qx "ALL"; then
      printf "%s\n" "${rows[@]}" | cut -f1
      return 0
    fi

    printf "%s\n" "$selected" | cut -f1
  }
  # ================================== 转换为 submodule（逐个确认） ==================================
  # 返回：0=允许继续；1=用户选择返回“起点目录输入”
  ensure_parent_clean_or_confirm() {
    debug "STEP -> ensure_parent_clean_or_confirm"
    local parent="$1"

    local st
    st="$(git -C "$parent" status --porcelain 2>/dev/null || true)"
    if [[ -n "$st" ]]; then
      warn "父仓库存在未提交变更（建议先提交/暂存），否则回退更麻烦。"
      printf "%s\n" "$st" | sed 's/^/  /' >"$TTY_OUT"
      note "仍要继续吗？直接回车=继续；输入任意字符=返回起点目录输入"
      local c=""
      read_tty c ""
      [[ -n "$c" ]] && return 1
    fi
    return 0
  }
  # 收集并校验用户输入，决定后续执行路径。
  confirm_skip_item() {
    # 返回 0 = 继续；返回 1 = 跳过
    local rel="$1"
    bold "目标：$rel"
    note "二次确认：是否将该嵌套 Git 转换为 submodule？"
    printf "%b\n" "👉 直接回车：继续" >"$TTY_OUT"
    printf "%b\n" "👉 输入任意字符后回车：跳过该项" >"$TTY_OUT"
    local c=""
    read_tty c ""
    [[ -n "$c" ]] && return 1
    return 0
  }
  # 尝试清理“path 已在 index / .gitmodules 残留”的历史状态
  cleanup_submodule_residue() {
    local parent="$1"
    local rel="$2"

    # 1) index 里已存在该路径（submodule add 会报 already exists in the index）
    if git -C "$parent" ls-files --error-unmatch "$rel" &>/dev/null; then
      warn "检测到该路径已在父仓库 index 中，先清理 git index：$rel"
      git -C "$parent" rm -r --cached -f "$rel" &>/dev/null || true
    fi

    # 2) .gitmodules 可能存在残留 section
    if [[ -f "$parent/.gitmodules" ]]; then
      if git -C "$parent" config -f .gitmodules --get-regexp "^submodule\\..*\\.path$" 2>/dev/null \
        | awk '{print $2}' | grep -qx "$rel"; then
        warn "检测到 .gitmodules 存在残留配置，尝试移除：$rel"
        # 找到对应 submodule 名称
        local name
        name="$(git -C "$parent" config -f .gitmodules --get-regexp "^submodule\\..*\\.path$" 2>/dev/null \
          | awk -v p="$rel" '$2==p{print $1}' \
          | sed 's/\.path$//' \
          | head -n 1)"
        [[ -n "$name" ]] && git -C "$parent" config -f .gitmodules --remove-section "$name" 2>/dev/null || true
        # 如果 .gitmodules 空了，保留文件由用户决定
      fi
    fi

    # 3) 父仓库 .git/modules 里可能残留
    rm -rf "$parent/.git/modules/$rel" 2>/dev/null || true
  }
  # 封装 convert_one_to_submodule 对应的独立处理逻辑。
  convert_one_to_submodule() {
    debug "STEP -> convert_one_to_submodule"

    local parent="$1"
    local rel="$2"
    local child_abs="$parent/$rel"

    if ! confirm_skip_item "$rel"; then
      note "⏭️ 跳过：$rel"
      return 0
    fi

    if [[ ! -d "$child_abs" ]]; then
      warn "目录不存在，跳过：$child_abs"
      return 0
    fi

    if ! is_git_worktree "$child_abs"; then
      warn "该目录不是有效 Git（可能已处理过），跳过：$rel"
      return 0
    fi

    local url
    url="$(child_origin_url "$child_abs")"
    if [[ -z "$url" || "$url" == "-" ]]; then
      warn "未检测到 remote.origin.url：$rel"
      note "请输入 submodule 的 URL（支持 https/ssh/本地路径），直接回车=跳过该项："
      read_tty url ""
      url="$(trim_path "$url")"
      if [[ -z "$url" ]]; then
        note "⏭️ 跳过：$rel（无 URL）"
        return 0
      fi
    fi
    info "submodule URL：$url"

    # 备份到 /tmp
    local backup_root
    backup_root="/tmp/${SCRIPT_BASENAME}.backup.$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_root" || die "无法创建备份目录：$backup_root"

    info "备份原目录到：$backup_root/$rel"
    mkdir -p "$(dirname "$backup_root/$rel")" || true
    mv "$child_abs" "$backup_root/$rel" || die "备份移动失败：$rel"

    # 清理历史残留（避免 already exists in the index）
    cleanup_submodule_residue "$parent" "$rel"

    # 执行 submodule add
    info "执行：git submodule add \"$url\" \"$rel\""
    if ! git -C "$parent" submodule add "$url" "$rel"; then
      error "submodule add 失败，尝试恢复：$rel"
      rm -rf "$parent/$rel" 2>/dev/null || true
      mkdir -p "$(dirname "$child_abs")" 2>/dev/null || true
      mv "$backup_root/$rel" "$child_abs" 2>/dev/null || true
      error "submodule add 失败：$rel"
      return 1
    fi

    success "已转换为 submodule：$rel"
    gray "说明：submodule 目录里会生成一个 .git【文件】（不是文件夹），这是正常行为。"
    gray "备份保留在：$backup_root"
    return 0
  }
  # ================================== 处理循环 / 继续策略 ==================================
  # 处理结束后：
  # - 直接回车：回到 fzf（同一个父仓库继续选）
  # - 输入任意字符：回到“输入/拖入起点目录”
  post_run_next_action() {
    cat >"$TTY_OUT" <<'EOF'
  ➤ 下一步：
  👉 直接回车：继续在当前父仓库中选择下一个 Git 目录（回到 fzf）
  👉 输入任意字符后回车：重新输入/拖入一个起点目录（回到第一步）
EOF
    local c=""
    read_tty c ""
    [[ -n "$c" ]] && return 1
    return 0
  }
  # 执行已经拆分完成的独立业务步骤。
  run_conversion_once() {
    debug "STEP -> run_conversion_once"
    local parent="$1"

    if ! ensure_parent_clean_or_confirm "$parent"; then
      return 2
    fi

    info "父 Git 起点：$parent"

    local selected
    selected="$(select_targets "$parent")"

    if [[ -z "$selected" ]]; then
      warn "没有选择任何目标"
      return 0
    fi

    local rel
    while IFS= read -r rel || [[ -n "$rel" ]]; do
      [[ -z "$rel" ]] && continue
      convert_one_to_submodule "$parent" "$rel" || true
    done <<<"$selected"

    success "处理完成"
    note "接下来建议你："
    gray "1) git -C \"$parent\" status 查看变更"
    gray "2) 检查 .gitmodules 与新增的 gitlink"
    gray "3) 提交一次：git add .gitmodules && git add <submodule paths> && git commit -m \"add submodules\""

    return 0
  }
  # ================================== 主流程封装 ==================================
  run_flow_forever() {
    debug "STEP -> run_flow_forever"

    local start_dir parent_root

    while true; do
      start_dir="$(pick_start_dir "${@:-}")"
      start_dir="$(abspath "$start_dir")"

      parent_root="$(resolve_parent_git_root "$start_dir")"
      parent_root="$(abspath "$parent_root")"

      cd "$parent_root" || die "无法进入父 Git 起点目录：$parent_root"
      info "已进入父 Git 起点目录：$(pwd)"

      while true; do
        # 0=正常；2=用户选择返回起点目录
        set +e
        run_conversion_once "$parent_root"
        local rc=$?
        set -e
        if [[ $rc -eq 2 ]]; then
          break
        fi

        # 处理后询问下一步
        if post_run_next_action; then
          continue
        else
          break
        fi
      done

      # 用户选择返回起点目录（外层循环继续）
      note "回到起点目录输入..."
      # 清空传参，避免重复使用老参数
      set --
    done
  }
  # ================================== main（模块化统一调用） ==================================
  main() {
    : >"$LOG_FILE"

    show_intro_and_wait
    deps_check
    run_flow_forever "$@"

    press_enter_to_continue
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
  # 展示脚本内置自述，并按运行入口完成防误触确认。
  show_readme_and_wait
  # 初始化 Shell 选项、日志、依赖和入口运行状态。
  initialize_script_runtime
  # 执行 run_original_logic 对应的核心业务步骤。
  run_original_logic "$@"
  # 输出脚本执行结果、摘要和日志位置。
  success_echo "脚本执行结束。日志：$LOG_FILE"
}

main "$@"
