#!/usr/bin/env python3
# Created by Jobs on 2026年10月18日，星期日.
"""Exercise complete reference-repair entries in isolated, offline Git fixtures."""

from __future__ import annotations

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


SCRIPT_NAME = "【MacOS】🧭更新引用Git父仓=>子仓.command"
SCRIPTS = [Path(item).resolve() for item in sys.argv[1:]] or [Path(__file__).resolve().parents[1] / SCRIPT_NAME]
REAL_GIT = shutil.which("git")


class ReferenceRepairTests(unittest.TestCase):
    """Check repository state, metadata ownership and failure boundaries."""

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="jobs-reference-repair-tests-")
        self.root = Path(self.temp.name).resolve()
        self.env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        self.env.update(
            HOME=str(self.root), GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=str(self.root / "empty-config"),
            GIT_ALLOW_PROTOCOL="file", GIT_TERMINAL_PROMPT="0", GIT_AUTHOR_NAME="Jobs Isolated Test",
            GIT_AUTHOR_EMAIL="test@example.invalid", GIT_COMMITTER_NAME="Jobs Isolated Test",
            GIT_COMMITTER_EMAIL="test@example.invalid", TERM="dumb", NO_COLOR="1", TMPDIR=str(self.root),
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    def git(self, repo: Path, *arguments: str, check: bool = True) -> str:
        result = subprocess.run(
            [str(REAL_GIT), "-c", "core.hooksPath=/dev/null", "-C", str(repo), *arguments],
            env=self.env, text=True, capture_output=True, timeout=15,
        )
        if check:
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        return result.stdout.strip()

    def repo(self, location: Path, name: str) -> Path:
        location.mkdir(parents=True)
        self.git(location, "init", "-b", "main")
        self.git(location, "remote", "add", "origin", f"https://code.example/team/{name}.git")
        (location / "seed").write_text("seed\n")
        self.git(location, "add", "seed")
        self.git(location, "commit", "-m", "offline fixture")
        return location

    def fixture(self, number: int, child_name: str = "Child") -> tuple[Path, Path]:
        parent = self.repo(self.root / str(number) / "Parent", "Parent")
        return parent, self.repo(parent / child_name, "Child")

    def entry(self, source: Path, parent: Path, packaged: bool = False) -> Path:
        folder = parent / SCRIPT_NAME if packaged else parent
        folder.mkdir(exist_ok=True)
        target = folder / SCRIPT_NAME
        shutil.copy2(source, target)
        return target

    def run_entry(
        self, entry: Path, *, dry_run: bool = False, skip: bool = False, extra_env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        env = self.env | (extra_env or {})
        command = ["/bin/zsh", str(entry)] + (["--dry-run"] if dry_run else [])
        if dry_run:
            return subprocess.run(command, env=env, capture_output=True, text=True, timeout=20)
        master, slave = pty.openpty()
        process = None
        output = bytearray()
        try:
            process = subprocess.Popen(command, stdin=slave, stdout=slave, stderr=slave, env=env, start_new_session=True)
            os.close(slave)
            slave = -1
            deadline = time.monotonic() + 20
            sent_intro = sent_plan = False
            while True:
                ready, _, _ = select.select([master], [], [], 0.05)
                if ready:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError:
                        break
                    if not chunk:
                        break
                    output.extend(chunk)
                elif process.poll() is not None:
                    break
                decoded = output.decode(errors="replace")
                if not sent_intro and "按回车查看计划；Ctrl+C 取消：" in decoded:
                    os.write(master, b"\n")
                    sent_intro = True
                if not sent_plan and "输入任意字符后回车执行：" in decoded:
                    os.write(master, b"\n" if skip else b"run\n")
                    sent_plan = True
                if time.monotonic() > deadline:
                    self.fail(f"Script timed out: {decoded}")
            code = process.wait(timeout=5)
            return subprocess.CompletedProcess(command, code, output.decode(errors="replace"), "")
        finally:
            if process is not None and process.poll() is None:
                process.kill()
                process.wait()
            if slave >= 0:
                os.close(slave)
            os.close(master)

    def assert_success(self, result: subprocess.CompletedProcess[str]) -> None:
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn("✔ 已完成", result.stdout)

    def assert_stopped(self, result: subprocess.CompletedProcess[str]) -> None:
        self.assertNotEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertNotIn("✔ 已完成", result.stdout)

    def parent_files(self, parent: Path) -> dict[str, bytes | None]:
        return {item: (parent / item).read_bytes() if (parent / item).exists() else None for item in [".git/config", ".git/index", ".gitmodules"]}

    def test_entries_are_identical_and_parse(self) -> None:
        expected = SCRIPTS[0].read_bytes()
        for source in SCRIPTS:
            with self.subTest(source=source):
                self.assertEqual(expected, source.read_bytes())
                subprocess.run(["/bin/zsh", "-n", str(source)], check=True, capture_output=True)

    def test_root_and_package_locate_target_parent_and_backup(self) -> None:
        for number, source in enumerate(SCRIPTS):
            for packaged in [False, True]:
                with self.subTest(source=source, packaged=packaged):
                    parent, child = self.fixture(number * 2 + int(packaged))
                    entry = self.entry(source, parent, packaged)
                    before_head = self.git(parent, "rev-parse", "HEAD")
                    result = self.run_entry(entry)
                    self.assert_success(result)
                    self.assertTrue((child / ".git").is_file())
                    self.assertEqual(parent, Path(self.git(child, "rev-parse", "--show-superproject-working-tree")))
                    self.assertEqual(before_head, self.git(parent, "rev-parse", "HEAD"))
                    backups = list((parent / ".git/jobs-submodule-backups").glob("reference.*"))
                    self.assertEqual(1, len(backups))
                    self.assertTrue((backups[0] / "config").is_file())
                    self.assertFalse((parent / ".git/jobs-reference-repair.lock").exists())

    def test_rename_preserves_original_section_metadata_and_fields(self) -> None:
        for number, source in enumerate(SCRIPTS):
            with self.subTest(source=source):
                parent, child = self.fixture(number, "Old Name")
                for key, value in {"path": child.name, "url": "../preserved.git", "ignore": "dirty", "update": "none"}.items():
                    self.git(parent, "config", "-f", ".gitmodules", f"submodule.custom section.{key}", value)
                entry = self.entry(source, parent)
                self.assert_success(self.run_entry(entry))
                self.git(parent, "commit", "-m", "record original relation")
                metadata = self.git(child, "rev-parse", "--absolute-git-dir")
                origin = self.git(child, "remote", "get-url", "origin")
                renamed = parent / "New 名称 (2)"
                child.rename(renamed)
                self.assert_success(self.run_entry(entry))
                self.assertEqual(metadata, self.git(renamed, "rev-parse", "--absolute-git-dir"))
                self.assertEqual(renamed.name, self.git(parent, "config", "-f", ".gitmodules", "submodule.custom section.path"))
                self.assertEqual("../preserved.git", self.git(parent, "config", "-f", ".gitmodules", "submodule.custom section.url"))
                self.assertEqual("dirty", self.git(parent, "config", "-f", ".gitmodules", "submodule.custom section.ignore"))
                self.assertEqual("none", self.git(parent, "config", "-f", ".gitmodules", "submodule.custom section.update"))
                self.assertEqual("", self.git(parent, "config", "-f", ".gitmodules", "submodule.custom section.branch", check=False))
                self.assertEqual(origin, self.git(renamed, "remote", "get-url", "origin"))

    def test_spaces_and_local_commits_branches_indexes_and_sources_survive(self) -> None:
        for number, source in enumerate(SCRIPTS):
            with self.subTest(source=source):
                parent, child = self.fixture(number, "有 空格(子仓)")
                self.git(child, "checkout", "-b", "topic/local-only")
                (child / "seed").write_text("local commit\n")
                self.git(child, "commit", "-am", "not pushed")
                (child / "seed").write_text("staged source\n")
                self.git(child, "add", "seed")
                (child / "untracked").write_text("keep me\n")
                (parent / "unrelated").write_text("already staged\n")
                self.git(parent, "add", "unrelated")
                before = {"head": self.git(child, "rev-parse", "HEAD"), "branch": self.git(child, "symbolic-ref", "HEAD"), "status": self.git(child, "status", "--porcelain"), "refs": self.git(child, "show-ref"), "origin": self.git(child, "remote", "get-url", "origin")}
                self.assert_success(self.run_entry(self.entry(source, parent)))
                self.assertEqual(before["head"], self.git(child, "rev-parse", "HEAD"))
                self.assertEqual(before["branch"], self.git(child, "symbolic-ref", "HEAD"))
                self.assertEqual(before["status"], self.git(child, "status", "--porcelain"))
                self.assertEqual(before["refs"], self.git(child, "show-ref"))
                self.assertEqual(before["origin"], self.git(child, "remote", "get-url", "origin"))
                self.assertEqual("already staged", self.git(parent, "show", ":unrelated"))
                self.assertEqual(before["head"], self.git(parent, "rev-parse", f":{child.name}"))

    def test_registered_nested_path_preserves_section_without_adopting_siblings(self) -> None:
        for number, source in enumerate(SCRIPTS):
            with self.subTest(source=source):
                child_path = "OS@Extension/平台 分类/Child 名称"
                parent, child = self.fixture(number, child_path)
                sibling = self.repo(child.parent / "Unregistered", "Unregistered")
                section = "existing custom section"
                for key, value in {"path": child_path, "url": "../preserved.git", "ignore": "dirty", "update": "none"}.items():
                    self.git(parent, "config", "-f", ".gitmodules", f"submodule.{section}.{key}", value)
                self.git(parent, "add", ".gitmodules")
                self.git(parent, "update-index", "--add", "--cacheinfo", "160000", self.git(child, "rev-parse", "HEAD"), child_path)
                self.git(parent, "commit", "-m", "record nested relation")
                entry = self.entry(source, parent)
                sibling_before = {"head": self.git(sibling, "rev-parse", "HEAD"), "status": self.git(sibling, "status", "--porcelain"), "config": (sibling / ".git/config").read_bytes()}
                for _ in range(2):
                    self.assert_success(self.run_entry(entry))
                    self.assertEqual(child_path, self.git(parent, "config", "-f", ".gitmodules", f"submodule.{section}.path"))
                    self.assertEqual("../preserved.git", self.git(parent, "config", "-f", ".gitmodules", f"submodule.{section}.url"))
                    self.assertEqual("dirty", self.git(parent, "config", "-f", ".gitmodules", f"submodule.{section}.ignore"))
                    self.assertEqual("none", self.git(parent, "config", "-f", ".gitmodules", f"submodule.{section}.update"))
                    self.assertEqual("", self.git(parent, "config", "-f", ".gitmodules", f"submodule.{section}.branch", check=False))
                    self.assertEqual(child_path + "\0", self.git(parent, "ls-files", "-z", "--", "OS@Extension"))
                    self.assertEqual(parent, Path(self.git(child, "rev-parse", "--show-superproject-working-tree")))
                self.assertTrue((sibling / ".git").is_dir())
                self.assertEqual(sibling_before["head"], self.git(sibling, "rev-parse", "HEAD"))
                self.assertEqual(sibling_before["status"], self.git(sibling, "status", "--porcelain"))
                self.assertEqual(sibling_before["config"], (sibling / ".git/config").read_bytes())

    def test_registered_nested_symlinks_and_intermediate_git_are_blocked(self) -> None:
        for number, source in enumerate(SCRIPTS):
            for variant in ["container-link", "child-link", "intermediate-git"]:
                with self.subTest(source=source, variant=variant):
                    base = self.root / str(number) / variant
                    parent = self.repo(base / "Parent", "Parent")
                    external = self.repo(base / "External/Child", "Child")
                    container = parent / "OS@Extension"
                    if variant == "container-link":
                        container.symlink_to(external.parent, target_is_directory=True)
                    elif variant == "child-link":
                        container.mkdir()
                        (container / "Child").symlink_to(external, target_is_directory=True)
                    else:
                        self.repo(container, "Intermediate")
                        self.repo(container / "Child", "Child")
                    self.git(parent, "config", "-f", ".gitmodules", "submodule.custom.path", "OS@Extension/Child")
                    self.git(parent, "config", "-f", ".gitmodules", "submodule.custom.url", "../Child.git")
                    entry = self.entry(source, parent)
                    before = self.parent_files(parent)
                    self.assert_stopped(self.run_entry(entry))
                    self.assertEqual(before, self.parent_files(parent))
                    self.assertTrue((external / ".git").is_dir())
                    self.assertFalse((parent / ".git/jobs-submodule-backups").exists())

    def test_missing_nested_registration_is_removed_without_recursing(self) -> None:
        for number, source in enumerate(SCRIPTS):
            with self.subTest(source=source):
                parent, child = self.fixture(number)
                missing = parent / "OS@Extension/Missing"
                missing.mkdir(parents=True)
                (missing / "notes").write_text("retain source\n")
                self.git(parent, "config", "-f", ".gitmodules", "submodule.stale.path", "OS@Extension/Missing")
                self.git(parent, "config", "-f", ".gitmodules", "submodule.stale.url", "../Missing.git")
                self.git(parent, "update-index", "--add", "--cacheinfo", "160000", self.git(child, "rev-parse", "HEAD"), "OS@Extension/Missing")
                self.assert_success(self.run_entry(self.entry(source, parent)))
                self.assertEqual("", self.git(parent, "config", "-f", ".gitmodules", "submodule.stale.path", check=False))
                self.assertEqual("", self.git(parent, "ls-files", "--", "OS@Extension/Missing"))
                self.assertEqual("retain source\n", (missing / "notes").read_text())

    def test_missing_registration_is_removed_but_disk_content_is_kept(self) -> None:
        for number, source in enumerate(SCRIPTS):
            with self.subTest(source=source):
                parent, child = self.fixture(number)
                missing = parent / "Missing Folder"
                missing.mkdir()
                (missing / "notes").write_text("retain source\n")
                self.git(parent, "config", "-f", ".gitmodules", "submodule.stale.path", missing.name)
                self.git(parent, "config", "-f", ".gitmodules", "submodule.stale.url", "../Missing.git")
                self.git(parent, "update-index", "--add", "--cacheinfo", "160000", self.git(child, "rev-parse", "HEAD"), missing.name)
                self.assert_success(self.run_entry(self.entry(source, parent)))
                self.assertEqual("", self.git(parent, "config", "-f", ".gitmodules", "submodule.stale.path", check=False))
                self.assertEqual("", self.git(parent, "ls-files", "--", missing.name))
                self.assertEqual("retain source\n", (missing / "notes").read_text())

    def test_preview_and_skip_do_not_change_association(self) -> None:
        for number, source in enumerate(SCRIPTS):
            for dry_run in [False, True]:
                with self.subTest(source=source, dry_run=dry_run):
                    parent, child = self.fixture(number * 2 + int(dry_run))
                    entry = self.entry(source, parent)
                    before = self.parent_files(parent)
                    result = self.run_entry(entry, dry_run=dry_run, skip=True)
                    self.assertEqual(0, result.returncode, result.stdout + result.stderr)
                    self.assertEqual(before, self.parent_files(parent))
                    self.assertTrue((child / ".git").is_dir())
                    self.assertFalse((parent / ".git/jobs-submodule-backups").exists())

    def test_conflicting_metadata_stops_before_write(self) -> None:
        for number, source in enumerate(SCRIPTS):
            with self.subTest(source=source):
                parent, child = self.fixture(number)
                conflict = parent / ".git/modules/Child"
                conflict.mkdir(parents=True)
                (conflict / "sentinel").write_text("other history\n")
                entry = self.entry(source, parent)
                before = self.parent_files(parent)
                self.assert_stopped(self.run_entry(entry))
                self.assertEqual(before, self.parent_files(parent))
                self.assertEqual("other history\n", (conflict / "sentinel").read_text())
                self.assertTrue((child / ".git").is_dir())

    def test_linked_child_and_linked_parent_are_blocked(self) -> None:
        for number, source in enumerate(SCRIPTS):
            with self.subTest(source=source):
                parent = self.repo(self.root / str(number) / "Parent", "Parent")
                external = self.repo(self.root / str(number) / "External", "External")
                self.git(external, "worktree", "add", "-b", "linked", str(parent / "Linked"))
                entry = self.entry(source, parent)
                before = self.parent_files(parent)
                self.assert_stopped(self.run_entry(entry))
                self.assertEqual(before, self.parent_files(parent))
                linked_parent = self.root / str(number) / "Parent Linked"
                self.git(parent, "worktree", "add", "-b", "linked-parent", str(linked_parent))
                self.repo(linked_parent / "Child", "Child")
                self.assert_stopped(self.run_entry(self.entry(source, linked_parent)))

    def test_broken_pointer_is_not_replaced_with_unproven_metadata(self) -> None:
        for number, source in enumerate(SCRIPTS):
            with self.subTest(source=source):
                parent = self.repo(self.root / str(number) / "Parent", "Parent")
                child = parent / "Broken"
                child.mkdir()
                marker = "gitdir: ../missing-metadata\n"
                (child / ".git").write_text(marker)
                entry = self.entry(source, parent)
                before = self.parent_files(parent)
                self.assert_stopped(self.run_entry(entry))
                self.assertEqual(before, self.parent_files(parent))
                self.assertEqual(marker, (child / ".git").read_text())

    def test_absorb_failure_keeps_backup_and_does_not_report_success(self) -> None:
        for number, source in enumerate(SCRIPTS):
            with self.subTest(source=source):
                parent, child = self.fixture(number)
                expected_head = self.git(child, "rev-parse", "HEAD")
                tools = self.root / str(number) / "tools"
                tools.mkdir()
                wrapper = tools / "git"
                wrapper.write_text('#!/bin/zsh\nif [[ "$1" == -C && "$3" == submodule && "$4" == absorbgitdirs ]]; then print -u2 -- "isolated absorb failure"; exit 42; fi\nexec "$TEST_REAL_GIT" "$@"\n')
                wrapper.chmod(0o755)
                result = self.run_entry(self.entry(source, parent), extra_env={"PATH": f"{tools}:{self.env.get('PATH', '')}", "TEST_REAL_GIT": str(REAL_GIT)})
                self.assert_stopped(result)
                self.assertIn("isolated absorb failure", result.stdout + result.stderr)
                self.assertEqual(expected_head, self.git(child, "rev-parse", "HEAD"))
                self.assertEqual(1, len(list((parent / ".git/jobs-submodule-backups").glob("reference.*"))))
                self.assertFalse((parent / ".git/jobs-reference-repair.lock").exists())


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]], verbosity=2)
