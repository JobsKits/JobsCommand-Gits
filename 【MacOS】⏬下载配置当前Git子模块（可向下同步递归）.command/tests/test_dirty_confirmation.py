#!/usr/bin/env python3
# Created by Jobs on 2026年10月19日，星期一.
"""Verify per-repository confirmations through real PTYs and disposable local Git."""

from __future__ import annotations

import errno
import os
from pathlib import Path
import pty
import re
import select
import subprocess
import time
from typing import Callable
import unittest

import test_downloaders_latest as downloaders

PROMPT = '（Ctrl+C 取消）：'


class DirtyConfirmationTests(unittest.TestCase):
    """Keep real repositories and user Git configuration outside every fixture."""

    def setUp(self) -> None:
        self.fixture_tools = downloaders.DownloaderLatestTests('runTest')
        self.fixture_tools.setUp()
        self.root = self.fixture_tools.root

    def tearDown(self) -> None:
        self.fixture_tools.tearDown()

    def interactive(
        self, source: Path, body: str,
        actions: list[tuple[str, bytes | Callable[[], bytes]]], *, expected: int = 0,
    ) -> str:
        """Wait for each visible prompt before delivering its answer or external repair."""
        library = self.root / 'interactive-library.zsh'
        library.write_text(re.sub(r'(?m)^main "\$@"\s*$', '', source.read_text()), encoding='utf-8')
        setup = r'''setopt ERR_EXIT PIPE_FAIL NO_NOMATCH
source "$1"
shift
CASE_ROOT="$1"
LOG_FILE="$CASE_ROOT/output.log"
run_cmd() { printf '%s\n' "$*" >> "$CASE_ROOT/commands.log"; "$@"; }
'''
        master, slave = pty.openpty()
        env = dict(self.fixture_tools.env)
        env.pop('NO_COLOR', None)
        env['TERM'] = 'xterm-256color'
        process = subprocess.Popen(
            ['/bin/zsh', '-f', '-c', setup + body, 'offline-confirmation', str(library), str(self.root)],
            cwd=self.root, env=env, stdin=slave, stdout=slave, stderr=slave,
        )
        os.close(slave)
        chunks = bytearray()
        next_action = 0
        cursor = 0
        deadline = time.monotonic() + 20
        try:
            while True:
                if time.monotonic() >= deadline:
                    self.fail(f'{source}: confirmation timed out: {chunks.decode(errors="replace")}')
                ready, _, _ = select.select([master], [], [], 0.1)
                if ready:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        break
                    if not chunk:
                        break
                    chunks.extend(chunk)
                output = chunks.decode(errors='replace')
                while next_action < len(actions):
                    marker, action = actions[next_action]
                    match = output.find(marker, cursor)
                    if match == -1:
                        break
                    answer = action() if callable(action) else action
                    os.write(master, answer)
                    cursor = match + len(marker)
                    next_action += 1
                if process.poll() is not None and not ready:
                    break
            process.wait(timeout=3)
            self.assertEqual(expected, process.returncode, f'{source}: {chunks.decode(errors="replace")}')
            self.assertEqual(len(actions), next_action, 'the child skipped a required confirmation')
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=3)
            os.close(master)
        return chunks.decode().replace('\r\n', '\n')

    def fixture(self, name: str) -> tuple[Path, Path]:
        parent, _, _, leaf = self.fixture_tools.fixture(name)
        return parent, leaf

    def test_exact_yes_rechecks_other_answers_and_preserves_ignored_files(self) -> None:
        for index, source in enumerate(downloaders.SOURCES):
            with self.subTest(source=source):
                parent, _ = self.fixture(f'exact-{index}')
                target = parent / '目标 child'
                git = self.fixture_tools.git
                (target / '.gitignore').write_text('ignored.txt\n')
                git(target, 'add', '.gitignore')
                git(target, 'commit', '-qm', 'ignore fixture')
                (target / 'seed').write_text('unstaged content\n')
                (target / 'staged.txt').write_text('staged content\n')
                git(target, 'add', 'staged.txt')
                (target / 'untracked.txt').write_text('untracked content\n')
                (target / 'ignored.txt').write_text('must remain\n')

                def unchanged() -> bytes:
                    self.assertEqual('unstaged content\n', (target / 'seed').read_text())
                    self.assertTrue((target / 'staged.txt').is_file())
                    self.assertTrue((target / 'untracked.txt').is_file())
                    return b'YES\n'

                output = self.interactive(
                    source, self.fixture_tools.script_body(parent) + "assert_clean_submodule '目标 child' '测试更新'\n",
                    [(PROMPT, b'\n'), (PROMPT, b'yes\n'), (PROMPT, b'YES \n'), (PROMPT, unchanged)],
                )
                self.assertIn(f'仓库：{target}', output)
                self.assertGreaterEqual(output.count('未收到 YES'), 3)
                self.assertIn('\x1b[1;31m', output)
                self.assertNotIn('\x1b', (self.root / 'output.log').read_text())
                self.assertEqual('leaf\n', (target / 'seed').read_text())
                self.assertFalse((target / 'staged.txt').exists())
                self.assertFalse((target / 'untracked.txt').exists())
                self.assertEqual('must remain\n', (target / 'ignored.txt').read_text())
                commands = (self.root / 'commands.log').read_text().splitlines()
                resets = [line for line in commands if ' reset ' in line]
                cleans = [line for line in commands if ' clean ' in line]
                self.assertTrue(resets and all('submodule.recurse=false reset --hard HEAD' in line for line in resets))
                self.assertTrue(cleans and all('submodule.recurse=false clean -fd --' in line for line in cleans))

    def test_external_repair_then_enter_continues_without_cleanup(self) -> None:
        for index, source in enumerate(downloaders.SOURCES):
            with self.subTest(source=source):
                parent, _ = self.fixture(f'external-{index}')
                target = parent / '目标 child'
                (target / 'seed').write_text('user edit\n')

                def repair() -> bytes:
                    self.fixture_tools.git(target, 'restore', '--', 'seed')
                    return b'\n'

                commands = self.root / 'commands.log'
                commands.unlink(missing_ok=True)
                output = self.interactive(
                    source, self.fixture_tools.script_body(parent) + "assert_clean_submodule '目标 child' '测试更新'\n",
                    [(PROMPT, b'wrong\n'), (PROMPT, repair)],
                )
                self.assertGreaterEqual(output.count('未收到 YES'), 2)
                self.assertFalse(commands.exists())
                self.assertEqual('', self.fixture_tools.git(target, 'status', '--porcelain'))

    def test_each_nested_repository_requires_its_own_yes_even_when_association_is_removed(self) -> None:
        for index, source in enumerate(downloaders.SOURCES):
            with self.subTest(source=source):
                parent, leaf = self.fixture(f'nested-{index}')
                target = parent / '目标 child'
                git = self.fixture_tools.git
                git(target, 'submodule', 'add', '-q', leaf.as_uri(), '深层 child')
                git(target, 'commit', '-qam', 'nested fixture')
                descendant = target / '深层 child'
                (target / 'seed').write_text('parent edit\n')
                (descendant / 'seed').write_text('nested edit\n')
                git(target, 'rm', '--cached', '--', '深层 child')
                (target / '.gitmodules').unlink()
                git(target, 'add', '.gitmodules')

                def second_confirmation() -> bytes:
                    self.assertEqual('leaf\n', (target / 'seed').read_text())
                    self.assertEqual('nested edit\n', (descendant / 'seed').read_text())
                    return b'YES\n'

                output = self.interactive(
                    source, self.fixture_tools.script_body(parent) + "assert_clean_submodule '目标 child' '测试更新'\n",
                    [(PROMPT, b'YES\n'), (PROMPT, second_confirmation)],
                )
                self.assertIn(f'仓库：{target}', output)
                self.assertIn(f'仓库：{descendant}', output)
                self.assertEqual(2, output.count('已按 YES 放弃当前仓未提交内容'))
                self.assertEqual('leaf\n', (descendant / 'seed').read_text())
                self.assertEqual('', git(target, 'status', '--porcelain'))

    def test_eof_and_dry_run_preserve_dirty_content(self) -> None:
        for index, source in enumerate(downloaders.SOURCES):
            with self.subTest(source=source):
                parent, _ = self.fixture(f'eof-{index}')
                target = parent / '目标 child'
                (target / 'seed').write_text('keep this edit\n')
                body = self.fixture_tools.script_body(parent) + "assert_clean_submodule '目标 child' '测试更新'\n"
                output = self.interactive(source, body, [(PROMPT, b'\x04')], expected=1)
                self.assertIn('输入已结束', output)
                self.assertEqual('keep this edit\n', (target / 'seed').read_text())
                output = self.fixture_tools.shell(source, 'DRY_RUN=1\n' + body, expected=1)
                self.assertIn('未执行清理', output)
                self.assertEqual('keep this edit\n', (target / 'seed').read_text())
                output = self.interactive(source, 'DRY_RUN=1\n' + body, [], expected=1)
                self.assertIn('未执行清理', output)
                self.assertEqual('keep this edit\n', (target / 'seed').read_text())

    def test_untracked_independent_git_survives_yes_and_waits_for_external_resolution(self) -> None:
        for index, source in enumerate(downloaders.SOURCES):
            with self.subTest(source=source):
                parent, _ = self.fixture(f'independent-{index}')
                target = parent / '目标 child'
                independent = target / '独立 Git'
                independent.mkdir()
                git = self.fixture_tools.git
                git(independent, 'init', '-q', '-b', 'main')
                (independent / 'seed').write_text('independent content\n')
                git(independent, 'add', 'seed')
                git(independent, 'commit', '-qm', 'independent fixture')
                expected_head = git(independent, 'rev-parse', 'HEAD')
                (target / 'seed').write_text('discard parent only\n')

                def resolve_independent() -> bytes:
                    self.assertTrue((independent / '.git').is_dir())
                    self.assertEqual(expected_head, git(independent, 'rev-parse', 'HEAD'))
                    exclude = Path(git(target, 'rev-parse', '--absolute-git-dir')) / 'info/exclude'
                    with exclude.open('a') as stream:
                        stream.write('\n/独立 Git/\n')
                    return b'\n'

                self.interactive(
                    source, self.fixture_tools.script_body(parent) + "assert_clean_submodule '目标 child' '测试更新'\n",
                    [(PROMPT, b'YES\n'), (PROMPT, resolve_independent)],
                )
                self.assertEqual('independent content\n', (independent / 'seed').read_text())
                self.assertEqual(expected_head, git(independent, 'rev-parse', 'HEAD'))

    def test_cached_index_refs_and_configuration_survive_missing_worktree_recovery(self) -> None:
        for index, source in enumerate(downloaders.SOURCES):
            with self.subTest(source=source):
                parent, _ = self.fixture(f'cached-index-{index}')
                target = parent / '目标 child'
                git = self.fixture_tools.git
                cache = Path(git(target, 'rev-parse', '--absolute-git-dir'))
                (target / 'seed').write_text('staged cached content\n')
                git(target, 'add', 'seed')
                git(target, 'update-ref', 'refs/heads/local-backup', 'HEAD')
                git(target, 'update-ref', 'refs/stash', 'HEAD')
                git(target, 'config', 'jobs.preserve', 'local-configuration')
                (cache / 'must-keep.marker').write_text('metadata marker\n')
                protected = ('HEAD', 'config', 'refs/heads/local-backup', 'refs/stash', 'must-keep.marker')
                before = {name: (cache / name).read_bytes() for name in protected}
                staged_before = git(target, 'ls-files', '--stage')
                target.rename(self.root / f'saved-worktree-{index}')
                output = self.fixture_tools.shell(
                    source, self.fixture_tools.script_body(parent) + "ensure_submodule_worktree_present '目标 child'\n",
                    expected=1,
                )
                self.assertIn('复用已有 Git 缓存', output)
                self.assertIn('已暂存', output)
                self.assertNotIn('首次克隆', output)
                self.assertEqual(before, {name: (cache / name).read_bytes() for name in protected})
                self.assertEqual(staged_before, git(target, 'ls-files', '--stage'))
                self.assertTrue((target / '.git').is_file())
                self.assertEqual('staged cached content\n', (target / 'seed').read_text())
                self.assertEqual(str(cache), git(target, 'rev-parse', '--absolute-git-dir'))

    def test_first_use_empty_and_missing_paths_clone_without_removing_legacy_folders(self) -> None:
        source = downloaders.SOURCES[0]
        for mode in ('empty', 'missing'):
            with self.subTest(mode=mode):
                parent, leaf = self.fixture(f'first-use-{mode}')
                target = parent / '新 child'
                if mode == 'empty':
                    target.mkdir()
                legacy = parent / 'LegacyRepo'
                legacy.mkdir()
                (legacy / 'must-keep.txt').write_text('legacy data\n')
                git = self.fixture_tools.git
                git(parent, 'config', '-f', '.gitmodules', 'submodule.fresh.path', target.name)
                git(parent, 'config', '-f', '.gitmodules', 'submodule.fresh.url', leaf.as_uri())
                output = self.fixture_tools.shell(
                    source, self.fixture_tools.script_body(parent) + f"ensure_submodule_worktree_present '新 child' '{leaf.as_uri()}'\n",
                )
                self.assertIn('首次克隆', output)
                self.assertEqual(git(leaf, 'rev-parse', 'HEAD'), git(target, 'rev-parse', 'HEAD'))
                self.assertTrue((target / '.git').is_file())
                self.assertEqual('legacy data\n', (legacy / 'must-keep.txt').read_text())


if __name__ == '__main__':
    unittest.main(verbosity=2)
