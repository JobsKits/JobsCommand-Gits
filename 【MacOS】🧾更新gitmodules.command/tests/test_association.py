#!/usr/bin/env python3
# Created by Jobs on 2026年10月15日，星期四.
"""Exercise only disposable Git repositories against a copied updater script."""

from __future__ import annotations

import argparse
import errno
import hashlib
import os
from pathlib import Path
import pty
import select
import shutil
import subprocess
import sys
import tempfile
import time
import unittest


SCRIPT_SOURCE: Path
ARTIFACT_ROOT = Path(tempfile.mkdtemp(prefix="jobs-gitmodules-integration-"))
SCRIPT_NAME = "【MacOS】🧾更新gitmodules.command"


def tree_fingerprint(root: Path) -> dict[str, str]:
    """Record contents and symlink targets without treating access times as changes."""
    result: dict[str, str] = {}
    if not root.exists():
        return result
    for path in sorted(root.rglob("*")):
        relative = str(path.relative_to(root))
        if path.is_symlink():
            result[relative] = f"symlink:{os.readlink(path)}"
        elif path.is_file():
            result[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


class AssociationTests(unittest.TestCase):
    """Verify repository linkage and preservation using the actual Git executable."""

    def setUp(self) -> None:
        self.sandbox = Path(tempfile.mkdtemp(prefix=f"{self._testMethodName}-", dir=ARTIFACT_ROOT))
        self.parent = self.sandbox / "父 仓库"
        self.home = self.sandbox / "home"
        self.home.mkdir()
        self.tmp = self.sandbox / "logs"
        self.tmp.mkdir()
        self.env = dict(os.environ)
        for key in list(self.env):
            if key.startswith("GIT_"):
                del self.env[key]
        self.env.update(
            HOME=str(self.home),
            XDG_CONFIG_HOME=str(self.home / "xdg"),
            GIT_CONFIG_NOSYSTEM="1",
            GIT_CONFIG_GLOBAL=str(self.home / "empty-gitconfig"),
            GIT_TERMINAL_PROMPT="0",
            GIT_AUTHOR_NAME="Isolated Integration Test",
            GIT_AUTHOR_EMAIL="isolated@example.invalid",
            GIT_COMMITTER_NAME="Isolated Integration Test",
            GIT_COMMITTER_EMAIL="isolated@example.invalid",
            GIT_ALLOW_PROTOCOL="file",
            TMPDIR=str(self.tmp) + "/",
            TERM="dumb",
            NO_COLOR="1",
        )
        self.init_repo(self.parent)
        self.install_script(self.parent)

    def tearDown(self) -> None:
        """Successful, refused, and interrupted runs must release their owned resources."""
        self.assertFalse((self.gitdir(self.parent) / "jobs-gitmodules.lock").exists(), "script lock leaked")
        self.assertEqual([], list(self.tmp.glob("jobs-gitmodules.*")), "temporary plan directory leaked")

    def git(self, repo: Path, *args: str, check: bool = True) -> str:
        """Run Git with isolated identity, configuration, hooks, and protocols."""
        process = subprocess.run(
            ["git", "-c", "core.hooksPath=/dev/null", "-C", str(repo), *args],
            env=self.env,
            capture_output=True,
            text=True,
            check=False,
        )
        if check and process.returncode:
            self.fail(f"git {args} failed ({process.returncode}): {process.stdout}{process.stderr}")
        return process.stdout.rstrip("\n")

    def init_repo(self, path: Path, *, commit: bool = True, origin: bool = True) -> Path:
        """Create a disposable repository with an optional initial commit and remote."""
        path.mkdir(parents=True, exist_ok=True)
        self.git(path, "init", "-b", "main")
        self.git(path, "config", "core.logAllRefUpdates", "true")
        self.git(path, "config", "core.quotePath", "false")
        if origin:
            self.git(path, "remote", "add", "origin", f"https://example.invalid/Jobs/{path.name}.git")
        if commit:
            (path / "seed.txt").write_text("initial content\n", encoding="utf-8")
            self.git(path, "add", "seed.txt")
            self.git(path, "commit", "-m", "test fixture initial commit")
        return path

    def install_script(self, parent: Path) -> Path:
        """Place the candidate in the repository root, as the deployed entrypoint is used."""
        script = parent / SCRIPT_NAME
        shutil.copyfile(SCRIPT_SOURCE, script)
        return script

    def child(self, name: str = "子 仓库", **kwargs: bool) -> Path:
        """Create a direct child repository with a path requiring robust quoting."""
        return self.init_repo(self.parent / name, **kwargs)

    def gitdir(self, repo: Path) -> Path:
        """Resolve .git indirection for parents that are themselves absorbed submodules."""
        return Path(self.git(repo, "rev-parse", "--absolute-git-dir"))

    def index(self, repo: Path | None = None) -> bytes:
        """Capture the exact staged entries rather than the worktree's porcelain summary."""
        target = repo or self.parent
        return subprocess.check_output(
            ["git", "-C", str(target), "ls-files", "--stage", "-z"], env=self.env
        )

    def head(self, repo: Path) -> str:
        """Return the currently checked out commit without changing it."""
        return self.git(repo, "rev-parse", "HEAD")

    def run_script(
        self, *args: str, parent: Path | None = None,
        confirmation: bytes = b"\ny\n\n", entrypoint: Path | None = None,
    ) -> tuple[int, str]:
        """Use a pseudo-terminal for the ordinary confirmation, never a bypass flag."""
        target = parent or self.parent
        script = entrypoint or target / SCRIPT_NAME
        master, slave = pty.openpty()
        process = subprocess.Popen(
            ["/bin/zsh", str(script), *args],
            cwd=self.sandbox,
            env=self.env,
            stdin=slave,
            stdout=slave,
            stderr=slave,
            start_new_session=True,
        )
        os.close(slave)
        output = bytearray()
        started = time.monotonic()
        confirmed = False
        while True:
            if not confirmed and time.monotonic() - started > 0.15:
                os.write(master, confirmation)
                confirmed = True
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
                output.extend(chunk)
            elif process.poll() is not None:
                break
            if time.monotonic() - started > 25:
                process.kill()
                process.wait()
                self.fail(f"Script timed out: {output.decode(errors='replace')}")
        os.close(master)
        code = process.wait(timeout=5)
        decoded = output.decode("utf-8", errors="replace")
        (self.sandbox / f"run-{len(list(self.sandbox.glob('run-*.log'))) + 1}.log").write_text(decoded)
        if code == 0:
            self.assertNotIn("\nfatal:", decoded, "Git reported a fatal error despite a successful script exit")
        return code, decoded

    def register(self, child: Path, *, section: str | None = None, url: str | None = None) -> None:
        """Construct a real submodule registration without cloning or network access."""
        relative = str(child.relative_to(self.parent))
        section = section or relative
        url = url or self.git(child, "remote", "get-url", "origin")
        self.git(self.parent, "config", "-f", ".gitmodules", f"submodule.{section}.path", relative)
        self.git(self.parent, "config", "-f", ".gitmodules", f"submodule.{section}.url", url)
        self.git(self.parent, "add", ".gitmodules")
        self.git(self.parent, "update-index", "--add", "--cacheinfo", f"160000,{self.head(child)},{relative}")
        self.git(self.parent, "submodule", "init", "--", relative)
        self.git(self.parent, "submodule", "absorbgitdirs", "--", relative)

    def assert_linked(self, child: Path, *, section: str | None = None) -> None:
        """Check gitlink, absorbed metadata, and Git's actual parent relationship."""
        relative = str(child.relative_to(self.parent))
        stage = self.git(self.parent, "--literal-pathspecs", "ls-files", "--stage", "--", relative)
        self.assertEqual(f"160000 {self.head(child)} 0\t{relative}", stage)
        self.assertTrue((child / ".git").is_file(), "child metadata was not absorbed")
        self.assertEqual((self.gitdir(self.parent) / "modules" / (section or relative)).resolve(), self.gitdir(child).resolve())
        superproject = self.git(child, "rev-parse", "--show-superproject-working-tree")
        self.assertEqual(self.parent.resolve(), Path(superproject).resolve())
        self.git(self.parent, "--literal-pathspecs", "submodule", "status", "--", relative)

    def test_new_child_preserves_dirty_source_index_history_and_remotes(self) -> None:
        child = self.child()
        (child / "seed.txt").write_text("staged change\n")
        self.git(child, "add", "seed.txt")
        (child / "seed.txt").write_text("staged change\nplus unstaged change\n")
        (child / "未跟踪文件.txt").write_text("keep me\n")
        before = (self.head(child), self.index(child), self.git(child, "diff"), self.git(child, "remote", "-v"))
        before_parent_head = self.head(self.parent)
        code, output = self.run_script()
        self.assertEqual(0, code, output)
        self.assert_linked(child)
        self.assertEqual(before, (self.head(child), self.index(child), self.git(child, "diff"), self.git(child, "remote", "-v")))
        self.assertEqual("keep me\n", (child / "未跟踪文件.txt").read_text())
        self.assertEqual(before_parent_head, self.head(self.parent))

    def test_existing_gitmodules_without_gitlink_is_repaired(self) -> None:
        child = self.child()
        self.git(self.parent, "config", "-f", ".gitmodules", "submodule.existing name.path", child.name)
        self.git(self.parent, "config", "-f", ".gitmodules", "submodule.existing name.url", "../relative.git")
        self.git(self.parent, "add", ".gitmodules")
        self.git(self.parent, "commit", "-m", "register metadata only")
        code, output = self.run_script()
        self.assertEqual(0, code, output)
        self.assert_linked(child, section="existing name")
        self.assertEqual("../relative.git", self.git(self.parent, "config", "-f", ".gitmodules", "submodule.existing name.url"))

    def test_untracked_gitmodules_without_gitlink_is_staged_and_repaired(self) -> None:
        child = self.child()
        self.git(self.parent, "config", "-f", ".gitmodules", "submodule.untracked metadata.path", child.name)
        self.git(self.parent, "config", "-f", ".gitmodules", "submodule.untracked metadata.url", "../relative.git")
        with (self.parent / ".gitmodules").open("a") as stream:
            stream.write("# custom comment survives association\n")
        before = (self.parent / ".gitmodules").read_bytes()
        code, output = self.run_script()
        self.assertEqual(0, code, output)
        self.assert_linked(child, section="untracked metadata")
        self.assertEqual(before, (self.parent / ".gitmodules").read_bytes())
        staged = subprocess.check_output(["git", "-C", str(self.parent), "show", ":.gitmodules"], env=self.env)
        self.assertEqual(before, staged)

    def test_untracked_gitmodules_is_staged_when_every_other_association_is_complete(self) -> None:
        child = self.child()
        self.register(child, section="complete association", url="../relative.git")
        self.git(self.parent, "rm", "--cached", "--", ".gitmodules")
        before_metadata = (self.parent / ".gitmodules").read_bytes()
        before_child_gitdir = self.gitdir(child)
        before_config = (self.gitdir(self.parent) / "config").read_bytes()
        code, output = self.run_script()
        self.assertEqual(0, code, output)
        self.assert_linked(child, section="complete association")
        staged = subprocess.check_output(["git", "-C", str(self.parent), "show", ":.gitmodules"], env=self.env)
        self.assertEqual(before_metadata, staged)
        self.assertEqual(before_child_gitdir, self.gitdir(child))
        self.assertEqual(before_config, (self.gitdir(self.parent) / "config").read_bytes())

    def test_second_new_child_registers_after_successful_first_run(self) -> None:
        first = self.child("first child")
        code, output = self.run_script()
        self.assertEqual(0, code, output)
        self.assert_linked(first)
        self.assertFalse((self.gitdir(self.parent) / "jobs-gitmodules.lock").exists())
        second = self.child("second child")
        code, output = self.run_script()
        self.assertEqual(0, code, output)
        self.assert_linked(first)
        self.assert_linked(second)

    def test_same_named_wrapper_directory_resolves_parent_repository(self) -> None:
        child = self.child()
        original = self.parent / SCRIPT_NAME
        script_bytes = original.read_bytes()
        original.unlink()
        original.mkdir()
        wrapped_script = original / SCRIPT_NAME
        wrapped_script.write_bytes(script_bytes)
        code, output = self.run_script(entrypoint=wrapped_script)
        self.assertEqual(0, code, output)
        self.assert_linked(child)

    def test_unknown_argument_fails_before_runtime_initialization_or_git_changes(self) -> None:
        child = self.child()
        before_parent = tree_fingerprint(self.gitdir(self.parent))
        before_child = tree_fingerprint(child / ".git")
        before_tmp = tree_fingerprint(self.tmp)
        process = subprocess.run(
            ["/bin/zsh", str(self.parent / SCRIPT_NAME), "--unknown-option"],
            cwd=self.sandbox, env=self.env, input="y\n", capture_output=True,
            text=True, timeout=25,
        )
        self.assertNotEqual(0, process.returncode, process.stdout + process.stderr)
        self.assertEqual(before_parent, tree_fingerprint(self.gitdir(self.parent)))
        self.assertEqual(before_child, tree_fingerprint(child / ".git"))
        self.assertEqual(before_tmp, tree_fingerprint(self.tmp))
        self.assertFalse((self.parent / ".gitmodules").exists())

    def test_staged_gitmodules_deletion_is_preserved_and_run_refused(self) -> None:
        child = self.child()
        self.register(child)
        self.git(self.parent, "commit", "-m", "registered baseline")
        self.git(self.parent, "rm", "--cached", "--", ".gitmodules")
        before_index = self.index()
        before_metadata = (self.parent / ".gitmodules").read_bytes()
        before_parent_git = tree_fingerprint(self.gitdir(self.parent))
        code, output = self.run_script()
        self.assertNotEqual(0, code, output)
        self.assertEqual(before_index, self.index())
        self.assertEqual(before_metadata, (self.parent / ".gitmodules").read_bytes())
        self.assertEqual(before_parent_git, tree_fingerprint(self.gitdir(self.parent)))

    def test_staged_child_gitlink_deletion_is_preserved_and_run_refused(self) -> None:
        child = self.child()
        self.register(child)
        self.git(self.parent, "commit", "-m", "registered baseline")
        self.git(self.parent, "update-index", "--force-remove", "--", child.name)
        before_index = self.index()
        before_metadata = (self.parent / ".gitmodules").read_bytes()
        before_parent_git = tree_fingerprint(self.gitdir(self.parent))
        code, output = self.run_script()
        self.assertNotEqual(0, code, output)
        self.assertEqual(before_index, self.index())
        self.assertEqual(before_metadata, (self.parent / ".gitmodules").read_bytes())
        self.assertEqual(before_parent_git, tree_fingerprint(self.gitdir(self.parent)))

    def test_section_metadata_prefix_conflict_is_refused_before_any_git_change(self) -> None:
        first = self.child("alpha")
        second = self.child("beta")
        for child, section in [(first, "first"), (second, "first/two")]:
            self.git(self.parent, "config", "-f", ".gitmodules", f"submodule.{section}.path", child.name)
            self.git(self.parent, "config", "-f", ".gitmodules", f"submodule.{section}.url", "../relative.git")
        self.git(self.parent, "add", ".gitmodules")
        before_parent = tree_fingerprint(self.gitdir(self.parent))
        before_first = tree_fingerprint(first / ".git")
        before_second = tree_fingerprint(second / ".git")
        before_metadata = (self.parent / ".gitmodules").read_bytes()
        code, output = self.run_script()
        self.assertNotEqual(0, code, output)
        self.assertEqual(before_parent, tree_fingerprint(self.gitdir(self.parent)))
        self.assertEqual(before_first, tree_fingerprint(first / ".git"))
        self.assertEqual(before_second, tree_fingerprint(second / ".git"))
        self.assertEqual(before_metadata, (self.parent / ".gitmodules").read_bytes())

    def test_symlink_backup_root_is_refused_without_external_writes(self) -> None:
        child = self.child()
        outside = self.sandbox / "external backup target"
        outside.mkdir()
        (self.gitdir(self.parent) / "jobs-submodule-backups").symlink_to(outside, target_is_directory=True)
        before_parent = tree_fingerprint(self.gitdir(self.parent))
        before_child = tree_fingerprint(child / ".git")
        code, output = self.run_script()
        self.assertNotEqual(0, code, output)
        self.assertEqual([], list(outside.iterdir()))
        self.assertEqual(before_parent, tree_fingerprint(self.gitdir(self.parent)))
        self.assertEqual(before_child, tree_fingerprint(child / ".git"))

    def test_failed_git_absorption_releases_lock_and_temporary_plan(self) -> None:
        child = self.child()
        shim_dir = self.sandbox / "failure shims"
        shim_dir.mkdir()
        git_shim = shim_dir / "git"
        git_shim.write_text(
            "#!/bin/sh\n"
            "for argument in \"$@\"; do\n"
            "  if [ \"$argument\" = absorbgitdirs ]; then\n"
            "    echo 'Injected absorption failure' >&2\n"
            "    exit 42\n"
            "  fi\n"
            "done\n"
            "exec /usr/bin/git \"$@\"\n"
        )
        git_shim.chmod(0o755)
        self.env["PATH"] = str(shim_dir) + os.pathsep + self.env["PATH"]
        code, output = self.run_script()
        self.assertNotEqual(0, code, output)
        self.assertIn("Injected absorption failure", output)
        self.assertTrue((child / ".git").is_dir())
        self.assertFalse((self.gitdir(self.parent) / "jobs-gitmodules.lock").exists())
        self.assertEqual([], list(self.tmp.glob("jobs-gitmodules.*")))
        self.assertTrue(list((self.gitdir(self.parent) / "jobs-submodule-backups").iterdir()))

    def test_ignored_new_child_is_refused_without_registration(self) -> None:
        child = self.child("ignored child")
        (self.parent / ".gitignore").write_text("ignored child/\n")
        self.git(self.parent, "add", ".gitignore")
        self.git(self.parent, "commit", "-m", "ignore child fixture")
        before = self.index()
        child_before = tree_fingerprint(child / ".git")
        code, output = self.run_script()
        self.assertNotEqual(0, code, output)
        self.assertEqual(before, self.index())
        self.assertEqual(child_before, tree_fingerprint(child / ".git"))
        self.assertTrue((child / ".git").is_dir())
        self.assertFalse((self.parent / ".gitmodules").exists())

    def test_glob_metacharacters_in_child_path_are_treated_literally(self) -> None:
        child = self.child("子[仓]*?库")
        self.git(child, "remote", "set-url", "origin", "https://example.invalid/Jobs/safe-url.git")
        code, output = self.run_script()
        self.assertEqual(0, code, output)
        self.assert_linked(child)
        self.assertEqual(child.name, self.git(self.parent, "config", "-f", ".gitmodules", f"submodule.{child.name}.path"))

    def test_existing_association_is_idempotent_and_preserves_gitmodules_options(self) -> None:
        child = self.child()
        self.register(child, section="custom section 中文", url="../relative-url.git")
        for key, value in {"branch": "custom-branch", "update": "none", "ignore": "dirty"}.items():
            self.git(self.parent, "config", "-f", ".gitmodules", f"submodule.custom section 中文.{key}", value)
        self.git(self.parent, "add", ".gitmodules")
        self.git(self.parent, "commit", "-m", "existing association")
        before_gm = (self.parent / ".gitmodules").read_bytes()
        before_index = self.index()
        before_config = (self.gitdir(self.parent) / "config").read_bytes()
        for _ in range(2):
            code, output = self.run_script()
            self.assertEqual(0, code, output)
        self.assert_linked(child, section="custom section 中文")
        self.assertEqual(before_gm, (self.parent / ".gitmodules").read_bytes())
        self.assertEqual(before_index, self.index())
        self.assertEqual(before_config, (self.gitdir(self.parent) / "config").read_bytes())

    def test_stale_gitmodules_entries_are_preserved(self) -> None:
        self.git(self.parent, "config", "-f", ".gitmodules", "submodule.stale.path", "missing checkout")
        self.git(self.parent, "config", "-f", ".gitmodules", "submodule.stale.url", "../missing.git")
        self.git(self.parent, "config", "-f", ".gitmodules", "submodule.stale.branch", "release")
        self.git(self.parent, "add", ".gitmodules")
        self.git(self.parent, "commit", "-m", "stale entry fixture")
        child = self.child()
        code, output = self.run_script()
        self.assertEqual(0, code, output)
        self.assert_linked(child)
        self.assertEqual("missing checkout", self.git(self.parent, "config", "-f", ".gitmodules", "submodule.stale.path"))
        self.assertEqual("../missing.git", self.git(self.parent, "config", "-f", ".gitmodules", "submodule.stale.url"))
        self.assertEqual("release", self.git(self.parent, "config", "-f", ".gitmodules", "submodule.stale.branch"))

    def test_unrelated_staged_content_is_preserved(self) -> None:
        (self.parent / "seed.txt").write_text("parent staged edit\n")
        self.git(self.parent, "add", "seed.txt")
        staged = self.git(self.parent, "show", ":seed.txt")
        child = self.child()
        code, output = self.run_script()
        self.assertEqual(0, code, output)
        self.assert_linked(child)
        self.assertEqual(staged, self.git(self.parent, "show", ":seed.txt"))

    def test_parent_staged_gitlink_is_not_overwritten_by_later_child_head(self) -> None:
        child = self.child()
        self.register(child)
        self.git(self.parent, "commit", "-m", "baseline registered child")
        (child / "seed.txt").write_text("child commit B\n")
        self.git(child, "add", "seed.txt")
        self.git(child, "commit", "-m", "child B")
        self.git(self.parent, "add", "--", child.name)
        staged_before = self.index()
        (child / "seed.txt").write_text("child commit C\n")
        self.git(child, "add", "seed.txt")
        self.git(child, "commit", "-m", "child C")
        self.run_script()
        self.assertEqual(staged_before, self.index())

    def test_no_origin_is_refused_without_fake_url_or_metadata_move(self) -> None:
        child = self.child(origin=False)
        before = self.index()
        code, output = self.run_script()
        self.assertNotEqual(0, code, output)
        self.assertEqual(before, self.index())
        self.assertTrue((child / ".git").is_dir())
        self.assertFalse((self.parent / ".gitmodules").exists())

    def test_unborn_child_is_refused_without_partial_registration(self) -> None:
        child = self.child(commit=False)
        before = self.index()
        code, output = self.run_script()
        self.assertNotEqual(0, code, output)
        self.assertEqual(before, self.index())
        self.assertTrue((child / ".git").is_dir())
        self.assertFalse((self.parent / ".gitmodules").exists())

    def test_invalid_child_preflight_prevents_mutations_of_valid_child(self) -> None:
        valid = self.child("a valid child")
        invalid = self.child("z invalid child", origin=False)
        before_index = self.index()
        valid_before = tree_fingerprint(valid / ".git")
        invalid_before = tree_fingerprint(invalid / ".git")
        code, output = self.run_script()
        self.assertNotEqual(0, code, output)
        self.assertEqual(before_index, self.index())
        self.assertEqual(valid_before, tree_fingerprint(valid / ".git"))
        self.assertEqual(invalid_before, tree_fingerprint(invalid / ".git"))
        self.assertFalse((self.parent / ".gitmodules").exists())

    def test_gitmodules_matching_staged_content_is_allowed(self) -> None:
        self.git(self.parent, "config", "-f", ".gitmodules", "submodule.stale.path", "missing")
        self.git(self.parent, "config", "-f", ".gitmodules", "submodule.stale.url", "../initial.git")
        self.git(self.parent, "add", ".gitmodules")
        child = self.child()
        code, output = self.run_script()
        self.assertEqual(0, code, output)
        self.assert_linked(child)
        self.assertEqual("../initial.git", self.git(self.parent, "config", "-f", ".gitmodules", "submodule.stale.url"))

    def test_tracked_regular_child_files_are_not_replaced_by_gitlink(self) -> None:
        directory = self.parent / "tracked child"
        directory.mkdir()
        (directory / "seed.txt").write_text("parent tracked source\n")
        self.git(self.parent, "add", "--", "tracked child/seed.txt")
        self.git(self.parent, "commit", "-m", "parent owns child file")
        child = self.init_repo(directory)
        before = self.index()
        code, output = self.run_script()
        self.assertNotEqual(0, code, output)
        self.assertEqual(before, self.index())
        self.assertTrue((child / ".git").is_dir())

    def test_gitmodules_partial_stage_is_protected(self) -> None:
        self.git(self.parent, "config", "-f", ".gitmodules", "submodule.stale.path", "missing")
        self.git(self.parent, "config", "-f", ".gitmodules", "submodule.stale.url", "../initial.git")
        self.git(self.parent, "add", ".gitmodules")
        self.git(self.parent, "commit", "-m", "initial metadata")
        self.git(self.parent, "config", "-f", ".gitmodules", "submodule.stale.url", "../staged.git")
        self.git(self.parent, "add", ".gitmodules")
        self.git(self.parent, "config", "-f", ".gitmodules", "submodule.stale.url", "../unstaged.git")
        child = self.child()
        before = self.index(), (self.parent / ".gitmodules").read_bytes()
        code, output = self.run_script()
        self.assertNotEqual(0, code, output)
        self.assertEqual(before, (self.index(), (self.parent / ".gitmodules").read_bytes()))
        self.assertTrue((child / ".git").is_dir())

    def test_linked_worktree_is_refused_without_relocating_metadata(self) -> None:
        source = self.init_repo(self.sandbox / "external worktree source")
        child = self.parent / "linked child"
        self.git(source, "worktree", "add", "-b", "linked-branch", str(child))
        before_index = self.index()
        before_pointer = (child / ".git").read_bytes()
        before_source = tree_fingerprint(source / ".git")
        code, output = self.run_script()
        self.assertNotEqual(0, code, output)
        self.assertEqual(before_index, self.index())
        self.assertEqual(before_pointer, (child / ".git").read_bytes())
        self.assertEqual(before_source, tree_fingerprint(source / ".git"))
        self.assertFalse((self.parent / ".gitmodules").exists())

    def test_modules_target_collision_preserves_both_git_histories(self) -> None:
        child = self.child("conflicting-child")
        collision = self.init_repo(self.gitdir(self.parent) / "modules" / child.name)
        collision_before = tree_fingerprint(collision)
        child_before = tree_fingerprint(child / ".git")
        before_index = self.index()
        code, output = self.run_script()
        self.assertNotEqual(0, code, output)
        self.assertEqual(before_index, self.index())
        self.assertEqual(collision_before, tree_fingerprint(collision))
        self.assertEqual(child_before, tree_fingerprint(child / ".git"))
        self.assertTrue((child / ".git").is_dir())

    def test_dry_run_leaves_index_gitmodules_config_and_metadata_unchanged(self) -> None:
        child = self.child()
        before_index = self.index()
        before_parent_git = tree_fingerprint(self.gitdir(self.parent))
        before_child_git = tree_fingerprint(child / ".git")
        code, output = self.run_script("--dry-run")
        self.assertEqual(0, code, output)
        self.assertEqual(before_index, self.index())
        self.assertEqual(before_parent_git, tree_fingerprint(self.gitdir(self.parent)))
        self.assertEqual(before_child_git, tree_fingerprint(child / ".git"))
        self.assertFalse((self.parent / ".gitmodules").exists())

    def test_enter_skips_actual_update_without_mutations(self) -> None:
        child = self.child()
        before_index = self.index()
        before_parent = tree_fingerprint(self.gitdir(self.parent))
        before_child = tree_fingerprint(child / ".git")
        self.run_script(confirmation=b"\n\n")
        self.assertEqual(before_index, self.index())
        self.assertEqual(before_parent, tree_fingerprint(self.gitdir(self.parent)))
        self.assertEqual(before_child, tree_fingerprint(child / ".git"))
        self.assertFalse((self.parent / ".gitmodules").exists())

    def test_non_tty_write_run_is_refused_without_mutations(self) -> None:
        child = self.child()
        before_parent = tree_fingerprint(self.gitdir(self.parent))
        before_child = tree_fingerprint(child / ".git")
        process = subprocess.run(
            ["/bin/zsh", str(self.parent / SCRIPT_NAME)], cwd=self.sandbox,
            env=self.env, input="y\n", capture_output=True, text=True, timeout=25,
        )
        self.assertNotEqual(0, process.returncode, process.stdout + process.stderr)
        self.assertEqual(before_parent, tree_fingerprint(self.gitdir(self.parent)))
        self.assertEqual(before_child, tree_fingerprint(child / ".git"))
        self.assertFalse((self.parent / ".gitmodules").exists())
        self.assertNotIn("\x1b[", process.stdout + process.stderr)

    def test_help_and_env_dryrun_work_without_tty_or_mutations(self) -> None:
        child = self.child()
        before_parent = tree_fingerprint(self.gitdir(self.parent))
        before_child = tree_fingerprint(child / ".git")
        for args, extra_env in [(["--help"], {}), ([], {"DRY_RUN": "1"})]:
            process = subprocess.run(
                ["/bin/zsh", str(self.parent / SCRIPT_NAME), *args], cwd=self.sandbox,
                env=dict(self.env, **extra_env), input="", capture_output=True, text=True, timeout=25,
            )
            self.assertEqual(0, process.returncode, process.stdout + process.stderr)
            self.assertEqual(before_parent, tree_fingerprint(self.gitdir(self.parent)))
            self.assertEqual(before_child, tree_fingerprint(child / ".git"))
            self.assertFalse((self.parent / ".gitmodules").exists())
            self.assertNotIn("\x1b[", process.stdout + process.stderr)

    def test_symlink_gitmodules_is_refused_without_writing_external_target(self) -> None:
        child = self.child()
        target = self.sandbox / "outside gitmodules"
        target.write_text("# keep external content\n")
        (self.parent / ".gitmodules").symlink_to(target)
        before_index = self.index()
        code, output = self.run_script()
        self.assertNotEqual(0, code, output)
        self.assertEqual("# keep external content\n", target.read_text())
        self.assertEqual(before_index, self.index())
        self.assertTrue((child / ".git").is_dir())
        self.assertTrue((self.parent / ".gitmodules").is_symlink())

    def test_duplicate_registered_path_is_refused_without_mutation(self) -> None:
        child = self.child()
        for section in ["first", "second"]:
            self.git(self.parent, "config", "-f", ".gitmodules", f"submodule.{section}.path", child.name)
            self.git(self.parent, "config", "-f", ".gitmodules", f"submodule.{section}.url", "../relative.git")
        self.git(self.parent, "add", ".gitmodules")
        before_index = self.index()
        before_metadata = (self.parent / ".gitmodules").read_bytes()
        code, output = self.run_script()
        self.assertNotEqual(0, code, output)
        self.assertEqual(before_index, self.index())
        self.assertEqual(before_metadata, (self.parent / ".gitmodules").read_bytes())
        self.assertTrue((child / ".git").is_dir())

    def test_invalid_gitmodules_config_is_refused_without_mutation(self) -> None:
        child = self.child()
        (self.parent / ".gitmodules").write_text("[submodule \"unterminated\n")
        self.git(self.parent, "add", ".gitmodules")
        before_index = self.index()
        before_metadata = (self.parent / ".gitmodules").read_bytes()
        code, output = self.run_script()
        self.assertNotEqual(0, code, output)
        self.assertEqual(before_index, self.index())
        self.assertEqual(before_metadata, (self.parent / ".gitmodules").read_bytes())
        self.assertTrue((child / ".git").is_dir())

    def test_nested_parent_uses_actual_gitdir_for_absorption(self) -> None:
        outer = self.init_repo(self.sandbox / "outer repo")
        nested = outer / "nested parent"
        shutil.move(str(self.parent), nested)
        self.parent = nested
        self.git(outer, "config", "-f", ".gitmodules", "submodule.nested parent.path", "nested parent")
        self.git(outer, "config", "-f", ".gitmodules", "submodule.nested parent.url", "../nested.git")
        self.git(outer, "add", ".gitmodules")
        self.git(outer, "update-index", "--add", "--cacheinfo", f"160000,{self.head(nested)},nested parent")
        self.git(outer, "submodule", "absorbgitdirs", "--", "nested parent")
        child = self.child()
        code, output = self.run_script()
        self.assertEqual(0, code, output)
        self.assert_linked(child)
        self.assertTrue((nested / ".git").is_file())
        self.assertIn("modules/nested parent/modules", str(self.gitdir(child)))

    def test_only_direct_child_git_is_discovered(self) -> None:
        direct = self.child("direct")
        grandchild = self.init_repo(direct / "grandchild")
        loose_nested = self.init_repo(self.parent / "ordinary folder" / "nested git")
        code, output = self.run_script()
        self.assertEqual(0, code, output)
        self.assert_linked(direct)
        self.assertTrue((grandchild / ".git").is_dir())
        self.assertTrue((loose_nested / ".git").is_dir())
        paths = self.git(self.parent, "config", "-f", ".gitmodules", "--get-regexp", r"\.path$")
        self.assertEqual("submodule.direct.path direct", paths)


def main() -> None:
    """Select the candidate and run tests while retaining logs and fixtures for review."""
    global SCRIPT_SOURCE
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "script", type=Path, nargs="?", default=Path(__file__).resolve().parents[1] / SCRIPT_NAME,
        help="Candidate updater; defaults to the entrypoint beside tests/ and only runs as a disposable copy",
    )
    parser.add_argument("tests", nargs="*", help="Optional unittest case names")
    options = parser.parse_args()
    SCRIPT_SOURCE = options.script.resolve(strict=True)
    print(f"Candidate: {SCRIPT_SOURCE}\nDisposable fixtures: {ARTIFACT_ROOT}", flush=True)
    names = options.tests or ["AssociationTests"]
    suite = unittest.TestLoader().loadTestsFromNames(names, module=sys.modules[__name__])
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(not result.wasSuccessful())


if __name__ == "__main__":
    main()
