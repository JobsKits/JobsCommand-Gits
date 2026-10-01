#!/bin/zsh
# 脚本自述：
# - 用途：接收 GitHub 仓库地址、本地视频文件，上传附件并返回 README 播放 URL。
# - 影响：创建远端附件，不修改 README、不提交或推送代码；重复运行会创建新附件。
# - 删除：单独删除附件较麻烦，请联系 https://support.github.com/。
#   删除整个 GitHub 远端仓库会触发延迟清理；删除本地文件夹或 README 链接无效。
# - 运行：双击后输入两个参数，或通过命令行传入；先按回车确认，Ctrl+C 取消。

# 展示上传范围与删除限制，确认前不执行任何写操作。
show_script_intro_and_wait() {
  print -r -- '🎬 上传 GitHub 视频附件'
  print -r -- '输入 GitHub 仓库地址和本地视频路径，支持 MP4 / MOV / WEBM。'
  print -r -- '将创建远端附件，返回 URL 并复制到剪贴板；重复上传会产生新附件。'
  print -r -- '附件单独删除比较麻烦，请联系 GitHub Support：https://support.github.com/'
  print -r -- 'GitHub 曾说明：删除整个远端仓库会触发延迟清理，不保证即时删除。'
  print -r -- '删除本地项目文件夹、仓库中的视频或 README 链接，不等于删除附件。'
  print -r -- '日志保存到系统临时目录；按 Ctrl+C 取消。'
  local answer
  IFS= read -r 'answer?按回车继续：' || exit 1
  [[ -z "$answer" ]] || exit 1
}
# 初始化日志与执行策略。
initialize_runtime() {
  setopt NO_NOMATCH PIPE_FAIL EXTENDED_GLOB
  SCRIPT_DIR="${${(%):-%x}:A:h}"
  SCRIPT_PATH="${${(%):-%x}:A}"
  SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
  LOG_FILE="$(mktemp "${TMPDIR:-/tmp/}${SCRIPT_BASENAME}.XXXXXX")" || exit 1
  export GH_HOST=github.com
  print -r -- "日志：$LOG_FILE"
}
# 同时写入终端和日志。
log() { print -r -- "$*" | tee -a "$LOG_FILE"; }
# 可见地停止失败流程。
fail() { log "✖ $*"; exit 1; }
# 收集两个业务参数并安全解析 Finder 拖入的单个路径。
collect_parameters() {
  (( $# == 0 || $# == 2 )) || fail '只接受两个参数：仓库地址、本地视频路径。'
  REPOSITORY="${1:-}"
  VIDEO_FILE="${2:-}"
  while [[ -z "${REPOSITORY//[[:space:]]/}" ]]; do
    IFS= read -r 'REPOSITORY?GitHub 仓库地址（必填）：' || fail '输入已取消。'
    [[ -n "${REPOSITORY//[[:space:]]/}" ]] || log '⚠ 仓库地址不能为空，请重新输入。'
  done
  REPOSITORY="${REPOSITORY##[[:space:]]#}"
  REPOSITORY="${REPOSITORY%%[[:space:]]#}"
  if [[ -z "${VIDEO_FILE//[[:space:]]/}" ]]; then
    while [[ -z "${VIDEO_FILE//[[:space:]]/}" ]]; do
      IFS= read -r 'VIDEO_FILE?本地视频路径（必填，可拖入文件）：' || fail '输入已取消。'
      [[ -n "${VIDEO_FILE//[[:space:]]/}" ]] || log '⚠ 视频路径不能为空，请重新输入。'
    done
    VIDEO_FILE="${VIDEO_FILE%$'\r'}"
    VIDEO_FILE="${VIDEO_FILE%%[[:space:]]#}"
    if [[ ! -f "$VIDEO_FILE" ]]; then
      local -a words
      words=( ${(z)VIDEO_FILE} )
      (( ${#words} == 1 )) || fail '请只拖入一个视频文件。'
      VIDEO_FILE="${(Q)words[1]}"
    fi
  fi
  REPOSITORY="${REPOSITORY%/}"
  REPOSITORY="${REPOSITORY#https://github.com/}"
  REPOSITORY="${REPOSITORY#git@github.com:}"
  REPOSITORY="${REPOSITORY%.git}"
  [[ "$REPOSITORY" =~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' ]] || fail '请输入 github.com 仓库首页地址或 owner/repo。'
  [[ -f "$VIDEO_FILE" && -r "$VIDEO_FILE" && -s "$VIDEO_FILE" ]] || fail "视频不存在、不可读或为空：$VIDEO_FILE"
  VIDEO_FILE="${VIDEO_FILE:A}"
  case "${VIDEO_FILE:e:l}" in
    mp4) CONTENT_TYPE=video/mp4 ;;
    mov) CONTENT_TYPE=video/quicktime ;;
    webm) CONTENT_TYPE=video/webm ;;
    *) fail '只支持 MP4、MOV、WEBM 视频。' ;;
  esac
}
# 检查客户端、登录身份和目标仓库写权限。
check_environment() {
  export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
  command -v gh >/dev/null || fail '需要 GitHub CLI，请安装 gh 后重新运行：https://cli.github.com/'
  gh auth status --hostname github.com >>"$LOG_FILE" 2>&1 || {
    log '需要登录 GitHub，即将打开 gh 登录流程。'
    gh auth login --hostname github.com --web || fail 'GitHub 登录失败。'
  }
  local metadata
  metadata="$(gh api "repos/$REPOSITORY" --jq '[.id, .permissions.push] | @tsv' 2>>"$LOG_FILE")" || fail "无法读取仓库 $REPOSITORY，详情见 $LOG_FILE"
  REPOSITORY_ID="${metadata%%$'\t'*}"
  [[ "$REPOSITORY_ID" == <-> && "${metadata#*$'\t'}" == true ]] || fail '当前账号需要目标仓库的写权限。'
}
# 二进制上传；失败不自动重试，避免产生重复附件。
upload_video() {
  log "ℹ 正在上传 ${VIDEO_FILE:t} 到 $REPOSITORY，请等待……"
  VIDEO_URL="$(gh api 'https://uploads.github.com/user-attachments/assets' \
    --method POST --header 'Content-Type: application/octet-stream' \
    --input "$VIDEO_FILE" --raw-field "name=${VIDEO_FILE:t}" \
    --raw-field "content_type=$CONTENT_TYPE" --raw-field "repository_id=$REPOSITORY_ID" \
    --jq '.url' 2>>"$LOG_FILE")" || fail "上传失败，详情见 $LOG_FILE；网络中断后重试前请确认是否已上传。"
  [[ "$VIDEO_URL" =~ '^https://github.com/user-attachments/assets/[A-Za-z0-9-]+$' ]] || fail "服务返回异常，详情见 $LOG_FILE；请勿盲目重复上传。"
}
# 输出可直接粘贴到 README 的裸 URL。
show_result() {
  log '✔ 上传成功，README 中请把下面 URL 单独放一段，前后留空行：'
  log "$VIDEO_URL"
  if command -v pbcopy >/dev/null && print -rn -- "$VIDEO_URL" | pbcopy; then
    log '✔ URL 已复制到剪贴板。'
  else
    log '⚠ 剪贴板不可用，请复制上面的 URL。'
  fi
  log "日志：$LOG_FILE"
}
main() {
  show_script_intro_and_wait # 先展示用途与删除限制并确认。
  initialize_runtime # 初始化日志与执行环境。
  collect_parameters "$@" # 获取仓库地址与视频路径。
  check_environment # 检查登录与仓库写权限。
  upload_video # 上传视频并提取附件 URL。
  show_result # 输出 URL 并复制到剪贴板。
}
main "$@"
