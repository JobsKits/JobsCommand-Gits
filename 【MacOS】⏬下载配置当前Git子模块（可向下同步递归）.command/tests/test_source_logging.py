#!/usr/bin/env python3
# Created by Jobs on 2026年10月18日，星期日.
"""Exercise source reporting offline without starting a downloader entrypoint."""

from __future__ import annotations

import errno
import os
from pathlib import Path
import pty
import re
import subprocess
import tempfile
import unittest

from test_gitee_https_transport import SOURCES


ALL_SOURCES = SOURCES
SETUP = r'''
setopt ERR_EXIT PIPE_FAIL NO_NOMATCH
source "$1"
shift
CASE_ROOT="$1"
cd "$CASE_ROOT/parent"
LOG_FILE="$CASE_ROOT/output.log"
GIT_URL_STYLE=auto
SUBMODULE_BRANCH=main
SUBMODULE_SHALLOW_CLONE=1
SUBMODULE_DEPTH=1
SUBMODULE_FETCH_TAGS=0
REMOTE_NAME=origin
run_cmd() { "$@"; }
'''


class SourceLoggingTests(unittest.TestCase):
    """Check effective URLs, safe display and logging order in all deployed copies."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="jobs-source-log-regression-")
        self.root = Path(self.tmp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.env = {
            key: value for key, value in os.environ.items()
            if not key.startswith("GIT_") and key != "JOBS_GITEE_HTTPS_CONFIGURED"
        }
        self.env.update(
            HOME=str(self.home), XDG_CONFIG_HOME=str(self.home / "xdg"),
            GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null",
            GIT_ALLOW_PROTOCOL="file", GIT_TERMINAL_PROMPT="0",
            GIT_ASKPASS="/usr/bin/false", SSH_ASKPASS="/usr/bin/false",
            GIT_SSH_COMMAND="/usr/bin/false", PATH="/usr/bin:/bin:/usr/sbin:/sbin",
            TERM="dumb", NO_COLOR="1",
        )
        self.case_count = 0

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def shell(self, source: Path, body: str, *, terminal: bool = False) -> tuple[str, str]:
        """Load real declarations; allow only disposable local Git repositories."""
        self.case_count += 1
        case_root = self.root / f"case-{self.case_count}"
        parent = case_root / "parent"
        parent.mkdir(parents=True)
        init = subprocess.run(
            ["/usr/bin/git", "init", "-q", str(parent)], env=self.env,
            capture_output=True, text=True, timeout=10,
        )
        self.assertEqual(0, init.returncode, init.stderr)
        content = source.read_text(encoding="utf-8")
        candidate = case_root / "functions.zsh"
        candidate.write_text(re.sub(r'(?m)^main "\$@"\s*$', '', content), encoding="utf-8")
        args = ["/bin/zsh", "-f", "-c", SETUP + body, "offline-source-test", str(candidate), str(case_root)]
        if terminal:
            master, slave = pty.openpty()
            process = subprocess.Popen(args, env=self.env, stdout=slave, stderr=subprocess.PIPE)
            os.close(slave)
            chunks = []
            try:
                while True:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        break
                    if not chunk:
                        break
                    chunks.append(chunk)
            finally:
                os.close(master)
            _, stderr = process.communicate(timeout=15)
            output = b"".join(chunks).decode().replace("\r\n", "\n")
            self.assertEqual(0, process.returncode, f"{source}: {output}{stderr.decode()}")
        else:
            result = subprocess.run(args, env=self.env, capture_output=True, text=True, timeout=15)
            output = result.stdout
            self.assertEqual(0, result.returncode, f"{source}: {output}{result.stderr}")
        log_file = case_root / "output.log"
        return output, log_file.read_text(encoding="utf-8") if log_file.exists() else ""

    def test_parent_route_uses_selected_remote_and_local_rewrite(self) -> None:
        for source in ALL_SOURCES:
            with self.subTest(script=source):
                output, disk = self.shell(source, r'''
git remote add origin https://github.com/team/Parent.git
git remote add company ssh://git@forge.example:2222/team/Parent.git
git config --add remote.company.url https://second.example/team/Unused.git
git config 'url.https://mirror.example:8443/team/.insteadOf' 'ssh://git@forge.example:2222/team/'
ensure_git_remote company
''')
                self.assertIn("父仓线路 [company]", output)
                self.assertIn("📥 拉取地址：https://mirror.example:8443/team/Parent.git", output)
                self.assertIn("🔎 解析地址：ssh://git@forge.example:2222/team/Parent.git", output)
                self.assertIn("平台 / 主机：mirror.example:8443", output)
                self.assertNotIn("github.com", output)
                self.assertNotIn("second.example", output)
                self.assertEqual(output, disk)

    def test_host_display_and_credentials_are_safe(self) -> None:
        for source in ALL_SOURCES:
            with self.subTest(script=source):
                output, disk = self.shell(source, r'''
for url in https://github.com/team/Child.git https://gitee.com/team/Child.git https://gitlab.com/group/Child.git ssh://git@forge.example:2222/team/Child.git; do
  print_git_source 测试 Child "$PWD" "$url"
done
print_git_source 测试 Child "$PWD" $'https://private-token:secret@forge.example/team/Child.git?access_token=hidden#private\033[31m\n'
print_git_source 测试 Child "$PWD" 'ssh://git:password@forge.example:2222/team/Child.git'
''')
                for expected in ("GitHub（github.com）", "Gitee（gitee.com）", "GitLab（gitlab.com）", "forge.example:2222"):
                    self.assertIn(expected, output)
                for hidden in ("private-token", "secret", "access_token", "hidden#", "private\x1b", "password"):
                    self.assertNotIn(hidden, output)
                self.assertIn("[凭据已隐藏]@forge.example", output)
                self.assertIn("[参数已隐藏]", output)
                self.assertNotIn("\x1b", output)
                self.assertEqual(output, disk)

    def test_rewritten_credentials_and_lookup_failure_are_safe(self) -> None:
        for source in ALL_SOURCES:
            with self.subTest(script=source):
                output, _ = self.shell(source, r'''
git config 'url.https://user:secret@mirror.example/team/.insteadOf' 'https://github.com/team/'
print_git_source 测试 Child "$PWD" 'https://github.com/team/Child.git'
print_git_source 测试 Missing "$CASE_ROOT/missing-repo" 'ssh://git@fallback.example:2200/team/Child.git'
''')
                self.assertNotIn("secret", output)
                self.assertIn("📥 拉取地址：https://[凭据已隐藏]@mirror.example/team/Child.git", output)
                self.assertIn("📥 拉取地址：ssh://git@fallback.example:2200/team/Child.git", output)

    def test_source_precedes_clone_network_probe_and_clone(self) -> None:
        for source in ALL_SOURCES:
            with self.subTest(script=source):
                _, disk = self.shell(source, r'''
clone_url_for_path() { print 'https://gitee.com/team/Child.git'; }
remote_branch_for_url() { print NETWORK_PROBE >> "$LOG_FILE"; print main; }
remote_branch_exists() { return 0; }
get_ncpu() { print 1; }
run_cmd() { print -r -- "COMMAND $*" >> "$LOG_FILE"; return 37; }
clone_submodule_worktree Child || true
''')
                self.assertLess(disk.index("首次克隆"), disk.index("NETWORK_PROBE"))
                self.assertLess(disk.index("拉取地址：https://gitee.com/team/Child.git"), disk.index("NETWORK_PROBE"))
                clone_line = next(line for line in disk.splitlines() if line.startswith("COMMAND git ") and " clone " in line)
                self.assertLess(disk.index("克隆分支：main"), disk.index(clone_line))

    def test_fetch_source_uses_child_scope_before_branch_probe(self) -> None:
        for source in ALL_SOURCES:
            with self.subTest(script=source):
                _, disk = self.shell(source, r'''
git init -q Child
git -C Child remote add origin https://github.com/team/Child.git
git -C Child -c user.name=Offline -c user.email=offline@example.invalid commit --allow-empty -qm fixture
git -C Child config 'url.ssh://git@child.example:2222/team/.insteadOf' 'https://github.com/team/'
clone_url_for_path() { print 'https://github.com/team/Child.git'; }
is_git_worktree() { return 0; }
assert_clean_submodule() { return 0; }
resolve_remote_branch_for_submodule() { print NETWORK_PROBE >> "$LOG_FILE"; print feature; }
get_ncpu() { print 1; }
run_cmd() {
  if [[ "$*" == *' fetch '* ]]; then print NETWORK_FETCH >> "$LOG_FILE"; return 0; fi
  if [[ "$*" == *' checkout '* || "$*" == *' reset '* || "$*" == *' branch '* || "$*" == *'submodule '* ]]; then return 0; fi
  "$@"
}
sync_one_submodule_to_latest Child
''')
                self.assertIn("拉取地址：ssh://git@child.example:2222/team/Child.git", disk)
                self.assertLess(disk.index("拉取更新"), disk.index("NETWORK_PROBE"))
                self.assertLess(disk.index("拉取分支：origin/feature"), disk.index("NETWORK_FETCH"))

    def test_recursive_sources_respect_each_repository_scope(self) -> None:
        for source in ALL_SOURCES:
            with self.subTest(script=source):
                output, disk = self.shell(source, r'''
git init -q Child
git -C Child remote add origin https://gitee.com/team/Child.git
git config 'url.https://parent.example/team/.insteadOf' 'https://gitee.com/team/'
git -C Child config 'url.https://child.example:8443/team/.insteadOf' 'https://gitee.com/team/'
git -C Child config 'url.ssh://git@nested.example:2222/team/.insteadOf' 'git@forge.example:team/'
git config -f .gitmodules submodule.Child.path Child
git config -f .gitmodules submodule.Child.url ../Child.git
git config -f .gitmodules submodule.Missing.path Missing
git config -f .gitmodules submodule.Missing.url ../Missing.git
git config -f Child/.gitmodules submodule.Leaf.path Leaf
git config -f Child/.gitmodules submodule.Leaf.url git@forge.example:team/Leaf.git
sync_submodule_urls_at_repo "$PWD" https://gitee.com/team/Parent.git 1
''')
                self.assertEqual(3, output.count("递归来源核对"))
                self.assertIn("拉取地址：https://child.example:8443/team/Child.git", output)
                self.assertIn("拉取地址：https://gitee.com/team/Missing.git", output)
                self.assertIn("拉取地址：git@forge.example:team/Leaf.git", output)
                self.assertEqual(output, disk)

    def test_clone_scope_matches_real_file_only_clone(self) -> None:
        for source in ALL_SOURCES:
            with self.subTest(script=source):
                output, _ = self.shell(source, r'''
git init -q "$CASE_ROOT/Child.git"
git -C "$CASE_ROOT/Child.git" -c user.name=Offline -c user.email=offline@example.invalid commit --allow-empty -qm fixture
raw='https://clone.example/team/Child.git'
expected="file://$CASE_ROOT/Child.git"
git config "url.file://$CASE_ROOT/.insteadOf" https://clone.example/team/
[[ "$(effective_git_source_url "$PWD" "$raw")" == "$expected" ]]
[[ "$(effective_git_source_url "$PWD" "$raw" clone)" == "$raw" ]]
print_git_source 首次克隆 Child "$PWD" "$raw" clone
if git clone -q "$raw" "$CASE_ROOT/local-must-not-apply" 2> "$CASE_ROOT/blocked.log"; then exit 93; fi
[[ "$(cat "$CASE_ROOT/blocked.log")" == *"transport 'https' not allowed"* ]]
export GIT_CONFIG_GLOBAL="$CASE_ROOT/test-global"
git config --global "url.file://$CASE_ROOT/.insteadOf" https://clone.example/team/
[[ "$(effective_git_source_url "$PWD" "$raw" clone)" == "$expected" ]]
git clone -q "$raw" "$CASE_ROOT/from-global"
[[ "$(git -C "$CASE_ROOT/from-global" rev-parse HEAD)" == "$(git -C "$CASE_ROOT/Child.git" rev-parse HEAD)" ]]
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0="url.file://$CASE_ROOT/.insteadOf"
export GIT_CONFIG_VALUE_0=https://clone.example/team/
[[ "$(effective_git_source_url "$PWD" "$raw" clone)" == "$expected" ]]
git clone -q "$raw" "$CASE_ROOT/from-process"
[[ "$(git -C "$CASE_ROOT/from-process" rev-parse HEAD)" == "$(git -C "$CASE_ROOT/Child.git" rev-parse HEAD)" ]]
''')
                self.assertIn("拉取地址：https://clone.example/team/Child.git", output)

    def test_success_line_repeats_safe_effective_source(self) -> None:
        for source in ALL_SOURCES:
            with self.subTest(script=source):
                output, disk = self.shell(source, r'''
git init -q Child
git -C Child remote add origin https://github.com/team/Child.git
git -C Child -c user.name=Offline -c user.email=offline@example.invalid commit --allow-empty -qm fixture
git -C Child config 'url.https://user:secret@mirror.example/team/.insteadOf' 'https://github.com/team/'
clone_url_for_path() { print 'https://github.com/team/Child.git'; }
is_git_worktree() { return 0; }
assert_clean_submodule() { return 0; }
resolve_remote_branch_for_submodule() { print main; }
get_ncpu() { print 1; }
run_cmd() {
  if [[ "$*" == *' fetch '* || "$*" == *' checkout '* || "$*" == *' reset '* || "$*" == *' branch '* || "$*" == *'submodule '* ]]; then return 0; fi
  "$@"
}
sync_one_submodule_to_latest Child
''')
                success = next(line for line in output.splitlines() if "已浅同步" in line)
                self.assertIn("来源：https://[凭据已隐藏]@mirror.example/team/Child.git", success)
                self.assertNotIn("secret", output)
                self.assertIn(success, disk)

    def test_terminal_color_does_not_enter_log_and_no_color_is_honored(self) -> None:
        for source in ALL_SOURCES:
            with self.subTest(script=source):
                output, disk = self.shell(source, r'''
unset NO_COLOR
TERM=xterm-256color
source_highlight_echo color-enabled
NO_COLOR=1
source_highlight_echo color-disabled
''', terminal=True)
                self.assertIn("\x1b[1;36mcolor-enabled\x1b[0m", output)
                self.assertIn("\ncolor-disabled\n", output)
                self.assertNotIn("\x1b", disk)
                self.assertEqual("color-enabled\ncolor-disabled\n", disk)


if __name__ == "__main__":
    unittest.main(verbosity=2)
