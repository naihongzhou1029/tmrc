"""Integration tests for the TMRC CLI (direct dotnet invocation)."""
from __future__ import annotations

import os
import re
import shutil
import time
from pathlib import Path

import pytest

# Make helpers importable from test/
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))
from helpers import assert_exit, assert_out, run_cli, wait_for_file


# ---------------------------------------------------------------------------
# Helpers local to this module
# ---------------------------------------------------------------------------

def _has_ffmpeg() -> bool:
    return shutil.which("ffmpeg") is not None


# ---------------------------------------------------------------------------
# Basic CLI commands (no daemon)
# ---------------------------------------------------------------------------

class TestCliBasic:
    def test_version_is_semver(self, cli_dll, isolated_storage):
        config_dir, _ = isolated_storage
        proc = run_cli(cli_dll, ["--version"], cwd=config_dir)
        assert_exit(proc, 0)
        combined = (proc.stdout or "") + (proc.stderr or "")
        assert re.search(r"\d+\.\d+\.\d+", combined), (
            f"--version output does not contain a semver string: {combined!r}"
        )

    def test_no_args_shows_usage(self, cli_dll, isolated_storage):
        config_dir, _ = isolated_storage
        proc = run_cli(cli_dll, [], cwd=config_dir)
        assert_exit(proc, 1)
        combined = (proc.stdout or "") + (proc.stderr or "")
        assert any(phrase in combined.lower() for phrase in ("usage:", "commands:")), (
            f"Expected usage info in output: {combined!r}"
        )

    def test_unknown_subcommand(self, cli_dll, isolated_storage):
        config_dir, _ = isolated_storage
        proc = run_cli(cli_dll, ["frobnicate"], cwd=config_dir)
        assert proc.returncode != 0, "Expected non-zero exit for unknown command"
        combined = (proc.stdout or "") + (proc.stderr or "")
        assert "frobnicate" in combined.lower(), (
            f"Expected error to name the bad command: {combined!r}"
        )
        # No unhandled CLR exception stack trace
        assert "unhandled exception" not in combined.lower(), (
            f"Unexpected CLR exception in output: {combined!r}"
        )


# ---------------------------------------------------------------------------
# install / uninstall
# ---------------------------------------------------------------------------

class TestCliInstall:
    def test_install_creates_dirs(self, cli_dll, isolated_storage):
        config_dir, storage_dir = isolated_storage
        proc = run_cli(cli_dll, ["install"], cwd=config_dir)
        assert_exit(proc, 0)
        assert (storage_dir / "segments").exists(), "segments/ dir missing"
        assert (storage_dir / "index").exists(), "index/ dir missing"

    def test_install_idempotent(self, cli_dll, isolated_storage):
        config_dir, storage_dir = isolated_storage
        proc1 = run_cli(cli_dll, ["install"], cwd=config_dir)
        assert_exit(proc1, 0)
        proc2 = run_cli(cli_dll, ["install"], cwd=config_dir)
        assert_exit(proc2, 0)
        assert (storage_dir / "segments").exists()
        assert (storage_dir / "index").exists()


class TestCliUninstall:
    def test_uninstall_removes_shortcut(self, cli_dll, isolated_storage):
        config_dir, _ = isolated_storage
        run_cli(cli_dll, ["install"], cwd=config_dir)
        proc = run_cli(cli_dll, ["uninstall"], cwd=config_dir)
        assert_exit(proc, 0)
        startup_dir = (
            Path(os.environ.get("APPDATA", ""))
            / "Microsoft/Windows/Start Menu/Programs/Startup"
        )
        shortcut = startup_dir / "tmrc.lnk"
        assert not shortcut.exists(), f"Shortcut still exists: {shortcut}"

    def test_uninstall_remove_data_deletes_storage(self, cli_dll, isolated_storage):
        config_dir, storage_dir = isolated_storage
        run_cli(cli_dll, ["install"], cwd=config_dir)
        proc = run_cli(cli_dll, ["uninstall", "--remove-data"], cwd=config_dir)
        assert_exit(proc, 0)
        assert not storage_dir.exists(), f"Storage dir still exists: {storage_dir}"


