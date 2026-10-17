#!/usr/bin/env python3
# Created by Jobs on 2026年10月18日，星期日.
"""Verify actual downloader functions with isolated Git configuration and file-only fixtures."""

from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


GENESIS = Path(__file__).resolve().parents[3]
SCRIPT_NAME = "【MacOS】⏬下载配置当前Git子模块.command"
SOURCES = [GENESIS / directory / SCRIPT_NAME for directory in (
    "", "JobsConfigOS", "JobsPythonTools.py", "MacOS@Extension", "JobsConfigOS/💻JobsCodexConfigs",
)]
SOURCES += [
    GENESIS / "JobsConfigOS/⚙️VScodeConfigs" / SCRIPT_NAME / SCRIPT_NAME,
    GENESIS / "JobsCommand@Gits" / SCRIPT_NAME / SCRIPT_NAME,
]
FUNCTIONS = (
    "trim_string", "parse_git_remote_url", "resolve_relative_git_url", "normalize_gitee_https_url",
    "configure_gitee_https_transport", "git_url_with_style", "validate_submodule_url_path",
    "sync_submodule_urls_at_repo", "clone_submodule_worktree", "ensure_submodule_worktree_present",
    "sync_one_submodule_to_latest", "sync_selected_submodules_to_latest",
)
SHELL_SETUP = r'''
setopt ERR_EXIT PIPE_FAIL NO_NOMATCH
source "$1"
shift
CASE_ROOT="$1"
GIT_URL_STYLE=auto
SUBMODULE_BRANCH=main
SUBMODULE_SHALLOW_CLONE=1
SUBMODULE_DEPTH=1
SUBMODULE_FETCH_TAGS=0
info_echo() { return 0; }
warn_echo() { print -r -- "$*"; }
error_echo() { print -r -- "$*"; }
run_cmd() { "$@"; }
'''
SYNC_FAILURE_SETUP = r'''
clone_url_for_path() { print 'https://gitee.com/JobsGo/Child.git'; }
is_git_worktree() { return 0; }
assert_clean_submodule() { return 0; }
resolve_remote_branch_for_submodule() { print main; }
sync_submodule_urls_at_repo() { return 0; }
get_ncpu() { print 2; }
success_echo() { print -r -- "UNEXPECTED_SUCCESS $*"; }
'''


