#!/usr/bin/env python3
# Created by Jobs on 2026年10月21日，星期三.
"""Keep configured Markdown filters active at a prepared recursive first checkout."""

from __future__ import annotations

import errno
import json
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

from test_downloaders_latest import SOURCES, render_readonly_engine

INVENTORY_SOURCES = tuple(SOURCES)


class MarkdownTocCheckoutTests(unittest.TestCase):
    """Use real Git and the embedded engine; all remotes and config are disposable."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="jobs-markdown-checkout-")
        self.root = Path(self.tmp.name).resolve()
        self.node = shutil.which("node")
        if not self.node:
            self.tmp.cleanup()
            self.skipTest("Node.js is required by the real Markdown TOC converter")
        self.converter = Path(__file__).resolve().parents[3] / ".jobs-markdown-toc/MarkdownToc.mjs"
        self.assertTrue(self.converter.is_file(), str(self.converter))
        self.original_converter = self.converter.read_text(encoding="utf-8")
        self.global_config = self.root / "isolated.gitconfig"
        self.global_config.write_text("[user]\n\tname = Offline Test\n\temail = offline@example.invalid\n", encoding="utf-8")
        self.journal = self.root / "filter-events.jsonl"
        self.env = {
            key: value for key, value in os.environ.items()
            if not key.startswith("GIT_") and key != "JOBS_GITEE_HTTPS_CONFIGURED"
        }
        # Keep the real HOME unchanged; only Git's configuration sources are isolated.
        self.env.update(
            TMPDIR=str(self.root), GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=str(self.global_config),
            GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="core.hooksPath", GIT_CONFIG_VALUE_0="/dev/null",
            GIT_ALLOW_PROTOCOL="file", GIT_TERMINAL_PROMPT="0", GIT_ASKPASS="/usr/bin/false",
            GIT_SSH_COMMAND="/usr/bin/false", SSH_ASKPASS="/usr/bin/false",
            GIT_AUTHOR_NAME="Offline Test", GIT_AUTHOR_EMAIL="offline@example.invalid",
            GIT_COMMITTER_NAME="Offline Test", GIT_COMMITTER_EMAIL="offline@example.invalid",
            PATH=f"{Path(self.node).parent}:/usr/bin:/bin:/usr/sbin:/sbin", TERM="dumb", NO_COLOR="1",
            JOBS_TOC_TEST_JOURNAL=str(self.journal),
        )
        self.trusted = self.root / "trusted-runtime/MarkdownToc.mjs"
        self.trusted.parent.mkdir()
        self.trusted.write_text(self.instrumented_converter("trusted"), encoding="utf-8")
        self.driver_config = self.root / "trusted-driver.gitconfig"
        for mode in ("clean", "smudge"):
            self.git(self.root, "config", "--file", str(self.driver_config),
                     f"filter.jobs-markdown-toc.{mode}",
                     f"{shlex.quote(self.node)} {shlex.quote(str(self.trusted))} {mode}")
        self.git(self.root, "config", "--file", str(self.driver_config), "filter.jobs-markdown-toc.required", "true")
        self.protected: dict[Path, bytes] = {}

    def tearDown(self) -> None:
        try:
            for path, before in self.protected.items():
                self.assertEqual(before, path.read_bytes(), f"external configuration changed: {path}")
        finally:
            self.tmp.cleanup()

    def instrumented_converter(self, role: str) -> str:
        """Log which trusted/checkout tool runs without changing its conversion logic."""
        prelude = r"""import * as tocTestFS from 'node:fs';
