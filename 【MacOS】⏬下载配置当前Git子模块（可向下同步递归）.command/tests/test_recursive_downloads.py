#!/usr/bin/env python3
# Created by Jobs on 2026年10月18日，星期日.
"""Exercise recursive downloads using local Git repositories and isolated config."""

from __future__ import annotations

import errno
import os
from pathlib import Path
import pty
import re
import select
import shlex
import shutil
import subprocess
import tempfile
import time
import unittest

from test_downloaders_latest import SOURCES


class RecursiveDownloadTests(unittest.TestCase):
    """Distinguish branch tips from pinned gitlinks without network access."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="jobs-recursive-downloads-")
        self.root = Path(self.tmp.name).resolve()
        home = self.root / "home"
        home.mkdir()
        self.global_config = home / "gitconfig"
        self.global_config.write_text(
            "[submodule]\n\trecurse = true\n[fetch]\n\trecurseSubmodules = true\n",
            encoding="utf-8",
        )
        self.global_before = self.global_config.read_bytes()
        self.env = {
            key: value for key, value in os.environ.items()
            if not key.startswith("GIT_") and key != "JOBS_GITEE_HTTPS_CONFIGURED"
        }
        self.env.update(
            HOME=str(home), XDG_CONFIG_HOME=str(home / "xdg"), TMPDIR=str(self.root),
            GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=str(self.global_config),
            GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="core.hooksPath",
            GIT_CONFIG_VALUE_0="/dev/null", GIT_ALLOW_PROTOCOL="file",
            GIT_TERMINAL_PROMPT="0", GIT_ASKPASS="/usr/bin/false",
            GIT_SSH_COMMAND="/usr/bin/false", SSH_ASKPASS="/usr/bin/false",
            GIT_AUTHOR_NAME="Offline Test", GIT_AUTHOR_EMAIL="offline@example.invalid",
            GIT_COMMITTER_NAME="Offline Test", GIT_COMMITTER_EMAIL="offline@example.invalid",
            PATH="/usr/bin:/bin:/usr/sbin:/sbin", TERM="dumb", NO_COLOR="1",
        )

    def tearDown(self) -> None:
        self.assertEqual(self.global_before, self.global_config.read_bytes())
        self.tmp.cleanup()

    def git(self, repo: Path, *args: str) -> str:
        """Disable implicit recursion in fixture setup; tested functions choose their own flags."""
        result = subprocess.run(
            ["/usr/bin/git", "-c", "core.hooksPath=/dev/null", "-c", "submodule.recurse=false",
             "-c", "fetch.recurseSubmodules=false", "-C", str(repo), *args],
            env=self.env, capture_output=True, text=True, timeout=20,
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        return result.stdout.strip()

    def commit(self, repo: Path, label: str) -> str:
        (repo / "seed").write_text(label + "\n", encoding="utf-8")
        self.git(repo, "add", "--", "seed")
        self.git(repo, "commit", "-qm", label)
        return self.git(repo, "rev-parse", "HEAD")

    def fixture(self, name: str, *, initialized: bool = False, relative: bool = False) -> dict[str, Path | str]:
        """Pin old commits first, then advance main and feature on every remote."""
        case = self.root / name
        case.mkdir()
        repos = {key: case / key for key in ("leaf", "middle", "child", "parent-source")}
        for repo in repos.values():
            repo.mkdir()
            self.git(repo, "init", "-q", "-b", "main")
            self.commit(repo, "initial")
        leaf, middle, child, parent_source = (repos[key] for key in repos)
        leaf_old = self.git(leaf, "rev-parse", "HEAD")
        self.git(leaf, "branch", "feature")
        self.git(middle, "submodule", "add", "-q", "--name", "leaf-section", leaf.as_uri(), "叶 child")
        self.git(middle, "config", "-f", ".gitmodules", "submodule.leaf-section.branch", ".")
        if relative:
            self.git(middle, "config", "-f", ".gitmodules", "submodule.leaf-section.url", "../leaf")
        self.git(middle, "add", ".gitmodules", "叶 child")
        self.git(middle, "commit", "-qm", "pin leaf")
        middle_old = self.git(middle, "rev-parse", "HEAD")
        self.git(middle, "branch", "feature")
        self.git(child, "submodule", "add", "-q", "--name", "middle-section", middle.as_uri(), "中 child")
        self.git(child, "config", "-f", ".gitmodules", "submodule.middle-section.branch", "feature")
        if relative:
            self.git(child, "config", "-f", ".gitmodules", "submodule.middle-section.url", "../middle")
        self.git(child, "add", ".gitmodules", "中 child")
        self.git(child, "commit", "-qm", "pin middle")
        child_old = self.git(child, "rev-parse", "HEAD")
        for section, path in (("selected-section", "Selected child"), ("bypass-section", "Bypass child")):
            self.git(parent_source, "submodule", "add", "-q", "--name", section, child.as_uri(), path)
            if relative:
                self.git(parent_source, "config", "-f", ".gitmodules", f"submodule.{section}.url", "../child")
        self.git(parent_source, "commit", "-qam", "pin children")
        parent = case / "parent"
        self.git(case, "clone", "-q", "--no-recurse-submodules", parent_source.as_uri(), str(parent))
        self.git(parent, "submodule", "update", "--init", "--", "Selected child", "Bypass child")
        self.git(parent / "Bypass child", "submodule", "update", "--init", "--recursive")
        if initialized:
            self.git(parent / "Selected child", "submodule", "update", "--init", "--recursive")
        self.commit(leaf, "leaf main latest")
        self.git(leaf, "checkout", "-q", "feature")
        leaf_latest = self.commit(leaf, "leaf feature latest")
        self.commit(middle, "middle main latest")
        self.git(middle, "checkout", "-q", "feature")
        middle_latest = self.commit(middle, "middle feature latest")
        child_latest = self.commit(child, "child main latest")
        return {
            **repos, "case": case, "parent": parent, "leaf_old": leaf_old,
            "middle_old": middle_old, "child_old": child_old,
            "leaf_latest": leaf_latest, "middle_latest": middle_latest, "child_latest": child_latest,
        }

    def shell(self, source: Path, fixture: dict[str, Path | str], body: str, *, recursive: int = 1) -> str:
        library = fixture["case"] / "library.zsh"
        library.write_text(
            re.sub(r'(?m)^main "\$@"\s*$', "", source.read_text(encoding="utf-8")),
            encoding="utf-8",
        )
        setup = f"cd {shlex.quote(str(fixture['parent']))}\n" + r'''
setopt ERR_EXIT PIPE_FAIL NO_NOMATCH
source "$1"
shift
REPO_ROOT="$PWD"
LOG_FILE="$2"
CONFIG_PATHS=('Selected child')
SUBMODULE_BRANCH=main
SUBMODULE_SHALLOW_CLONE=0
SUBMODULE_FETCH_TAGS=0
REMOTE_NAME=origin
GIT_URL_STYLE=auto
AUTO_PARENT_COMMIT=0
AUTO_PARENT_PUSH=0
''' + f"SUBMODULE_RECURSIVE={recursive}\n"
        result = subprocess.run(
            ["/bin/zsh", "-f", "-c", setup + body, "offline-recursion", str(library),
             str(fixture["case"]), str(fixture["case"] / "output.log")],
            cwd=fixture["parent"], env=self.env, stdin=subprocess.DEVNULL,
            capture_output=True, text=True, timeout=40,
        )
        self.assertEqual(0, result.returncode, f"{source}: {result.stdout}{result.stderr}")
        return result.stdout + result.stderr

    def snapshot(self, repo: Path) -> dict[str, bytes | None]:
        """Check real descendant HEAD, fetch state, configuration and staged gitlinks."""
        gitdir = Path(self.git(repo, "rev-parse", "--absolute-git-dir"))
        return {
            name: (gitdir / name).read_bytes() if (gitdir / name).exists() else None
            for name in ("HEAD", "FETCH_HEAD", "config", "index", "refs/heads/main", "refs/heads/feature")
        }

    def forget_selected_worktree(self, fixture: dict[str, Path | str]) -> Path:
        """Keep the disposable old cache aside so the next run really clones."""
        parent = fixture["parent"]
        child = parent / "Selected child"
        cache = Path(self.git(child, "rev-parse", "--absolute-git-dir"))
        self.git(parent, "submodule", "deinit", "-f", "--", "Selected child")
        cache.rename(fixture["case"] / "saved-selected-cache")
        return child

    def readonly_shell(self, source: Path, fixture: dict[str, Path | str], repo: Path) -> tuple[int, str]:
        """Give the real embedded entrypoint a terminal while keeping every Git operation local."""
        engine = source.read_text(encoding="utf-8").split("<<'JOBS_READONLY_PULL_ENGINE'\n", 1)[1].split("\nJOBS_READONLY_PULL_ENGINE", 1)[0]
        script = fixture["case"] / "readonly-engine.zsh"
        script.write_text(engine, encoding="utf-8")
        master, slave = pty.openpty()
        process = subprocess.Popen(
            ["/bin/zsh", str(script), "--terminal-run", str(repo)],
            cwd=fixture["case"], env=self.env, stdin=slave, stdout=slave, stderr=slave,
        )
        os.close(slave)
        output = bytearray()
        deadline = time.monotonic() + 45
        try:
            os.write(master, b"\n")
            while time.monotonic() < deadline:
                readable, _, _ = select.select([master], [], [], 0.1)
                if readable:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError as error:
                        if error.errno == errno.EIO:
                            break
                        raise
                    if not chunk:
                        break
                    output.extend(chunk)
                if process.poll() is not None and not readable:
                    break
            else:
                self.fail("readonly engine timed out: " + output.decode(errors="replace"))
            process.wait(timeout=5)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)
            os.close(master)
        return process.returncode, output.decode(errors="replace")

    def test_readonly_detached_entry_restores_branch_recurses_and_repeats(self) -> None:
        for index, source in enumerate(SOURCES):
            with self.subTest(script=source):
                fixture = self.fixture(f"readonly-detached-{index}")
                parent = fixture["parent"]
                parent_before = self.snapshot(parent)
                child = parent / "Selected child"
                self.assertEqual("", self.git(child, "branch", "--show-current"))
                for _ in range(2):
                    code, output = self.readonly_shell(source, fixture, child)
                    self.assertEqual(0, code, output)
                    for repo, key, branch in (
                        (child, "child", "main"),
                        (child / "中 child", "middle", "feature"),
                        (child / "中 child/叶 child", "leaf", "feature"),
                    ):
                        self.assertEqual(branch, self.git(repo, "branch", "--show-current"))
                        self.assertEqual(fixture[f"{key}_latest"], self.git(repo, "rev-parse", "HEAD"))
                        self.assertEqual(f"origin/{branch}", self.git(repo, "rev-parse", "--abbrev-ref", "@{upstream}"))
                    self.assertEqual(parent_before, self.snapshot(parent))
                    self.assertEqual(fixture["middle_old"], self.git(child, "rev-parse", ":中 child"))

    def test_readonly_detached_entry_preserves_unique_commit(self) -> None:
        for index, source in enumerate(SOURCES):
            with self.subTest(script=source):
                fixture = self.fixture(f"readonly-unique-{index}", initialized=True)
                parent = fixture["parent"]
                parent_before = self.snapshot(parent)
                child = parent / "Selected child"
                self.git(child, "commit", "--allow-empty", "-qm", "must preserve detached entry commit")
                expected = self.git(child, "rev-parse", "HEAD")
                code, output = self.readonly_shell(source, fixture, child)
                self.assertNotEqual(0, code, output)
                self.assertEqual(expected, self.git(child, "rev-parse", "HEAD"))
                self.assertEqual("", self.git(child, "branch", "--show-current"))
                self.assertEqual(parent_before, self.snapshot(parent))

    def test_unconfigured_branches_follow_remote_trunk_even_when_main_exists(self) -> None:
        for initialized in (False, True):
            for index, source in enumerate(SOURCES):
                with self.subTest(script=source, initialized=initialized):
                    fixture = self.fixture(f"default-{initialized}-{index}", initialized=initialized)
                    expected = {}
                    for key, section in (("leaf", None), ("middle", "leaf-section"), ("child", "middle-section")):
                        remote = fixture[key]
                        self.git(remote, "checkout", "-qb", "trunk")
                        if section:
                            self.git(remote, "config", "-f", ".gitmodules", "--unset", f"submodule.{section}.branch")
                            self.git(remote, "add", ".gitmodules")
                        expected[key] = self.commit(remote, f"{key} default trunk latest")
                    if not initialized:
                        self.forget_selected_worktree(fixture)
                    self.shell(source, fixture, "sync_selected_submodules_to_latest 'Selected child'\nsync_selected_submodules_to_latest 'Selected child'\n")
                    child = fixture["parent"] / "Selected child"
                    for key, repo in (("child", child), ("middle", child / "中 child"), ("leaf", child / "中 child/叶 child")):
                        self.assertEqual("trunk", self.git(repo, "branch", "--show-current"))
                        self.assertEqual(expected[key], self.git(repo, "rev-parse", "HEAD"))
                        self.assertEqual("origin/trunk", self.git(repo, "rev-parse", "--abbrev-ref", "@{upstream}"))

    def test_explicit_missing_branch_stops_before_clone_or_checkout(self) -> None:
        for initialized in (False, True):
            for index, source in enumerate(SOURCES):
                with self.subTest(script=source, initialized=initialized):
                    fixture = self.fixture(f"missing-{initialized}-{index}", initialized=initialized)
                    parent = fixture["parent"]
                    child = parent / "Selected child"
                    before = (self.git(child, "rev-parse", "HEAD"), self.git(child, "branch", "--show-current"))
                    self.git(parent, "config", "-f", ".gitmodules", "submodule.selected-section.branch", "does-not-exist")
                    if not initialized:
                        self.forget_selected_worktree(fixture)
                    output = self.shell(source, fixture, "if sync_selected_submodules_to_latest 'Selected child'; then exit 96; fi\n")
                    self.assertNotIn("Selected child 已浅同步", output)
                    if initialized:
                        self.assertEqual(before, (self.git(child, "rev-parse", "HEAD"), self.git(child, "branch", "--show-current")))
                    else:
                        self.assertFalse((child / ".git").exists())

    def test_descendant_missing_branch_never_falls_back_to_remote_default(self) -> None:
        for initialized in (False, True):
            for index, source in enumerate(SOURCES):
                with self.subTest(script=source, initialized=initialized):
                    fixture = self.fixture(f"missing-descendant-{initialized}-{index}", initialized=initialized)
                    self.git(fixture["child"], "config", "-f", ".gitmodules", "submodule.middle-section.branch", "does-not-exist")
                    self.git(fixture["child"], "add", ".gitmodules")
                    self.git(fixture["child"], "commit", "-qm", "invalid explicit descendant branch")
                    middle = fixture["parent"] / "Selected child/中 child"
                    before = (self.git(middle, "rev-parse", "HEAD"), self.git(middle, "branch", "--show-current")) if initialized else None
                    output = self.shell(source, fixture, "if sync_selected_submodules_to_latest 'Selected child'; then exit 97; fi\n")
                    self.assertIn("does-not-exist", output)
                    if initialized:
                        self.assertEqual(before, (self.git(middle, "rev-parse", "HEAD"), self.git(middle, "branch", "--show-current")))
                    else:
                        self.assertFalse((middle / ".git").exists())

    def test_shallow_fetch_can_fast_forward_old_local_main(self) -> None:
        for index, source in enumerate(SOURCES):
            with self.subTest(script=source):
                fixture = self.fixture(f"shallow-main-{index}")
                child = fixture["parent"] / "Selected child"
                self.git(child, "checkout", "-q", "main")
                self.git(child, "fetch", "--depth=1", "origin", fixture["child_old"])
                self.assertEqual("true", self.git(child, "rev-parse", "--is-shallow-repository"))
                self.shell(source, fixture, "SUBMODULE_SHALLOW_CLONE=1\nsync_selected_submodules_to_latest 'Selected child'\n", recursive=0)
                self.assertEqual("main", self.git(child, "branch", "--show-current"))
                self.assertEqual(fixture["child_latest"], self.git(child, "rev-parse", "HEAD"))

    def test_recursive_latest_honors_explicit_and_inherited_branches_without_staging_descendants(self) -> None:
        self.assertTrue(SOURCES, "no retained standalone downloader was found")
        for index, source in enumerate(SOURCES):
            with self.subTest(script=source):
                fixture = self.fixture(f"latest-{index}", relative=True)
                parent = fixture["parent"]
                self.git(parent, "remote", "set-url", "origin", "https://fixture.invalid/team/parent-source")
                self.env["GIT_CONFIG_COUNT"] = "4"
                for config_index, name in enumerate(("child", "middle", "leaf"), 1):
                    self.env[f"GIT_CONFIG_KEY_{config_index}"] = f"url.{(fixture['case'] / name).as_uri()}.insteadOf"
                    self.env[f"GIT_CONFIG_VALUE_{config_index}"] = f"https://fixture.invalid/team/{name}"
                bypass = parent / "Bypass child"
                self.git(bypass, "remote", "set-url", "origin", (fixture["case"] / "unselected-do-not-use").as_uri())
                bypass_repos = (bypass, bypass / "中 child", bypass / "中 child/叶 child")
                before = {repo: self.snapshot(repo) for repo in bypass_repos}
                self.shell(source, fixture, "sync_selected_submodules_to_latest 'Selected child'\nsync_selected_submodules_to_latest 'Selected child'\n")
                child = parent / "Selected child"
                middle = child / "中 child"
                leaf = middle / "叶 child"
                for repo, expected, branch in (
                    (child, fixture["child_latest"], "main"),
                    (middle, fixture["middle_latest"], "feature"),
                    (leaf, fixture["leaf_latest"], "feature"),
                ):
                    self.assertEqual(expected, self.git(repo, "rev-parse", "HEAD"))
                    self.assertEqual(branch, self.git(repo, "branch", "--show-current"))
                    self.assertTrue((repo / ".git").is_file())
                self.assertEqual(fixture["middle_old"], self.git(child, "rev-parse", ":中 child"))
                self.assertEqual(fixture["leaf_old"], self.git(middle, "rev-parse", ":叶 child"))
                self.assertEqual("../child", self.git(parent, "config", "-f", ".gitmodules", "submodule.selected-section.url"))
                self.assertEqual("../middle", self.git(child, "config", "-f", ".gitmodules", "submodule.middle-section.url"))
                self.assertEqual("../leaf", self.git(middle, "config", "-f", ".gitmodules", "submodule.leaf-section.url"))
                self.assertEqual(before, {repo: self.snapshot(repo) for repo in bypass_repos})

    def test_nonrecursive_first_clone_does_not_initialize_descendants_despite_global_recurse(self) -> None:
        for index, source in enumerate(SOURCES):
            with self.subTest(script=source):
                fixture = self.fixture(f"first-{index}")
                parent = fixture["parent"]
                child = parent / "Selected child"
                cache = Path(self.git(child, 'rev-parse', '--absolute-git-dir'))
                self.git(parent, 'submodule', 'deinit', '-f', '--', 'Selected child')
                cache.rename(fixture['case'] / 'saved-selected-cache')
                self.shell(source, fixture, "sync_selected_submodules_to_latest 'Selected child'\n", recursive=0)
                self.assertEqual(fixture["child_latest"], self.git(child, "rev-parse", "HEAD"))
                self.assertFalse((child / "中 child/.git").exists())
                config = Path(self.git(child, "rev-parse", "--absolute-git-dir")) / "config"
                self.assertNotIn("[submodule", config.read_text(encoding="utf-8"))

    def test_nonrecursive_existing_descendants_remain_untouched_despite_global_recurse(self) -> None:
        for index, source in enumerate(SOURCES):
            with self.subTest(script=source):
                fixture = self.fixture(f"existing-{index}", initialized=True)
                child = fixture["parent"] / "Selected child"
                descendants = (child / "中 child", child / "中 child/叶 child")
                for repo in descendants:
                    self.git(repo, "remote", "set-url", "origin", (fixture["case"] / "untouched-origin").as_uri())
                before = {repo: self.snapshot(repo) for repo in descendants}
                self.shell(source, fixture, "sync_selected_submodules_to_latest 'Selected child'\n", recursive=0)
                self.assertEqual(fixture["child_latest"], self.git(child, "rev-parse", "HEAD"))
                self.assertEqual(before, {repo: self.snapshot(repo) for repo in descendants})

    def test_dirty_leaf_without_tty_stops_ancestor_updates_and_preserves_data(self) -> None:
        for index, source in enumerate(SOURCES):
            with self.subTest(script=source):
                fixture = self.fixture(f"dirty-{index}", initialized=True)
                child = fixture["parent"] / "Selected child"
                middle = child / "中 child"
                leaf = middle / "叶 child"
                dirty = leaf / "seed"
                dirty.write_text("uncommitted user work\n", encoding="utf-8")
                before = {repo: self.snapshot(repo) for repo in (child, middle, leaf)}
                output = self.shell(source, fixture, r'''
if sync_selected_submodules_to_latest 'Selected child'; then exit 91; fi
''')
                self.assertIn("尚未提交", output)
                self.assertEqual("uncommitted user work\n", dirty.read_text(encoding="utf-8"))
                self.assertEqual(before, {repo: self.snapshot(repo) for repo in (child, middle, leaf)})

    def test_staged_descendant_gitlink_stops_before_reset_and_preserves_user_index(self) -> None:
        for index, source in enumerate(SOURCES):
            with self.subTest(script=source):
                fixture = self.fixture(f"staged-{index}", initialized=True)
                child = fixture["parent"] / "Selected child"
                middle = child / "中 child"
                self.git(middle, "commit", "--allow-empty", "-qm", "user staged association")
                expected = self.git(middle, "rev-parse", "HEAD")
                self.git(child, "add", "--", "中 child")
                before = self.git(child, "diff", "--cached", "--raw")
                output = self.shell(source, fixture, "if sync_selected_submodules_to_latest 'Selected child'; then exit 95; fi\n")
                self.assertIn("已暂存", output)
                self.assertEqual(fixture["child_old"], self.git(child, "rev-parse", "HEAD"))
                self.assertEqual(expected, self.git(child, "rev-parse", ":中 child"))
                self.assertEqual(before, self.git(child, "diff", "--cached", "--raw"))

    def test_descendant_failure_propagates_and_never_reports_parent_success(self) -> None:
        for index, source in enumerate(SOURCES):
            with self.subTest(script=source):
                fixture = self.fixture(f"failure-{index}")
                middle = fixture["middle"]
                invalid = (fixture["case"] / "missing-leaf").as_uri()
                self.git(middle, "config", "-f", ".gitmodules", "submodule.leaf-section.url", invalid)
                self.git(middle, "add", ".gitmodules")
                self.git(middle, "commit", "-qm", "unavailable leaf")
                output = self.shell(source, fixture, "if sync_selected_submodules_to_latest 'Selected child'; then exit 93; fi\n")
                self.assertIn("递归子模块同步失败", output)
                self.assertNotIn("Selected child 已浅同步", output)
                self.assertNotIn("中 child 已浅同步", output)
                self.assertFalse((fixture["parent"] / "Selected child/中 child/叶 child/.git").exists())

    def test_missing_worktree_restores_from_retained_cache_without_reclone(self) -> None:
        for index, source in enumerate(SOURCES):
            with self.subTest(script=source):
                fixture = self.fixture(f"cache-{index}")
                parent = fixture["parent"]
                child = parent / "Selected child"
                cache = Path(self.git(child, "rev-parse", "--absolute-git-dir"))
                marker = cache / "must-preserve.marker"
                marker.write_text("preserved cache\n", encoding="utf-8")
                shutil.rmtree(child)
                before = {name: (cache / name).read_bytes() for name in ("HEAD", "config", "must-preserve.marker")}
                output = self.shell(source, fixture, "ensure_submodule_worktree_present 'Selected child'\n")
                self.assertIn("复用已有 Git 缓存", output)
                self.assertNotIn("首次克隆", output)
                self.assertEqual(before, {name: (cache / name).read_bytes() for name in before})
                self.assertTrue((child / ".git").is_file())

    def test_parent_pull_never_fetches_or_initializes_children_despite_global_recurse(self) -> None:
        for index, source in enumerate(SOURCES):
            with self.subTest(script=source):
                fixture = self.fixture(f"parent-{index}", initialized=True)
                parent, parent_source = fixture["parent"], fixture["parent-source"]
                for name in ("Selected child", "Bypass child"):
                    upstream_child = parent_source / name
                    self.git(upstream_child, "fetch", "--no-recurse-submodules", "origin")
                    self.git(upstream_child, "checkout", "-q", fixture["child_latest"])
                    self.git(parent_source, "add", "--", name)
                self.git(parent_source, "commit", "-qm", "parent latest associations")
                child = parent / "Selected child"
                repos = (child, child / "中 child", child / "中 child/叶 child", parent / "Bypass child")
                before = {repo: self.snapshot(repo) for repo in repos}
                self.shell(source, fixture, "parent_pull_rebase\n", recursive=0)
                self.assertEqual(self.git(parent_source, "rev-parse", "HEAD"), self.git(parent, "rev-parse", "HEAD"))
                self.assertEqual(before, {repo: self.snapshot(repo) for repo in repos})


if __name__ == "__main__":
    unittest.main(verbosity=2)
