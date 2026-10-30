#!/usr/bin/env python3
# Created by Jobs on 2026年10月27日，星期二.
"""Exercise persistent download objects and bounded retries without network access."""

from __future__ import annotations

import errno
import json
import os
from pathlib import Path
import pty
import re
import select
import shlex
import signal
import subprocess
import sys
import tempfile
import time
import unittest

from test_downloaders_latest import GENESIS, SCRIPT_NAME, SOURCES as DOWNLOADER_SOURCES, render_readonly_engine


# 全部同名入口共享下载蓝本，包含JobsBaseConfig的独立配置。
SOURCES = list(DOWNLOADER_SOURCES)


class DownloadResumeTests(unittest.TestCase):
    """All Git repositories, credentials, transport failures and settings are disposable."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="jobs-download-resume-")
        self.root = Path(self.tmp.name).resolve()
        self.home = self.root / "home"
        self.home.mkdir()
        self.global_config = self.home / "gitconfig"
        self.global_config.write_text("[test]\n\tpreserved = true\n", encoding="utf-8")
        self.global_before = self.global_config.read_bytes()
        self.source = GENESIS / SCRIPT_NAME
        self.env = {
            key: value for key, value in os.environ.items()
            if not key.startswith(("GIT_", "JOBS_DOWNLOAD_", "JOBS_TEST_"))
        }
        self.env.update(
            HOME=str(self.home), TMPDIR=str(self.root),
            XDG_CONFIG_HOME=str(self.home / "xdg"),
            GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=str(self.global_config),
            GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="core.hooksPath",
            GIT_CONFIG_VALUE_0="/dev/null", GIT_ALLOW_PROTOCOL="file",
            GIT_TERMINAL_PROMPT="0", GIT_ASKPASS="/usr/bin/false",
            GIT_SSH_COMMAND="/usr/bin/false", SSH_ASKPASS="/usr/bin/false",
            GIT_AUTHOR_NAME="Offline Test", GIT_AUTHOR_EMAIL="offline@example.invalid",
            GIT_COMMITTER_NAME="Offline Test", GIT_COMMITTER_EMAIL="offline@example.invalid",
            PATH="/usr/bin:/bin:/usr/sbin:/sbin", NO_COLOR="1", TERM="dumb",
            JOBS_DOWNLOAD_TIMEOUT="20", JOBS_DOWNLOAD_ATTEMPTS="1",
            JOBS_DOWNLOAD_RETRY_DELAY="0", JOBS_DOWNLOAD_LOW_SPEED_LIMIT="1",
            JOBS_DOWNLOAD_LOW_SPEED_TIME="2",
        )
        self.serial = 0

    def tearDown(self) -> None:
        self.assertEqual(self.global_before, self.global_config.read_bytes())
        self.tmp.cleanup()

    def git(self, repo: Path, *args: str) -> str:
        result = subprocess.run(
            ["/usr/bin/git", "-c", "core.hooksPath=/dev/null", "-c", "submodule.recurse=false",
             "-c", "fetch.recurseSubmodules=false", "-C", str(repo), *args],
            env=self.env, capture_output=True, text=True, timeout=20,
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        return result.stdout.strip()

    def repository(self, name: str) -> Path:
        repo = self.root / name
        repo.mkdir(parents=True)
        self.git(repo, "init", "-q", "-b", "main")
        self.commit(repo, "initial")
        return repo

    def commit(self, repo: Path, label: str) -> str:
        (repo / "seed").write_text(label + "\n", encoding="utf-8")
        self.git(repo, "add", "seed")
        self.git(repo, "commit", "-qm", label)
        return self.git(repo, "rev-parse", "HEAD")

    def shell(self, body: str, *, source: Path | None = None, cwd: Path | None = None,
              env: dict[str, str] | None = None, expected: int = 0) -> str:
        self.serial += 1
        library = self.root / f"library-{self.serial}.zsh"
        library.write_text(
            re.sub(r'(?m)^main "\$@"\s*$', "", (source or self.source).read_text()),
            encoding="utf-8",
        )
        setup = r'''setopt ERR_EXIT PIPE_FAIL NO_NOMATCH
source "$1"
shift
CASE_ROOT="$1"
LOG_FILE="$CASE_ROOT/output.log"
REPO_ROOT="$PWD"
'''
        process = subprocess.Popen(
            ["/bin/zsh", "-f", "-c", setup + body, "offline-resume", str(library), str(self.root)],
            cwd=cwd or self.root, env=env or self.env, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, start_new_session=True,
        )
        try:
            stdout, stderr = process.communicate(timeout=90)
        except subprocess.TimeoutExpired:
            process.terminate()
            try:
                stdout, stderr = process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                stdout, stderr = process.communicate(timeout=5)
            self.fail("fixture shell timed out: " + stdout + stderr)
        self.assertEqual(expected, process.returncode, stdout + stderr)
        return stdout + stderr

    def engine(self, repo: Path, env: dict[str, str] | None = None) -> tuple[int, str]:
        engine = render_readonly_engine(self.source)
        script = self.root / "engine.zsh"
        script.write_text(engine, encoding="utf-8")
        master, slave = pty.openpty()
        process = subprocess.Popen(
            ["/bin/zsh", str(script), "--terminal-run", str(repo)],
            cwd=self.root, env=env or self.env, stdin=slave, stdout=slave, stderr=slave,
            start_new_session=True,
        )
        os.close(slave)
        output = bytearray()
        deadline = time.monotonic() + 90
        try:
            os.write(master, b"\n")
            while time.monotonic() < deadline:
                ready, _, _ = select.select([master], [], [], 0.1)
                if ready:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError as error:
                        if error.errno == errno.EIO:
                            break
                        raise
                    if not chunk:
                        break
                    output.extend(chunk)
                if process.poll() is not None and not ready:
                    break
            else:
                self.fail("download engine timed out: " + output.decode(errors="replace"))
            process.wait(timeout=5)
            return process.returncode, output.decode(errors="replace")
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=5)
            os.close(master)

    def shim(self) -> dict[str, str]:
        """A Git shim injects failures before delegating every real operation to file-only Git."""
        binary_dir = self.root / "bin"
        binary_dir.mkdir(exist_ok=True)
        shim = binary_dir / "git"
        handler = binary_dir / "git-transport.py"
        handler.write_text(r'''
import json
import os
from pathlib import Path
import subprocess
import sys
import time

args = sys.argv[1:]
trace_args = list(args)
working_directory = Path.cwd()
for index, argument in enumerate(args[:-1]):
    if argument == "-C":
        working_directory = (working_directory / args[index + 1]).resolve()
        trace_args[index + 1] = str(working_directory)
mode = os.environ.get("JOBS_TEST_MODE", "")
is_fetch = "fetch" in args
if any(operation in args for operation in ("fetch", "checkout", "ls-remote")):
    with open(os.environ["JOBS_TEST_OPERATION_TRACE"], "a", encoding="utf-8") as trace:
        trace.write(json.dumps({"args": trace_args}) + "\n")
if is_fetch:
    record = {"args": trace_args}
    expected = os.environ.get("JOBS_TEST_EXPECT_REUSE_OID", "")
    source = os.environ.get("JOBS_TEST_EXPECT_REUSE_URL", "")
    if expected and source in args:
        index = args.index("-C")
        found = subprocess.run(["/usr/bin/git", "-C", args[index + 1], "cat-file", "-e", expected],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        record["reused_object"] = found.returncode == 0
    with open(os.environ["JOBS_TEST_TRACE"], "a", encoding="utf-8") as trace:
        trace.write(json.dumps(record) + "\n")
    fail_url = os.environ.get("JOBS_TEST_FAIL_URL", "")
    marker = Path(os.environ["JOBS_TEST_MARKER"])
    if mode == "persistent" and fail_url in args and marker.exists():
        print("fatal: unable to access file fixture: Connection reset by peer", file=sys.stderr)
        sys.exit(128)
    if mode == "transient" and not marker.exists():
        marker.write_text("failed once")
        print("fatal: unable to access file fixture: Connection reset by peer", file=sys.stderr)
        sys.exit(128)
    if mode == "auth":
        print("fatal: Authentication failed for 'https://fixture.invalid/repo'", file=sys.stderr)
        sys.exit(128)
    if mode == "sensitive":
        print("PASSTHROUGH-STDOUT", flush=True)
        for chunk in (b"fatal: Authentication failed for '\x1b[31mhttps://user-secret:",
                      b"password-secret@fixture.invalid/repo?access_token=", b"query-secret'\x1b[0m\r",
                      b"https://another-secret:final-password@fixture.invalid/repo?key=", b"eof-secret"):
            os.write(2, chunk)
            time.sleep(0.1)
        sys.exit(128)
    if mode == "sleep":
        child = subprocess.Popen(["/bin/sleep", "300"])
        Path(os.environ["JOBS_TEST_CHILD_PID"]).write_text(str(child.pid))
        time.sleep(300)
os.execv("/usr/bin/git", ["/usr/bin/git", *args])
''', encoding="utf-8")
        shim.write_text(
            '#!/bin/sh\nfor argument in "$@"; do\n'
            '  case "$argument" in --get-url) exec /usr/bin/git "$@" ;; esac\n'
            'done\nfor argument in "$@"; do\n'
            '  case "$argument" in\n'
            f'    fetch|checkout|ls-remote) exec {shlex.quote(sys.executable)} {shlex.quote(str(handler))} "$@" ;;\n'
            '  esac\ndone\nexec /usr/bin/git "$@"\n',
            encoding="utf-8",
        )
        shim.chmod(0o755)
        env = dict(self.env)
        env.update(
            PATH=f"{binary_dir}:{self.env['PATH']}", JOBS_TEST_TRACE=str(self.root / "trace.jsonl"),
            JOBS_TEST_MARKER=str(self.root / "fail.marker"),
            JOBS_TEST_CHILD_PID=str(self.root / "child.pid"),
            JOBS_TEST_OPERATION_TRACE=str(self.root / "operations.jsonl"),
        )
        return env

    def events(self) -> list[dict]:
        trace = self.root / "trace.jsonl"
        return [json.loads(line) for line in trace.read_text().splitlines()] if trace.exists() else []

    def operations(self) -> list[list[str]]:
        trace = self.root / "operations.jsonl"
        return [json.loads(line)["args"] for line in trace.read_text().splitlines()] if trace.exists() else []

    def recursive_fixture(self) -> tuple[Path, Path, Path]:
        leaf = self.repository("leaf")
        child = self.repository("child")
        seed = self.repository("parent-source")
        self.git(child, "submodule", "add", "-q", leaf.as_uri(), "叶 child")
        self.git(child, "commit", "-qam", "nested leaf")
        self.git(seed, "submodule", "add", "-q", child.as_uri(), "A child")
        self.git(seed, "config", "-f", ".gitmodules", "submodule.A child.branch", "main")
        self.git(seed, "commit", "-qam", "child")
        parent = self.root / "parent"
        self.git(self.root, "clone", "-q", "--no-recurse-submodules", seed.as_uri(), str(parent))
        return parent, child, leaf

    def test_readonly_markers_skip_transfer_revalidate_and_keep_descendants_current(self) -> None:
        parent, child_remote, leaf_remote = self.recursive_fixture()
        env = self.shim()
        code, output = self.engine(parent, env)
        self.assertEqual(0, code, output)
        child = parent / "A child"
        leaf = child / "叶 child"
        marker_paths = [Path(self.git(repo, "rev-parse", "--absolute-git-dir")) / "jobs-download-complete"
                        for repo in (parent, child, leaf)]
        self.assertTrue(all(marker.is_file() for marker in marker_paths), output)

        cursor = len(self.operations())
        code, output = self.engine(parent, env)
        self.assertEqual(0, code, output)
        operations = self.operations()[cursor:]
        self.assertFalse(any("fetch" in args or "checkout" in args for args in operations), operations)
        self.assertGreaterEqual(sum("ls-remote" in args and "--get-url" not in args for args in operations), 3)

        cursor = len(self.operations())
        leaf_latest = self.commit(leaf_remote, "leaf remote advances")
        code, output = self.engine(parent, env)
        self.assertEqual(0, code, output)
        self.assertEqual(leaf_latest, self.git(leaf, "rev-parse", "HEAD"))
        transfers = [args for args in self.operations()[cursor:] if "fetch" in args]
        self.assertTrue(transfers, output)
        self.assertTrue(all(str(leaf) in args for args in transfers), transfers)

        cursor = len(self.operations())
        child_latest = self.commit(child_remote, "child remote advances")
        code, output = self.engine(parent, env)
        self.assertEqual(0, code, output)
        self.assertEqual(child_latest, self.git(child, "rev-parse", "HEAD"))
        self.assertTrue(any("fetch" in args and str(child) in args for args in self.operations()[cursor:]))

        marker_paths[1].unlink()
        cursor = len(self.operations())
        code, output = self.engine(parent, env)
        self.assertEqual(0, code, output)
        self.assertTrue(marker_paths[1].is_file())
        self.assertTrue(any("fetch" in args and str(child) in args for args in self.operations()[cursor:]))

        (leaf / "seed").write_text("uncommitted user work\n", encoding="utf-8")
        cursor = len(self.operations())
        code, output = self.engine(parent, env)
        self.assertNotEqual(0, code, output)
        self.assertEqual("uncommitted user work\n", (leaf / "seed").read_text())
        self.assertFalse(any("checkout" in args for args in self.operations()[cursor:]), output)

    def test_management_markers_skip_current_child_and_recurse_into_updated_leaf(self) -> None:
        parent, child_remote, leaf_remote = self.recursive_fixture()
        env = self.shim()
        body = f'''
SUBMODULE_RECURSIVE=1
SUBMODULE_SHALLOW_CLONE=1
SUBMODULE_DEPTH=1
SUBMODULE_FETCH_TAGS=0
GIT_URL_STYLE=auto
REMOTE_NAME=origin
ensure_submodule_worktree_present 'A child' {shlex.quote(child_remote.as_uri())} main 0
sync_one_submodule_to_latest 'A child' {shlex.quote(child_remote.as_uri())} main
'''
        self.shell(body, cwd=parent, env=env)
        child = parent / "A child"
        leaf = child / "叶 child"
        cursor = len(self.operations())
        self.shell(body, cwd=parent, env=env)
        operations = self.operations()[cursor:]
        self.assertFalse(any("fetch" in args or "checkout" in args for args in operations), operations)
        self.assertTrue(any("ls-remote" in args and "--get-url" not in args for args in operations))
        cursor = len(self.operations())
        leaf_latest = self.commit(leaf_remote, "leaf latest through parent marker")
        self.shell(body, cwd=parent, env=env)
        self.assertEqual(leaf_latest, self.git(leaf, "rev-parse", "HEAD"))
        transfers = [args for args in self.operations()[cursor:] if "fetch" in args]
        self.assertTrue(transfers)
        self.assertTrue(all(str(leaf) in args for args in transfers), transfers)

    def test_cache_identity_survives_reorder_and_separates_sources(self) -> None:
        parent = self.repository("parent 中文")
        first = self.repository("first")
        second = self.repository("second")
        for source in SOURCES:
            with self.subTest(source=source):
                self.shell(f'''
first="$(jobs_download_cache_repository "$PWD" "$PWD/child 中文" {shlex.quote(first.as_uri())})"
other="$(jobs_download_cache_repository "$PWD" "$PWD/other" {shlex.quote(first.as_uri())})"
again="$(jobs_download_cache_repository "$PWD" "$PWD/child 中文" {shlex.quote(first.as_uri())})"
changed="$(jobs_download_cache_repository "$PWD" "$PWD/child 中文" {shlex.quote(second.as_uri())})"
[[ "$first" == "$again" && "$first" != "$other" && "$first" != "$changed" ]]
[[ "$(git -C "$first" rev-parse --is-bare-repository)" == true ]]
''', source=source, cwd=parent)

    def test_each_copy_revalidates_marker_source_branch_head_and_dirty_files(self) -> None:
        remote = self.repository("remote")
        target = self.root / "target"
        self.git(self.root, "clone", "-q", remote.as_uri(), str(target))
        original = self.git(remote, "rev-parse", "HEAD")
        latest = self.commit(remote, "new remote version")
        for source in SOURCES:
            with self.subTest(source=source):
                self.shell(f'''
url={shlex.quote(remote.as_uri())}
old={shlex.quote(original)}
latest={shlex.quote(latest)}
jobs_download_write_marker "$PWD" "$url" main "$old"
jobs_download_marker_matches "$PWD" "$url" main "$old"
[[ "$(jobs_download_remote_tip "$PWD" "$url" main)" == "$latest" ]]
if jobs_download_marker_matches "$PWD" "$url" main "$latest"; then exit 91; fi
if jobs_download_marker_matches "$PWD" "$url/" main "$old"; then exit 92; fi
if jobs_download_marker_matches "$PWD" "$url" feature "$old"; then exit 93; fi
print -r -- 'uncommitted user content' > seed
if jobs_download_marker_matches "$PWD" "$url" main "$old"; then exit 94; fi
git checkout -- seed
marker="$(git rev-parse --absolute-git-dir)/jobs-download-complete"
rm -- "$marker"
if jobs_download_marker_matches "$PWD" "$url" main "$old"; then exit 95; fi
jobs_download_write_marker "$PWD" "$url" main "$old"
jobs_download_marker_matches "$PWD" "$url" main "$old"
''', source=source, cwd=target)

    def test_management_lock_lasts_until_exit_and_preserves_cache(self) -> None:
        remote = self.repository("remote")
        for termination in ("normal", "term"):
            with self.subTest(termination=termination):
                parent = self.repository(f"parent-{termination}")
                library = self.root / f"lock-library-{termination}.zsh"
                library.write_text(re.sub(r'(?m)^main "\$@"\s*$', "", self.source.read_text()), encoding="utf-8")
                ready = self.root / f"ready-{termination}"
                finish = self.root / f"finish-{termination}"
                body = r'''setopt ERR_EXIT PIPE_FAIL NO_NOMATCH
source "$1"
REPO_ROOT="$PWD"
LOG_FILE="$2"
SCRIPT_BASENAME=lock-fixture
acquire_download_lock
[[ -d "$DOWNLOAD_LOCK_DIRECTORY" ]]
jobs_download_git -C "$PWD" ls-remote --heads "$5" main > /dev/null
jobs_download_git -C "$PWD" status --porcelain > /dev/null
[[ -d "$DOWNLOAD_LOCK_DIRECTORY" ]]
prepare_preview_runtime
cache="$(jobs_download_cache_repository "$PWD" "$PWD/child" "$5")"
print -rl -- "$DOWNLOAD_LOCK_DIRECTORY" "$PREVIEW_FILE" "$cache" > "$3"
while [[ ! -e "$4" ]]; do /bin/sleep 0.05; done
'''
                process = subprocess.Popen(
                    ["/bin/zsh", "-f", "-c", body, "offline-lock", str(library), str(self.root / "lock.log"),
                     str(ready), str(finish), remote.as_uri()],
                    cwd=parent, env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    text=True, start_new_session=True,
                )
                try:
                    deadline = time.monotonic() + 10
                    while not ready.exists() and process.poll() is None and time.monotonic() < deadline:
                        time.sleep(0.05)
                    self.assertTrue(ready.is_file(), "lock holder did not become ready")
                    lock, preview, cache = [Path(line) for line in ready.read_text().splitlines()]
                    self.assertTrue(lock.is_dir())
                    self.assertTrue(preview.is_file())
                    sentinel = cache / "retained.marker"
                    sentinel.write_text("persistent objects stay", encoding="utf-8")
                    self.shell('if acquire_download_lock; then exit 91; fi\n', cwd=parent)
                    self.assertTrue(lock.is_dir(), "competing process released the holder's lock")
                    if termination == "term":
                        process.terminate()
                    else:
                        finish.touch()
                    stdout, stderr = process.communicate(timeout=8)
                    self.assertEqual(143 if termination == "term" else 0, process.returncode, stdout + stderr)
                    self.assertFalse(lock.exists())
                    self.assertFalse(preview.exists())
                    self.assertTrue(sentinel.is_file())
                finally:
                    if process.poll() is None:
                        process.terminate()
                        try:
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            os.killpg(process.pid, signal.SIGKILL)
                            process.wait(timeout=5)
                    process.stdout.close()
                    process.stderr.close()

    def test_failed_later_child_keeps_completed_objects_for_next_run(self) -> None:
        leaf = self.repository("leaf")
        first = self.repository("first")
        second = self.repository("second")
        seed = self.repository("parent-source")
        self.git(first, "submodule", "add", "-q", leaf.as_uri(), "叶 child")
        self.git(first, "commit", "-qam", "nested leaf")
        for section, remote, path in (("first", first, "A first"), ("second", second, "Z second")):
            self.git(seed, "submodule", "add", "-q", "--name", section, remote.as_uri(), path)
            self.git(seed, "config", "-f", ".gitmodules", f"submodule.{section}.branch", "main")
        self.git(seed, "commit", "-qam", "children")
        parent = self.root / "parent"
        self.git(self.root, "clone", "-q", "--no-recurse-submodules", seed.as_uri(), str(parent))
        target = self.git(first, "rev-parse", "HEAD")
        env = self.shim()
        env.update(JOBS_TEST_MODE="persistent", JOBS_TEST_FAIL_URL=second.as_uri())
        marker = Path(env["JOBS_TEST_MARKER"])
        marker.touch()
        before_head = self.git(parent, "rev-parse", "HEAD")
        before_index = self.git(parent, "diff", "--cached", "--raw")
        code, output = self.engine(parent, env)
        self.assertNotEqual(0, code, output)
        self.assertFalse((parent / "A first/.git").exists(), output)
        cache_output = self.shell(
            f'jobs_download_cache_repository "$PWD" "$PWD/A first" {shlex.quote(first.as_uri())}\n', cwd=parent,
        )
        cache = Path(cache_output.strip().splitlines()[-1])
        self.assertTrue(cache.is_dir(), output + cache_output)
        self.git(cache, "cat-file", "-e", target)
        kept = cache / "retained.marker"
        kept.write_text("keep complete objects", encoding="utf-8")
        marker.unlink()
        env.update(JOBS_TEST_EXPECT_REUSE_OID=target, JOBS_TEST_EXPECT_REUSE_URL=first.as_uri())
        code, output = self.engine(parent, env)
        self.assertEqual(0, code, output)
        self.assertTrue(kept.exists())
        self.assertTrue(any(event.get("reused_object") for event in self.events()))
        for repo, remote in ((parent / "A first", first), (parent / "A first/叶 child", leaf), (parent / "Z second", second)):
            self.assertEqual(self.git(remote, "rev-parse", "HEAD"), self.git(repo, "rev-parse", "HEAD"))
            self.assertEqual("main", self.git(repo, "branch", "--show-current"))
            self.assertTrue((repo / ".git").is_file())
        self.assertEqual(before_head, self.git(parent, "rev-parse", "HEAD"))
        self.assertEqual(before_index, self.git(parent, "diff", "--cached", "--raw"))
        self.assertFalse((parent / ".git/jobs-readonly-pull.lock").exists())

    def test_existing_full_and_shallow_children_keep_ancestor_history(self) -> None:
        for shallow in (False, True):
            with self.subTest(shallow=shallow):
                remote = self.repository(f"remote-{shallow}")
                seed = self.repository(f"source-{shallow}")
                self.git(seed, "submodule", "add", "-q", remote.as_uri(), "child")
                self.git(seed, "commit", "-qam", "child")
                parent = self.root / f"parent-{shallow}"
                self.git(self.root, "clone", "-q", "--no-recurse-submodules", seed.as_uri(), str(parent))
                self.git(parent, "submodule", "update", "--init")
                child = parent / "child"
                old = self.git(child, "rev-parse", "HEAD")
                self.git(child, "checkout", "-q", "main")
                if shallow:
                    self.git(child, "fetch", "--depth=1", "origin", old)
                for number in range(4):
                    latest = self.commit(remote, f"remote update {number}")
                code, output = self.engine(parent)
                self.assertEqual(0, code, output)
                self.assertEqual(latest, self.git(child, "rev-parse", "HEAD"))
                self.git(child, "merge-base", "--is-ancestor", old, latest)
                self.assertEqual("4", self.git(child, "rev-list", "--count", f"{old}..{latest}"))
                if not shallow:
                    self.assertEqual("false", self.git(child, "rev-parse", "--is-shallow-repository"))

    def test_transport_retries_transient_failure_and_preserves_result(self) -> None:
        remote = self.repository("remote")
        target = self.repository("target")
        env = self.shim()
        env.update(JOBS_TEST_MODE="transient", JOBS_DOWNLOAD_ATTEMPTS="3")
        self.shell(f'jobs_download_git -C "$PWD" fetch --no-tags -- {shlex.quote(remote.as_uri())} refs/heads/main:refs/remotes/test/main\n', cwd=target, env=env)
        self.assertEqual(2, len(self.events()))
        self.assertEqual(self.git(remote, "rev-parse", "HEAD"), self.git(target, "rev-parse", "refs/remotes/test/main"))

    def test_authentication_failure_is_not_retried(self) -> None:
        repo = self.repository("repo")
        env = self.shim()
        env.update(JOBS_TEST_MODE="auth", JOBS_DOWNLOAD_ATTEMPTS="3")
        output = self.shell('jobs_download_git -C "$PWD" fetch --no-tags file:///unused refs/heads/main\n', cwd=repo, env=env, expected=128)
        self.assertEqual(1, len(self.events()), output)

    def test_chunked_stderr_redacts_credentials_and_cleans_private_diagnostics(self) -> None:
        repo = self.repository("repo")
        env = self.shim()
        env.update(JOBS_TEST_MODE="sensitive", JOBS_DOWNLOAD_ATTEMPTS="3")
        output = self.shell('jobs_download_git -C "$PWD" fetch --no-tags file:///unused refs/heads/main\n', cwd=repo, env=env, expected=128)
        self.assertIn("PASSTHROUGH-STDOUT", output)
        for secret in ("user-secret", "password-secret", "query-secret", "another-secret", "final-password", "eof-secret", "\x1b"):
            self.assertNotIn(secret, output)
        self.assertEqual(1, len(self.events()), output)
        self.assertFalse(list(self.root.glob("jobs-git-transfer.*")))

    def test_timeout_stops_git_descendants_and_returns_failure(self) -> None:
        repo = self.repository("repo")
        env = self.shim()
        env.update(JOBS_TEST_MODE="sleep", JOBS_DOWNLOAD_TIMEOUT="1")
        started = time.monotonic()
        output = self.shell('jobs_download_git -C "$PWD" fetch --no-tags file:///unused refs/heads/main\n', cwd=repo, env=env, expected=124)
        self.assertLess(time.monotonic() - started, 12, output)
        self.assert_mock_child_stopped(env, output)

    def assert_mock_child_stopped(self, env: dict[str, str], output: str) -> None:
        pid = int(Path(env["JOBS_TEST_CHILD_PID"]).read_text())
        try:
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline:
                try:
                    os.kill(pid, 0)
                except ProcessLookupError:
                    break
                time.sleep(0.05)
            else:
                self.fail(f"timeout left Git child {pid} running: {output}")
        finally:
            try:
                os.kill(pid, 9)
            except ProcessLookupError:
                pass

    def test_termination_cancels_once_and_stops_git_descendants(self) -> None:
        repo = self.repository("repo")
        env = self.shim()
        env.update(JOBS_TEST_MODE="sleep", JOBS_DOWNLOAD_ATTEMPTS="3")
        output = self.shell(r'''
jobs_download_git -C "$PWD" fetch --no-tags file:///unused refs/heads/main &
transfer_pid=$!
for attempt in {1..100}; do
  [[ -f "$JOBS_TEST_CHILD_PID" ]] && break
  /bin/sleep 0.05
done
[[ -f "$JOBS_TEST_CHILD_PID" ]]
kill -TERM "$transfer_pid"
if wait "$transfer_pid"; then exit 91; else transfer_result=$?; fi
[[ "$transfer_result" == 143 ]]
''', cwd=repo, env=env)
        self.assertEqual(1, len(self.events()), output)
        self.assert_mock_child_stopped(env, output)

    def test_invalid_transfer_settings_stop_before_transport(self) -> None:
        for key, values in {
            "JOBS_DOWNLOAD_TIMEOUT": ("0", "-1", "abc", "86401"),
            "JOBS_DOWNLOAD_ATTEMPTS": ("0", "11"),
            "JOBS_DOWNLOAD_RETRY_DELAY": ("-1", "61"),
            "JOBS_DOWNLOAD_LOW_SPEED_LIMIT": ("0", "1000000001"),
            "JOBS_DOWNLOAD_LOW_SPEED_TIME": ("0", "3601"),
        }.items():
            for value in values:
                with self.subTest(setting=key, value=value):
                    env = dict(self.env, **{key: value})
                    self.shell('if jobs_download_validate_settings; then exit 91; fi\n', env=env)
        self.shell('jobs_download_validate_settings\n', env=dict(self.env, JOBS_DOWNLOAD_TIMEOUT="0001", JOBS_DOWNLOAD_RETRY_DELAY="0"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