import { spawnSync as tocTestSpawn } from 'node:child_process';
if (process.env.JOBS_TOC_TEST_JOURNAL) {
  const origin = tocTestSpawn('/usr/bin/git', ['config', '--get', 'remote.origin.url'], {encoding: 'utf8'});
  tocTestFS.appendFileSync(process.env.JOBS_TOC_TEST_JOURNAL, JSON.stringify({
    role: ROLE, mode: process.argv[2], cwd: process.cwd(), origin: origin.stdout.trim(),
    readmeExists: tocTestFS.existsSync('README.md'),
  }) + '\n');
}
""".replace("ROLE", json.dumps(role))
        return prelude + self.original_converter

    def git(self, repo: Path, *args: str) -> str:
        result = subprocess.run(
            ["/usr/bin/git", "-c", "core.hooksPath=/dev/null", "-c", "submodule.recurse=false",
             "-c", "fetch.recurseSubmodules=false", "-C", str(repo), *args],
            env=self.env, capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        return result.stdout.rstrip("\n")

    def convert(self, source: str, mode: str) -> str:
        result = subprocess.run([self.node, str(self.trusted), mode], env=self.env,
                                cwd=self.root, input=source, capture_output=True, text=True, timeout=20)
        self.assertEqual(0, result.returncode, result.stderr)
        return result.stdout

    def source_document(self, name: str, revision: str) -> str:
        return f"# {name}\n\n[toc]\n\n## 第一章\n\n{revision} 正文，保留本地编辑。\n\n### 第二级\n\n细节。\n"

    def seed(self, case: Path, name: str, branch: str) -> tuple[Path, Path, str]:
        repo = case / f"{name}-source"
        repo.mkdir()
        self.git(repo, "init", "-q", "-b", branch)
        tools = repo / ".jobs-markdown-toc"
        tools.mkdir()
        (tools / "MarkdownToc.mjs").write_text(self.instrumented_converter("repository"), encoding="utf-8")
        (tools / "manifest.json").write_text(json.dumps({"version": 1, "files": ["README.md"]}) + "\n", encoding="utf-8")
        (repo / ".gitattributes").write_text("README.md filter=jobs-markdown-toc\n", encoding="utf-8")
        source = self.source_document(name, "revision one")
        (repo / "README.md").write_text(self.convert(source, "clean"), encoding="utf-8")
        self.git(repo, "add", ".")
        self.git(repo, "commit", "-qm", "initial generated publication")
        bare = case / f"{name}.git"
        self.git(case, "clone", "-q", "--bare", repo.as_uri(), str(bare))
        return repo, bare, source

    def publish(self, repo: Path, bare: Path, branch: str) -> None:
        """Prepare a disposable remote by fetching locally, without invoking push."""
        self.git(bare, "fetch", "-q", repo.as_uri(), f"HEAD:refs/heads/{branch}")

    def link(self, repo: Path, path: str, section: str, url: str, branch: str, pin: str) -> None:
        for key, value in (("path", path), ("url", url), ("branch", branch)):
            self.git(repo, "config", "-f", ".gitmodules", f"submodule.{section}.{key}", value)
        self.git(repo, "add", ".gitmodules")
        self.git(repo, "update-index", "--add", "--cacheinfo", f"160000,{pin},{path}")
        self.git(repo, "commit", "-qm", "pin nested child")

    def register(self, urls: dict[str, str], bares: dict[str, Path]) -> None:
        for key, url in urls.items():
            self.git(self.root, "config", "--file", str(self.global_config),
                     f"url.{bares[key].as_uri()}.insteadOf", url)
            self.git(self.root, "config", "--file", str(self.global_config),
                     f"includeIf.hasconfig:remote.*.url:{url}.path", str(self.driver_config))
        self.protected = {path: path.read_bytes() for path in (self.global_config, self.driver_config, self.trusted)}

    def fixture(self, name: str) -> dict:
        case = self.root / name
        case.mkdir()
        branches = {"parent": "main", "child": "release", "leaf": "trunk"}
        seeds, bares, documents = {}, {}, {}
        for key, branch in branches.items():
            seeds[key], bares[key], documents[key] = self.seed(case, key, branch)
        urls = {key: f"https://github.com/JobsTocOffline/{name}-{key}.git" for key in branches}
        self.link(seeds["child"], "叶 child", "leaf section", urls["leaf"], branches["leaf"], self.git(seeds["leaf"], "rev-parse", "HEAD"))
        self.publish(seeds["child"], bares["child"], branches["child"])
        self.link(seeds["parent"], "Selected child", "child section", urls["child"], branches["child"], self.git(seeds["child"], "rev-parse", "HEAD"))
        self.publish(seeds["parent"], bares["parent"], branches["parent"])
        self.register(urls, bares)
        parent = case / "parent"
        self.git(case, "clone", "-q", "--no-recurse-submodules", urls["parent"], str(parent))
        self.journal.write_text("", encoding="utf-8")
        return {"case": case, "parent": parent, "seeds": seeds, "bares": bares,
                "urls": urls, "branches": branches, "documents": documents}

    def engine(self, source: Path) -> str:
        return render_readonly_engine(source)

    def run_engine(self, source: Path, fixture: dict) -> tuple[int, str]:
        script = fixture["case"] / "readonly-engine.zsh"
        script.write_text(self.engine(source), encoding="utf-8")
        master, slave = pty.openpty()
        process = subprocess.Popen(["/bin/zsh", str(script), "--terminal-run", str(fixture["parent"])],
                                   cwd=fixture["case"], env=self.env, stdin=slave, stdout=slave, stderr=slave)
        os.close(slave)
        output = bytearray()
        deadline = time.monotonic() + 60
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
        for path, before in self.protected.items():
            self.assertEqual(before, path.read_bytes(), f"external configuration changed: {path}")
        return process.returncode, output.decode(errors="replace")

    def events(self) -> list[dict]:
        return [json.loads(line) for line in self.journal.read_text(encoding="utf-8").splitlines() if line]

    def run_restore(self, source: Path, repo: Path, *, embedded: bool, no_node: bool = False) -> tuple[int, str]:
        content = self.engine(source) if embedded else source.read_text(encoding="utf-8")
        library = repo.parent / "restore-library.zsh"
        library.write_text(re.sub(r'(?m)^main "\$@"\s*$', "", content), encoding="utf-8")
        env = dict(self.env)
        if no_node:
            env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        external_before = {path: path.read_bytes() for path in (self.global_config, self.driver_config, self.trusted)}
        result = subprocess.run(
            ["/bin/zsh", "-f", "-c", 'source "$1"; restore_configured_markdown_toc "$2"',
             "isolated-restore", str(library), str(repo)],
            cwd=repo, env=env, stdin=subprocess.DEVNULL,
            capture_output=True, text=True, timeout=25,
        )
        for path, before in external_before.items():
            self.assertEqual(before, path.read_bytes(), f"external configuration changed: {path}")
        return result.returncode, result.stdout + result.stderr

    def assert_publication_and_worktree(self, repo: Path, source: str, branch: str, url: str) -> None:
        self.assertEqual(source, (repo / "README.md").read_text(encoding="utf-8"))
        generated = self.convert(source, "clean")
        self.assertIn("<details>", generated)
        self.assertEqual(generated.rstrip("\n"), self.git(repo, "show", "HEAD:README.md"))
        self.assertEqual(generated.rstrip("\n"), self.git(repo, "show", ":README.md"))
        self.assertEqual(branch, self.git(repo, "branch", "--show-current"))
        self.assertEqual(f"origin/{branch}", self.git(repo, "rev-parse", "--abbrev-ref", "@{upstream}"))
        self.assertEqual(url, self.git(repo, "config", "--get", "remote.origin.url"))
        self.assertEqual("", self.git(repo, "status", "--porcelain=v1", "--untracked-files=all"))
        local_keys = self.git(repo, "config", "--local", "--name-only", "--list").splitlines()
        self.assertFalse(any(key.startswith("filter.") for key in local_keys), local_keys)

    def test_prepared_recursive_first_checkout_uses_real_remote_before_smudge_and_later_updates(self) -> None:
        self.assertEqual(7, len(INVENTORY_SOURCES), "update the inventory if a maintained downloader is added or removed")
        for index, source in enumerate(SOURCES):
            with self.subTest(script=source):
                fixture = self.fixture(f"checkout-{index}")
                code, output = self.run_engine(source, fixture)
                self.assertEqual(0, code, output)
                repos = {"parent": fixture["parent"], "child": fixture["parent"] / "Selected child",
                         "leaf": fixture["parent"] / "Selected child/叶 child"}
                first_events = self.events()
                for key in ("child", "leaf"):
                    events = [event for event in first_events if event["origin"] == fixture["urls"][key]]
                    first_smudge = next((event for event in events if event["mode"] == "smudge"), None)
                    self.assertIsNotNone(first_smudge, f"{key}: initial checkout bypassed the configured smudge; {events}")
                    # 首次检出在直属父仓的受控暂存区完成，随后才原子移入最终路径。
                    parent_repo = repos["parent" if key == "child" else "child"]
                    stage_parent = Path(self.git(parent_repo, "rev-parse", "--absolute-git-dir")) / "jobs-download-cache/worktrees"
                    smudge_root = Path(first_smudge["cwd"])
                    self.assertEqual(stage_parent, smudge_root.parent.parent)
                    self.assertTrue(smudge_root.parent.name.startswith("checkout."))
                    self.assertEqual("worktree", smudge_root.name)
                    self.assertEqual("trusted", first_smudge["role"])
                    self.assertEqual(fixture["urls"][key], first_smudge["origin"])
                    self.assertFalse(first_smudge["readmeExists"], "first checkout must write [toc] directly")
                    self.assertNotIn("install", [event["mode"] for event in events])
                    self.assertNotIn("smudge", [event["mode"] for event in events if event["role"] == "repository"])
                for key, repo in repos.items():
                    self.assert_publication_and_worktree(repo, fixture["documents"][key], fixture["branches"][key], fixture["urls"][key])
                # Neither a no-op fetch nor checkout rewrites an old generated file.
                # The configured restore step must repair it before child readiness checks.
                indexes = {key: self.git(repo, "ls-files", "--stage") for key, repo in repos.items()}
                for key, repo in repos.items():
                    (repo / "README.md").write_text(self.convert(fixture["documents"][key], "clean"), encoding="utf-8")
                code, output = self.run_engine(source, fixture)
                self.assertEqual(0, code, output)
                for key, repo in repos.items():
                    self.assertEqual(indexes[key], self.git(repo, "ls-files", "--stage"))
                    self.assert_publication_and_worktree(repo, fixture["documents"][key], fixture["branches"][key], fixture["urls"][key])
                for key in ("leaf", "child", "parent"):
                    seed = fixture["seeds"][key]
                    fixture["documents"][key] = self.source_document(key, "revision two latest")
                    (seed / "README.md").write_text(self.convert(fixture["documents"][key], "clean"), encoding="utf-8")
                    self.git(seed, "add", "README.md")
                    if key != "leaf":
                        child_key, path = ("leaf", "叶 child") if key == "child" else ("child", "Selected child")
                        self.git(seed, "update-index", "--cacheinfo", f"160000,{self.git(fixture['seeds'][child_key], 'rev-parse', 'HEAD')},{path}")
                    self.git(seed, "commit", "-qm", "advance branch without reinstalling filters")
                    self.publish(seed, fixture["bares"][key], fixture["branches"][key])
                code, output = self.run_engine(source, fixture)
                self.assertEqual(0, code, output)
                for key, repo in repos.items():
                    self.assertEqual(self.git(fixture["seeds"][key], "rev-parse", "HEAD"), self.git(repo, "rev-parse", "HEAD"))
                    self.assert_publication_and_worktree(repo, fixture["documents"][key], fixture["branches"][key], fixture["urls"][key])
                self.assertNotIn("install", [event["mode"] for event in self.events()])

    def test_configured_restore_preserves_uncommitted_body_and_original_index(self) -> None:
        for index, source in enumerate(SOURCES):
            for embedded in (False, True):
                with self.subTest(script=source, embedded=embedded):
                    case = self.root / f"body-{index}-{embedded}"
                    case.mkdir()
                    repo, _, original = self.seed(case, "edited", "main")
                    url = f"https://github.com/JobsTocOffline/edited-{index}-{embedded}.git"
                    self.git(repo, "remote", "add", "origin", url)
                    self.git(self.root, "config", "--file", str(self.global_config),
                             f"includeIf.hasconfig:remote.*.url:{url}.path", str(self.driver_config))
                    self.protected = {path: path.read_bytes() for path in (self.global_config, self.driver_config, self.trusted)}
                    edited = original.replace("revision one", "用户尚未提交的新增内容")
                    (repo / "README.md").write_text(self.convert(edited, "clean"), encoding="utf-8")
                    (repo / "staged.txt").write_text("partial staging remains\n", encoding="utf-8")
                    self.git(repo, "add", "staged.txt")
                    (repo / "untracked.txt").write_text("untracked remains\n", encoding="utf-8")
                    before_head = self.git(repo, "rev-parse", "HEAD")
                    before_index = self.git(repo, "ls-files", "--stage")
                    before_config = (repo / ".git/config").read_bytes()
                    self.journal.write_text("", encoding="utf-8")
                    code, output = self.run_restore(source, repo, embedded=embedded)
                    self.assertEqual(0, code, output)
                    self.assertEqual(edited, (repo / "README.md").read_text(encoding="utf-8"))
                    self.assertEqual(before_head, self.git(repo, "rev-parse", "HEAD"))
                    self.assertEqual(before_index, self.git(repo, "ls-files", "--stage"))
                    self.assertEqual(before_config, (repo / ".git/config").read_bytes())
                    self.assertEqual("untracked remains\n", (repo / "untracked.txt").read_text(encoding="utf-8"))
                    modes = [event["mode"] for event in self.events() if event["role"] == "repository"]
                    self.assertEqual(["restore", "verify"], modes)

    def test_unconfigured_restore_skips_missing_runtime_and_never_executes_repository_tool(self) -> None:
        for index, source in enumerate(SOURCES):
            for embedded in (False, True):
                with self.subTest(script=source, embedded=embedded):
                    case = self.root / f"skip-{index}-{embedded}"
                    case.mkdir()
                    repo, _, _ = self.seed(case, "unconfigured", "main")
                    tool = repo / ".jobs-markdown-toc/MarkdownToc.mjs"
                    tool.write_text("throw new Error('unconfigured repository tool must never run');\n", encoding="utf-8")
                    before = {"readme": (repo / "README.md").read_bytes(),
                              "config": (repo / ".git/config").read_bytes(),
                              "head": self.git(repo, "rev-parse", "HEAD"),
                              "index": self.git(repo, "ls-files", "--stage")}
                    self.journal.write_text("", encoding="utf-8")
                    code, output = self.run_restore(source, repo, embedded=embedded, no_node=True)
                    self.assertEqual(0, code, output)
                    self.assertIn("跳过", output)
                    self.assertEqual(before["readme"], (repo / "README.md").read_bytes())
                    self.assertEqual(before["config"], (repo / ".git/config").read_bytes())
                    self.assertEqual(before["head"], self.git(repo, "rev-parse", "HEAD"))
                    self.assertEqual(before["index"], self.git(repo, "ls-files", "--stage"))
                    self.assertEqual([], self.events())

    def test_configured_missing_tool_process_conflict_and_unfinished_git_stop_without_installing(self) -> None:
        for index, source in enumerate(SOURCES):
            for embedded in (False, True):
                for failure in ("missing-tool", "missing-directory", "process-conflict", "process-only", "unfinished-git"):
                    with self.subTest(script=source, embedded=embedded, failure=failure):
                        case = self.root / f"reject-{index}-{embedded}-{failure}"
                        case.mkdir()
                        repo, _, _ = self.seed(case, "configured", "main")
                        self.git(repo, "config", "filter.jobs-markdown-toc.smudge",
                                 f"{shlex.quote(self.node)} {shlex.quote(str(self.trusted))} smudge")
                        tool = repo / ".jobs-markdown-toc/MarkdownToc.mjs"
                        if failure == "missing-tool":
                            tool.unlink()
                        elif failure == "missing-directory":
                            shutil.rmtree(tool.parent)
                        elif failure in ("process-conflict", "process-only"):
                            self.git(repo, "config", "filter.jobs-markdown-toc.process", "/usr/bin/false")
                            if failure == "process-only":
                                self.git(repo, "config", "--unset", "filter.jobs-markdown-toc.smudge")
                        else:
                            (repo / ".git/MERGE_HEAD").write_text(self.git(repo, "rev-parse", "HEAD") + "\n", encoding="utf-8")
                        before = ((repo / "README.md").read_bytes(), (repo / ".git/config").read_bytes(),
                                  self.git(repo, "rev-parse", "HEAD"), self.git(repo, "ls-files", "--stage"))
                        self.journal.write_text("", encoding="utf-8")
                        code, output = self.run_restore(source, repo, embedded=embedded)
                        self.assertNotEqual(0, code, output)
                        if failure == "process-only":
                            self.assertIn("process", output)
                            self.assertNotIn("跳过", output)
                        self.assertEqual(before, ((repo / "README.md").read_bytes(), (repo / ".git/config").read_bytes(),
                                                  self.git(repo, "rev-parse", "HEAD"), self.git(repo, "ls-files", "--stage")))
                        self.assertEqual([], self.events())

    def test_unconfigured_missing_directory_skips_without_runtime_or_writes(self) -> None:
        for index, source in enumerate(SOURCES):
            for embedded in (False, True):
                with self.subTest(script=source, embedded=embedded):
                    case = self.root / f"missing-directory-{index}-{embedded}"
                    case.mkdir()
                    repo, _, _ = self.seed(case, "unconfigured", "main")
                    shutil.rmtree(repo / ".jobs-markdown-toc")
                    before = ((repo / "README.md").read_bytes(), (repo / ".git/config").read_bytes(),
                              self.git(repo, "rev-parse", "HEAD"), self.git(repo, "ls-files", "--stage"))
                    self.journal.write_text("", encoding="utf-8")
                    code, output = self.run_restore(source, repo, embedded=embedded, no_node=True)
                    self.assertEqual(0, code, output)
                    self.assertIn("跳过", output)
                    self.assertFalse((repo / ".jobs-markdown-toc").exists())
                    self.assertEqual(before, ((repo / "README.md").read_bytes(), (repo / ".git/config").read_bytes(),
                                              self.git(repo, "rev-parse", "HEAD"), self.git(repo, "ls-files", "--stage")))
                    self.assertEqual([], self.events())


if __name__ == "__main__":
    unittest.main()
