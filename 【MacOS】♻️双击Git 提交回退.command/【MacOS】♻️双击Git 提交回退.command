#!/bin/zsh
# =====================================================================
# Jobs 标准化脚本外壳
# 说明：保留原脚本业务逻辑，补齐 README 防误触、彩色日志、zsh 入口、Homebrew 健康自检标准。
# =====================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
SCRIPT_BASENAME="$(basename "$0" | sed 's/\.[^.]*$//')"
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
: > "$LOG_FILE"

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
  # ============================================================
  # 📜 Git 回退工具：支持 soft/hard/tag/reflog + fzf + 拖入路径
  # ============================================================

  # ✅ 彩色输出函数
  SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')   # 当前脚本名（去掉扩展名）
  LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"                  # 设置对应的日志文件路径

  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  log()            { echo -e "$1" | tee -a "$LOG_FILE"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  color_echo()     { log "\033[1;32m$1\033[0m"; }        # ✅ 正常绿色输出
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  info_echo()      { log "\033[1;34mℹ $1\033[0m"; }      # ℹ 信息
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  success_echo()   { log "\033[1;32m✔ $1\033[0m"; }      # ✔ 成功
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }      # ⚠ 警告
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  warm_echo()      { log "\033[1;33m$1\033[0m"; }        # 🟡 温馨提示（无图标）
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  note_echo()      { log "\033[1;35m➤ $1\033[0m"; }      # ➤ 说明
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  error_echo()     { log "\033[1;31m✖ $1\033[0m"; }      # ✖ 错误
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  err_echo()       { log "\033[1;31m$1\033[0m"; }        # 🔴 错误纯文本
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }     # 🐞 调试
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }     # 🔹 高亮
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  gray_echo()      { log "\033[0;90m$1\033[0m"; }        # ⚫ 次要信息
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  bold_echo()      { log "\033[1m$1\033[0m"; }           # 📝 加粗
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  underline_echo() { log "\033[4m$1\033[0m"; }           # 🔗 下划线

  # ✅ 单行写文件（避免重复写入）
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

  # ✅ 获取 CPU 架构信息
  get_cpu_arch() {
    [[ "$(uname -m)" == "arm64" ]] && echo "arm64" || echo "x86_64"
  }

  # ✅ fzf 安装方式选择器
  fzf_select() {
    printf "%s\n" "$@" | fzf --prompt="📦 请选择：" --header="👇 请选择操作"
  }

  # ✅ 安装 Homebrew（芯片架构兼容、含环境注入）
  install_homebrew() {
    local arch="$(get_cpu_arch)"
    local shell_name="${SHELL##*/}"
    local profile_file=""
    local brew_bin=""

    if ! command -v brew >/dev/null 2>&1 && [[ ! -x "/opt/homebrew/bin/brew" && ! -x "/usr/local/bin/brew" ]]; then
      warn_echo "未检测到 Homebrew，准备安装（架构：$arch）"
      if [[ "$arch" == "arm64" ]]; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || { error_echo "Homebrew 安装失败（arm64）"; return 1; }
        brew_bin="/opt/homebrew/bin/brew"
      else
        arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || { error_echo "Homebrew 安装失败（x86_64）"; return 1; }
        brew_bin="/usr/local/bin/brew"
      fi
      success_echo "Homebrew 安装完成"
    else
      command -v brew >/dev/null 2>&1 && brew_bin="$(command -v brew)"
      [[ -z "$brew_bin" && -x "/opt/homebrew/bin/brew" ]] && brew_bin="/opt/homebrew/bin/brew"
      [[ -z "$brew_bin" && -x "/usr/local/bin/brew" ]] && brew_bin="/usr/local/bin/brew"
    fi

    case "$shell_name" in
      zsh) profile_file="$HOME/.zprofile" ;;
      bash) profile_file="$HOME/.bash_profile" ;;
      *) profile_file="$HOME/.profile" ;;
    esac
    inject_shellenv_block "$profile_file" "eval \"\$(${brew_bin} shellenv)\""
    eval "$(${brew_bin} shellenv)" || true

    info_echo "Homebrew 已安装。"
    if ask_run "是否执行 Homebrew 更新 / 升级 / 清理 / doctor？"; then
      brew update  || { error_echo "brew update 失败"; return 1; }
      brew upgrade || { error_echo "brew upgrade 失败"; return 1; }
      brew cleanup || { error_echo "brew cleanup 失败"; return 1; }
      brew doctor  || warn_echo "brew doctor 有警告，请按输出处理"
      brew -v      || warn_echo "打印 brew 版本失败，可忽略"
      success_echo "Homebrew 健康更新完成"
    else
      note_echo "已跳过 Homebrew 更新"
    fi
  }

  # ✅ 安装 fzf 工具
  install_fzf() {
    if ! command -v fzf &>/dev/null; then
      note_echo "📦 未检测到 fzf，正在通过 Homebrew 安装..."
      brew install fzf || { error_echo "❌ fzf 安装失败"; exit 1; }
      success_echo "✅ fzf 安装成功"
    else
      info_echo "🔄 fzf 已安装，升级中..."
      brew upgrade fzf && brew cleanup
      success_echo "✅ fzf 已是最新版"
    fi
  }

  # ✅ 判断是否是 Git 仓库
  _is_git_repo() {
    [[ -d "$1/.git" ]]
  }

  # ✅ 获取 Git 仓库路径（支持拖入）
  resolve_git_repo_path() {
    while true; do
      local script_dir=$(dirname "$(realpath "$0")")
      if _is_git_repo "$script_dir"; then
        highlight_echo "📁 当前脚本目录是 Git 仓库：$script_dir"
        echo "$script_dir"
        return
      fi
      warn_echo "📂 当前目录不是 Git 仓库，请拖入有效路径："
      read "input_path?👉 拖入路径："
      input_path="${input_path//\"/}"
      local abs_path="$(cd "$input_path" 2>/dev/null && pwd)"
      if [[ -n "$abs_path" && -d "$abs_path" ]] && _is_git_repo "$abs_path"; then
        highlight_echo "📁 已识别 Git 仓库路径：$abs_path"
        echo "$abs_path"
        return
      fi
      error_echo "❌ 路径无效或非 Git 仓库，请重新输入。"
    done
  }

  # ✅ 检查暂存区是否干净
  check_staged_changes() {
    if ! git diff --cached --quiet; then
      warn_echo "⚠️ 暂存区存在更改，请先 git reset 或提交后再执行回退。"
      exit 1
    fi
  }

  # ✅ 回退到上一提交（支持 soft/hard）
  reset_to_previous_commit() {
    local mode=$(fzf_select "soft 回退（保留更改）" "hard 回退（清除所有更改）")
    if [[ "$mode" == *soft* ]]; then
      git reset --soft HEAD^
      success_echo "✅ soft 回退成功"
    elif [[ "$mode" == *hard* ]]; then
      git reset --hard HEAD^
      error_echo "⚠️ hard 回退成功"
    else
      warn_echo "❌ 操作取消"
    fi
  }

  # ✅ 回退到 tag（可选 soft/hard）
  reset_to_tag() {
    local tag=$(git tag | sort -r | fzf --prompt="🏷️ 选择 tag：" --header="👇 可回退的 tag")
    [[ -z "$tag" ]] && warn_echo "❌ 未选择 tag，已取消" && return
    local mode=$(fzf_select "soft 回退到 tag $tag" "hard 回退到 tag $tag")
    if [[ "$mode" == *soft* ]]; then
      git reset --soft "$tag"
      success_echo "✅ 已 soft 回退到 tag: $tag"
    elif [[ "$mode" == *hard* ]]; then
      git reset --hard "$tag"
      error_echo "⚠️ 已 hard 回退到 tag: $tag"
    fi
  }

  # ✅ 通过 reflog 回退（安全恢复）
  reset_to_reflog() {
    local target=$(git reflog --pretty=oneline | fzf --prompt="📜 选择 reflog 记录：" --height=80% \
      --header="👇 Git reflog 历史记录回退" | awk '{print $1}')
    [[ -z "$target" ]] && warn_echo "❌ 未选择记录，已取消" && return
    git reset --soft "$target"
    success_echo "✅ 已 soft 回退到 reflog: $target"
  }

  # ✅ 模式选择器入口
  select_reset_mode() {
    local choice=$(fzf_select \
      "回退到上一提交（soft/hard）" \
      "回退到 tag（按标签选择）" \
      "回退到 reflog 历史记录")

    case "$choice" in
      *上一提交*) reset_to_previous_commit ;;
      *tag*)       reset_to_tag ;;
      *reflog*)    reset_to_reflog ;;
      *) warn_echo "❌ 未选择操作，已取消" ;;
    esac
  }

  # ✅ 进入 Git 仓库路径
  enter_git_repo_dir() {
    local git_root=$(resolve_git_repo_path)  # 🔍 获取用户输入或脚本目录下的 Git 仓库路径
    cd "$git_root" || { error_echo "❌ 进入 Git 仓库失败：$git_root"; exit 1; }  # 📁 切换目录并校验
    success_echo "✅ 当前目录已切换为 Git 仓库：$git_root"
  }

  # ✅ 自述信息
  print_git_reset_intro() {
    clear
    highlight_echo "📌 Git 回退工具（支持 tag/reflog/soft/hard + fzf）"
    highlight_echo "=================================================================="
    note_echo "🧩 支持模式："
    note_echo "  1️⃣ soft/hard 回退到上一提交"
    note_echo "  2️⃣ 回退到 tag（保留/丢弃更改）"
    note_echo "  3️⃣ 回退到 reflog 历史记录（安全）"
    highlight_echo "=================================================================="
    read "confirm?📎 按回车继续（Ctrl+C 退出）："
    echo ""
  }

  # ✅ 主流程入口函数
  main() {
    clear
    print_git_reset_intro   # 自述
    install_homebrew        # 🍺 安装或更新 Homebrew（根据 CPU 架构）
    install_fzf             # 🔍 安装或升级 fzf 工具（交互选择器）
    enter_git_repo_dir      # 📂 获取并进入 Git 仓库路径（支持拖入路径）
    check_staged_changes    # ⚠️ 检查是否存在暂存更改，避免数据冲突
    select_reset_mode       # 🚦 交互式选择 Git 回退模式并执行
  }

  main "$@"

  # =========================== 原脚本业务逻辑区结束 ===========================
}

# 编排完整业务流程，复杂步骤继续下沉到职责明确的函数。
run_main_flow() {
  show_readme_and_wait
  run_original_logic "$@"
  success_echo "脚本执行结束。日志：$LOG_FILE"
}

# 统一收口脚本入口，仅委托已经拆分完成的业务流程。
main() {
  # 主入口只负责委托完整业务流程，复杂逻辑统一下沉。
  run_main_flow "$@"
}

main "$@"