# ---------------------------------------------------------------------------
# record / stop / status
# ---------------------------------------------------------------------------

@pytest.mark.integration
class TestCliRecord:
    def test_record_writes_pid(self, cli_dll, isolated_storage, stop_daemon):
        config_dir, storage_dir = isolated_storage
        run_cli(cli_dll, ["install"], cwd=config_dir)
        proc = run_cli(cli_dll, ["record"], cwd=config_dir, capture=False)
        assert_exit(proc, 0)
        pid_file = storage_dir / "tmrc.pid"
        wait_for_file(pid_file, timeout=5.0)
        content = pid_file.read_text(encoding="utf-8").strip()
        assert content.isdigit(), f"PID file content is not an integer: {content!r}"

    def test_record_idempotent(self, cli_dll, isolated_storage, stop_daemon):
        config_dir, storage_dir = isolated_storage
        run_cli(cli_dll, ["install"], cwd=config_dir)
        run_cli(cli_dll, ["record"], cwd=config_dir, capture=False)
        wait_for_file(storage_dir / "tmrc.pid", timeout=5.0)
        # Second record exits immediately (no new daemon), so capture=True is safe
        proc2 = run_cli(cli_dll, ["record"], cwd=config_dir)
        assert_exit(proc2, 0)
        combined = (proc2.stdout or "") + (proc2.stderr or "")
        assert any(phrase in combined.lower() for phrase in ("already recording", "already running")), (
            f"Expected 'already recording' in output: {combined!r}"
        )
        # Only one PID file
        assert (storage_dir / "tmrc.pid").exists()

    def test_stop_removes_pid(self, cli_dll, isolated_storage):
        config_dir, storage_dir = isolated_storage
        run_cli(cli_dll, ["install"], cwd=config_dir)
        run_cli(cli_dll, ["record"], cwd=config_dir, capture=False)
        wait_for_file(storage_dir / "tmrc.pid", timeout=5.0)
        time.sleep(1)
        proc = run_cli(cli_dll, ["stop"], cwd=config_dir)
        assert_exit(proc, 0)
        time.sleep(1)
        assert not (storage_dir / "tmrc.pid").exists(), "PID file still exists after stop"

    def test_stop_when_not_recording(self, cli_dll, isolated_storage):
        config_dir, _ = isolated_storage
        run_cli(cli_dll, ["install"], cwd=config_dir)
        proc = run_cli(cli_dll, ["stop"], cwd=config_dir)
        assert_exit(proc, 0)
        combined = (proc.stdout or "") + (proc.stderr or "")
        assert any(phrase in combined.lower() for phrase in ("not currently recording", "not recording", "no daemon")), (
            f"Expected 'not recording' or similar in output: {combined!r}"
        )


@pytest.mark.integration
class TestCliStatus:
    def test_status_not_recording(self, cli_dll, isolated_storage):
        config_dir, storage_dir = isolated_storage
        run_cli(cli_dll, ["install"], cwd=config_dir)
        proc = run_cli(cli_dll, ["status"], cwd=config_dir)
        assert_exit(proc, 0)
        combined = (proc.stdout or "") + (proc.stderr or "")
        assert combined.strip(), "status output is empty"
        # Should mention the storage path or disk info
        assert str(storage_dir).lower() in combined.lower() or "storage" in combined.lower(), (
            f"Expected storage path in status output: {combined!r}"
        )

    def test_status_while_recording(self, cli_dll, isolated_storage, stop_daemon):
        config_dir, storage_dir = isolated_storage
        run_cli(cli_dll, ["install"], cwd=config_dir)
        run_cli(cli_dll, ["record"], cwd=config_dir, capture=False)
        wait_for_file(storage_dir / "tmrc.pid", timeout=5.0)
        proc = run_cli(cli_dll, ["status"], cwd=config_dir)
        assert_exit(proc, 0)
        combined = (proc.stdout or "") + (proc.stderr or "")
        assert any(phrase in combined.lower() for phrase in ("daemon", "recording", "pid")), (
            f"Expected daemon/recording info in status: {combined!r}"
        )


