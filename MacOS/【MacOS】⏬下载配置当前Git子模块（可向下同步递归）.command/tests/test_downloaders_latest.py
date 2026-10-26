#!/usr/bin/env python3
# Created by Jobs on 2026年10月18日，星期日.
"""Verify standalone downloaders with disposable repositories and file-only transport."""

from __future__ import annotations

import hashlib
import os
from pathlib import Path
import pty
import re
import shlex
import subprocess
import tempfile
import unittest

SCRIPT_NAME = "【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command"
GENESIS = Path(__file__).resolve().parents[4]
CANDIDATES = [Path(__file__).resolve().parents[1] / SCRIPT_NAME]
CANDIDATES += [GENESIS / folder / SCRIPT_NAME for folder in (
    "", "JobsConfigOS", "JobsPythonTools.py", "OS@Extension/MacOS@Extension", "JobsConfigOS/💻JobsCodexConfigs",
)]
CANDIDATES += [
    GENESIS.parent / "JobsBaseConfig" / SCRIPT_NAME,
    GENESIS / "JobsConfigOS/⚙️VScodeConfigs" / SCRIPT_NAME / SCRIPT_NAME,
]
SOURCES = list(dict.fromkeys(path for path in CANDIDATES if path.is_file()))
CONFIG_PATTERN = r"(?ms)^[ \t]*SUBMODULE_REPO_URLS=\(\n.*?^[ \t]*\)"


