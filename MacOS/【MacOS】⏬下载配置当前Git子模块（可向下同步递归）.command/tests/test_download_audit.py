#!/usr/bin/env python3
# Created by Jobs on 2026年10月27日，星期二.
"""Targeted interrupted-download and state-protection regressions using file-only Git."""

from __future__ import annotations

from pathlib import Path
import os
import pty
import re
import shlex
import shutil
import subprocess
import unittest

import test_download_resume as resume


class DownloadAuditTests(unittest.TestCase):
    """Keep each reproducer independent from real repositories and user configuration."""

    def setUp(self) -> None:
        self.tools = resume.DownloadResumeTests("runTest")
        self.tools.setUp()
        self.root = self.tools.root
        self.env = self.tools.env
        snapshot = self.root / "source.command"
        snapshot.write_text(self.tools.source.read_text(encoding="utf-8"), encoding="utf-8")
        self.tools.source = snapshot

    def tearDown(self) -> None:
        self.tools.tearDown()

    def fixture(self, *, initialized: bool = False) -> tuple[Path, Path, Path]:
        child_remote = self.tools.repository("child-remote")
        parent_remote = self.tools.repository("parent-remote")
        self.tools.git(parent_remote, "submodule", "add", "-q", "--name", "child-section", child_remote.as_uri(), "child")
        self.tools.git(parent_remote, "config", "-f", ".gitmodules", "submodule.child-section.branch", "main")
        self.tools.git(parent_remote, "commit", "-qam", "register child")
        parent = self.root / "parent"
        self.tools.git(self.root, "clone", "-q", "--no-recurse-submodules", parent_remote.as_uri(), str(parent))
        if initialized:
            self.tools.git(parent, "submodule", "update", "--init")
            self.tools.git(parent / "child", "checkout", "-q", "main")
        return parent, child_remote, parent_remote

    def management_body(self, child_remote: Path) -> str:
        return f'''SUBMODULE_RECURSIVE=0
SUBMODULE_SHALLOW_CLONE=1
SUBMODULE_DEPTH=1
SUBMODULE_FETCH_TAGS=0
GIT_URL_STYLE=auto
REMOTE_NAME=origin
sync_one_submodule_to_latest child {shlex.quote(child_remote.as_uri())} main
'''

    def discard_with_yes(self, repo: Path) -> str:
        library = self.root / "discard-library.zsh"
        library.write_text(re.sub(r'(?m)^main "\$@"\s*$', "", self.tools.source.read_text()), encoding="utf-8")
        body = r'''setopt PIPE_FAIL NO_NOMATCH
source "$1"
LOG_FILE="$2"
DRY_RUN=0
SUBMODULE_RECURSIVE=0
if wait_for_clean_submodule "$PWD" 更新; then print DONE; else print BLOCKED; fi
'''
        master, slave = pty.openpty()
        process = subprocess.Popen(
            ["/bin/zsh", "-f", "-c", body, "offline-discard", str(library), str(self.root / "discard.log")],
            cwd=repo, env=self.env, stdin=slave, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        os.close(slave)
        try:
            os.write(master, b"YES\n\x04")
            stdout, stderr = process.communicate(timeout=15)
            self.assertEqual(0, process.returncode, stdout + stderr)
            return stdout + stderr
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate(timeout=5)
            os.close(master)

    def test_readonly_finishes_registration_after_checkout_was_interrupted(self) -> None:
        parent, child_remote, _ = self.fixture()
        child = parent / "child"
        # This is the state between first checkout and parent registration/absorbgitdirs.
        self.tools.git(parent, "clone", "-q", "--no-recurse-submodules", child_remote.as_uri(), str(child))
        self.assertTrue((child / ".git").is_dir())
        code, output = self.tools.engine(parent)
        self.assertEqual(0, code, output)
        self.assertTrue((child / ".git").is_file(), "success left an unabsorbed child repository: " + output)
        self.assertEqual(child_remote.as_uri(), self.tools.git(parent, "config", "--get", "submodule.child-section.url"))
        self.assertEqual("true", self.tools.git(parent, "config", "--get", "submodule.child-section.active"))
        self.assertFalse(self.tools.git(parent, "submodule", "status").startswith("-"))

    def test_management_preserves_assume_unchanged_user_content(self) -> None:
        parent, child_remote, _ = self.fixture(initialized=True)
        child = parent / "child"
        old_head = self.tools.git(child, "rev-parse", "HEAD")
        self.tools.git(child, "update-index", "--assume-unchanged", "seed")
        (child / "seed").write_text("uncommitted hidden user content\n", encoding="utf-8")
        self.tools.commit(child_remote, "remote changes same file")
        output = self.tools.shell(
            "if {\n" + self.management_body(child_remote) + "}; then exit 91; fi\n", cwd=parent,
        )
        self.assertEqual("uncommitted hidden user content\n", (child / "seed").read_text(), output)
        self.assertEqual(old_head, self.tools.git(child, "rev-parse", "HEAD"), output)

    def test_readonly_resumes_its_own_first_checkout_failure(self) -> None:
        parent, _, _ = self.fixture()
        child = parent / "child"
        binary_dir = self.root / "bin"
        binary_dir.mkdir()
        shim = binary_dir / "git"
        shim.write_text(r'''#!/bin/sh
repository=
operation=
previous=
for argument in "$@"; do
  if [ "$previous" = -C ]; then repository="$argument"; fi
  if [ "$argument" = checkout ]; then operation=checkout; fi
  previous="$argument"
done
if [ "$operation" = checkout ]; then
  printf '%s\n' 'simulated interruption before first checkout' >&2
  exit 143
fi
exec /usr/bin/git "$@"
''', encoding="utf-8")
        shim.chmod(0o755)
        env = dict(self.env, PATH=f"{binary_dir}:{self.env['PATH']}", JOBS_AUDIT_CHILD=str(child))
        code, first_output = self.tools.engine(parent, env)
        self.assertNotEqual(0, code, first_output)
        self.assertFalse((child / ".git").exists(), first_output)
        self.assertTrue(not child.exists() or not any(child.iterdir()), first_output)
        self.assertFalse((child / "seed").exists(), first_output)
        code, output = self.tools.engine(parent)
        self.assertEqual(0, code, "first run:\n" + first_output + "\nretry:\n" + output)
        self.assertTrue((child / "seed").is_file())
        self.assertTrue((child / ".git").is_file())

    def test_management_fetch_tags_is_honored_when_branch_head_does_not_change(self) -> None:
        parent, child_remote, _ = self.fixture(initialized=True)
        self.tools.shell(self.management_body(child_remote), cwd=parent)
        self.tools.git(child_remote, "tag", "release-after-first-sync")
        body = self.management_body(child_remote).replace("SUBMODULE_FETCH_TAGS=0", "SUBMODULE_FETCH_TAGS=1")
        self.tools.shell(body, cwd=parent)
        self.assertEqual(
            self.tools.git(child_remote, "rev-parse", "refs/tags/release-after-first-sync"),
            self.tools.git(parent / "child", "rev-parse", "refs/tags/release-after-first-sync"),
        )

    def test_management_yes_preserves_ignored_path_blocking_tracked_directory(self) -> None:
        repo = self.tools.repository("repository")
        directory = repo / "folder"
        directory.mkdir()
        (directory / "seed").write_text("tracked data\n", encoding="utf-8")
        self.tools.git(repo, "add", "folder/seed")
        self.tools.git(repo, "commit", "-qm", "track nested file")
        shutil.rmtree(directory)
        directory.write_text("must preserve ignored file\n", encoding="utf-8")
        git_directory = Path(self.tools.git(repo, "rev-parse", "--absolute-git-dir"))
        (git_directory / "info/exclude").write_text("folder\n", encoding="utf-8")
        output = self.discard_with_yes(repo)
        self.assertTrue(directory.is_file(), "YES removed an ignored path: " + output)
        self.assertEqual("must preserve ignored file\n", directory.read_text(), output)

    def test_management_yes_preserves_nested_repository_worktree(self) -> None:
        repo = self.tools.repository("repository")
        nested = repo / "nested"
        nested.mkdir()
        (nested / "seed").write_text("parent tracked file\n", encoding="utf-8")
        self.tools.git(repo, "add", "nested/seed")
        self.tools.git(repo, "commit", "-qm", "track nested file")
        self.tools.git(nested, "init", "-q", "-b", "main")
        (nested / "seed").write_text("nested repository committed file\n", encoding="utf-8")
        self.tools.git(nested, "add", "seed")
        self.tools.git(nested, "commit", "-qm", "own nested content")
        (nested / "seed").write_text("uncommitted nested user content\n", encoding="utf-8")
        nested_head = self.tools.git(nested, "rev-parse", "HEAD")
        output = self.discard_with_yes(repo)
        self.assertEqual("uncommitted nested user content\n", (nested / "seed").read_text(), output)
        self.assertEqual(nested_head, self.tools.git(nested, "rev-parse", "HEAD"))

    def test_management_yes_preserves_untracked_nested_bare_repository(self) -> None:
        repo = self.tools.repository("repository")
        remote = self.tools.repository("independent-source")
        nested = repo / "independent.git"
        self.tools.git(repo, "clone", "-q", "--bare", remote.as_uri(), str(nested))
        nested_head = self.tools.git(nested, "rev-parse", "HEAD")
        output = self.discard_with_yes(repo)
        self.assertTrue(nested.is_dir(), "YES removed a nested bare repository: " + output)
        self.assertEqual(nested_head, self.tools.git(nested, "rev-parse", "HEAD"))

    def test_empty_private_cache_is_reinitialized_without_discarding_user_data(self) -> None:
        parent = self.tools.repository("parent")
        remote = self.tools.repository("remote")
        body = f'jobs_download_cache_repository "$PWD" "$PWD/child" {shlex.quote(remote.as_uri())}\n'
        cache = Path(self.tools.shell(body, cwd=parent).strip().splitlines()[-1])
        for entry in cache.iterdir():
            if entry.is_dir():
                shutil.rmtree(entry)
            else:
                entry.unlink()
        self.assertTrue(cache.is_dir())
        self.assertFalse(any(cache.iterdir()))
        output = self.tools.shell(body, cwd=parent)
        self.assertEqual(cache, Path(output.strip().splitlines()[-1]))
        self.assertEqual("true", self.tools.git(cache, "rev-parse", "--is-bare-repository"))

    def test_invalid_nonempty_cache_is_preserved_for_manual_inspection(self) -> None:
        parent = self.tools.repository("parent")
        remote = self.tools.repository("remote")
        body = f'jobs_download_cache_repository "$PWD" "$PWD/child" {shlex.quote(remote.as_uri())}\n'
        cache = Path(self.tools.shell(body, cwd=parent).strip().splitlines()[-1])
        for entry in cache.iterdir():
            if entry.is_dir():
                shutil.rmtree(entry)
            else:
                entry.unlink()
        sentinel = cache / "unknown-user-data"
        sentinel.write_text("must stay untouched\n", encoding="utf-8")
        self.tools.shell("if " + body.strip() + "; then exit 91; fi\n", cwd=parent)
        self.assertEqual("must stay untouched\n", sentinel.read_text())
        self.assertEqual([sentinel], list(cache.iterdir()))


if __name__ == "__main__":
    unittest.main(verbosity=2)