# ---------------------------------------------------------------------------
# wipe / reindex
# ---------------------------------------------------------------------------

@pytest.mark.integration
class TestCliWipe:
    def test_wipe_empties_dirs(self, cli_dll, isolated_storage):
        config_dir, storage_dir = isolated_storage
        run_cli(cli_dll, ["install"], cwd=config_dir)
        proc = run_cli(cli_dll, ["wipe"], cwd=config_dir)
        assert_exit(proc, 0)
        if (storage_dir / "segments").exists():
            assert not list((storage_dir / "segments").iterdir()), "segments/ not empty after wipe"
        if (storage_dir / "index").exists():
            assert not list((storage_dir / "index").iterdir()), "index/ not empty after wipe"
        assert not (storage_dir / "tmrc.pid").exists(), "PID file exists after wipe"


@pytest.mark.integration
class TestCliReindex:
    def test_reindex_empty_storage(self, cli_dll, isolated_storage):
        config_dir, _ = isolated_storage
        run_cli(cli_dll, ["install"], cwd=config_dir)
        proc = run_cli(cli_dll, ["reindex"], cwd=config_dir)
        # With no recorded segments the CLI exits 1 and prints a meaningful
        # message ("No index found…"). That is correct — verify no CLR crash.
        assert proc.returncode in (0, 1), f"Unexpected exit code: {proc.returncode}"
        combined = (proc.stdout or "") + (proc.stderr or "")
        assert "unhandled exception" not in combined.lower(), (
            f"Unexpected CLR exception: {combined!r}"
        )
        assert combined.strip(), "reindex produced no output at all"

    def test_reindex_force_flag(self, cli_dll, isolated_storage):
        config_dir, _ = isolated_storage
        run_cli(cli_dll, ["install"], cwd=config_dir)
        proc = run_cli(cli_dll, ["reindex", "--force"], cwd=config_dir)
        assert proc.returncode in (0, 1), f"Unexpected exit code: {proc.returncode}"
        combined = (proc.stdout or "") + (proc.stderr or "")
        assert "unhandled exception" not in combined.lower(), (
            f"Unexpected CLR exception: {combined!r}"
        )
        assert combined.strip(), "reindex --force produced no output at all"


# ---------------------------------------------------------------------------
# export
# ---------------------------------------------------------------------------

@pytest.mark.integration
class TestCliExport:
    def test_export_empty_no_crash(self, cli_dll, isolated_storage, tmp_path):
        config_dir, _ = isolated_storage
        out_mp4 = tmp_path / "out.mp4"
        run_cli(cli_dll, ["install"], cwd=config_dir)
        proc = run_cli(
            cli_dll,
            ["export", "--from", "1h ago", "--to", "now", "-o", str(out_mp4)],
            cwd=config_dir,
            timeout=60,
        )
        # Exit 0 or 1 accepted — what matters is no CLR exception
        combined = (proc.stdout or "") + (proc.stderr or "")
        assert "unhandled exception" not in combined.lower(), (
            f"Unexpected CLR exception: {combined!r}"
        )

    @pytest.mark.slow
    @pytest.mark.skipif(not _has_ffmpeg(), reason="ffmpeg not available")
    def test_export_produces_mp4(self, cli_dll, isolated_storage, tmp_path, stop_daemon):
        config_dir, storage_dir = isolated_storage
        out_mp4 = tmp_path / "out.mp4"
        run_cli(cli_dll, ["install"], cwd=config_dir)
        run_cli(cli_dll, ["record"], cwd=config_dir, capture=False)
        wait_for_file(storage_dir / "tmrc.pid", timeout=5.0)
        time.sleep(3)
        run_cli(cli_dll, ["stop"], cwd=config_dir, timeout=15)
        time.sleep(1)

        proc = run_cli(
            cli_dll,
            ["export", "--from", "10m ago", "--to", "now", "-o", str(out_mp4)],
            cwd=config_dir,
            timeout=120,
        )
        assert_exit(proc, 0)
        assert out_mp4.exists(), f"Output MP4 not found: {out_mp4}"
        assert out_mp4.stat().st_size > 0, "Output MP4 is empty"
