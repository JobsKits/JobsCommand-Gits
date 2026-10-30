#!/usr/bin/env python3
# test_download_transport_tty.py
# JobsCommand@Gits · Git 下载传输终端回归
# Created by Jobs on 2026年10月27日，星期二.
"""Verify controlling-terminal handoff with disposable Git shims and no network."""

from __future__ import annotations

import errno
import os
from pathlib import Path
import pty
import select
import signal
import tempfile
import time
import unittest

from test_downloaders_latest import GENESIS, SCRIPT_NAME


class DownloadTransportTTYTests(unittest.TestCase):
    """Exercise actual PTY reads, foreground Ctrl+C and parent-terminal recovery."""

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="jobs-download-tty-")
        self.root = Path(self.temporary.name).resolve()
        self.home = self.root / "home"
        self.home.mkdir()
        self.binary_dir = self.root / "bin"
        self.binary_dir.mkdir()
        content = (GENESIS / SCRIPT_NAME).read_text(encoding="utf-8")
        start = "# >>> Jobs download transport >>>"
        end = "# <<< Jobs download transport <<<"
        self.module = self.root / "transport.zsh"
        self.module.write_text(
            start + content.split(start, 1)[1].split(end, 1)[0] + end + "\n",
            encoding="utf-8",
        )
        self.git_pid_file = self.root / "git.pid"
        self.child_pid_file = self.root / "child.pid"
        mock = self.binary_dir / "git"
        mock.write_text(
            r'''#!/bin/sh
printf '%s\n' "$$" > "$JOBS_TEST_GIT_PID_FILE"
case "$JOBS_TEST_TTY_MODE" in
  authenticate)
    printf 'Username: ' >&2
    IFS= read -r username || exit 9
    printf 'Password: ' >&2
    IFS= read -r password || exit 10
    printf 'AUTH:%s:%s\n' "$username" "${#password}"
    ;;
  cancel)
    trap 'exit 130' INT
    sleep 300 &
    printf '%s\n' "$!" > "$JOBS_TEST_CHILD_PID_FILE"
    printf 'GIT-READY\n' >&2
    wait
    ;;
  *) exit 11 ;;
esac
''',
            encoding="utf-8",
        )
        mock.chmod(0o700)
        self.environment = {
            "HOME": str(self.home),
            "ZDOTDIR": str(self.home),
            "TMPDIR": str(self.root),
            "PATH": f"{self.binary_dir}:/usr/bin:/bin:/usr/sbin:/sbin",
            "TERM": "xterm-256color",
            "LANG": "C",
            "NO_COLOR": "1",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_ALLOW_PROTOCOL": "file",
            "GIT_ASKPASS": "/usr/bin/false",
            "GIT_SSH_COMMAND": "/usr/bin/false",
            "SSH_ASKPASS": "/usr/bin/false",
            "JOBS_DOWNLOAD_TIMEOUT": "20",
            "JOBS_DOWNLOAD_ATTEMPTS": "1",
            "JOBS_DOWNLOAD_RETRY_DELAY": "0",
            "JOBS_TEST_GIT_PID_FILE": str(self.git_pid_file),
            "JOBS_TEST_CHILD_PID_FILE": str(self.child_pid_file),
        }
        self.session_pid = 0
        self.master = -1
        self.wait_status: int | None = None
        self.output = bytearray()
        self.groups: set[int] = set()

    def tearDown(self) -> None:
        """Signal only groups created by this fixture, including a detached Git group."""
        for pid_file in (self.git_pid_file, self.child_pid_file):
            if pid_file.exists():
                try:
                    group = os.getpgid(int(pid_file.read_text().strip()))
                except (ProcessLookupError, ValueError):
                    continue
                if group != os.getpgrp():
                    self.groups.add(group)
        if self.session_pid:
            self.groups.add(self.session_pid)
        for group in self.groups:
            self._signal_group(group, signal.SIGTERM)
        deadline = time.monotonic() + 3
        while self.session_pid and self.wait_status is None and time.monotonic() < deadline:
            self._poll()
            time.sleep(0.05)
        for group in self.groups:
            self._signal_group(group, signal.SIGKILL)
        if self.session_pid and self.wait_status is None:
            _, self.wait_status = os.waitpid(self.session_pid, 0)
        if self.master >= 0:
            os.close(self.master)
        self.temporary.cleanup()

    @staticmethod
    def _signal_group(group: int, signum: signal.Signals) -> None:
        try:
            os.killpg(group, signum)
        except ProcessLookupError:
            pass

    def _poll(self) -> None:
        if self.wait_status is None:
            child, status = os.waitpid(self.session_pid, os.WNOHANG)
            if child:
                self.wait_status = status

    def _read(self) -> None:
        if not select.select([self.master], [], [], 0.05)[0]:
            return
        try:
            chunk = os.read(self.master, 65536)
        except OSError as error:
            if error.errno == errno.EIO:
                return
            raise
        self.output.extend(chunk)

    def _read_until(self, marker: str, timeout: float = 10) -> None:
        deadline = time.monotonic() + timeout
        target = marker.encode()
        while time.monotonic() < deadline:
            self._read()
            if target in self.output:
                return
            self._poll()
            if self.wait_status is not None:
                break
        self.fail(f"PTY did not reach {marker!r}: {self.output.decode(errors='replace')}")

    def _send(self, value: bytes) -> None:
        os.write(self.master, value)

    def _start(self, mode: str) -> None:
        """pty.fork gives the child a new session and its own controlling terminal."""
        environment = {**self.environment, "JOBS_TEST_TTY_MODE": mode}
        shell = r'''setopt NO_NOMATCH
source "$1"
if jobs_download_git fetch origin; then
  transfer_result=0
else
  transfer_result=$?
fi
print -r -- "TRANSPORT-RC:${transfer_result}"
IFS= read -r 'after?PARENT-INPUT: ' || exit 12
print -r -- "PARENT-RESTORED:${after}"
exit "$transfer_result"
'''
        self.session_pid, self.master = pty.fork()
        if self.session_pid == 0:
            os.chdir(self.root)
            os.execve("/bin/zsh", ["/bin/zsh", "-f", "-c", shell, "tty-fixture", str(self.module)], environment)

    def _finish(self, expected_status: int) -> str:
        self._read_until("PARENT-INPUT: ")
        self._send(b"parent-input\n")
        self._read_until("PARENT-RESTORED:parent-input")
        deadline = time.monotonic() + 10
        while self.wait_status is None and time.monotonic() < deadline:
            self._read()
            self._poll()
        self.assertIsNotNone(self.wait_status, self.output.decode(errors="replace"))
        self.assertEqual(expected_status, os.waitstatus_to_exitcode(self.wait_status))
        self.assertFalse(list(self.root.glob("jobs-git-transfer.*")))
        return self.output.decode(errors="replace")

    def test_username_password_prompts_read_tty_and_restore_parent(self) -> None:
        self._start("authenticate")
        self._read_until("Username: ")
        self._send(b"fixture-user\n")
        self._read_until("Password: ")
        self._send(b"fixture-password\n")
        output = self._finish(0)
        self.assertIn("AUTH:fixture-user:16", output)
        self.assertIn("TRANSPORT-RC:0", output)

    def test_ctrl_c_returns_130_cleans_descendants_and_restores_parent(self) -> None:
        self._start("cancel")
        self._read_until("GIT-READY")
        child_pid = int(self.child_pid_file.read_text().strip())
        self.groups.add(os.getpgid(child_pid))
        self._send(b"\x03")
        output = self._finish(130)
        self.assertIn("TRANSPORT-RC:130", output)
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            try:
                os.kill(child_pid, 0)
            except ProcessLookupError:
                break
            time.sleep(0.05)
        else:
            self.fail(f"Git descendant remains after Ctrl+C: {child_pid}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
