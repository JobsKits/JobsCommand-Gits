#!/usr/bin/env python3
# Created by Jobs on 2026年10月27日，星期二.
"""Keep parent failures and dependency preparation inside the downloader's scope."""

from __future__ import annotations

from pathlib import Path
import re
import shlex
import unittest

import test_downloaders_latest as latest


class DownloaderBlueprintTests(unittest.TestCase):
    """Use disposable repositories; never update an installed package manager."""

    def setUp(self) -> None:
        self.fixture = latest.DownloaderLatestTests()
        self.fixture.setUp()
        self.root = self.fixture.root
        self.source = latest.GENESIS / latest.SCRIPT_NAME

    def tearDown(self) -> None:
        self.fixture.tearDown()

    def repository(self, name: str) -> Path:
        repository = self.root / name
        repository.mkdir()
        self.fixture.git(repository, "init", "-q", "-b", "main")
        (repository / "seed").write_text("base\n", encoding="utf-8")
        self.fixture.git(repository, "add", "seed")
        self.fixture.git(repository, "commit", "-qm", "base")
        return repository

    def test_parent_fetch_failure_prevents_rebase_and_child_work(self) -> None:
        repository = self.repository("fetch failure")
        output = self.fixture.shell(self.source, f'''
cd {shlex.quote(str(repository))}
run_cmd() {{
  if [[ "$*" == *' fetch '* ]]; then print FETCH_FAILED; return 37; fi
  print -r -- "UNEXPECTED $*"
}}
if parent_pull_rebase; then print UNEXPECTED_SUCCESS; exit 9; fi
''')
        self.assertIn("FETCH_FAILED", output)
        self.assertNotIn("UNEXPECTED", output)

    def test_parent_fetch_is_followed_by_local_rebase_without_second_network_call(self) -> None:
        repository = self.repository("one fetch")
        output = self.fixture.shell(self.source, f'''
cd {shlex.quote(str(repository))}
run_cmd() {{ print -r -- "OP $*"; }}
parent_pull_rebase
''')
        operations = [line for line in output.splitlines() if line.startswith("OP ")]
        self.assertEqual(1, sum(" fetch " in line for line in operations), output)
        self.assertEqual(1, sum(" rebase " in line for line in operations), output)
        self.assertFalse(any(" pull " in line or " ls-remote " in line for line in operations), output)

    def test_parent_rebase_conflict_is_a_failure_and_preserves_both_histories(self) -> None:
        remote = self.repository("remote")
        local = self.root / "local"
        self.fixture.git(self.root, "clone", "-q", remote.as_uri(), str(local))
        (local / "seed").write_text("local edit\n", encoding="utf-8")
        self.fixture.git(local, "commit", "-qam", "local edit")
        local_head = self.fixture.git(local, "rev-parse", "HEAD")
        (remote / "seed").write_text("remote edit\n", encoding="utf-8")
        self.fixture.git(remote, "commit", "-qam", "remote edit")
        remote_head = self.fixture.git(remote, "rev-parse", "HEAD")
        output = self.fixture.shell(self.source, f'''
cd {shlex.quote(str(local))}
if parent_pull_rebase; then print UNEXPECTED_SUCCESS; exit 9; fi
''')
        self.assertNotIn("UNEXPECTED_SUCCESS", output)
        self.assertEqual(local_head, self.fixture.git(local, "rev-parse", "refs/heads/main"))
        self.assertEqual(remote_head, self.fixture.git(local, "rev-parse", "refs/remotes/origin/main"))
        self.assertTrue((local / ".git/rebase-merge").is_dir())

    def test_healthy_homebrew_is_reused_without_updates_or_profile_writes(self) -> None:
        output = self.fixture.shell(self.source, r'''
jobs_brew_find() { print /unused/fake-homebrew; }
jobs_brew_activate() { print REUSED_HEALTHY_BREW; }
jobs_brew_install_or_exit() { print UNEXPECTED_INSTALL; return 9; }
run_cmd() { print -r -- "UNEXPECTED_COMMAND $*"; return 9; }
ensure_homebrew_healthy
[[ ! -e "$HOME/.zprofile" && ! -e "$HOME/.zshrc" ]]
''')
        self.assertIn("REUSED_HEALTHY_BREW", output)
        self.assertNotIn("UNEXPECTED", output)

    def test_renderer_exports_the_shared_engine_without_outer_maintenance_state(self) -> None:
        source = self.source.read_text(encoding="utf-8")
        engine = latest.render_readonly_engine(self.source)
        self.assertEqual(1, len(re.findall(r"^jobs_download_git\(\)", source, re.M)))
        self.assertEqual(1, len(re.findall(r"^jobs_download_git\s*\(\)", engine, re.M)))
        self.assertNotIn("SUBMODULE_REPO_URLS=", engine)
        self.assertNotIn("jobs_brew_install_or_exit", engine)
        self.assertNotRegex(engine, r"(?m)^git\s*\(\)")
        self.assertIn("main \"$@\"", engine)

    def test_unfinished_git_state_and_hidden_index_content_stop_before_discard(self) -> None:
        repository = self.repository("protected state")
        merge_head = repository / ".git/MERGE_HEAD"
        merge_head.write_text(self.fixture.git(repository, "rev-parse", "HEAD") + "\n")
        self.fixture.shell(self.source, f'''
if submodule_own_changes {shlex.quote(str(repository))}; then exit 9; fi
''')
        self.assertTrue(merge_head.is_file())
        merge_head.unlink()
        self.fixture.git(repository, "update-index", "--assume-unchanged", "seed")
        (repository / "seed").write_text("hidden user content\n", encoding="utf-8")
        self.fixture.shell(self.source, f'''
if submodule_own_changes {shlex.quote(str(repository))}; then exit 9; fi
''')
        self.assertEqual("hidden user content\n", (repository / "seed").read_text())


if __name__ == "__main__":
    unittest.main()
