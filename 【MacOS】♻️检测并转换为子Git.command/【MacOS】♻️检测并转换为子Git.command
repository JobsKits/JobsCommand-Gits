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
# >>> Jobs embedded Python runtime >>>
# 输出诊断，不污染函数返回的解释器路径。
_jobs_python_note() {
  print -u2 -r -- "$*"
}
# 标识当前 zsh 进程及其子 shell，避免继承环境绕过确认。
_jobs_python_process_token() {
  print -r -- "$$:${ZSH_SUBSHELL:-0}"
}
# 只有当前可交互进程内形成的确认才允许环境写操作。
_jobs_python_has_authorization() {
  [[ -t 0 && -t 2 && "${IS_SOURCETREE_RUNTIME:-0}" != 1 && "${DRY_RUN:-0}" != 1 ]] || return 1
  [[ "${parameters[_JOBS_PYTHON_CONFIRMED_PROCESS]:-}" != *export* &&
     "${_JOBS_PYTHON_CONFIRMED_PROCESS:-}" == "$(_jobs_python_process_token)" ]]
}
# 记录调用方已完成的终端确认；非交互入口只允许后续只读检查。
jobs_python_mark_confirmed() {
  emulate -L zsh
  if [[ -t 0 && -t 2 && "${IS_SOURCETREE_RUNTIME:-0}" != 1 && "${DRY_RUN:-0}" != 1 ]]; then
    typeset -g +x _JOBS_PYTHON_CONFIRMED_PROCESS="$(_jobs_python_process_token)"
  fi
  return 0
}
# 在业务自述之后确认本次 Homebrew 更新及 Python 环境准备。
jobs_python_confirm_prepare() {
  emulate -L zsh
  local answer=""
  _jobs_python_has_authorization && return 0
  _jobs_python_note "${1:-Python 环境预检：更新 Homebrew；Python 不满足业务版本时经确认安装或修复。}"
  if [[ ! -t 0 || ! -t 2 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 || "${DRY_RUN:-0}" == 1 ]]; then
    _jobs_python_note "✖ 环境准备需要终端确认；当前未更新或安装任何环境。"
    return 1
  fi
  print -u2 -n -r -- '➤ 按回车准备环境；任意非空输入（含空格）取消：'
  if ! IFS= read -r answer || [[ -n "$answer" ]]; then
    _jobs_python_note '✖ 已取消环境准备。'
    return 1
  fi
  jobs_python_mark_confirmed
}
# 对缺失依赖和已有虚拟环境修复使用统一的必需动作确认。
_jobs_python_confirm_required() {
  emulate -L zsh
  local answer=""
  if ! _jobs_python_has_authorization; then
    _jobs_python_note "✖ $1；需要在终端确认后重试，未执行安装或修复。"
    return 1
  fi
  print -u2 -n -r -- "➤ $1；直接回车执行，任意非空输入（含空格）取消："
  if ! IFS= read -r answer || [[ -n "$answer" ]]; then
    _jobs_python_note '✖ 已取消，停止当前流程。'
    return 1
  fi
}
# 校验版本参数，避免把调用参数作为公式或命令选项解释。
_jobs_python_validate_arguments() {
  emulate -L zsh
  local minimum="$1" formula="$2" maximum="${3:-}"
  if [[ ! "$minimum" =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' ||
        ( -n "$maximum" && ! "$maximum" =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' ) ||
        ! "$formula" =~ '^python(@[0-9]+\.[0-9]+)?$' ]]; then
    _jobs_python_note "✖ Python 版本或 Homebrew 公式参数无效：$minimum / $formula / $maximum"
    return 1
  fi
  if [[ -n "$maximum" ]] && ! _jobs_python_version_less "$minimum" "$maximum"; then
    _jobs_python_note '✖ Python 最低版本必须小于排他上限。'
    return 1
  fi
}
# 以数值逐段比较版本，不依赖任何 Python 运行时。
_jobs_python_version_less() {
  emulate -L zsh
  local -a left right
  local component left_value right_value
  left=("${(@s:.:)1}")
  right=("${(@s:.:)2}")
  for component in 1 2 3; do
    left_value=$((10#${left[$component]:-0}))
    right_value=$((10#${right[$component]:-0}))
    (( left_value < right_value )) && return 0
    (( left_value > right_value )) && return 1
  done
  return 1
}
# 验证本脚本内封装的 Homebrew 接口，不读取外部函数库。
_jobs_python_load_brew_helpers() {
  emulate -L zsh
  local helper
  for helper in jobs_brew_find jobs_brew_choose_installation jobs_brew_install_system jobs_brew_install_user jobs_brew_activate; do
    (( $+functions[$helper] )) || { _jobs_python_note "✖ 脚本内置 Homebrew 接口缺失：$helper"; return 1; }
  done
}
# 验证解释器版本、标准库与归属，返回可机器判断的状态码。
_jobs_python_probe() {
  emulate -L zsh
  local candidate="$1" minimum="$2" maximum="$3" tree="$4" mode="$5"
  [[ -x "$candidate" ]] || return 1
  PYTHONDONTWRITEBYTECODE=1 "$candidate" -c '
import sys
def version(value):
    return tuple((list(map(int, value.split("."))) + [0, 0, 0])[:3])
actual = tuple(sys.version_info[:3])
if actual < version(sys.argv[1]):
    sys.exit(2)
if sys.argv[2] and actual >= version(sys.argv[2]):
    sys.exit(5)
try:
    import venv
    from pathlib import Path
    if actual >= (3, 11, 0):
        import tomllib
except Exception as error:
    print("Python standard library unavailable: " + str(error), file=sys.stderr)
    sys.exit(3)
try:
    target = Path(sys.argv[3]).resolve()
    executable = Path(sys.executable).resolve()
    if sys.argv[4] == "venv":
        if Path(sys.prefix).resolve() != target or sys.prefix == sys.base_prefix:
            sys.exit(4)
    else:
        executable.relative_to(target)
except (ValueError, OSError):
    sys.exit(4)
print("JOBS_PYTHON_OK|" + ".".join(map(str, actual)) + "|" + str(executable))
' "$minimum" "$maximum" "$tree" "$mode"
}
# 验证公式路径属于当前 Homebrew Cellar，再寻找该公式内的健康解释器。
_jobs_python_find_formula_python() {
  emulate -L zsh
  local minimum="$1" formula="$2" maximum="${3:-}"
  local cellar_root formula_cellar formula_prefix candidate probe_result probe_code=1 version_suffix actual_formula python3_command link_target
  local -a candidates runtime_bins
  cellar_root="$(HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" --cellar 2>/dev/null)" || return 1
  formula_cellar="$(HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" --cellar "$formula" 2>/dev/null)" || return 1
  actual_formula="${formula_cellar:t}"
  [[ "$cellar_root" == /* && "$cellar_root" != / && "$formula_cellar" == /* &&
     "${formula_cellar:A}" == "${cellar_root:A}/$actual_formula" &&
     ( "$actual_formula" == "$formula" ||
       ( "$formula" == python && "$actual_formula" =~ '^python@[0-9]+\.[0-9]+$' ) ) ]] || {
    _jobs_python_note "✖ Homebrew 公式 Cellar 路径异常：$formula_cellar"
    return 4
  }
  formula_prefix="$(HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" --prefix "$formula" 2>/dev/null)" || return 1
  if [[ "$formula_prefix" == /* && ! -e "$formula_prefix" && ! -L "$formula_prefix" ]]; then
    return 1
  fi
  if [[ -L "$formula_prefix" && ! -e "$formula_prefix" ]]; then
    link_target="$(/usr/bin/readlink "$formula_prefix")" || return 4
    [[ "$link_target" == /* ]] || link_target="${formula_prefix:h}/$link_target"
    if [[ "${link_target:a}" == "${formula_cellar:A}/"* ]]; then
      return 1
    fi
    _jobs_python_note "✖ 损坏的公式链接指向外部路径：$formula_prefix"
    return 4
  fi
  [[ "$formula_prefix" == /* && "${formula_prefix:A}" == "${formula_cellar:A}/"* && -d "$formula_prefix" ]] || {
    _jobs_python_note "✖ Homebrew 公式前缀不属于指定公式：$formula_prefix"
    return 4
  }
  version_suffix="${actual_formula#python@}"
  [[ "$actual_formula" != python ]] || version_suffix=3
  candidates=("$formula_prefix/libexec/bin/python3" "$formula_prefix/bin/python$version_suffix" "$formula_prefix/bin/python3")
  runtime_bins=()
  for candidate in "$formula_prefix/libexec/bin" "$formula_prefix/bin"; do
    if [[ -d "$candidate" && "${candidate:A}" == "${formula_prefix:A}/"* ]]; then
      runtime_bins+=("$candidate")
    fi
  done
  for candidate in "${candidates[@]}"; do
    [[ -x "$candidate" ]] || continue
    probe_code=0
    probe_result="$(_jobs_python_probe "$candidate" "$minimum" "$maximum" "${formula_cellar:A}" runtime 2>&1)" || probe_code=$?
    if (( probe_code == 0 )) && [[ "$probe_result" == JOBS_PYTHON_OK\|* ]]; then
      python3_command=""
      local runtime_bin
      for runtime_bin in "${runtime_bins[@]}"; do
        if [[ -x "$runtime_bin/python3" ]]; then
          python3_command="$runtime_bin/python3"
          break
        fi
      done
      if [[ -z "$python3_command" ]] ||
         ! _jobs_python_probe "$python3_command" "$minimum" "$maximum" "${formula_cellar:A}" runtime >/dev/null 2>&1; then
        _jobs_python_note "✖ 公式缺少健康的 python3 命令入口：$formula_prefix"
        return 3
      fi
      typeset -gx JOBS_PYTHON_BIN="$candidate"
      typeset -g +x _JOBS_PYTHON_SELECTED_PROCESS="$(_jobs_python_process_token)"
      typeset -g +x _JOBS_PYTHON_SELECTED_BIN="$candidate"
      typeset -g +x _JOBS_PYTHON_SELECTED_TREE="${formula_cellar:A}"
      export PATH="${(j.:.)runtime_bins}:$PATH"
      rehash
      _jobs_python_note "✔ 复用 Homebrew Python：$candidate（${${probe_result#*|}%%|*}）"
      return 0
    fi
    (( probe_code != 0 )) || probe_code=1
    [[ "$probe_code" != 2 && "$probe_code" != 5 ]] || break
  done
  return "$probe_code"
}
# 在当前进程一次更新 Homebrew；失败不进入 Python 安装或业务。
_jobs_python_update_brew_once() {
  emulate -L zsh
  local brew_key="${JOBS_HOMEBREW_BIN:A}" token="$(_jobs_python_process_token)"
  _jobs_python_has_authorization || return 1
  if [[ "${parameters[_JOBS_PYTHON_UPDATED_BREWS]:-}" != association* ||
        "${parameters[_JOBS_PYTHON_UPDATED_BREWS]:-}" == *export* ]]; then
    unset _JOBS_PYTHON_UPDATED_BREWS
    typeset -gA +x _JOBS_PYTHON_UPDATED_BREWS
  fi
  [[ "${_JOBS_PYTHON_UPDATED_BREWS[$brew_key]:-}" != "$token" ]] || return 0
  _jobs_python_note "ℹ 更新 Homebrew 本体及公式索引：$JOBS_HOMEBREW_BIN update"
  if ! HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" update; then
    _jobs_python_note '✖ Homebrew 更新失败，停止 Python 准备；未升级其它公式。'
    return 1
  fi
  jobs_brew_activate || { _jobs_python_note '✖ Homebrew 更新后激活或健康复检失败。'; return 1; }
  _JOBS_PYTHON_UPDATED_BREWS[$brew_key]="$token"
}
# 全新 Mac 缺少 CLT 时只请求系统安装一次，完成对话框后由用户重新运行。
_jobs_python_require_clt_for_install() {
  emulate -L zsh
  local developer_directory git_command token="$(_jobs_python_process_token)"
  [[ "$(/usr/bin/uname -s)" == Darwin ]] || return 0
  developer_directory="$(/usr/bin/xcode-select -p 2>/dev/null)" || developer_directory=""
  git_command="$(command -v git 2>/dev/null)"
  if [[ -n "$developer_directory" && -d "$developer_directory" && -n "$git_command" ]] &&
     "$git_command" --version >/dev/null 2>&1; then
    return 0
  fi
  if [[ "${parameters[_JOBS_PYTHON_CLT_REQUESTED_PROCESS]:-}" != *export* &&
        "${_JOBS_PYTHON_CLT_REQUESTED_PROCESS:-}" == "$token" ]]; then
    _jobs_python_note '✖ 已请求 Command Line Tools 安装；请完成系统对话框后重新运行脚本。'
    return 1
  fi
  _jobs_python_confirm_required '缺少可用 Git / Command Line Tools，将打开 Apple 系统安装对话框' || return 1
  typeset -g +x _JOBS_PYTHON_CLT_REQUESTED_PROCESS="$token"
  if ! /usr/bin/xcode-select --install; then
    _jobs_python_note '✖ 无法发起 Command Line Tools 安装；请先在系统中安装或修复开发者工具。'
    return 1
  fi
  _jobs_python_note 'ℹ 已请求系统安装；请完成 Command Line Tools 对话框后重新运行，本次不继续安装 Homebrew。'
  return 1
}
# 准备必经的 Homebrew 通道，缺失时复用内置安装路径选择。
_jobs_python_prepare_brew() {
  emulate -L zsh
  local installed=""
  _jobs_python_load_brew_helpers || return 1
  if ! JOBS_HOMEBREW_BIN="$(jobs_brew_find)"; then
    if ! _jobs_python_has_authorization; then
      _jobs_python_note '✖ 缺少健康 Homebrew；请在终端确认环境准备，未执行安装。'
      return 1
    fi
    _jobs_python_require_clt_for_install || return 1
    jobs_brew_choose_installation || return 1
    case "${JOBS_HOMEBREW_INSTALL_MODE:-}" in
      system) jobs_brew_install_system || return 1 ;;
      user) jobs_brew_install_user || return 1 ;;
      *) _jobs_python_note '✖ Homebrew 安装路径选择无效，停止。'; return 1 ;;
    esac
    installed=installed
  fi
  jobs_brew_activate "$installed" || { _jobs_python_note '✖ Homebrew 激活或健康检查失败。'; return 1; }
  if _jobs_python_has_authorization; then
    _jobs_python_update_brew_once || return 1
  else
    _jobs_python_note 'ℹ 当前未获得终端确认，仅只读检查已有 Homebrew / Python，不更新或安装。'
  fi
}
# 更新 Homebrew 后只处理业务指定的 Python 公式，并立即复检。
jobs_python_ensure() {
  emulate -L zsh
  local minimum="${1:-}" formula="${2:-python@3.13}" maximum="${3:-}"
  local probe_code=0 action=install installed_versions=""
  unset JOBS_PYTHON_BIN
  _jobs_python_validate_arguments "$minimum" "$formula" "$maximum" || return 1
  _jobs_python_prepare_brew || return 1
  _jobs_python_find_formula_python "$minimum" "$formula" "$maximum" || probe_code=$?
  (( probe_code != 0 )) || return 0
  if ! _jobs_python_has_authorization; then
    _jobs_python_note "✖ $formula 不满足 Python $minimum${maximum:+ 至小于 $maximum}；无交互确认，停止。"
    return 1
  fi
  if (( probe_code == 4 )); then
    _jobs_python_note '✖ Python 或公式路径归属异常，停止；不覆盖外部解释器。'
    return 1
  fi
  if (( probe_code == 5 )); then
    _jobs_python_note "✖ $formula 的 Python 版本高于业务允许范围（须小于 $maximum）；停止，不尝试无效升级。"
    return 1
  fi
  installed_versions="$(HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" list --versions "$formula" 2>/dev/null)" || installed_versions=""
  if [[ -n "$installed_versions" ]]; then
    action=reinstall
    (( probe_code != 2 )) || action=upgrade
  fi
  _jobs_python_confirm_required "必需的 $formula 未就绪，执行 brew $action $formula" || return 1
  if ! HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" "$action" "$formula"; then
    _jobs_python_note "✖ brew $action $formula 失败；停止，不重复安装。"
    return 1
  fi
  jobs_brew_activate || return 1
  if ! _jobs_python_find_formula_python "$minimum" "$formula" "$maximum"; then
    _jobs_python_note "✖ $formula 安装或修复后仍不满足要求；停止下游业务。"
    return 1
  fi
}
# 拒绝空目录、根目录及符号链接路径，防止虚拟环境修复涉及其它目录。
_jobs_python_validate_venv_path() {
  emulate -L zsh
  local supplied="${1:-}" absolute
  [[ -n "$supplied" ]] || { _jobs_python_note '✖ 虚拟环境路径不能为空。'; return 1; }
  absolute="${supplied:a}"
  if [[ "$absolute" == / || "$absolute" == "${HOME:a}" || "$absolute" != "${absolute:A}" ||
        -L "$absolute" || ( -e "$absolute" && ! -d "$absolute" ) ]]; then
    _jobs_python_note "✖ 虚拟环境须为独立真实目录，拒绝危险路径：$supplied"
    return 1
  fi
  if [[ -d "$absolute" && ! -f "$absolute/pyvenv.cfg" && ! -e "$absolute/bin/python" &&
        ! -L "$absolute/bin/python" && "${absolute:t}" != .venv && "${absolute:t}" != venv ]]; then
    _jobs_python_note "✖ 目录不是可识别的虚拟环境，不移动源码或用户目录：$absolute"
    return 1
  fi
  print -r -- "$absolute"
}
# 复用健康虚拟环境；旧坏环境完整改名备份后重建，不删除原目录。
jobs_python_prepare_venv() {
  emulate -L zsh
  local supplied="${1:-}" minimum="${2:-}" maximum="${3:-}" environment candidate probe_result backup suffix=0
  _jobs_python_validate_arguments "$minimum" python "${maximum:-}" || return 1
  environment="$(_jobs_python_validate_venv_path "$supplied")" || return 1
  candidate="$environment/bin/python"
  if [[ -d "$environment" ]] &&
     probe_result="$(_jobs_python_probe "$candidate" "$minimum" "$maximum" "$environment" venv 2>&1)" &&
     [[ "$probe_result" == JOBS_PYTHON_OK\|* ]]; then
    _jobs_python_note "✔ 复用虚拟环境：$environment"
    return 0
  fi
  if ! _jobs_python_has_authorization; then
    _jobs_python_note "✖ 虚拟环境缺失或不健康，需要终端确认后准备：$environment"
    return 1
  fi
  if [[ -z "${JOBS_PYTHON_BIN:-}" || ! -x "$JOBS_PYTHON_BIN" ||
        "${parameters[_JOBS_PYTHON_SELECTED_PROCESS]:-}" == *export* ||
        "${parameters[_JOBS_PYTHON_SELECTED_BIN]:-}" == *export* ||
        "${parameters[_JOBS_PYTHON_SELECTED_TREE]:-}" == *export* ||
        "${_JOBS_PYTHON_SELECTED_PROCESS:-}" != "$(_jobs_python_process_token)" ||
        "${_JOBS_PYTHON_SELECTED_BIN:-}" != "$JOBS_PYTHON_BIN" ]]; then
    _jobs_python_note '✖ 尚未选定健康 Homebrew Python，请先调用 jobs_python_ensure。'
    return 1
  fi
  if ! _jobs_python_probe "$JOBS_PYTHON_BIN" "$minimum" "$maximum" "$_JOBS_PYTHON_SELECTED_TREE" runtime >/dev/null 2>&1; then
    _jobs_python_note '✖ 已选择的 Homebrew Python 不满足虚拟环境版本要求，停止。'
    return 1
  fi
  if [[ -d "$environment" ]]; then
    _jobs_python_confirm_required "修复旧或损坏的虚拟环境 $environment（完整改名备份）" || return 1
    backup="$environment.backup.$(/bin/date '+%Y%m%d-%H%M%S').$$"
    while [[ -e "$backup" || -L "$backup" ]]; do
      (( suffix += 1 ))
      backup="$environment.backup.$(/bin/date '+%Y%m%d-%H%M%S').$$.$suffix"
    done
    if ! mv -- "$environment" "$backup"; then
      _jobs_python_note "✖ 原虚拟环境备份失败，停止：$environment"
      return 1
    fi
    _jobs_python_note "ℹ 原虚拟环境已完整保留：$backup"
  fi
  if ! PYTHONDONTWRITEBYTECODE=1 "$JOBS_PYTHON_BIN" -m venv "$environment"; then
    _jobs_python_note "✖ 虚拟环境创建失败，停止；备份保持原状：${backup:-无旧环境}"
    return 1
  fi
  if ! probe_result="$(_jobs_python_probe "$candidate" "$minimum" "$maximum" "$environment" venv 2>&1)" ||
     [[ "$probe_result" != JOBS_PYTHON_OK\|* ]]; then
    _jobs_python_note "✖ 虚拟环境创建后复检失败，停止：$environment"
    return 1
  fi
  _jobs_python_note "✔ 虚拟环境已就绪：$environment"
}
# <<< Jobs embedded Python runtime <<<

# 编排本文件内嵌的环境自检，保留当前入口的确认和版本要求。
jobs_gitconvert_python_preflight() {
  case "${1:-interactive}" in
    confirmed) jobs_python_mark_confirmed ;;
    readonly) ;;
    *)
      if [[ -t 0 && -t 2 && "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]]; then
        jobs_python_confirm_prepare || return 1
      fi
      ;;
  esac
  jobs_python_ensure 3.11 python@3.13
}

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
      jobs_brew_install_or_exit || { error_echo "Homebrew 安装失败（arm64）"; return 1; }
      brew_bin="${JOBS_HOMEBREW_BIN:-$(jobs_brew_find 2>/dev/null || true)}"
    else
      jobs_brew_install_or_exit || { error_echo "Homebrew 安装失败（x86_64）"; return 1; }
      brew_bin="${JOBS_HOMEBREW_BIN:-$(jobs_brew_find 2>/dev/null || true)}"
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
show_script_intro_and_wait() {
  clear
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- "Python 环境：确认后更新 Homebrew；缺失时选择安装路径，Python 不满足要求才修复。" | jobs_intro_style body
  print -r -- '脚本名称：【MacOS】♻️检测并转换为子Git.command' | jobs_intro_style title
  print -r -- '核心用途：执行“♻️检测并转换为子Git”对应的 Git 自动化操作。' | jobs_intro_style body
  print -r -- '影响范围：可能修改当前仓库、工作区、分支或 Git 索引。' | jobs_intro_style body
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。' | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title
  echo "" | jobs_intro_style body
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _ || exit 1
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
  SCRIPT_PATH="${(%):-%x}"
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
      "$JOBS_PYTHON_BIN" - <<'PY' "$p" 2>/dev/null || perl -MCwd -e 'print Cwd::abs_path($ARGV[0])' "$p"
  import os,sys
  print(os.path.abspath(sys.argv[1]))
PY
    fi
  }
  # ================================== 自述 ==================================
  show_intro_and_wait() {
    cat <<EOF | jobs_intro_style auto >"$TTY_OUT"
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
      jobs_brew_install_or_exit \
        || die "Homebrew 安装失败"

      # 尝试让 brew 在当前会话可用
      if [[ -x "/opt/homebrew/bin/brew" ]]; then
        eval "$("${JOBS_HOMEBREW_BIN:-$(jobs_brew_find)}" shellenv)"
      elif [[ -x "/usr/local/bin/brew" ]]; then
        eval "$("${JOBS_HOMEBREW_BIN:-$(jobs_brew_find)}" shellenv)"
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
      gray "${rows[1]//\t/ | }"
      note "是否继续处理该项？直接回车=继续；输入任意字符=返回上一步"
      local c=""
      read_tty c ""
      if [[ -n "$c" ]]; then
        printf "%s" ""
        return 0
      fi
      printf "%s" "$(printf "%s" "${rows[1]}" | cut -f1)"
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
# 入口失败在阶段内终止；source 业务继续使用可返回的预检函数。
jobs_gitconvert_python_prepare_runtime() {
  jobs_gitconvert_python_preflight confirmed || exit 1
}


main() {
  show_script_intro_and_wait # 展示脚本内置自述，并按运行入口完成防误触确认。
  jobs_gitconvert_python_prepare_runtime # 业务确认后使用内嵌函数准备 Homebrew Python。
  initialize_script_runtime # 初始化 Shell 选项、日志、依赖和入口运行状态。
  run_original_logic "$@" # 执行 run_original_logic 对应的核心业务步骤。
  success_echo "脚本执行结束。日志：$LOG_FILE" # 输出脚本执行结果、摘要和日志位置。
}

main "$@"
