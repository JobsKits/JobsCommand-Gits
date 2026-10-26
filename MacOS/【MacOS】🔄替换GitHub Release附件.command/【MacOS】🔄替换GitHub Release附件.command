#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】🔄替换GitHub Release附件.command
# - 核心用途：接收分支与版本 Tag，选择仓库及本地同名附件，备份后替换已有 GitHub Release 附件。
# - 影响范围：仅覆盖确认清单中的远端附件；在系统临时目录保留日志、暂存、旧文件及下载校验结果。
# - 运行提示：先回车阅读确认，再用 fzf 选择；精确输入 YES 才覆盖；← 返回上层，Ctrl+C 取消。
# - 分支用途：校验远端分支存在且包含 Tag 的提交；上传内容取自所选本地目录，不切分支、不移动 Tag。
# shell: zsh

SCRIPT_SOURCE="${(%):-%x}"
SCRIPT_DIR=""
SCRIPT_PATH=""
SCRIPT_BASENAME=""
LOG_FILE=""
WORK_DIR=""
REPO_DIR_OPTION=""
SOURCE_DIR_OPTION=""
BASE_DIR=""
REPO_DIR=""
REPOSITORY=""
BRANCH_ARGUMENT=""
TAG_ARGUMENT=""
BRANCH=""
TAG=""
BRANCH_SHA=""
TAG_SHA=""
RESOLVED_TAG_SHA=""
SOURCE_DIR=""
RELEASE_ID=""
FZF_ACTION=""
FZF_PICKED=""
NORMALIZED_PATH=""
COMPLETED_COUNT=0
UPLOAD_STARTED=0
typeset -a REPO_DIRS=() REMOTE_REPOS=() REMOTE_LABELS=() BRANCHES=() TAGS=() FILE_NAMES=() SELECTED_NAMES=() STEPS=()
typeset -A FZF_QUERIES=()

