#!/bin/zsh
emulate -R zsh
set -e
set -o pipefail
setopt NO_NOMATCH

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export LANG="${LANG:-zh_CN.UTF-8}"
export LC_CTYPE="${LC_CTYPE:-UTF-8}"

SCRIPT_FILE="${0:A}"
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_FILE")" && pwd)"
REPO_ROOT="$(cd -P "${SCRIPT_DIR}/.." && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$SCRIPT_FILE")"
SCRIPT_BASENAME="$(basename "$SCRIPT_FILE" | sed 's/\.[^.]*$//')"
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
: > "$LOG_FILE"

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

log()            { printf '%s\n' "$1" | tee -a "$LOG_FILE"; }
info_echo()      { log "ℹ $*"; }
success_echo()   { log "✔ $*"; }
warn_echo()      { log "⚠ $*"; }
note_echo()      { log "➤ $*"; }
error_echo()     { printf '%s\n' "✖ $*" >&2; printf '%s\n' "✖ $*" >> "$LOG_FILE"; }

run_cmd() {
  if [[ "$DRY_RUN" == "1" ]]; then
    note_echo "[DRY_RUN] $*"
  else
    "$@"
  fi
}

append_gitignore_line() {
  local gitignore="$1"
  local line="$2"

  if [[ "$DRY_RUN" == "1" ]]; then
    note_echo "[DRY_RUN] 写入 ${gitignore}: ${line}"
  else
    printf '%s\n' "$line" >> "$gitignore"
  fi
}

show_readme_and_wait() {
  local readme_path="${SCRIPT_DIR}/README.md"
  if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != "dumb" ]]; then
    clear
  fi

  if [[ -f "$readme_path" ]]; then
    note_echo "============================== README.md =============================="
    cat "$readme_path" | tee -a "$LOG_FILE"
    note_echo "======================================================================="
  else
    warn_echo "未找到 README.md，继续执行内置流程说明。"
    note_echo "本脚本会清理 Git 索引中的 Codex 运行态文件记录，不删除本地真实文件。"
  fi

  echo ""
  read -r "?👉 已阅读说明，按回车继续执行；按 Ctrl+C 取消：" _
}

confirm_yes() {
  echo ""
  warn_echo "$1"
  note_echo "请输入 YES 后回车继续；其它输入一律取消。"
  local input=""
  IFS= read -r "input?➤ "
  [[ "$input" == "YES" ]]
}

ensure_git_repo() {
  if ! git -C "$REPO_ROOT" rev-parse --show-toplevel >/dev/null 2>&1; then
    error_echo "脚本所在目录不在 Git 仓库内：${REPO_ROOT}"
    exit 1
  fi
}

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

collect_repo_paths() {
  local repo="$1"
  local submodule_path=""
  print -r -- "$repo"

  while IFS= read -r submodule_path; do
    [[ -n "$submodule_path" ]] || continue
    print -r -- "${repo}/${submodule_path}"
  done < <(git -C "$repo" config --file .gitmodules --get-regexp path 2>/dev/null | awk '{print $2}')
}

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

run_main_flow() {
  show_readme_and_wait
  ensure_git_repo

  if ! confirm_yes "即将扫描外层仓库和 .gitmodules 中的子仓库，并修改 Git 索引。真实文件不会被删除。"; then
    warn_echo "已取消。"
    exit 0
  fi

  local repo=""
  local -a repos
  repos=("${(@f)$(collect_repo_paths "$REPO_ROOT")}")

  for repo in "${repos[@]}"; do
    process_repo "$repo"
  done

  success_echo "处理完成。日志：${LOG_FILE}"
  note_echo "下一步建议执行：git status --short；子仓可用 git -C '子仓路径' status --short 检查。"
}

main() {
  # 主入口只负责委托完整业务流程，复杂逻辑统一下沉。
  run_main_flow "$@"
}

main "$@"
