#!/usr/bin/env python3
# test_download_transport_audit.py
# JobsCommand@Gits · Git 下载传输与真实入口锁回归
# Created by Jobs on 2026年10月27日，星期二.
"""Regress partial retry output, one-query branch resolution and entry locking offline."""

from __future__ import annotations

import os
from pathlib import Path
import re
import signal
import subprocess
import tempfile
import time
import unittest

from test_downloaders_latest import GENESIS, SCRIPT_NAME


FIRST_SHA = "1" * 40
LATEST_SHA = "2" * 40


class DownloadTransportAuditTests(unittest.TestCase):
    """Load the shipped downloader; mock only network transport in a private HOME."""

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="jobs-download-audit-")
        self.root = Path(self.temporary.name).resolve()
        self.home = self.root / "home"
        self.home.mkdir()
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.binary_dir = self.root / "bin"
        self.binary_dir.mkdir()
        self.count_file = self.root / "count"
        self.library = self.root / "library.zsh"
        source = (GENESIS / SCRIPT_NAME).read_text(encoding="utf-8")
        self.library.write_text(re.sub(r'(?m)^main "\$@"\s*$', "", source), encoding="utf-8")
        self.environment = {
            "HOME": str(self.home), "ZDOTDIR": str(self.home), "TMPDIR": str(self.root),
            "PATH": f"{self.binary_dir}:/usr/bin:/bin:/usr/sbin:/sbin",
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_ALLOW_PROTOCOL": "file", "GIT_TERMINAL_PROMPT": "0",
            "GIT_ASKPASS": "/usr/bin/false", "GIT_SSH_COMMAND": "/usr/bin/false",
            "SSH_ASKPASS": "/usr/bin/false", "NO_COLOR": "1", "TERM": "dumb",
            "JOBS_DOWNLOAD_TIMEOUT": "10", "JOBS_DOWNLOAD_ATTEMPTS": "3",
            "JOBS_DOWNLOAD_RETRY_DELAY": "0", "JOBS_TEST_COUNT_FILE": str(self.count_file),
            "JOBS_TEST_FIRST_SHA": FIRST_SHA, "JOBS_TEST_LATEST_SHA": LATEST_SHA,
            "JOBS_TEST_MODE": "partial",
        }
        subprocess.run(["/usr/bin/git", "-C", str(self.repo), "init", "-q"], env=self.environment, check=True)
        shim = self.binary_dir / "git"
        shim.write_text(r'''#!/bin/sh
network=0
for argument do
  [ "$argument" != ls-remote ] || network=1
done
[ "$network" = 1 ] || exec /usr/bin/git "$@"
count=0
[ ! -f "$JOBS_TEST_COUNT_FILE" ] || count=$(cat "$JOBS_TEST_COUNT_FILE")
count=$((count + 1))
printf '%s\n' "$count" > "$JOBS_TEST_COUNT_FILE"
case "$JOBS_TEST_MODE" in
  partial)
    if [ "$count" = 1 ]; then
      printf '%s\trefs/heads/main\n' "$JOBS_TEST_FIRST_SHA"
      printf 'fatal: Connection reset by peer\n' >&2
      exit 128
    fi
    printf '%s\trefs/heads/main\n' "$JOBS_TEST_LATEST_SHA"
    ;;
  explicit) printf '%s\trefs/heads/main\n' "$JOBS_TEST_LATEST_SHA" ;;
  default)
    printf 'ref: refs/heads/main\tHEAD\n%s\tHEAD\n' "$JOBS_TEST_LATEST_SHA"
    ;;
  malformed) printf '%s\trefs/heads/main\n%s\trefs/heads/main\n' "$JOBS_TEST_FIRST_SHA" "$JOBS_TEST_LATEST_SHA" ;;
  *) exit 2 ;;
esac
''', encoding="utf-8")
        shim.chmod(0o700)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def shell(self, body: str, *, mode: str = "partial", expected: int = 0) -> subprocess.CompletedProcess[str]:
        environment = {**self.environment, "JOBS_TEST_MODE": mode}
        result = subprocess.run(
            ["/bin/zsh", "-f", "-c", 'source "$1"\nREPO_ROOT="$2"\nLOG_FILE="$3"\n' + body,
             "audit", str(self.library), str(self.repo), str(self.root / "output.log")],
            env=environment, capture_output=True, text=True, timeout=20,
        )
        self.assertEqual(expected, result.returncode, result.stdout + result.stderr)
        return result

    def test_ls_remote_retry_discards_partial_failed_stdout(self) -> None:
        result = self.shell('jobs_download_remote_tip "$REPO_ROOT" https://fixture.invalid/repo main')
        self.assertEqual(LATEST_SHA, result.stdout.strip())
        self.assertEqual("2", self.count_file.read_text().strip())
        self.assertFalse(list(self.root.glob("jobs-git-query.*")))

    def test_remote_branch_and_tip_share_one_query(self) -> None:
        for mode, requested in (("explicit", "main"), ("default", "")):
            with self.subTest(mode=mode):
                self.count_file.unlink(missing_ok=True)
                result = self.shell(
                    f'jobs_download_remote_branch "$REPO_ROOT" https://fixture.invalid/repo "{requested}"', mode=mode,
                )
                self.assertEqual(f"main\t{LATEST_SHA}", result.stdout.strip())
                self.assertEqual("1", self.count_file.read_text().strip())

    def test_remote_branch_rejects_ambiguous_listing(self) -> None:
        self.shell(
            'jobs_download_remote_branch "$REPO_ROOT" https://fixture.invalid/repo main',
            mode="malformed", expected=1,
        )

    def test_remote_branch_rejects_invalid_name_before_query(self) -> None:
        self.shell(
            'jobs_download_remote_branch "$REPO_ROOT" https://fixture.invalid/repo "main..bad"',
            mode="explicit", expected=1,
        )
        self.assertFalse(self.count_file.exists())

    def test_remote_branch_rejects_invalid_commit_hash(self) -> None:
        self.environment["JOBS_TEST_LATEST_SHA"] = "not-a-commit"
        self.shell(
            'jobs_download_remote_branch "$REPO_ROOT" https://fixture.invalid/repo main',
            mode="explicit", expected=1,
        )

    def test_remote_default_branch_accepts_sha256(self) -> None:
        self.environment["JOBS_TEST_LATEST_SHA"] = "a" * 64
        result = self.shell(
            'jobs_download_remote_branch "$REPO_ROOT" https://fixture.invalid/repo ""', mode="default",
        )
        self.assertEqual("main\t" + "a" * 64, result.stdout.strip())
        self.assertEqual("1", self.count_file.read_text().strip())

    def test_real_management_dispatch_releases_lock_on_success_and_failure(self) -> None:
        for operation_status in (0, 17):
            with self.subTest(operation_status=operation_status):
                result = self.shell(r'''
select_download_operation_mode() { DOWNLOAD_OPERATION_MODE=maintenance; }
run_selected_download_mode() {
  acquire_download_lock
  print -r -- "LOCK-HELD:${ZSH_SUBSHELL}"
  return ''' + str(operation_status) + r'''
}
offer_global_markdown_toc_setup() { :; }
run_download_selection_loop
operation_result=$?
[[ ! -d "$REPO_ROOT/.git/jobs-readonly-pull.lock" ]] || { print STALE-LOCK; exit 90; }
exit "$operation_result"
''', expected=operation_status)
                self.assertIn("LOCK-HELD:1", result.stdout)

    def test_real_management_dispatch_keeps_lock_during_competition(self) -> None:
        holder = r'''
source "$1"
REPO_ROOT="$2"
LOG_FILE="$3"
select_download_operation_mode() { DOWNLOAD_OPERATION_MODE=maintenance; }
run_selected_download_mode() {
  acquire_download_lock
  local repository_top="$(git -C "$REPO_ROOT" rev-parse --show-toplevel)"
  [[ -d "$DOWNLOAD_LOCK_DIRECTORY" ]] || exit 91
  /bin/sleep 1
}
offer_global_markdown_toc_setup() { :; }
run_download_selection_loop
'''
        process = subprocess.Popen(
            ["/bin/zsh", "-f", "-c", holder, "holder", str(self.library), str(self.repo), str(self.root / "holder.log")],
            env=self.environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True,
        )
        try:
            lock = self.repo / ".git/jobs-readonly-pull.lock"
            deadline = time.monotonic() + 5
            while not lock.exists() and process.poll() is None and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue(lock.exists(), "holder did not acquire its entry lock")
            contender = self.shell('acquire_download_lock', expected=1)
            self.assertIn("下载任务可能正在运行", contender.stderr + contender.stdout)
            self.assertTrue(lock.exists(), "contender or command substitution released the holder lock")
            stdout, stderr = process.communicate(timeout=10)
            self.assertEqual(0, process.returncode, stdout + stderr)
            self.assertFalse(lock.exists(), "successful holder leaked its entry lock")
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.communicate(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.communicate(timeout=3)


if __name__ == "__main__":
    unittest.main(verbosity=2)
