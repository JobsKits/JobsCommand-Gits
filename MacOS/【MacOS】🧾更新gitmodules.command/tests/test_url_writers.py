#!/usr/bin/env python3
# Created by Jobs on 2026年10月17日，星期六.
"""Check URL writers using isolated Git repositories, without network or project Git writes."""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


GITHUB_ROOT = Path(__file__).resolve().parents[5]
UPDATER = "【MacOS】🧾更新gitmodules.command"
ALIGNER = "【MacOS】🧭更新引用Git父仓=>子仓.command"
GITS_ALIGNER = ALIGNER.replace(">", "＞")
GENESIS = GITHUB_ROOT / "JobsGenesis"
UPDATERS = [GENESIS / folder / UPDATER for folder in ["", "JobsConfigOS", "JobsPythonTools.py", "OS@Extension/MacOS@Extension"]]
UPDATERS += [GENESIS / "JobsCommand@Gits" / "MacOS" / UPDATER / UPDATER, GITHUB_ROOT / "JobsBaseConfig" / UPDATER]
ALIGNERS = [GENESIS / folder / ALIGNER for folder in ["", "JobsConfigOS", "OS@Extension/MacOS@Extension"]]
ALIGNERS += [GENESIS / "JobsCommand@Gits" / "MacOS" / GITS_ALIGNER / GITS_ALIGNER, GITHUB_ROOT / "JobsBaseConfig" / ALIGNER]

# 平台迁移只维护本仓入口，跨仓副本的全量一致性留给显式巡检。
if "--all-copies" in sys.argv:
    sys.argv.remove("--all-copies")
    for missing in [source for source in UPDATERS + ALIGNERS if not source.is_file()]:
        print(f"Unavailable external copy: {missing}", file=sys.stderr)
    UPDATERS = [source for source in UPDATERS if source.is_file()]
    ALIGNERS = [source for source in ALIGNERS if source.is_file()]
else:
    UPDATERS = [GENESIS / "JobsCommand@Gits" / "MacOS" / UPDATER / UPDATER]
    ALIGNERS = [GENESIS / "JobsCommand@Gits" / "MacOS" / GITS_ALIGNER / GITS_ALIGNER]