# 根据终端能力渲染自述；不初始化日志或更改环境。
intro_line() {
  local role="$1" message="$2" color='0;34'
  [[ "$role" == title ]] && color='1;31'
  if [[ -t 1 && -n "${TERM:-}" && "$TERM" != dumb && -z "${NO_COLOR+x}" ]]; then
    printf '\033[%sm%s\033[0m\n' "$color" "$message"
  else
    print -r -- "$message"
  fi
}
# 展示参数与边界，帮助模式不联网、不创建文件。
show_help() {
  print -r -- '用法：./【MacOS】🔄替换GitHub Release附件.command [分支 版本Tag] [选项]'
  print -r -- '  main v1.0.0          校验 main 包含该 Tag 的提交，替换 v1.0.0 的同名附件。'
  print -r -- '  不传位置参数          通过 fzf 选择远端分支和已有 Release；只传一个参数会停止。'
  print -r -- '  --repo-dir 目录       选择的 Git 基目录；面板包含本仓及直属已初始化子模块。'
  print -r -- '  --source-dir 目录     新附件目录；只使用目录顶层的精确同名普通文件。'
  print -r -- '  --help                显示帮助；无需 gh、fzf、登录或交互终端。'
  print -r -- '未指定仓库目录时，优先当前工作目录所在 Git 仓，其次脚本所在 Git 仓，否则提示拖入目录。'
  print -r -- '新附件目录默认是目标仓 Releases/<Tag>（存在时），否则目标仓根目录；可拖入其它目录。'
  print -r -- '单选 Enter 确认；多选 Enter 勾选/取消、Space 确认、Ctrl-A 全选、Ctrl-D 清空。'
  print -r -- '非根面板 ← 返回真正上一层；目录输入 :back 返回；Esc/Ctrl-C 取消，空选不执行。'
  print -r -- '只有精确 YES 才覆盖；先备份、逐个上传、按新资产 ID 下载校验；失败保留恢复材料。'
  print -r -- '仅支持 github.com 的已有、已发布、可修改 Release；不创建版本，不提交、推送或 checkout。'
  print -r -- '依赖：macOS、zsh、Git、gh、jq、fzf、shasum、cmp；不会执行所选脚本。'
}
# 打印写死在脚本内的用途与风险，确认前只进行展示。
show_script_intro_and_wait() {
  local argument='' answer=''
  SCRIPT_PATH="${SCRIPT_SOURCE:A}"
  SCRIPT_DIR="${SCRIPT_PATH:h}"
  SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
  intro_line title '【MacOS】🔄替换GitHub Release附件.command'
  intro_line body '1、用途：输入分支和版本 Tag，选择 GitHub 仓库及本地同名附件，更新已有 Release。'
  intro_line body '2、分支只用于校验 Tag 的提交历史；实际上传本地文件，不切分支、不移动 Tag、不提交推送。'
  intro_line body '3、覆盖会先按已备份的附件 ID 删除旧文件，再上传同名新版；最终必须精确输入 YES。'
  intro_line body '4、fzf 子层 ← 返回上层；Ctrl+C 取消。上传阶段中断可能留下部分完成状态，不自动回滚。'
  intro_line body '5、日志与备份保留在系统临时目录 GitHub-Release-Replace.XXXXXX，启动后显示完整路径。'
  for argument in "$@"; do
    if [[ "$argument" == --help ]]; then
      show_help
      exit 0
    fi
  done
  if [[ ! -t 0 || ! -t 1 ]]; then
    print -u2 -r -- '✖ 本工具需要交互终端；请双击或在 Terminal 运行，--help 可非交互查看。'
    exit 1
  fi
  IFS= read -r 'answer?已了解用途与影响，按回车继续；其它输入取消：' || exit 1
  [[ -z "$answer" ]] || exit 0
}
# 同时输出纯文本日志到终端和本次运行目录。
log() {
  print -r -- "$*" | tee -a "$LOG_FILE"
}
# 失败时保留全部材料并说明部分上传边界。
fail() {
  log "✖ $*"
  if (( UPLOAD_STARTED )); then
    log "⚠ 已完成并校验 $COMPLETED_COUNT/${#SELECTED_NAMES} 个附件；当前失败附件可能已被删除或上传。"
    log "⚠ 请核对远端后参考恢复说明，不自动覆盖可能的并发修改：$WORK_DIR/RESTORE.txt"
  fi
  log "➤ 本次材料：$WORK_DIR"
  exit 1
}
# 中断时保留备份、暂存文件和已完成状态。
handle_interrupt() {
  log '⚠ 已中断，未完成的上传不能视为成功；不会自动回滚远端。'
  (( UPLOAD_STARTED )) && log "➤ 已校验 $COMPLETED_COUNT/${#SELECTED_NAMES}；核对远端后参考 $WORK_DIR/RESTORE.txt"
  log "➤ 本次材料保留：$WORK_DIR"
  exit 130
}
# 在自述确认后建立日志并限制本次运行文件的权限。
initialize_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  umask 077
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/GitHub-Release-Replace.XXXXXX")" || exit 1
  LOG_FILE="$WORK_DIR/$SCRIPT_BASENAME.log"
  : > "$LOG_FILE"
  export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
  export GH_HOST=github.com GH_PAGER=cat GH_PROMPT_DISABLED=1
  trap handle_interrupt INT TERM
  log "➤ 日志：$LOG_FILE"
}
# 解析两个位置参数和可选路径，不允许缺半个业务参数。
parse_arguments() {
  local -a positional=()
  while (( $# )); do
    case "$1" in
      --repo-dir|--source-dir)
        (( $# >= 2 )) || fail "$1 缺少目录。"
        [[ "$1" == --repo-dir ]] && REPO_DIR_OPTION="$2" || SOURCE_DIR_OPTION="$2"
        shift 2
        ;;
      --*) fail "未知选项：$1；使用 --help 查看帮助。" ;;
      *) positional+=("$1"); shift ;;
    esac
  done
  (( ${#positional} == 0 || ${#positional} == 2 )) || fail '位置参数必须同时提供：分支 版本Tag。'
  if (( ${#positional} == 2 )); then
    BRANCH_ARGUMENT="${positional[1]}"
    TAG_ARGUMENT="${positional[2]}"
    [[ -n "$BRANCH_ARGUMENT" && -n "$TAG_ARGUMENT" ]] || fail '分支和版本 Tag 不能为空。'
    [[ "$BRANCH_ARGUMENT$TAG_ARGUMENT" != *[[:cntrl:]]* ]] || fail '分支和 Tag 不能包含控制字符。'
  fi
}
# 仅在依赖缺失时查找并核验现有 Homebrew，不安装 Homebrew 或升级环境。
find_homebrew() {
  local candidate=''
  for candidate in "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [[ -n "$candidate" && -x "$candidate" ]] || continue
    if "$candidate" --version >>"$LOG_FILE" 2>&1 && "$candidate" --prefix >>"$LOG_FILE" 2>&1; then
      print -r -- "$candidate"
      return 0
    fi
  done
  return 1
}
# 先检验依赖；缺失时经独立确认安装一次并立即复检。
ensure_tool() {
  local tool="$1" brew_path='' answer=''
  if command -v "$tool" >/dev/null && "$tool" --version >>"$LOG_FILE" 2>&1; then
    return 0
  fi
  log "⚠ 依赖缺失或不可用：$tool"
  brew_path="$(find_homebrew)" || fail '未找到可用 Homebrew；请先按 https://brew.sh/ 安装，再重新运行。'
  log "➤ 安装来源｜Homebrew｜https://formulae.brew.sh/formula/$tool｜命令：$brew_path install $tool"
  IFS= read -r "answer?安装 $tool？直接回车跳过并停止；输入任意字符后回车安装：" || fail '输入结束，未安装依赖。'
  [[ -n "$answer" ]] || fail "已跳过安装 $tool。"
  "$brew_path" install "$tool" 2>&1 | tee -a "$LOG_FILE" || fail "安装 $tool 失败。"
  rehash
  command -v "$tool" >/dev/null && "$tool" --version >>"$LOG_FILE" 2>&1 || fail "$tool 安装后复检失败。"
}
# 验证平台、工具能力及登录；不自动发起登录或远端修改。
check_environment() {
  [[ "$(uname -s)" == Darwin ]] || fail '本脚本面向 macOS 原生 zsh。'
  local tool='' help_text=''
  for tool in git shasum cmp stat cp mktemp tee mkdir mv awk; do
    command -v "$tool" >/dev/null || fail "系统命令不可用：$tool"
  done
  git --version >>"$LOG_FILE" 2>&1 || fail 'Git 不可用；请先安装 Command Line Tools。'
  for tool in gh jq fzf; do
    ensure_tool "$tool"
  done
  help_text="$(fzf --help)" || fail '无法读取 fzf 能力。'
  [[ "$help_text" == *--footer* && "$help_text" == *--expect* && "$help_text" == *--bind* ]] || fail 'fzf 缺少所需选项，请更新后重试。'
  print -r -- 'probe' | FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= fzf --filter=probe --multi --print-query --expect=left --footer=probe \
    --bind 'enter:toggle,space:transform:printf accept,ctrl-e:print(__probe__)+accept' >/dev/null 2>>"$LOG_FILE" || fail 'fzf 按键能力检查失败。'
  help_text="$(gh release upload --help)" || fail '无法读取 gh 上传能力。'
  [[ "$help_text" == *--clobber* ]] || fail 'gh 缺少 --clobber，请更新后重试。'
  gh auth status --hostname github.com >>"$LOG_FILE" 2>&1 || fail '请先运行 gh auth login --hostname github.com 完成登录，再重新运行。'
}
# 安全解析 Finder 拖入的单个目录，不执行路径中的 Shell 文本。
normalize_directory() {
  local value="${1%$'\r'}"
  local -a words=()
  [[ "$value" != *[[:cntrl:]]* ]] || return 1
  if [[ ! -d "$value" ]]; then
    words=( ${(z)value} )
    (( ${#words} == 1 )) || return 1
    value="${(Q)words[1]}"
    [[ "$value" == '~/'* ]] && value="$HOME/${value#'~/'}"
  fi
  [[ -d "$value" ]] || return 1
  NORMALIZED_PATH="${value:A}"
}
# 确定 Git 基目录，并仅枚举本仓与直属已初始化子模块。
collect_repository_candidates() {
  local input='' record='' child='' root=''
  if [[ -n "$REPO_DIR_OPTION" ]]; then
    normalize_directory "$REPO_DIR_OPTION" || fail '--repo-dir 不是可访问目录。'
    root="$NORMALIZED_PATH"
  elif root="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)"; then
    :
  elif root="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"; then
    :
  else
    IFS= read -r 'input?拖入目标 Git 仓库或父仓目录（空输入取消）：' || fail '目录输入结束。'
    [[ -n "$input" ]] || exit 0
    normalize_directory "$input" || fail '请提供一个有效目录，支持带空格路径或 Finder 拖入。'
    root="$NORMALIZED_PATH"
  fi
  BASE_DIR="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)" || fail "不是 Git 工作树：$root"
  [[ "$BASE_DIR" != *[[:cntrl:]]* ]] || fail '目录名包含控制字符，不能安全展示。'
  REPO_DIRS=("$BASE_DIR")
  if [[ -f "$BASE_DIR/.gitmodules" ]]; then
    while IFS= read -r -d '' record; do
      child="${record#*$'\n'}"
      [[ -n "$child" && "$child" != *[[:cntrl:]]* ]] || continue
      child="$BASE_DIR/$child"
      [[ -d "$child" && -e "$child/.git" ]] || continue
      root="$(git -C "$child" rev-parse --show-toplevel 2>/dev/null)" || continue
      [[ "$root" == "$BASE_DIR/"* && ${REPO_DIRS[(Ie)$root]} == 0 ]] && REPO_DIRS+=("$root")
    done < <(git config -z --file "$BASE_DIR/.gitmodules" --get-regexp '\.path$' 2>>"$LOG_FILE")
  fi
}
# 使用固定主机的只读 API，错误直接停止，不盲目重放远端写入。
api_get() {
  local endpoint="$1" destination="$2"
  gh api --hostname github.com --method GET "$endpoint" >"$destination" 2>>"$LOG_FILE" || fail "读取失败：https://api.github.com/$endpoint；检查网络、权限和限流。"
}
# 读取全部分页，避免 Release 内嵌资产清单不完整。
api_array() {
  local endpoint="$1" destination="$2"
  gh api --hostname github.com --method GET --paginate --slurp "$endpoint" >"$destination.pages" 2>>"$LOG_FILE" || fail "分页读取失败：https://api.github.com/$endpoint"
  jq -e 'type == "array" and all(.[]; type == "array")' "$destination.pages" >/dev/null || fail '分页响应格式错误。'
  jq 'add // []' "$destination.pages" >"$destination" || fail '无法合并完整清单。'
}
# 编码分支与 Tag，防止斜杠、空格等改变 API 路径。
encode_ref() {
  jq -nr --arg value "$1" '$value | @uri'
}
# 将 fzf 的选择、返回、取消、空选和错误分别传递，保留有效查询。
choose_with_fzf() {
  local key="$1" mode="$2" rows="$3" back_title="$4" output='' exit_code=0 query='' pressed=''
  local hint='Enter 确认；Esc / Ctrl-C 取消' line=''
  local -a options=(--sync --layout=reverse --border --height=80% --delimiter=$'\t' --with-nth=2.. --print-query --query="${FZF_QUERIES[$key]:-}" --prompt="$key > ")
  FZF_ACTION='empty'
  FZF_PICKED=''
  [[ -n "$rows" ]] || return 0
  if [[ "$mode" == multi ]]; then
    hint='Enter 勾选/取消；Space 确认；Ctrl-A 全选；Ctrl-D 清空；空选不执行；Esc / Ctrl-C 取消'
    options+=(--multi --bind 'enter:toggle,ctrl-a:select-all,ctrl-d:deselect-all,esc:abort,space:transform:if [ "$FZF_SELECT_COUNT" -gt 0 ]; then printf accept; else printf "print(__JOBS_EMPTY__)+accept"; fi')
  else
    options+=(--bind 'enter:accept,esc:abort')
  fi
  if [[ -n "$back_title" ]]; then
    hint+="；← 返回$back_title"
    options+=(--expect=left)
  fi
  options+=(--header="$hint" --footer="$hint")
  output="$(print -r -- "$rows" | FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= fzf "${options[@]}")" || exit_code=$?
  for line in "${(@f)output}"; do
    if [[ "$line" == __JOBS_EMPTY__ ]]; then
      FZF_ACTION='empty'
      return 0
    fi
  done
  query="${output%%$'\n'*}"
  FZF_QUERIES[$key]="$query"
  [[ "$output" == *$'\n'* ]] && output="${output#*$'\n'}" || output=''
  if [[ -n "$back_title" ]]; then
    pressed="${output%%$'\n'*}"
    if [[ "$pressed" == left && ( "$exit_code" == 0 || "$exit_code" == 1 ) ]]; then
      FZF_ACTION='back'
      return 0
    fi
    [[ "$output" == *$'\n'* ]] && output="${output#*$'\n'}" || output=''
  fi
  if (( exit_code == 130 )); then
    FZF_ACTION='cancel'
    return 0
  elif (( exit_code == 1 )); then
    FZF_ACTION='empty'
    return 0
  elif (( exit_code != 0 )); then
    fail "fzf 失败，退出码 $exit_code。"
  fi
  [[ -n "$output" ]] || return 0
  FZF_PICKED="$output"
  FZF_ACTION='selected'
}
# 从候选行提取可靠的编号，拒绝越界或伪造结果。
selected_index() {
  local value="${1%%$'\t'*}" limit="$2"
  [[ "$value" == <-> && ${#value} -le 8 ]] && (( value >= 1 && value <= limit )) || fail '选择结果编号无效。'
  print -r -- "$value"
}
# 选择一个本地 Git 仓库，改变仓库后清除依赖它的下层状态。
select_repository() {
  local rows='' index=0 chosen=''
  for chosen in "${REPO_DIRS[@]}"; do
    (( index++ ))
    rows+="$index"$'\t'"$chosen"$'\n'
  done
  choose_with_fzf '仓库' single "${rows%$'\n'}" ''
  [[ "$FZF_ACTION" == selected ]] || return 0
  index="$(selected_index "$FZF_PICKED" "${#REPO_DIRS}")" || exit 1
  chosen="${REPO_DIRS[$index]}"
  if [[ "$chosen" != "$REPO_DIR" ]]; then
    REPOSITORY=''; BRANCH=''; TAG=''; SOURCE_DIR=''; SELECTED_NAMES=(); FZF_QUERIES=()
  fi
  REPO_DIR="$chosen"
}
# 只接受明确的 github.com Git 远端，不输出或使用带凭据的 URL。
github_repository_from_url() {
  local value="$1"
  case "$value" in
    https://github.com/*) value="${value#https://github.com/}" ;;
    git@github.com:*) value="${value#git@github.com:}" ;;
    ssh://git@github.com/*) value="${value#ssh://git@github.com/}" ;;
    *) return 1 ;;
  esac
  value="${value%/}"
  value="${value%.git}"
  [[ "$value" =~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' ]] || return 1
  print -r -- "$value"
}
# 从所选仓库的 GitHub 远端中选择，随后验证写权限。
select_remote() {
  local remote='' address='' repository='' rows='' index=0
  REMOTE_REPOS=(); REMOTE_LABELS=()
  for remote in "${(@f)$(git -C "$REPO_DIR" remote)}"; do
    [[ -n "$remote" && "$remote" != *[[:cntrl:]]* ]] || continue
    address="$(git -C "$REPO_DIR" remote get-url "$remote" 2>>"$LOG_FILE")" || continue
    repository="$(github_repository_from_url "$address")" || continue
    REMOTE_REPOS+=("$repository"); REMOTE_LABELS+=("$remote → $repository")
    (( index++ )); rows+="$index"$'\t'"${REMOTE_LABELS[-1]}"$'\n'
  done
  (( ${#REMOTE_REPOS} )) || fail "所选仓库没有支持的 github.com 远端：$REPO_DIR"
  choose_with_fzf '远端' single "${rows%$'\n'}" '仓库'
  [[ "$FZF_ACTION" == selected ]] || return 0
  index="$(selected_index "$FZF_PICKED" "${#REMOTE_REPOS}")" || exit 1
  repository="${REMOTE_REPOS[$index]}"
  if [[ "$repository" != "$REPOSITORY" ]]; then
    BRANCH=''; TAG=''; SOURCE_DIR=''; SELECTED_NAMES=()
    FZF_QUERIES[分支]=''; FZF_QUERIES[版本]=''; FZF_QUERIES[附件]=''
  fi
  REPOSITORY="$repository"
  api_get "repos/$REPOSITORY" "$WORK_DIR/repository.json"
  jq -e '.permissions.push == true' "$WORK_DIR/repository.json" >/dev/null || fail '当前 gh 账号缺少目标仓库写权限。'
  BRANCH="$BRANCH_ARGUMENT"; TAG="$TAG_ARGUMENT"
}
# 无分支参数时选择一个远端分支。
select_branch() {
  local rows='' index=0 name='' chosen=''
  api_array "repos/$REPOSITORY/branches?per_page=100" "$WORK_DIR/branches.json"
  BRANCHES=("${(@f)$(jq -r '.[].name' "$WORK_DIR/branches.json")}")
  for name in "${BRANCHES[@]}"; do
    [[ -n "$name" && "$name" != *[[:cntrl:]]* ]] || fail '远端分支名无法安全展示。'
    (( index++ )); rows+="$index"$'\t'"$name"$'\n'
  done
  choose_with_fzf '分支' single "${rows%$'\n'}" '远端'
  [[ "$FZF_ACTION" == selected ]] || return 0
  index="$(selected_index "$FZF_PICKED" "${#BRANCHES}")" || exit 1
  chosen="${BRANCHES[$index]}"
  if [[ "$chosen" != "$BRANCH" ]]; then
    TAG=''; SOURCE_DIR=''; SELECTED_NAMES=()
    FZF_QUERIES[版本]=''; FZF_QUERIES[附件]=''
  fi
  BRANCH="$chosen"
}
# 无版本参数时选择已发布的 Release，锁定版本在后续预检中明确拒绝。
select_release() {
  local rows='' index=0 name='' chosen=''
  api_array "repos/$REPOSITORY/releases?per_page=100" "$WORK_DIR/releases.json"
  TAGS=("${(@f)$(jq -r '.[] | select(.draft == false) | .tag_name' "$WORK_DIR/releases.json")}")
  for name in "${TAGS[@]}"; do
    [[ -n "$name" && "$name" != *[[:cntrl:]]* ]] || fail 'Release Tag 无法安全展示。'
    (( index++ )); rows+="$index"$'\t'"$name"$'\n'
  done
  choose_with_fzf '版本' single "${rows%$'\n'}" '分支'
  [[ "$FZF_ACTION" == selected ]] || return 0
  index="$(selected_index "$FZF_PICKED" "${#TAGS}")" || exit 1
  chosen="${TAGS[$index]}"
  if [[ "$chosen" != "$TAG" ]]; then
    SOURCE_DIR=''; SELECTED_NAMES=(); FZF_QUERIES[附件]=''
  fi
  TAG="$chosen"
}
# 精确解析 Tag 引用并剥离附注标签，避免与同名分支混淆。
resolve_tag_commit() {
  local encoded_tag='' object_type='' object_sha='' depth=0
  encoded_tag="$(encode_ref "$TAG")" || fail 'Tag 编码失败。'
  api_get "repos/$REPOSITORY/git/ref/tags/$encoded_tag" "$WORK_DIR/tag-object.json"
  while (( depth <= 10 )); do
    object_type="$(jq -er '.object.type' "$WORK_DIR/tag-object.json")" || fail 'Tag 对象类型无效。'
    object_sha="$(jq -er '.object.sha | select(test("^[a-fA-F0-9]{40,64}$"))' "$WORK_DIR/tag-object.json")" || fail 'Tag 对象 SHA 无效。'
    if [[ "$object_type" == commit ]]; then
      RESOLVED_TAG_SHA="$object_sha"
      return 0
    fi
    [[ "$object_type" == tag ]] || fail 'Tag 没有指向提交。'
    (( depth++ ))
    api_get "repos/$REPOSITORY/git/tags/$object_sha" "$WORK_DIR/tag-object.json"
  done
  fail '附注 Tag 嵌套超过 10 层，停止解析。'
}
# 检验分支存在，并按提交 SHA 确认 Tag 属于指定分支的历史。
validate_branch_and_tag() {
  local encoded_branch=''
  encoded_branch="$(encode_ref "$BRANCH")" || fail '分支编码失败。'
  api_get "repos/$REPOSITORY/branches/$encoded_branch" "$WORK_DIR/branch.json"
  BRANCH_SHA="$(jq -er '.commit.sha | select(test("^[a-fA-F0-9]{40,64}$"))' "$WORK_DIR/branch.json")" || fail '分支提交无效。'
  resolve_tag_commit
  TAG_SHA="$RESOLVED_TAG_SHA"
  api_get "repos/$REPOSITORY/compare/$TAG_SHA...$BRANCH_SHA" "$WORK_DIR/compare.json"
  jq -e '.status == "ahead" or .status == "identical"' "$WORK_DIR/compare.json" >/dev/null || fail "Tag $TAG 的提交不属于分支 $BRANCH，已停止。"
  [[ "$(jq -r '.base_commit.sha' "$WORK_DIR/compare.json")" == "$TAG_SHA" ]] || fail '比较响应中的 Tag 提交不一致。'
  log "➤ 校验｜$REPOSITORY｜分支 $BRANCH｜Tag $TAG｜提交 $TAG_SHA"
}
# 保存 Release 信息与全部资产；不允许草稿、锁定版本或重复资产名。
fetch_snapshot() {
  local prefix="$1" encoded_tag=''
  encoded_tag="$(encode_ref "$TAG")" || fail 'Tag 编码失败。'
  api_get "repos/$REPOSITORY/releases/tags/$encoded_tag" "$prefix.release.json"
  jq -e --arg tag "$TAG" '.tag_name == $tag and .draft == false and .immutable == false and (.id | type == "number")' "$prefix.release.json" >/dev/null || fail 'Release 不存在、未发布、已不可变或响应无效。'
  RELEASE_ID="$(jq -r '.id' "$prefix.release.json")"
  api_array "repos/$REPOSITORY/releases/$RELEASE_ID/assets?per_page=100" "$prefix.assets.json"
  jq -e 'all(.[]; (.id | type == "number") and (.name | type == "string") and (.size | type == "number") and .state == "uploaded") and ((map(.name) | unique | length) == length)' "$prefix.assets.json" >/dev/null || fail '附件清单不完整、重名或存在未完成上传。'
}
# 附件名必须是可安全映射到单个本地文件的名称；# 是 gh 的标签分隔符。
safe_filename() {
  local name="$1"
  [[ -n "$name" && "$name" != . && "$name" != .. && "$name" != */* && "$name" != *\\* && "$name" != *'#'* && "$name" != *[[:cntrl:]]* ]]
}
# 按真实目录项精确匹配名称，避免大小写不敏感磁盘选中其它文件。
source_has_exact_file() {
  local name="$1" candidate=''
  for candidate in "$SOURCE_DIR"/*(ND.); do
    [[ "${candidate:t}" == "$name" ]] || continue
    [[ -f "$candidate" && ! -L "$candidate" && -r "$candidate" && -s "$candidate" ]]
    return $?
  done
  return 1
}
# 获取新文件目录并选择与远端精确同名的顶层普通文件。
select_files() {
  local input='' default_dir='' name='' rows='' index=0 picked='' count=0
  validate_branch_and_tag
  fetch_snapshot "$WORK_DIR/plan"
  default_dir="$REPO_DIR/Releases/$TAG"
  [[ -d "$default_dir" ]] || default_dir="$REPO_DIR"
  [[ -n "$SOURCE_DIR" ]] && default_dir="$SOURCE_DIR"
  [[ -n "$SOURCE_DIR_OPTION" ]] && default_dir="$SOURCE_DIR_OPTION"
  log "➤ 新附件默认目录：$default_dir"
  IFS= read -r 'input?拖入新附件目录；回车使用默认目录；输入 :back 返回上一选择器：' || fail '目录输入结束。'
  if [[ "$input" == :back ]]; then
    FZF_ACTION='back'
    return 0
  fi
  normalize_directory "${input:-$default_dir}" || fail '新附件目录不存在或无法解析。'
  SOURCE_DIR="$NORMALIZED_PATH"
  FILE_NAMES=()
  count="$(jq 'length' "$WORK_DIR/plan.assets.json")"
  for (( index=0; index<count; index++ )); do
    name="$(jq -r --argjson i "$index" '.[$i].name' "$WORK_DIR/plan.assets.json")"
    safe_filename "$name" || continue
    source_has_exact_file "$name" || continue
    FILE_NAMES+=("$name")
    rows+="${#FILE_NAMES}"$'\t'"$name｜$(stat -f %z "$SOURCE_DIR/$name") 字节"$'\n'
  done
  if (( ! ${#FILE_NAMES} )); then
    log "⚠ 该目录没有可替换的同名非空普通文件：$SOURCE_DIR"
    FZF_ACTION='empty'
    return 0
  fi
  choose_with_fzf '附件' multi "${rows%$'\n'}" "${STEPS[-2]}"
  [[ "$FZF_ACTION" == selected ]] || return 0
  SELECTED_NAMES=()
  for picked in "${(@f)FZF_PICKED}"; do
    index="$(selected_index "$picked" "${#FILE_NAMES}")" || exit 1
    name="${FILE_NAMES[$index]}"
    (( ${SELECTED_NAMES[(Ie)$name]} )) || SELECTED_NAMES+=("$name")
  done
}
# 用循环实现真正的上一选择层，返回不触发备份或上传。
collect_plan() {
  local step_index=1 step=''
  STEPS=(仓库 远端)
  [[ -z "$BRANCH_ARGUMENT" ]] && STEPS+=(分支 版本)
  STEPS+=(附件)
  while (( step_index <= ${#STEPS} )); do
    step="${STEPS[$step_index]}"
    case "$step" in
      仓库) select_repository ;;
      远端) select_remote ;;
      分支) select_branch ;;
      版本) select_release ;;
      附件) select_files ;;
    esac
    case "$FZF_ACTION" in
      selected) (( step_index++ )) ;;
      back) (( step_index > 1 )) && (( step_index-- )) ;;
      cancel) log 'ℹ 已取消；未上传或删除附件。'; exit 0 ;;
      empty) log 'ℹ 没有选择附件或没有匹配项；未上传或删除附件。'; exit 0 ;;
      *) fail '选择器返回了未知状态。' ;;
    esac
  done
}
# 计算文件 SHA-256，调用方只使用已验证的普通文件。
file_sha256() {
  shasum -a 256 "$1" | awk '{print $1}'
}
# 固定本次上传副本并生成选中资产清单，避免操作中本地文件变化。
stage_plan() {
  local name='' old_asset='' digest='' bytes=''
  mkdir "$WORK_DIR/staged" "$WORK_DIR/backup" "$WORK_DIR/verified" || fail '无法创建本次材料目录。'
  : > "$WORK_DIR/selection.jsonl"
  for name in "${SELECTED_NAMES[@]}"; do
    source_has_exact_file "$name" || fail "源文件状态或精确名称已变化：$SOURCE_DIR/$name"
    cp -p "$SOURCE_DIR/$name" "$WORK_DIR/staged/$name" || fail "暂存失败：$name"
    digest="$(file_sha256 "$WORK_DIR/staged/$name")" || fail "无法计算哈希：$name"
    bytes="$(stat -f %z "$WORK_DIR/staged/$name")" || fail "无法读取大小：$name"
    old_asset="$(jq -ec --arg name "$name" '.[] | select(.name == $name)' "$WORK_DIR/plan.assets.json")" || fail "远端没有同名附件：$name"
    jq -cn --argjson old "$old_asset" --arg source "$SOURCE_DIR/$name" --arg sha "$digest" --argjson size "$bytes" \
      '{name:$old.name,old:$old,source:$source,new_sha256:$sha,new_size:$size}' >>"$WORK_DIR/selection.jsonl" || fail '无法记录选择清单。'
  done
  jq -s '.' "$WORK_DIR/selection.jsonl" > "$WORK_DIR/selection.json" || fail '无法保存完整清单。'
  cp "$WORK_DIR/plan.assets.json" "$WORK_DIR/expected-live.assets.json" || fail '无法固定资产状态。'
  log "➤ 替换目标｜GitHub｜https://github.com/$REPOSITORY/releases/tag/$TAG"
  log "➤ 本地来源｜$SOURCE_DIR"
  jq -r '.[] | "  \(.name)｜旧 \(.old.size) 字节 → 新 \(.new_size) 字节｜SHA256 \(.new_sha256)"' "$WORK_DIR/selection.json" | tee -a "$LOG_FILE"
}
# 通过资产 ID 精确下载，避免文件名中的通配字符误匹配其它附件。
download_asset() {
  local asset_id="$1" destination="$2"
  log "➤ 下载来源｜GitHub｜https://api.github.com/repos/$REPOSITORY/releases/assets/$asset_id"
  log "➤ 下载位置｜$destination"
  gh api --hostname github.com --method GET --header 'Accept: application/octet-stream' \
    "repos/$REPOSITORY/releases/assets/$asset_id" >"$destination" 2>>"$LOG_FILE" || fail "下载失败：资产 $asset_id"
}
# 检查下载大小及服务端提供的摘要；无摘要时仍保存本地 SHA-256。
verify_download() {
  local local_file="$1" asset_json="$2" bytes='' expected_size='' digest=''
  bytes="$(stat -f %z "$local_file")" || fail '无法读取下载文件大小。'
  expected_size="$(print -r -- "$asset_json" | jq -r '.size')"
  [[ "$bytes" == "$expected_size" ]] || fail "下载大小不一致：$local_file"
  digest="$(print -r -- "$asset_json" | jq -r '.digest // ""')"
  if [[ -n "$digest" ]]; then
    [[ "$digest" == "sha256:$(file_sha256 "$local_file")" ]] || fail "下载摘要不一致或服务端摘要格式不支持：$local_file"
  fi
}
# 备份所有选中的旧附件并写入可审查的手动恢复命令。
backup_assets() {
  local name='' asset='' asset_id='' label='' restore_spec=''
  printf '%s\n' '手动恢复前先核对远端当前附件，避免覆盖其他人的后续更新。' \
    '下面命令会先删除同名附件再上传备份，不是原子操作。原资产 ID 和下载次数不能恢复。' \
    "目标：https://github.com/$REPOSITORY/releases/tag/$TAG" \
    "先在终端运行：cd ${(q)WORK_DIR}" '' > "$WORK_DIR/RESTORE.txt"
  for name in "${SELECTED_NAMES[@]}"; do
    asset="$(jq -ec --arg name "$name" '.[] | select(.name == $name)' "$WORK_DIR/plan.assets.json")" || fail '无法读取旧资产。'
    asset_id="$(print -r -- "$asset" | jq -r '.id')"
    download_asset "$asset_id" "$WORK_DIR/backup/$name"
    verify_download "$WORK_DIR/backup/$name" "$asset"
    shasum -a 256 "$WORK_DIR/backup/$name" >> "$WORK_DIR/backup.sha256"
    label="$(print -r -- "$asset" | jq -r '.label // ""')"
    [[ "$label" != *[[:cntrl:]]* ]] || fail '旧附件标签含控制字符，无法安全生成恢复命令。'
    restore_spec="./backup/$name"
    [[ -n "$label" ]] && restore_spec+="#$label"
    printf '%q ' gh release upload --repo "$REPOSITORY" --clobber -- "$TAG" "$restore_spec" >> "$WORK_DIR/RESTORE.txt"
    printf '\n' >> "$WORK_DIR/RESTORE.txt"
    log "✔ 已备份并校验：$name"
  done
}
# 输出可比较的 Release 固定字段，忽略资产上传会改变的时间戳。
canonical_release() {
  jq -S '{id,tag_name,target_commitish,name,body,draft,prerelease,immutable,published_at}' "$1"
}
# 输出可比较的资产状态，不将下载计数当成并发修改。
canonical_assets() {
  jq -S 'map({id,name,size,digest,state,label,content_type}) | sort_by(.name)' "$1"
}
# 检查 Tag 是否仍指向预检提交，防止确认期间移动 Tag。
check_tag_commit() {
  resolve_tag_commit
  [[ "$RESOLVED_TAG_SHA" == "$TAG_SHA" ]] || fail 'Tag 提交在执行期间发生变化。'
}
# 覆盖前重新读取完整快照，旧资产或版本变化时保留备份并停止。
check_concurrent_changes() {
  fetch_snapshot "$WORK_DIR/before-upload"
  canonical_release "$WORK_DIR/plan.release.json" > "$WORK_DIR/expected-release.json"
  canonical_release "$WORK_DIR/before-upload.release.json" > "$WORK_DIR/current-release.json"
  cmp -s "$WORK_DIR/expected-release.json" "$WORK_DIR/current-release.json" || fail 'Release 信息在选择后发生变化，请重新运行。'
  canonical_assets "$WORK_DIR/plan.assets.json" > "$WORK_DIR/expected-assets.json"
  canonical_assets "$WORK_DIR/before-upload.assets.json" > "$WORK_DIR/current-assets.json"
  cmp -s "$WORK_DIR/expected-assets.json" "$WORK_DIR/current-assets.json" || fail '附件在选择后发生变化，请重新运行。'
  check_tag_commit
}
# 每次覆盖前核对完整资产状态，保护尚未处理及已校验的附件。
check_live_assets() {
  fetch_snapshot "$WORK_DIR/live-$COMPLETED_COUNT"
  canonical_release "$WORK_DIR/live-$COMPLETED_COUNT.release.json" > "$WORK_DIR/live-release.json"
  cmp -s "$WORK_DIR/expected-release.json" "$WORK_DIR/live-release.json" || fail 'Release 信息在上传过程中发生变化。'
  canonical_assets "$WORK_DIR/expected-live.assets.json" > "$WORK_DIR/expected-live-canonical.json"
  canonical_assets "$WORK_DIR/live-$COMPLETED_COUNT.assets.json" > "$WORK_DIR/live-canonical.json"
  cmp -s "$WORK_DIR/expected-live-canonical.json" "$WORK_DIR/live-canonical.json" || fail '附件在上传过程中被并发修改，已停止后续覆盖。'
  check_tag_commit
}
# 覆盖前展示已备份清单，只有精确大写 YES 才允许开始删除上传。
confirm_replacement() {
  local answer=''
  log "⚠ 即将覆盖 $REPOSITORY / $TAG 的 ${#SELECTED_NAMES} 个同名附件。"
  log '⚠ 会按已备份 ID 删除旧附件再上传同名新版；网络失败可能只完成一部分，不自动回滚或重试覆盖。'
  log "➤ 已保存备份与恢复说明：$WORK_DIR"
  IFS= read -r 'answer?精确输入 YES 后回车执行；其它输入取消：' || fail '确认输入结束，未覆盖远端。'
  if [[ "$answer" != YES ]]; then
    log 'ℹ 已取消覆盖；远端未修改，备份保留。'
    exit 0
  fi
  check_concurrent_changes
}
# 逐个替换并按新资产 ID 下载比对，任何失败都保留已完成状态。
replace_assets() {
  local name='' old_asset='' label='' upload_spec='' new_asset='' asset_id='' old_id='' expected_sha=''
  : > "$WORK_DIR/completed.txt"
  for name in "${SELECTED_NAMES[@]}"; do
    check_live_assets
    expected_sha="$(jq -r --arg name "$name" '.[] | select(.name == $name) | .new_sha256' "$WORK_DIR/selection.json")"
    [[ "$(file_sha256 "$WORK_DIR/staged/$name")" == "$expected_sha" ]] || fail "暂存文件在确认后发生变化：$name"
    old_asset="$(jq -ec --arg name "$name" '.[] | select(.name == $name)' "$WORK_DIR/plan.assets.json")" || fail '无法读取附件原标签。'
    old_id="$(print -r -- "$old_asset" | jq -r '.id')"
    label="$(print -r -- "$old_asset" | jq -r '.label // ""')"
    upload_spec="./$name"
    [[ -n "$label" ]] && upload_spec+="#$label"
    log "➤ 上传来源｜$WORK_DIR/staged/$name"
    log "➤ 上传目标｜$(print -r -- "$old_asset" | jq -r '.browser_download_url')"
    UPLOAD_STARTED=1
    gh api --hostname github.com --method DELETE "repos/$REPOSITORY/releases/assets/$old_id" >>"$LOG_FILE" 2>&1 || fail "删除已批准的旧附件 ID $old_id 失败，已停止：$name"
    (cd "$WORK_DIR/staged" && gh release upload --repo "$REPOSITORY" -- "$TAG" "$upload_spec") >>"$LOG_FILE" 2>&1 || fail "上传失败：$name；已保留备份，请核对远端。"
    fetch_snapshot "$WORK_DIR/after-$((COMPLETED_COUNT+1))"
    new_asset="$(jq -ec --arg name "$name" '.[] | select(.name == $name)' "$WORK_DIR/after-$((COMPLETED_COUNT+1)).assets.json")" || fail "上传后没有找到同名附件：$name"
    asset_id="$(print -r -- "$new_asset" | jq -r '.id')"
    download_asset "$asset_id" "$WORK_DIR/verified/$name"
    verify_download "$WORK_DIR/verified/$name" "$new_asset"
    cmp -s "$WORK_DIR/staged/$name" "$WORK_DIR/verified/$name" || fail "上传后逐字节比对失败：$name"
    [[ "$(file_sha256 "$WORK_DIR/verified/$name")" == "$expected_sha" ]] || fail "上传后 SHA-256 不一致：$name"
    [[ "$(print -r -- "$new_asset" | jq -r '.label // ""')" == "$label" ]] || fail "附件显示标签未保留：$name"
    jq --argjson asset "$new_asset" 'map(if .name == $asset.name then $asset else . end)' "$WORK_DIR/expected-live.assets.json" \
      > "$WORK_DIR/expected-live.next.json" || fail '无法记录本次已校验的资产状态。'
    mv "$WORK_DIR/expected-live.next.json" "$WORK_DIR/expected-live.assets.json" || fail '无法保存资产状态。'
    (( COMPLETED_COUNT++ ))
    printf '%s\t%s\t%s\n' "$name" "$asset_id" "$expected_sha" >> "$WORK_DIR/completed.txt"
    log "✔ 已替换并下载校验：$name｜SHA256 $expected_sha"
  done
}
# 验证其它资产、Release 固定字段和 Tag 提交均保持不变。
verify_final_state() {
  fetch_snapshot "$WORK_DIR/final"
  canonical_release "$WORK_DIR/final.release.json" > "$WORK_DIR/final-release.json"
  cmp -s "$WORK_DIR/expected-release.json" "$WORK_DIR/final-release.json" || fail '最终 Release 信息发生变化。'
  jq --slurpfile selected "$WORK_DIR/selection.json" '[.[] | select(.name as $n | ($selected[0] | map(.name) | index($n)) == null)]' \
    "$WORK_DIR/plan.assets.json" > "$WORK_DIR/other-before.json"
  jq --slurpfile selected "$WORK_DIR/selection.json" '[.[] | select(.name as $n | ($selected[0] | map(.name) | index($n)) == null)]' \
    "$WORK_DIR/final.assets.json" > "$WORK_DIR/other-after.json"
  canonical_assets "$WORK_DIR/other-before.json" > "$WORK_DIR/other-before-canonical.json"
  canonical_assets "$WORK_DIR/other-after.json" > "$WORK_DIR/other-after-canonical.json"
  cmp -s "$WORK_DIR/other-before-canonical.json" "$WORK_DIR/other-after-canonical.json" || fail '其余附件发生变化，请检查并发操作。'
  canonical_assets "$WORK_DIR/expected-live.assets.json" > "$WORK_DIR/final-expected-assets.json"
  canonical_assets "$WORK_DIR/final.assets.json" > "$WORK_DIR/final-actual-assets.json"
  cmp -s "$WORK_DIR/final-expected-assets.json" "$WORK_DIR/final-actual-assets.json" || fail '已处理附件在校验后再次发生变化。'
  check_tag_commit
  log "✔ 完成：$COMPLETED_COUNT/${#SELECTED_NAMES} 个附件已替换并下载校验；其它附件、Release 信息及 Tag 提交保持不变。"
  log "➤ 查看：https://github.com/$REPOSITORY/releases/tag/$TAG"
  log "➤ 日志、备份、校验文件与 RESTORE.txt：$WORK_DIR"
  log 'ℹ 系统临时目录可能被清理；需要长期保存时请自行复制本次材料目录。'
}
# 依次完成自述、只读选择、备份确认、替换和下载校验。
main() {
  show_script_intro_and_wait "$@" # 首先展示用途、风险与回车确认；--help 只读退出。
  initialize_runtime # 确认后才建立日志和运行目录。
  parse_arguments "$@" # 接收分支、版本 Tag 以及可选目录。
  check_environment # 检查工具、可选依赖安装及 GitHub 登录。
  collect_repository_candidates # 定位基仓及直属已初始化子模块。
  collect_plan # 通过可返回的 fzf 层级形成精确替换清单。
  stage_plan # 固定上传副本并记录来源、大小和哈希。
  backup_assets # 备份选中的旧附件并生成手动恢复说明。
  check_concurrent_changes # 备份后核对远端是否被并发修改。
  confirm_replacement # 精确 YES 后再次检查并发变化。
  replace_assets # 逐个覆盖并下载逐字节校验。
  verify_final_state # 确认其余附件、Release 信息和 Tag 未变化。
}
main "$@"
