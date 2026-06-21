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
show_readme_and_wait() {
  clear
  print -r -- '============================== 脚本内置自述 =============================='
  print -r -- '脚本名称：【MacOS】⬆️Git添加子模块.command'
  print -r -- '核心用途：执行“⬆️Git添加子模块”对应的 Git 自动化操作。'
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
# 执行 run original logic 对应的独立业务步骤。
run_original_logic() {
  # ============================= 原脚本业务逻辑区 =============================
  set -euo pipefail
  # ============================ Git 子模块批量管理（模块化调用） ============================
  # —— 自述 & 用户确认 ——
  show_intro_and_wait() {
    cat <<'EOF'
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
        read -p "请输入Git远程仓库地址: " remote_url
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