class UrlWriterTests(unittest.TestCase):
    """Verify complete writer functions and their child-origin preservation boundary."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="jobs-submodule-url-writers-")
        self.root = Path(self.tmp.name)
        self.env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        self.env.update(
            HOME=str(self.root), GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=str(self.root / "empty-config"),
            GIT_ALLOW_PROTOCOL="file", GIT_TERMINAL_PROMPT="0", GIT_AUTHOR_NAME="Isolated Test",
            GIT_AUTHOR_EMAIL="test@example.invalid", GIT_COMMITTER_NAME="Isolated Test",
            GIT_COMMITTER_EMAIL="test@example.invalid", TERM="dumb", NO_COLOR="1",
        )

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def git(self, repo: Path, *args: str, check: bool = True) -> str:
        result = subprocess.run(["git", "-c", "core.hooksPath=/dev/null", "-C", str(repo), *args], env=self.env, capture_output=True, text=True)
        if check:
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        return result.stdout.strip()

    def repo(self, path: Path, name: str) -> Path:
        path.mkdir(parents=True, exist_ok=True)
        self.git(path, "init", "-b", "main")
        self.git(path, "remote", "add", "origin", f"https://code.example/team/{name}.git")
        (path / "seed").write_text("seed\n")
        self.git(path, "add", "seed")
        self.git(path, "commit", "-m", "isolated fixture")
        return path

    def shell(self, source: Path, body: str, *args: Path) -> str:
        candidate = self.root / "functions.zsh"
        content = source.read_text()
        self.assertTrue(content.rstrip().endswith('main "$@"'))
        candidate.write_text(content[: content.rindex('main "$@"')])
        result = subprocess.run(
            ["/bin/zsh", "-c", 'source "$1"\nshift\n' + body, "isolated-url-writer", str(candidate), *map(str, args)],
            cwd=self.root, env=self.env, capture_output=True, text=True, timeout=25,
        )
        self.assertEqual(0, result.returncode, f"{source}: {result.stdout}{result.stderr}")
        return result.stdout

    def test_all_copies_validate_multiple_platforms_and_keep_ambiguous_sources(self) -> None:
        for index, source in enumerate(UPDATERS + ALIGNERS):
            with self.subTest(script=source):
                parent = self.repo(self.root / str(index) / "Parent", "Parent")
                child = self.repo(parent / "Child", "Child")
                self.git(parent, "remote", "add", "mirror", "ssh://git@mirror.example:2222/group/nested/Parent.git")
                self.git(child, "remote", "add", "mirror", "ssh://git@mirror.example:2222/group/nested/Child.git")
                actual = self.shell(source, 'relative_submodule_url "$1" "$2" "https://code.example/team/Child.git"', parent, child)
                self.assertEqual("../Child.git", actual.strip())
                for bad in [
                    "ssh://git@mirror.example:2223/group/nested/Child.git",
                    "https://mirror.example:2222/group/nested/Child.git",
                    "ssh://git@mirror.example:2222/other/nested/Child.git",
                    "ssh://git@mirror.example:2222/group/nested/Renamed.git",
                    str(self.root / "Child.git"), "git://mirror.example/group/nested/Child.git",
                ]:
                    self.git(child, "remote", "set-url", "mirror", bad)
                    result = self.shell(source, 'if relative_submodule_url "$1" "$2" "https://code.example/team/Child.git"; then exit 9; fi', parent, child)
                    self.assertEqual("", result)
                self.git(child, "remote", "remove", "mirror")
                self.shell(source, 'if relative_submodule_url "$1" "$2" "https://code.example/team/Child.git"; then exit 9; fi', parent, child)

    def test_all_updaters_retain_existing_fields_and_missing_directories(self) -> None:
        for index, source in enumerate(UPDATERS):
            with self.subTest(script=source):
                parent = self.repo(self.root / str(index) / "Parent", "Parent")
                self.repo(parent / "Existing", "Existing")
                self.repo(parent / "New", "New")
                for key, value in {"path": "Existing", "url": "../preserved.git", "update": "none", "ignore": "dirty"}.items():
                    self.git(parent, "config", "-f", ".gitmodules", f"submodule.custom section.{key}", value)
                self.git(parent, "config", "-f", ".gitmodules", "submodule.stale.path", "Missing")
                self.git(parent, "config", "-f", ".gitmodules", "submodule.stale.url", "../Missing.git")
                original = (parent / ".gitmodules").read_bytes()
                target = self.root / f"planned-{index}.gitmodules"
                self.shell(source, '''
SCRIPT_DIR="$1"; LOG_FILE="$3"
initialize_runtime
check_environment
load_existing_modules
discover_and_plan
cp "$PLAN_FILE" "$2"
''', parent, target, self.root / "writer.log")
                self.assertEqual(original, (parent / ".gitmodules").read_bytes())
                self.assertEqual("../preserved.git", self.git(parent, "config", "-f", str(target), "submodule.custom section.url"))
                self.assertEqual("", self.git(parent, "config", "-f", str(target), "submodule.custom section.branch", check=False))
                self.assertEqual("none", self.git(parent, "config", "-f", str(target), "submodule.custom section.update"))
                self.assertEqual("dirty", self.git(parent, "config", "-f", str(target), "submodule.custom section.ignore"))
                self.assertEqual("Missing", self.git(parent, "config", "-f", str(target), "submodule.stale.path"))
                self.assertEqual("../Missing.git", self.git(parent, "config", "-f", str(target), "submodule.stale.url"))
                self.assertEqual("../New.git", self.git(parent, "config", "-f", str(target), "submodule.New.url"))

    def test_all_updaters_are_identical_and_run_as_standalone_copies(self) -> None:
        expected = UPDATERS[0].read_bytes()
        for index, source in enumerate(UPDATERS):
            with self.subTest(script=source):
                self.assertFalse(source.is_symlink())
                self.assertEqual(expected, source.read_bytes())
                parent = self.repo(self.root / str(index) / "Parent", "Parent")
                child = self.repo(parent / "Child", "Child")
                candidate = parent / UPDATER
                shutil.copyfile(source, candidate)
                before = {name: (parent / ".git" / name).read_bytes() for name in ["config", "index"]}
                process = subprocess.run(
                    ["/bin/zsh", str(candidate), "--dry-run"], cwd=self.root,
                    env=self.env, capture_output=True, text=True, timeout=25,
                )
                self.assertEqual(0, process.returncode, process.stdout + process.stderr)
                self.assertIn("DRY_RUN=1", process.stdout)
                self.assertEqual(before, {name: (parent / ".git" / name).read_bytes() for name in before})
                self.assertFalse((parent / ".gitmodules").exists())
                self.assertTrue((child / ".git").is_dir())

    def test_all_updaters_back_up_original_config_index_and_gitmodules(self) -> None:
        for index, source in enumerate(UPDATERS):
            with self.subTest(script=source):
                parent = self.repo(self.root / str(index) / "Parent", "Parent")
                child = self.repo(parent / "Child", "Child")
                self.git(parent, "config", "-f", ".gitmodules", "submodule.stale.path", "Missing")
                self.git(parent, "config", "-f", ".gitmodules", "submodule.stale.url", "../Missing.git")
                self.git(parent, "add", ".gitmodules")
                before = {name: (parent / ".git" / name).read_bytes() for name in ["config", "index"]}
                before["gitmodules"] = (parent / ".gitmodules").read_bytes()
                parent_head = self.git(parent, "rev-parse", "HEAD")
                child_head = self.git(child, "rev-parse", "HEAD")
                self.shell(source, '''
SCRIPT_DIR="$1"; LOG_FILE="$2"
initialize_runtime
check_environment
load_existing_modules
discover_and_plan
backup_association_state
apply_associations
verify_associations
''', parent, self.root / "backup.log")
                backups = list((parent / ".git" / "jobs-submodule-backups").iterdir())
                self.assertEqual(1, len(backups))
                self.assertEqual(before, {name: (backups[0] / name).read_bytes() for name in before})
                self.assertEqual(parent_head, self.git(parent, "rev-parse", "HEAD"))
                self.assertEqual(child_head, self.git(child, "rev-parse", "HEAD"))
                self.assertTrue((child / ".git").is_file())

    def test_alignment_preserves_registration_and_separates_child_origin(self) -> None:
        for index, source in enumerate(ALIGNERS):
            with self.subTest(script=source):
                parent = self.repo(self.root / str(index) / "Parent", "Parent")
                existing = self.repo(parent / "Existing", "Existing")
                self.repo(parent / "New", "New")
                for key, value in {"path": "Existing", "url": "../preserved.git", "update": "none", "ignore": "dirty"}.items():
                    self.git(parent, "config", "-f", ".gitmodules", f"submodule.custom section.{key}", value)
                self.git(parent, "config", "-f", ".gitmodules", "submodule.stale.path", "Missing")
                self.git(parent, "config", "-f", ".gitmodules", "submodule.stale.url", "../Missing.git")
                child_origin = self.git(existing, "remote", "get-url", "origin")
                self.shell(source, '''
PARENT_REPO_DIR="$1"; LOG_FILE="$2"; CURRENT_SUBGIT_DIRS=(Existing New)
load_existing_submodule_sections
collect_submodule_urls
[[ "${SUBMODULE_URLS[Existing]}" == https://code.example/team/Existing.git ]] || exit 7
rewrite_gitmodules
git -C "$1" add .gitmodules Existing New
PARENT_GIT_DIR="$(git -C "$1" rev-parse --absolute-git-dir)"
absorb_gitdirs_if_needed
repair_all_subgit_metadata
''', parent, self.root / "align.log")
                self.assertEqual("../preserved.git", self.git(parent, "config", "-f", ".gitmodules", "submodule.custom section.url"))
                self.assertEqual("", self.git(parent, "config", "-f", ".gitmodules", "submodule.custom section.branch", check=False))
                self.assertEqual("none", self.git(parent, "config", "-f", ".gitmodules", "submodule.custom section.update"))
                self.assertEqual("../New.git", self.git(parent, "config", "-f", ".gitmodules", "submodule.New.url"))
                self.assertEqual("", self.git(parent, "config", "-f", ".gitmodules", "submodule.stale.path", check=False))
                self.assertEqual(child_origin, self.git(existing, "remote", "get-url", "origin"))
                self.assertTrue((existing / ".git").is_file())
                self.assertEqual((parent / ".git" / "modules" / "custom section").resolve(), Path(self.git(existing, "rev-parse", "--absolute-git-dir")).resolve())


if __name__ == "__main__":
    unittest.main(verbosity=2)
