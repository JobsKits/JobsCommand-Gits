#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】🧹清理Git子仓运行态记录.command
# - 核心用途：执行“🧹清理Git子仓运行态记录”对应的 Git / Sourcetree 自动化操作。
# - 影响范围：可能修改当前仓库、工作区、分支、菜单配置或 Git 索引。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export LANG="${LANG:-zh_CN.UTF-8}"
export LC_CTYPE="${LC_CTYPE:-UTF-8}"

SCRIPT_FILE="${0:A}"
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_FILE")" && pwd)"
REPO_ROOT="$(cd -P "${SCRIPT_DIR}/.." && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$SCRIPT_FILE")"
SCRIPT_BASENAME="$(basename "$SCRIPT_FILE" | sed 's/\.[^.]*$//')"
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"

DRY_RUN="${DRY_RUN:-0}"

RUNTIME_IGNORE_BLOCK=(
  "# Jobs local runtime data"
  "codex配置文件夹/"
  "**/.codex/sessions/"
  "**/.codex/logs*.sqlite"
  "**/.codex/logs*.sqlite-*"
  "**/.codex/.tmp/"
  "**/plugins/cache/"
  "**/tmp/arg0/"
  "**/shell_snapshots/"
  "**/session_index.jsonl"
  "**/state_*.sqlite"
  "**/state_*.sqlite-*"
)

RUNTIME_PATHS=(
  "codex配置文件夹"
  ".codex/sessions"
  ".codex/.tmp"
  "plugins/cache"
  "tmp/arg0"
  "shell_snapshots"
)

