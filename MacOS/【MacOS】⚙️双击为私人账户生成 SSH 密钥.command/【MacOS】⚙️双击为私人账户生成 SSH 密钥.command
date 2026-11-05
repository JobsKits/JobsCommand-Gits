#!/bin/zsh
# shell: zsh
# 脚本自述：终端管理个人 GitHub SSH 密钥；fzf 选择算法，只需填写绑定邮箱（默认 295060456@qq.com）。
# 影响范围：创建或复用个人密钥，仅在未占用时新建 .ssh/README.md，备份并更新 SSH 配置，加载 agent，复制公钥；认证通过后添加 Sourcetree 相对链接。
# 远端：仅在 gh 已授权且绑定邮箱匹配时登记公钥；否则打开官方页面并明确提示未完成。
# 不覆盖已有密钥，不读取或记录私钥正文，不修改其它账户密钥和仓库地址。

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
  print -r -- "$*" | tee -a "$LOG_FILE"
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
  IFS= read -r 'answer?按回车继续；输入任意字符后回车取消：' || return 1
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
    IFS= read -r "SSH_EMAIL?绑定邮箱（回车使用 $default_email）：" || return 1
    SSH_EMAIL="${SSH_EMAIL:-$default_email}"
  else
    IFS= read -r 'SSH_EMAIL?绑定邮箱：' || return 1
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