class GiteeHttpsTransportTests(unittest.TestCase):
    """Exercise all deployed copies without invoking their business entrypoints."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="jobs-gitee-https-regression-")
        self.root = Path(self.tmp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.global_config = self.home / "gitconfig"
        self.global_config.write_text("[test]\n\tpreserved = true\n", encoding="utf-8")
        self.global_before = self.global_config.read_bytes()
        self.env = {
            key: value for key, value in os.environ.items()
            if not key.startswith("GIT_") and key != "JOBS_GITEE_HTTPS_CONFIGURED"
        }
        self.env.update(
            HOME=str(self.home), XDG_CONFIG_HOME=str(self.home / "xdg"),
            GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=str(self.global_config),
            GIT_ALLOW_PROTOCOL="file", GIT_TERMINAL_PROMPT="0", GIT_ASKPASS="/usr/bin/false",
            SSH_ASKPASS="/usr/bin/false", GIT_SSH_COMMAND="/usr/bin/false",
            GIT_AUTHOR_NAME="Offline Test", GIT_AUTHOR_EMAIL="offline@example.invalid",
            GIT_COMMITTER_NAME="Offline Test", GIT_COMMITTER_EMAIL="offline@example.invalid",
            PATH="/usr/bin:/bin:/usr/sbin:/sbin", TERM="dumb", NO_COLOR="1",
        )
        self.case_count = 0

    def tearDown(self) -> None:
        self.assertEqual(self.global_before, self.global_config.read_bytes(), "global configuration changed")
        self.tmp.cleanup()

    def git(self, repo: Path, *args: str) -> str:
        """Run real Git against a disposable repository with hooks disabled."""
        result = subprocess.run(
            ["/usr/bin/git", "-c", "core.hooksPath=/dev/null", "-C", str(repo), *args],
            env=self.env, capture_output=True, text=True, timeout=15,
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        return result.stdout.strip()

    def fixture(self, case_root: Path, *, second: bool = False) -> Path:
        """Create only local parent/child repositories for real recursive Git subprocesses."""
        leaf = case_root / "leaf"
        parent = case_root / "parent"
        for repo in (leaf, parent):
            repo.mkdir(parents=True)
            self.git(repo, "init", "-q", "-b", "main")
        (leaf / "seed").write_text("fixture\n", encoding="utf-8")
        self.git(leaf, "add", "seed")
        self.git(leaf, "commit", "-qm", "offline fixture")
        self.git(parent, "submodule", "add", "-q", leaf.as_uri(), "nested child")
        if second:
            self.git(parent, "submodule", "add", "-q", leaf.as_uri(), "no branch")
        return parent

    def shell(self, source: Path, body: str, *, fixture: bool = False, second: bool = False) -> str:
        """Source only selected real functions, including indented functions in the generic copy."""
        self.case_count += 1
        case_root = self.root / f"case-{self.case_count}"
        case_root.mkdir()
        if fixture:
            self.fixture(case_root, second=second)
        content = source.read_text(encoding="utf-8")
        extracted = []
        for name in FUNCTIONS:
            match = re.search(rf"(?ms)^([ \t]*){re.escape(name)}\(\)[ \t]*\{{.*?^\1\}}", content)
            self.assertIsNotNone(match, f"{source}: missing function {name}")
            extracted.append(match.group())
        candidate = case_root / "functions.zsh"
        candidate.write_text("\n".join(extracted) + "\n", encoding="utf-8")
        result = subprocess.run(
            ["/bin/zsh", "-f", "-c", SHELL_SETUP + body, "offline-gitee-test", str(candidate), str(case_root)],
            cwd=case_root, env=self.env, capture_output=True, text=True, timeout=20,
        )
        self.assertEqual(0, result.returncode, f"{source}: {result.stdout}{result.stderr}")
        return result.stdout

    def test_process_rules_preserve_existing_config_and_are_idempotent(self) -> None:
        for source in SOURCES:
            with self.subTest(script=source):
                self.shell(source, r'''
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.quotePath GIT_CONFIG_VALUE_0=false
configure_gitee_https_transport
[[ "$GIT_CONFIG_COUNT" == 4 && "$GIT_CONFIG_KEY_0" == core.quotePath && "$GIT_CONFIG_VALUE_0" == false ]]
[[ "$(git config core.quotePath)" == false ]]
configure_gitee_https_transport
[[ "$GIT_CONFIG_COUNT" == 4 ]]
for GIT_URL_STYLE in auto ssh https; do
  for prefix in 'git@gitee.com:' 'ssh://git@gitee.com/' 'ssh://git@gitee.com:22/'; do
    expected='https://gitee.com/JobsGo/jobs-code-snippetsJobsCodeSnippets.git'
    [[ "$(git ls-remote --get-url "${prefix}JobsGo/jobs-code-snippetsJobsCodeSnippets.git")" == "$expected" ]]
    [[ "$(git_url_with_style "${prefix}JobsGo/jobs-code-snippetsJobsCodeSnippets.git")" == "$expected" ]]
  done
done
for invalid_count in invalid -1 1.5 1000000000; do
  (
    unset JOBS_GITEE_HTTPS_CONFIGURED
    export GIT_CONFIG_COUNT="$invalid_count"
    if configure_gitee_https_transport; then exit 91; fi
    [[ "$GIT_CONFIG_COUNT" == "$invalid_count" ]]
  )
done
(
  unset JOBS_GITEE_HTTPS_CONFIGURED
  export GIT_CONFIG_COUNT=0001
  configure_gitee_https_transport
  [[ "$GIT_CONFIG_COUNT" == 4 && "$GIT_CONFIG_KEY_0" == core.quotePath && "$GIT_CONFIG_VALUE_0" == false ]]
  [[ "$(git config core.quotePath)" == false ]]
)
''')

    def test_unrelated_hosts_custom_ports_and_relative_urls_keep_their_scope(self) -> None:
        for source in SOURCES:
            with self.subTest(script=source):
                self.shell(source, r'''
configure_gitee_https_transport
for url in 'git@github.com:JobsKits/Child.git' 'ssh://git@gitee.com:2222/group/Child.git' 'git@mirror.example:team/Child.git'; do
  [[ "$(git ls-remote --get-url "$url")" == "$url" ]]
  [[ "$(git_url_with_style "$url")" == "$url" ]]
done
[[ "$(resolve_relative_git_url 'https://gitee.com/team/nested/Parent.git' '../odd-name.git')" == 'https://gitee.com/team/nested/odd-name.git' ]]
[[ "$(resolve_relative_git_url 'ssh://git@mirror.example:2222/team/nested/Parent.git' '../Child.git')" == 'ssh://git@mirror.example:2222/team/nested/Child.git' ]]
GIT_URL_STYLE=ssh
[[ "$(git_url_with_style 'https://github.com/JobsKits/Child.git')" == 'git@github.com:JobsKits/Child.git' ]]
GIT_URL_STYLE=https
[[ "$(git_url_with_style 'git@github.com:JobsKits/Child.git')" == 'https://github.com/JobsKits/Child.git' ]]
''')

    def test_real_recursive_git_subprocesses_inherit_process_rules(self) -> None:
        for source in SOURCES:
            with self.subTest(script=source):
                self.shell(source, r'''
configure_gitee_https_transport
/bin/zsh -f -c '[[ -z ${JOBS_GITEE_HTTPS_CONFIGURED+x} ]] && [[ $(git ls-remote --get-url git@gitee.com:JobsGo/Child.git) == https://gitee.com/JobsGo/Child.git ]]'
actual="$(git -C "$CASE_ROOT/parent" submodule foreach --quiet --recursive 'git ls-remote --get-url git@gitee.com:JobsGo/Child.git')"
[[ "$actual" == 'https://gitee.com/JobsGo/Child.git' ]]
''', fixture=True)

    def test_url_sync_preserves_metadata_index_and_local_edits(self) -> None:
        for source in SOURCES:
            with self.subTest(script=source):
                self.shell(source, r'''
parent="$CASE_ROOT/parent"
git -C "$parent" config -f .gitmodules 'submodule.nested child.url' 'git@gitee.com:JobsGo/jobs-code-snippetsJobsCodeSnippets.git'
git -C "$parent" config -f .gitmodules 'submodule.nested child.branch' feature
git -C "$parent" config -f .gitmodules 'submodule.nested child.ignore' dirty
git -C "$parent" config -f .gitmodules 'submodule.nested child.update' checkout
git -C "$parent" config -f .gitmodules 'submodule.no branch.url' '../Other.git'
print dirty > "$parent/untouched.txt"
print local-edit > "$parent/nested child/seed"
before="$(/usr/bin/shasum -a 256 "$parent/.gitmodules" "$parent/untouched.txt" "$parent/nested child/seed" "$parent/.git/index")"
sync_submodule_urls_at_repo "$parent" 'https://gitee.com/JobsGo/Parent.git'
after="$(/usr/bin/shasum -a 256 "$parent/.gitmodules" "$parent/untouched.txt" "$parent/nested child/seed" "$parent/.git/index")"
[[ "$before" == "$after" ]]
[[ "$(git -C "$parent" config 'submodule.nested child.url')" == 'https://gitee.com/JobsGo/jobs-code-snippetsJobsCodeSnippets.git' ]]
[[ "$(git -C "$parent/nested child" remote get-url origin)" == 'https://gitee.com/JobsGo/jobs-code-snippetsJobsCodeSnippets.git' ]]
[[ "$(git -C "$parent" config -f .gitmodules 'submodule.nested child.branch')" == feature ]]
if git -C "$parent" config -f .gitmodules 'submodule.no branch.branch'; then exit 92; fi
''', fixture=True, second=True)

    def test_recursive_update_failure_is_not_reported_as_success(self) -> None:
        for source in SOURCES:
            with self.subTest(script=source):
                output = self.shell(source, SYNC_FAILURE_SETUP + r'''
run_cmd() { [[ "$*" == *'submodule update --init --recursive'* ]] && return 37; return 0; }
if sync_one_submodule_to_latest "$CASE_ROOT"; then print UNEXPECTED_ZERO; exit 93; fi
''')
                self.assertNotIn("UNEXPECTED_", output)
                self.assertIn("递归子模块同步失败", output)

    def test_fetch_failure_stops_before_checkout_or_reset(self) -> None:
        for source in SOURCES:
            with self.subTest(script=source):
                output = self.shell(source, SYNC_FAILURE_SETUP + r'''
run_cmd() {
  if [[ "$*" == *' fetch '* ]]; then print EXPECTED_FETCH_FAILURE; return 37; fi
  [[ "$*" == *' checkout '* || "$*" == *' reset '* ]] && print UNEXPECTED_MUTATION
  return 0
}
if sync_one_submodule_to_latest "$CASE_ROOT"; then print UNEXPECTED_ZERO; exit 94; fi
''')
                self.assertIn("EXPECTED_FETCH_FAILURE", output)
                self.assertNotIn("UNEXPECTED_", output)

    def test_clone_and_registration_failures_stop_following_steps(self) -> None:
        for source in SOURCES:
            with self.subTest(script=source):
                output = self.shell(source, r'''
clone_url_for_path() { print 'https://gitee.com/JobsGo/Child.git'; }
remote_branch_for_url() { print main; }
remote_branch_exists() { [[ "$BRANCH_EXISTS" == 1 ]]; }
get_ncpu() { print 1; }
run_cmd() {
  if [[ "$1 $2" == 'git clone' ]]; then print EXPECTED_CLONE_FAILURE; return 37; fi
  print UNEXPECTED_AFTER_CLONE
  return 0
}
for BRANCH_EXISTS in 1 0; do
  if clone_submodule_worktree "$CASE_ROOT/not-created"; then print UNEXPECTED_ZERO; exit 95; fi
done
clone_submodule_worktree() { return 37; }
run_cmd() { print UNEXPECTED_REGISTER; return 0; }
if ensure_submodule_worktree_present "$CASE_ROOT/not-created"; then print UNEXPECTED_ZERO; exit 96; fi
ensure_submodule_worktree_present() { return 37; }
sync_one_submodule_to_latest() { print UNEXPECTED_SYNC; return 0; }
if sync_selected_submodules_to_latest one two; then print UNEXPECTED_ZERO; exit 97; fi
''')
                self.assertEqual(2, output.count("EXPECTED_CLONE_FAILURE"))
                self.assertNotIn("UNEXPECTED_", output)

    def test_empty_directory_removal_failure_stops_before_registration(self) -> None:
        for source in SOURCES:
            with self.subTest(script=source):
                output = self.shell(source, r'''
/bin/mkdir "$CASE_ROOT/empty-target"
is_git_worktree() { return 1; }
is_dir_empty() { return 0; }
success_echo() { print UNEXPECTED_SUCCESS; }
run_cmd() {
  if [[ "$1 $2" == 'rm -rf' ]]; then print EXPECTED_REMOVE_FAILURE; return 37; fi
  print UNEXPECTED_REGISTER
  return 0
}
if ensure_submodule_worktree_present "$CASE_ROOT/empty-target"; then print UNEXPECTED_ZERO; exit 98; fi
[[ -d "$CASE_ROOT/empty-target" ]]
''')
                self.assertIn("EXPECTED_REMOVE_FAILURE", output)
                self.assertNotIn("UNEXPECTED_", output)


if __name__ == "__main__":
    unittest.main(verbosity=2)