RUNTIME_GLOBS=(
  "**/.codex/sessions/**"
  "**/.codex/.tmp/**"
  "**/plugins/cache/**"
  "**/tmp/arg0/**"
  "**/shell_snapshots/**"
  "**/session_index.jsonl"
  "**/state_*.sqlite"
  "**/state_*.sqlite-*"
  "**/.codex/logs*.sqlite"
  "**/.codex/logs*.sqlite-*"
)
# 统一输出终端信息并同步记录日志。
log()            { printf '%s\n' "$1" | tee -a "$LOG_FILE"; }
# 输出 info echo 对应级别的日志信息。
info_echo()      { log "ℹ $*"; }
# 输出 success echo 对应级别的日志信息。
success_echo()   { log "✔ $*"; }
# 输出 warn echo 对应级别的日志信息。
warn_echo()      { log "⚠ $*"; }
# 输出 note echo 对应级别的日志信息。
note_echo()      { log "➤ $*"; }
# 输出 error echo 对应级别的日志信息。
error_echo()     { printf '%s\n' "✖ $*" >&2; printf '%s\n' "✖ $*" >> "$LOG_FILE"; }
# 执行 run cmd 对应的独立业务步骤。
run_cmd() {
  if [[ "$DRY_RUN" == "1" ]]; then
    note_echo "[DRY_RUN] $*"
  else
    "$@"
  fi
}
# 封装 append gitignore line 对应的独立处理逻辑。
append_gitignore_line() {
  local gitignore="$1"
  local line="$2"

  if [[ "$DRY_RUN" == "1" ]]; then
    note_echo "[DRY_RUN] 写入 ${gitignore}: ${line}"
  else
    printf '%s\n' "$line" >> "$gitignore"
  fi
}
# 输出 show readme and wait 对应的说明与结果。
show_script_intro_and_wait() {
  if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != "dumb" ]]; then
    clear
  fi
  print -r -- '============================== 脚本内置自述 =============================='
  print -r -- '脚本名称：【MacOS】🧹清理Git子仓运行态记录.command'
  print -r -- '核心用途：执行“🧹清理Git子仓运行态记录”对应的 Git 自动化操作。'
  print -r -- '影响范围：可能修改当前仓库、工作区、分支或 Git 索引。'
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。'
  print -r -- '============================================================================'


  echo ""
  read -r "?👉 已阅读说明，按回车继续执行；按 Ctrl+C 取消：" _
}
# 收集并校验 confirm yes 对应的用户确认。
confirm_yes() {
  echo ""
  warn_echo "$1"
  note_echo "请输入 YES 后回车继续；其它输入一律取消。"
  local input=""
  IFS= read -r "input?➤ "
  [[ "$input" == "YES" ]]
}
# 检查 ensure git repo 所需条件，不满足时阻止继续执行。
ensure_git_repo() {
  if ! git -C "$REPO_ROOT" rev-parse --show-toplevel >/dev/null 2>&1; then
    error_echo "脚本所在目录不在 Git 仓库内：${REPO_ROOT}"
    exit 1
  fi
}
# 封装 append ignore rules 对应的独立处理逻辑。
append_ignore_rules() {
  local repo="$1"
  local gitignore="${repo}/.gitignore"
  local changed=0
  local rule=""

  [[ -f "$gitignore" ]] || run_cmd touch "$gitignore"

  for rule in "${RUNTIME_IGNORE_BLOCK[@]}"; do
    if ! grep -Fxq -- "$rule" "$gitignore" 2>/dev/null; then
      if [[ "$changed" == "0" ]]; then
        append_gitignore_line "$gitignore" ""
        changed=1
      fi
      append_gitignore_line "$gitignore" "$rule"
    fi
  done

  if [[ "$changed" == "1" ]]; then
    success_echo "已补齐忽略规则：${repo}/.gitignore"
  else
    info_echo "忽略规则已存在：${repo}/.gitignore"
  fi
}
# 解析并返回 collect repo paths 所需信息。
collect_repo_paths() {
  local repo="$1"
  local submodule_path=""
  print -r -- "$repo"

  while IFS= read -r submodule_path; do
    [[ -n "$submodule_path" ]] || continue
    print -r -- "${repo}/${submodule_path}"
  done < <(git -C "$repo" config --file .gitmodules --get-regexp path 2>/dev/null | awk '{print $2}')
}
# 解析并返回 collect tracked runtime paths 所需信息。
collect_tracked_runtime_paths() {
  local repo="$1"
  local direct_path=""
  local glob_path=""

  for direct_path in "${RUNTIME_PATHS[@]}"; do
    git -C "$repo" ls-files -z -- "$direct_path" "${direct_path}/**" 2>/dev/null || true
  done

  for glob_path in "${RUNTIME_GLOBS[@]}"; do
    git -C "$repo" ls-files -z -- ":(glob)${glob_path}" 2>/dev/null || true
  done
}
# 清理 untrack runtime paths 对应的目标内容。
untrack_runtime_paths() {
  local repo="$1"
  local tmp_file=""
  local count=0

  tmp_file="$(mktemp "/tmp/${SCRIPT_BASENAME}.XXXXXX")"
  collect_tracked_runtime_paths "$repo" > "$tmp_file"

  if [[ ! -s "$tmp_file" ]]; then
    info_echo "未发现已跟踪运行态路径：${repo}"
    rm -f "$tmp_file"
    return 0
  fi

  count="$(tr '\0' '\n' < "$tmp_file" | sort -u | sed '/^$/d' | wc -l | tr -d ' ')"
  warn_echo "发现 ${count} 个已跟踪运行态路径：${repo}"

  if [[ "$DRY_RUN" == "1" ]]; then
    tr '\0' '\n' < "$tmp_file" | sort -u | sed '/^$/d' | sed 's/^/  - /' | tee -a "$LOG_FILE"
  else
    tr '\0' '\n' < "$tmp_file" | sort -u | sed '/^$/d' | tr '\n' '\0' | \
      git -C "$repo" rm -r --cached --ignore-unmatch --pathspec-from-file=- --pathspec-file-nul
  fi

  rm -f "$tmp_file"
  success_echo "已从 Git 索引移除运行态记录：${repo}"
}
# 执行 process repo 对应的独立业务步骤。
process_repo() {
  local repo="$1"

  if [[ ! -d "$repo" ]]; then
    warn_echo "跳过不存在的子仓路径：${repo}"
    return 0
  fi

  if ! git -C "$repo" rev-parse --show-toplevel >/dev/null 2>&1; then
    warn_echo "跳过非 Git 仓库：${repo}"
    return 0
  fi

  note_echo "处理仓库：${repo}"
  append_ignore_rules "$repo"
  untrack_runtime_paths "$repo"
}
# 确认 Git 索引修改风险，并依次处理外层仓库及其子仓库。
confirm_and_process_repositories() {
  local repo=""
  local -a repos

  if ! confirm_yes "即将扫描外层仓库和 .gitmodules 中的子仓库，并修改 Git 索引。真实文件不会被删除。"; then
    warn_echo "已取消。"
    exit 0
  fi

  repos=("${(@f)$(collect_repo_paths "$REPO_ROOT")}")
  for repo in "${repos[@]}"; do
    process_repo "$repo"
  done
}
# 编排脚本说明、环境检查、仓库处理和结果提示。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_runtime() {
  emulate -R zsh
  set -e
  set -o pipefail
  setopt NO_NOMATCH
  : > "$LOG_FILE"
}
# 编排脚本的高层业务流程。
main() {
  # 展示脚本内置自述，并按运行入口完成防误触确认。
  show_script_intro_and_wait
  # 初始化 Shell 选项、日志、依赖和入口运行状态。
  initialize_script_runtime
  # 检查当前环境与执行条件是否满足脚本要求。
  ensure_git_repo
  # 执行 confirm_and_process_repositories 对应的核心业务步骤。
  confirm_and_process_repositories
  # 输出脚本执行结果、摘要和日志位置。
  success_echo "处理完成。日志：${LOG_FILE}"
  # 执行 note_echo 对应的独立业务步骤。
  note_echo "下一步建议执行：git status --short；子仓可用 git -C '子仓路径' status --short 检查。"
}

main "$@"