class DownloaderLatestTests(unittest.TestCase):
    """Load real functions after removing the entrypoint; refuse network and real hooks."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix='jobs-downloader-latest-')
        self.root = Path(self.tmp.name).resolve()
        (self.root / 'home').mkdir()
        self.env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
        self.env.update(
            HOME=str(self.root / 'home'), TMPDIR=str(self.root),
            XDG_CONFIG_HOME=str(self.root / 'home/xdg'),
            GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL='/dev/null',
            GIT_CONFIG_COUNT='1', GIT_CONFIG_KEY_0='core.hooksPath',
            GIT_CONFIG_VALUE_0='/dev/null', GIT_ALLOW_PROTOCOL='file',
            GIT_TERMINAL_PROMPT='0', GIT_ASKPASS='/usr/bin/false',
            GIT_SSH_COMMAND='/usr/bin/false', SSH_ASKPASS='/usr/bin/false',
            GIT_AUTHOR_NAME='Offline Test', GIT_AUTHOR_EMAIL='offline@example.invalid',
            GIT_COMMITTER_NAME='Offline Test', GIT_COMMITTER_EMAIL='offline@example.invalid',
            PATH='/usr/bin:/bin:/usr/sbin:/sbin', NO_COLOR='1', TERM='dumb',
        )

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def shell(
        self, source: Path, body: str, *, tty_input: str | None = None, expected: int = 0,
    ) -> str:
        """Load real functions after removing the entrypoint, without initial side effects."""
        lib = self.root / 'library.zsh'
        lib.write_text(re.sub('(?m)^main "\\$@"\\s*$', '', source.read_text()))
        prefix = r'''setopt ERR_EXIT PIPE_FAIL NO_NOMATCH
original_path="$PATH"
original_pwd="$PWD"
source "$1"
shift
CASE_ROOT="$1"
[[ "$PATH" == "$original_path" && "$PWD" == "$original_pwd" ]]
LOG_FILE="$CASE_ROOT/output.log"
'''
        args = ['/bin/zsh', '-f', '-c', prefix + body, 'offline-latest', str(lib), str(self.root)]
        if tty_input is not None:
            master, slave = pty.openpty()
            proc = subprocess.Popen(
                args, cwd=self.root, env=self.env, stdin=slave,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            )
            os.close(slave)
            try:
                os.write(master, tty_input.encode())
                out, err = proc.communicate(timeout=20)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.communicate()
                raise
            finally:
                os.close(master)
            code = proc.returncode
        else:
            r = subprocess.run(
                args, cwd=self.root, env=self.env, stdin=subprocess.DEVNULL,
                capture_output=True, text=True, timeout=20,
            )
            code = r.returncode
            out = r.stdout
            err = r.stderr
        self.assertEqual(expected, code, f'{source}: {out}{err}')
        return out + err

    def git(self, repo: Path, *args: str) -> str:
        """Run Git only in the disposable fixture, with real hooks disabled."""
        r = subprocess.run(
            ['/usr/bin/git', '-c', 'core.hooksPath=/dev/null', '-C', str(repo), *args],
            env=self.env, capture_output=True, text=True, timeout=20,
        )
        self.assertEqual(0, r.returncode, r.stdout + r.stderr)
        return r.stdout.strip()

    def fixture(self, key: str) -> tuple[Path, Path, Path, Path]:
        """Create a parent Git pointer file and children whose section names differ from paths."""
        root = (self.root / key).resolve()
        root.mkdir()
        leaf = root / 'leaf'
        seed = root / 'seed parent'
        outer = root / 'outer'
        for repo in (leaf, seed, outer):
            repo.mkdir()
            self.git(repo, 'init', '-q', '-b', 'main')
            self.git(repo, 'commit', '--allow-empty', '-qm', 'fixture')
        (leaf / 'seed').write_text('leaf\n')
        self.git(leaf, 'add', 'seed')
        self.git(leaf, 'commit', '-qm', 'leaf seed')
        self.git(seed, 'submodule', 'add', '-q', '--name', 'real-section', leaf.as_uri(), '目标 child')
        self.git(seed, 'submodule', 'add', '-q', '--name', 'bypass-section', leaf.as_uri(), '旁路 child')
        self.git(seed, 'commit', '-qam', 'children')
        self.git(outer, 'submodule', 'add', '-q', '--name', 'parent-section', seed.as_uri(), 'parent tree')
        parent = outer / 'parent tree'
        self.git(parent, 'submodule', 'update', '--init', '--recursive')
        parent_git = Path(self.git(parent, 'rev-parse', '--absolute-git-dir'))
        return (parent, parent_git / 'modules/real-section', parent_git / 'modules/bypass-section', leaf)

    def script_body(self, parent: Path) -> str:
        """Exercise real local Git without automatically publishing the parent."""
        return f"cd {shlex.quote(str(parent))}\n" + r'''CONFIG_PATHS=('目标 child')
SUBMODULE_BRANCH=main
SUBMODULE_SHALLOW_CLONE=0
SUBMODULE_FETCH_TAGS=0
PRUNE_STALE_GITMODULES=0
AUTO_PARENT_COMMIT=0
AUTO_PARENT_PUSH=0
GITMODULES_RECONCILED=0
REMOTE_NAME=origin
GIT_URL_STYLE=auto
repo_name_by_path() { print -r -- "$1"; }
'''

    def test_common_implementation_and_independent_configurations(self) -> None:
        configurations = set()
        self.assertTrue(SOURCES, 'the standalone downloader is missing')
        for source in SOURCES:
            with self.subTest(script=source):
                content = source.read_text(encoding='utf-8')
                config = re.search(CONFIG_PATTERN, content)
                self.assertIsNotNone(config, str(source))
                configurations.add(config.group())
                outer = re.sub(r"(?ms)^  engine_code=.*?^JOBS_READONLY_PULL_ENGINE$", '', content, count=1)
                self.assertEqual(1, len(re.findall('^main\\(\\)', outer, re.M)))
                self.assertEqual(1, outer.count('main "$@"'))
                self.assertNotIn('jobs_run_original_script', content)
                self.assertNotIn('run_original_logic', content)
                self.assertNotIn('collect_existing_child_git_dirs', content)
                # 各仓可有不同附加流程；校验取消选择时的行为，不能用逐行格式或
                # 整文件相等约束已支持的可选安装与真实退出码传播。
                output = self.shell(source, r'''
select_download_operation_mode() { print SELECT; return 19; }
run_selected_download_mode() { print UNEXPECTED_DOWNLOAD; }
offer_global_markdown_toc_setup() { print UNEXPECTED_SETUP; }
main
''', expected=19)
                self.assertIn('SELECT', output)
                self.assertNotIn('UNEXPECTED_', output)
        if len(SOURCES) > 1:
            self.assertGreater(len(configurations), 1)

    def test_declarations_do_not_execute_or_change_environment(self) -> None:
        for source in SOURCES:
            with self.subTest(source=source):
                self.shell(source, r'''[[ -z "$SCRIPT_DIR" && -z "$REPO_ROOT" ]]
[[ ! -e "$LOG_FILE" ]]
[[ ! -e "$CASE_ROOT/home/.zprofile" ]]
''')

    def test_root_and_package_paths_with_unicode_and_spaces(self) -> None:
        for i, source in enumerate(SOURCES):
            with self.subTest(source=source):
                target = self.root / f'case {i} 中文'
                target.mkdir()
                subprocess.run(['/usr/bin/git', 'init', '-q', str(target)], env=self.env, check=True)
                name = source.name
                (target / name).write_text('fixture')
                package = target / name
                package.unlink()
                package.mkdir()
                (package / name).write_text('fixture')
                self.shell(source, f'expected={str(target.resolve())!r}\nSCRIPT_FILE="$expected/{name}/{name}"\ninitialize_script_paths\n[[ "$SCRIPT_DIR" == "$expected/{name}" && "$REPO_ROOT" == "$expected" ]]\nLOG_FILE="$CASE_ROOT/output.log"\ncd_to_script_dir\nensure_repo_initialized\nSCRIPT_FILE="$expected/{name}"\ninitialize_script_paths\n[[ "$REPO_ROOT" == "$expected" ]]\n')

    def test_wrong_root_is_rejected_without_initializing_nested_repo(self) -> None:
        for i, source in enumerate(SOURCES):
            with self.subTest(source=source):
                target = self.root / f'parent-{i}'
                target.mkdir()
                (target / 'wrong-layer').mkdir()
                subprocess.run(['/usr/bin/git', 'init', '-q', str(target)], env=self.env, check=True)
                self.shell(source, f"cd {str(target / 'wrong-layer')!r}\nif ensure_repo_initialized; then print UNEXPECTED_SUCCESS; exit 92; fi\n[[ ! -e .git ]]\n")

    def test_full_sync_reuses_configured_paths_without_delete_or_global_confirmation(self) -> None:
        for source in SOURCES:
            with self.subTest(source=source):
                trace = self.root / 'trace'
                trace.unlink(missing_ok=True)
                self.shell(source, r'''CONFIG_PATHS=('Child with space' '第二个 child')
repo_name_by_path() { print UNEXPECTED_LEGACY_LOOKUP; return 1; }
reconcile_gitmodules_with_config_once() { print RECONCILE >> "$CASE_ROOT/trace"; }
sync_selected_submodules_to_latest() { printf 'SYNC %s\n' "$@" >> "$CASE_ROOT/trace"; }
stage_and_commit_parent_changes() { printf 'STAGE %s\n' "$@" >> "$CASE_ROOT/trace"; }
parent_push_if_needed() { print PUSH_POLICY >> "$CASE_ROOT/trace"; }
full_sync_to_latest
''')
                self.assertEqual([
                    'RECONCILE', 'SYNC Child with space', 'SYNC 第二个 child',
                    'STAGE Child with space', 'STAGE 第二个 child', 'PUSH_POLICY',
                ], trace.read_text().splitlines())
                content = source.read_text(encoding='utf-8')
                for obsolete in ('collect_full_delete_targets()', 'confirm_full_rebuild()', 'remove_worktree_dir_safely()'):
                    self.assertNotIn(obsolete, content)

    def test_full_failure_propagates_before_later_actions(self) -> None:
        for source in SOURCES:
            with self.subTest(source=source):
                output = self.shell(source, r'''reconcile_gitmodules_with_config_once() { print EXPECTED_FAILURE; return 37; }
sync_selected_submodules_to_latest() { print UNEXPECTED_SYNC; }
success_echo() { print UNEXPECTED_SUCCESS; }
if full_sync_to_latest; then print UNEXPECTED_ZERO; exit 93; fi
''')
                self.assertIn('EXPECTED_FAILURE', output)
                self.assertNotIn('UNEXPECTED_', output)

    def test_explicit_stale_prune_requires_its_own_terminal_yes(self) -> None:
        for source in SOURCES:
            with self.subTest(source=source):
                self.assertIn('未执行删除', self.shell(
                    source, "confirm_stale_submodule_removal 'Legacy child'\n", expected=1,
                ))
                for answer in ('\n', 'yes\n', 'YES \n'):
                    self.assertIn('停止旧登记裁剪', self.shell(
                        source, "confirm_stale_submodule_removal 'Legacy child'\n",
                        tty_input=answer, expected=1,
                    ))
                self.shell(source, "confirm_stale_submodule_removal 'Legacy child'\n", tty_input='YES\n')
                self.assertIn('仅展示旧登记裁剪', self.shell(
                    source, "DRY_RUN=1\nconfirm_stale_submodule_removal 'Legacy child'\n",
                ))

    def test_multiselect_back_returns_to_menu_with_err_exit(self) -> None:
        for source in SOURCES:
            with self.subTest(source=source):
                counter = self.root / 'counter'
                counter.unlink(missing_ok=True)
                output = self.shell(source, r'''build_intro_content() { print preview; }
select_menu_action() {
 if [[ -f "$CASE_ROOT/counter" ]]; then print 2 >> "$CASE_ROOT/counter"; print '退出'; else print 1 > "$CASE_ROOT/counter"; print '选择指定子模块同步（可多选）'; fi
}
select_configured_submodules_interactive() { return 2; }
menu_result=0
main_menu_loop "$CASE_ROOT/preview" || menu_result=$?
if (( $+functions[run_download_selection_loop] )); then
 [[ "$menu_result" == 130 ]]
else
 [[ "$menu_result" == 0 ]]
fi
[[ "$(cat "$CASE_ROOT/counter")" == $'1\n2' ]]
''')
                self.assertIn('已退出', output)

    def test_menu_action_failure_is_not_success(self) -> None:
        for source in SOURCES:
            for action, func in [('全量同步更新下载到最新', 'full_sync_to_latest'), ('只更新目前已有的', 'update_existing_to_latest'), ('添加并同步一个新的 Git 地址', 'add_new_git_url_interactive')]:
                with self.subTest(source=source, action=action):
                    self.shell(source, f'build_intro_content() {{ print preview; }}\nsynchronize_parent_repository() {{ return 0; }}\nselect_menu_action() {{ print -r -- {action!r}; }}\n{func}() {{ return 37; }}\nif main_menu_loop "$CASE_ROOT/preview"; then print UNEXPECTED_ZERO; exit 94; fi\n')

    def test_recursion_menu_choice_changes_mode_and_cancel_preserves_previous_mode(self) -> None:
        for source in SOURCES:
            with self.subTest(source=source):
                self.shell(source, r'''
[[ "$SUBMODULE_RECURSIVE" == 1 && "$(submodule_recursion_label)" == *向下递归* ]]
fzf() {
 cat >/dev/null
 (( $+functions[run_download_selection_loop] )) && print ''
 print -r -- '仅直属一层（不拉取下层）'
}
select_submodule_recursion_interactive
[[ "$SUBMODULE_RECURSIVE" == 0 && "$(submodule_recursion_label)" == *仅直属一层* ]]
fzf() { cat >/dev/null; return 130; }
picker_result=0
select_submodule_recursion_interactive || picker_result=$?
[[ "$SUBMODULE_RECURSIVE" == 0 ]]
if (( $+functions[run_download_selection_loop] )); then [[ "$picker_result" == 130 ]]; fi
fzf() {
 cat >/dev/null
 (( $+functions[run_download_selection_loop] )) && print ''
 print -r -- '向下递归（所选子树逐层最新）'
}
select_submodule_recursion_interactive
[[ "$SUBMODULE_RECURSIVE" == 1 ]]
fzf() { cat >/dev/null; return 130; }
picker_result=0
select_submodule_recursion_interactive || picker_result=$?
[[ "$SUBMODULE_RECURSIVE" == 1 ]]
''')

    def test_symlink_selection_is_rejected_before_remote_or_worktree_mutation(self) -> None:
        for index, source in enumerate(SOURCES):
            with self.subTest(source=source):
                target = self.root / f"outside-{index}"
                target.mkdir()
                self.git(target, "init", "-q")
                self.git(target, "commit", "--allow-empty", "-qm", "fixture")
                self.git(target, "remote", "add", "origin", "https://must-preserve.invalid/repo")
                pointer = self.root / f"symlink-{index}"
                pointer.symlink_to(target, target_is_directory=True)
                before = (target / ".git/config").read_bytes()
                output = self.shell(source, f"selected={shlex.quote(pointer.name)}\n" + r'''
clone_url_for_path() { print UNEXPECTED_URL_LOOKUP; return 1; }
if sync_selected_submodules_to_latest "$selected"; then print UNEXPECTED_SUCCESS; exit 98; fi
''')
                self.assertNotIn("UNEXPECTED_", output)
                self.assertIn("拒绝", output)
                self.assertEqual(before, (target / ".git/config").read_bytes())

    def test_nested_configured_paths_keep_the_classification_directory(self) -> None:
        for source in SOURCES:
            with self.subTest(source=source):
                self.shell(source, r'''
SUBMODULE_REPO_URLS=(
  'https://github.com/JobsKits/MacOS_Extension|OS@Extension/MacOS@Extension'
  'https://github.com/JobsKits/WindowsOS_Extension|OS@Extension/WindowsOS@Extension'
)
load_configured_submodules
[[ "${CONFIG_PATHS[1]}" == OS@Extension/MacOS@Extension ]]
[[ "${CONFIG_PATHS[2]}" == OS@Extension/WindowsOS@Extension ]]
[[ ! -e OS@Extension ]]
for invalid in '' /absolute 'OS@Extension/' 'OS@Extension//child' './child' '../child' 'OS@Extension/../child' 'OS@Extension/.GIT/child' 'OS@Extension/-child' 'OS@Extension/child|other' $'OS@Extension/child\t'; do
  if validate_local_path "$invalid"; then print -r -- "UNEXPECTED_ACCEPTED:$invalid"; exit 91; fi
done
''')

    def test_nested_clone_reuses_different_section_and_preserves_sibling(self) -> None:
        for index, source in enumerate(SOURCES):
            with self.subTest(source=source):
                case = self.root / f'nested-clone-{index}'
                parent, leaf = case / 'parent', case / 'leaf'
                for repo in (parent, leaf):
                    repo.mkdir(parents=True)
                    self.git(repo, 'init', '-q', '-b', 'main')
                    (repo / 'seed').write_text('fixture\n')
                    self.git(repo, 'add', 'seed')
                    self.git(repo, 'commit', '-qm', 'fixture')
                self.git(parent, 'remote', 'add', 'origin', 'https://code.example/team/Parent.git')
                nested = 'OS@Extension/WindowsOS@Extension'
                self.git(parent, 'config', '-f', '.gitmodules', 'submodule.Stable Windows section.path', nested)
                self.git(parent, 'config', '-f', '.gitmodules', 'submodule.Stable Windows section.url', leaf.as_uri())
                self.git(parent, 'config', '-f', '.gitmodules', 'submodule.Stable Windows section.update', 'checkout')
                body = self.script_body(parent) + f'leaf_url={shlex.quote(leaf.as_uri())}\n' + r'''
SUBMODULE_RECURSIVE=0
ensure_submodule_worktree_present 'OS@Extension/WindowsOS@Extension' "$leaf_url" main
ensure_gitmodules_entry 'OS@Extension/WindowsOS@Extension'
'''
                self.shell(source, body)
                child = parent / nested
                self.assertTrue((child / '.git').is_file())
                self.assertEqual(str(parent), self.git(child, 'rev-parse', '--show-superproject-working-tree'))
                self.assertEqual('OS@Extension/WindowsOS@Extension', self.git(parent, 'config', '-f', '.gitmodules', 'submodule.Stable Windows section.path'))
                self.assertEqual('checkout', self.git(parent, 'config', '-f', '.gitmodules', 'submodule.Stable Windows section.update'))
                self.assertTrue(self.git(parent, 'ls-files', '--stage', '--', nested).startswith('160000 '))
                sibling = parent / 'OS@Extension/MacOS@Extension'
                sibling.mkdir()
                (sibling / 'keep').write_bytes(b'keep sibling')
                self.git(parent, 'config', '-f', '.gitmodules', 'submodule.legacy.path', 'OS@Extension')
                self.git(parent, 'config', '-f', '.gitmodules', 'submodule.legacy.url', leaf.as_uri())
                before = (parent / '.gitmodules').read_bytes()
                output = self.shell(source, self.script_body(parent) + r'''
CONFIG_PATHS=('OS@Extension/WindowsOS@Extension')
PRUNE_STALE_GITMODULES=1
FORCE_DELETE=1
confirm_stale_submodule_removal() { print UNEXPECTED_CONFIRM; return 0; }
if prune_unconfigured_gitmodules; then print UNEXPECTED_PRUNE; exit 92; fi
''')
                self.assertNotIn('UNEXPECTED_', output)
                self.assertIn('保留分类目录', output)
                self.assertEqual(before, (parent / '.gitmodules').read_bytes())
                self.assertEqual(b'keep sibling', (sibling / 'keep').read_bytes())
                self.assertTrue((child / '.git').is_file())

    def test_nested_path_cannot_cross_an_independent_repository(self) -> None:
        for index, source in enumerate(SOURCES):
            with self.subTest(source=source):
                parent = self.root / f'nested-boundary-{index}'
                middle = parent / 'OS@Extension'
                middle.mkdir(parents=True)
                self.git(middle, 'init', '-q', '-b', 'main')
                before = (middle / '.git/config').read_bytes()
                output = self.shell(source, f'cd {shlex.quote(str(parent))}\n' + r'''
if validate_local_path 'OS@Extension/WindowsOS@Extension'; then print UNEXPECTED_ACCEPTED; exit 93; fi
if ensure_submodule_worktree_present 'OS@Extension/WindowsOS@Extension'; then print UNEXPECTED_CREATED; exit 94; fi
''')
                self.assertNotIn('UNEXPECTED_', output)
                self.assertEqual(before, (middle / '.git/config').read_bytes())
                self.assertFalse((middle / 'WindowsOS@Extension').exists())

    def test_nested_symlink_components_inside_parent_are_rejected_before_mutation(self) -> None:
        for index, source in enumerate(SOURCES):
            with self.subTest(source=source):
                parent = self.root / f'component-links-{index}'
                target = parent / 'existing/child'
                target.mkdir(parents=True)
                self.git(parent, 'init', '-q')
                self.git(target, 'init', '-q')
                self.git(target, 'commit', '--allow-empty', '-qm', 'fixture')
                self.git(target, 'remote', 'add', 'origin', 'https://must-preserve.invalid/repo')
                (parent / 'shortcut').symlink_to(parent / 'existing', target_is_directory=True)
                (parent / 'deep').mkdir()
                (parent / 'deep/link').symlink_to(target, target_is_directory=True)
                before = {name: (target / '.git' / name).read_bytes() for name in ('HEAD', 'config')}
                output = self.shell(source, f'cd {shlex.quote(str(parent))}\n' + r'''
clone_url_for_path() { print UNEXPECTED_URL_LOOKUP; return 1; }
for selected in 'shortcut/child' 'deep/link' '.git/child' 'deep/.git/child'; do
  if sync_selected_submodules_to_latest "$selected"; then print UNEXPECTED_SUCCESS; exit 99; fi
done
''')
                self.assertNotIn('UNEXPECTED_', output)
                self.assertEqual(before, {name: (target / '.git' / name).read_bytes() for name in before})

    def test_initialized_entry_stops_before_completion_on_failure(self) -> None:
        for source in SOURCES:
            with self.subTest(source=source):
                output = self.shell(source, r'''
SCRIPT_FILE="$CASE_ROOT/fixture.command"
TMPDIR="$CASE_ROOT"
show_script_intro_and_wait() { return 0; }
prepare_parent_repository() { print EXPECTED_PARENT_FAILURE; return 37; }
synchronize_parent_repository() { print UNEXPECTED_PARENT_UPDATE; }
ensure_fzf_healthy() { print UNEXPECTED_INSTALL; }
prepare_preview_runtime() { print UNEXPECTED_PREVIEW; }
main_menu_loop() { print UNEXPECTED_MENU; }
report_completion() { print UNEXPECTED_SUCCESS; }
run_management_download
''', expected=37)
                self.assertIn('EXPECTED_PARENT_FAILURE', output)
                self.assertNotIn('UNEXPECTED_', output)

    def test_intro_refuses_noninteractive_before_log_or_environment_writes(self) -> None:
        for source in SOURCES:
            with self.subTest(source=source):
                output = self.shell(source, r'''show_script_intro_and_wait
print UNEXPECTED_CONTINUED
''', expected=1)
                self.assertIn('当前没有可交互输入', output)
                self.assertNotIn('UNEXPECTED_', output)
                self.assertFalse((self.root / 'output.log').exists())

    def test_real_nested_parent_reuses_worktree_and_owned_cache_and_commits_only_association(self) -> None:
        for i, source in enumerate(SOURCES):
            with self.subTest(source=source):
                parent, cache, bypass, leaf = self.fixture(f'reuse-{i}')
                self.assertTrue((parent / '.git').is_file())
                self.assertTrue((parent / '目标 child/.git').is_file())
                (cache / 'old-target.marker').write_text('old target cache')
                (bypass / 'bypass.marker').write_text('must stay')
                before = {p: hashlib.sha256((bypass / p).read_bytes()).hexdigest() for p in ('config', 'HEAD', 'bypass.marker')}
                output = self.shell(source, self.script_body(parent) + r'''full_sync_to_latest
[[ -f '目标 child/.git' ]]
expected_cache="$(git rev-parse --absolute-git-dir)/modules/real-section"
[[ "$(git -C '目标 child' rev-parse --absolute-git-dir)" == "$expected_cache" ]]
[[ -f "$expected_cache/old-target.marker" ]]
[[ "$(git config -f .gitmodules submodule.real-section.path)" == '目标 child' ]]
# 关联提交只包含目标 gitlink，原有其它暂存仍留在索引中。
print unrelated > unrelated-staged.txt
git add -- unrelated-staged.txt
staged_before="$(git ls-files --stage -- unrelated-staged.txt)"
git -C '目标 child' commit --allow-empty -qm 'local fixture commit'
expected_head="$(git -C '目标 child' rev-parse HEAD)"
AUTO_PARENT_COMMIT=1
stage_and_commit_parent_changes '目标 child'
[[ "$(git ls-files --stage -- unrelated-staged.txt)" == "$staged_before" ]]
[[ "$(git rev-parse 'HEAD:目标 child')" == "$expected_head" ]]
if git cat-file -e HEAD:unrelated-staged.txt 2>/dev/null; then exit 94; fi
[[ "$(git -c core.quotepath=false diff-tree --no-commit-id --name-only -r HEAD)" == '目标 child' ]]
''')
                self.assertIn('全量同步完成', output)
                self.assertEqual(before, {p: hashlib.sha256((bypass / p).read_bytes()).hexdigest() for p in before})

    def test_cache_ownership_symlinks_and_overlapping_modules_are_rejected(self) -> None:
        source = SOURCES[0]
        for mode in ('wrong-owner', 'symlink', 'overlap', 'linked-worktree'):
            with self.subTest(mode=mode):
                parent, cache, bypass, leaf = self.fixture(mode)
                (cache / 'keep.marker').write_text('keep target')
                (bypass / 'keep.marker').write_text('keep bypass')
                before = (cache / 'keep.marker').read_bytes()
                if mode == 'wrong-owner':
                    self.git(parent, 'config', '--file', str(cache / 'config'), 'core.worktree', str(parent / '旁路 child'))
                if mode == 'symlink':
                    saved = cache.with_name('saved-cache')
                    cache.rename(saved)
                    cache.symlink_to(bypass, target_is_directory=True)
                if mode == 'overlap':
                    self.git(parent, 'config', '-f', '.gitmodules', 'submodule.real-section/other.path', 'other')
                    self.git(parent, 'config', '-f', '.gitmodules', 'submodule.real-section/other.url', leaf.as_uri())
                if mode == 'linked-worktree':
                    (cache / 'worktrees').mkdir()
                    (cache / 'worktrees/other').mkdir()
                output = self.shell(source, self.script_body(parent) + "if submodule_cache_for_removal '目标 child'; then print UNEXPECTED_ACCEPTED; exit 95; fi\n")
                self.assertIn('拒绝复用', output)
                self.assertNotIn('UNEXPECTED_', output)
                self.assertEqual(b'keep bypass', (bypass / 'keep.marker').read_bytes())
                if mode != 'symlink':
                    self.assertEqual(before, (cache / 'keep.marker').read_bytes())

    def test_real_absorb_collision_stops_registration_and_update_success(self) -> None:
        for i, source in enumerate(SOURCES):
            with self.subTest(source=source):
                parent, cache, bypass, leaf = self.fixture(f'collision-{i}')
                self.git(parent, 'submodule', 'deinit', '-f', '--', '目标 child')
                target = parent / '目标 child'
                target.rmdir()
                self.git(parent, 'clone', '-q', leaf.as_uri(), '目标 child')
                self.assertTrue((target / '.git').is_dir())
                self.assertTrue(cache.is_dir())
                output = self.shell(source, self.script_body(parent) + r'''if ensure_submodule_worktree_present '目标 child'; then print UNEXPECTED_REGISTERED; exit 96; fi
if sync_one_submodule_to_latest '目标 child'; then print UNEXPECTED_SYNCED; exit 97; fi
''')
                self.assertIn('子模块元数据归集失败', output)
                self.assertNotIn('UNEXPECTED_', output)
                self.assertNotIn('已登记标准子模块', output)
                self.assertNotIn('已浅同步', output)
                self.assertTrue((target / '.git').is_dir())
                self.assertTrue(cache.is_dir())


    def test_fzf_navigation_never_runs_business_on_back_empty_or_cancel(self) -> None:
        for source in SOURCES:
            if "run_download_selection_loop()" not in source.read_text():
                continue
            with self.subTest(source=source):
                output = self.shell(source, r'''
CONFIG_PATHS=('目标 child' 'second child')
build_submodule_picker_content() { print preview; }
synchronize_parent_repository() { print UNEXPECTED_PARENT; }
reconcile_gitmodules_with_config_once() { print UNEXPECTED_RECONCILE; }
sync_selected_submodules_to_latest() { print UNEXPECTED_SYNC; }
stage_and_commit_parent_changes() { print UNEXPECTED_COMMIT; }
parent_push_if_needed() { print UNEXPECTED_PUSH; }
fzf() { cat >/dev/null; print -r -- left; return 1; }
picker_result=0
select_configured_submodules_interactive "$CASE_ROOT/preview" || picker_result=$?
[[ "$picker_result" == 2 ]]
select_submodule_recursion_interactive
[[ "$SUBMODULE_RECURSIVE" == 1 ]]
[[ "$(select_menu_action "$CASE_ROOT/preview")" == __JOBS_BACK_MODE__ ]]
fzf() { cat >/dev/null; return 130; }
picker_result=0
select_configured_submodules_interactive "$CASE_ROOT/preview" || picker_result=$?
[[ "$picker_result" == 130 ]]
fzf() { cat >/dev/null; print ''; }
picker_result=0
select_configured_submodules_interactive "$CASE_ROOT/preview" || picker_result=$?
[[ "$picker_result" == 2 ]]
fzf() { cat >/dev/null; return 2; }
picker_result=0
select_configured_submodules_interactive "$CASE_ROOT/preview" || picker_result=$?
[[ "$picker_result" == 1 ]]
''')
                self.assertNotIn("UNEXPECTED_", output)

    def test_mode_back_reopens_chooser_and_only_success_runs_optional_setup(self) -> None:
        for source in SOURCES:
            if "run_download_selection_loop()" not in source.read_text():
                continue
            with self.subTest(source=source):
                (self.root / "mode-counter").unlink(missing_ok=True)
                output = self.shell(source, r'''
select_download_operation_mode() { print CHOOSE_MODE; DOWNLOAD_OPERATION_MODE=readonly; }
run_selected_download_mode() {
 if [[ ! -f "$CASE_ROOT/mode-counter" ]]; then
  print 1 > "$CASE_ROOT/mode-counter"
  return 20
 fi
 print COMPLETED_DOWNLOAD
}
offer_global_markdown_toc_setup() { print OPTIONAL_SETUP; }
run_download_selection_loop
''')
                self.assertEqual(2, output.count("CHOOSE_MODE"))
                self.assertEqual(1, output.count("COMPLETED_DOWNLOAD"))
                self.assertEqual(1, output.count("OPTIONAL_SETUP"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
