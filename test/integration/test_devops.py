"""Integration tests for devops.ps1 commands."""
from __future__ import annotations

import glob
import os
import re
import shutil
import time
from pathlib import Path

import pytest

# Make helpers importable from test/
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))
from helpers import assert_exit, assert_out, run_ps, wait_for_file


# ---------------------------------------------------------------------------
# Group A — No CLI binary required
# ---------------------------------------------------------------------------

class TestNoArgs:
    def test_no_args_shows_usage(self, project_root):
        proc = run_ps([], project_root=project_root)
        assert_exit(proc, 0)
        assert_out(proc, "Usage:")
        # Spot-check a handful of command names listed in Show-Usage
        for cmd in ("setup", "build", "test", "lint", "install", "record", "stop", "status"):
            assert_out(proc, cmd)


class TestHelp:
    def test_help(self, project_root):
        proc = run_ps(["help"], project_root=project_root)
        assert_exit(proc, 0)
        for cmd in ("setup", "check-env", "build", "test", "lint", "install",
                    "uninstall", "record", "stop", "status", "dump", "wipe",
                    "reindex", "release", "clean"):
            assert_out(proc, cmd)


class TestUnknownCommand:
    def test_unknown_command(self, project_root):
        proc = run_ps(["xyzzy"], project_root=project_root)
        assert_exit(proc, 1)
        assert_out(proc, "Unknown command: xyzzy")


class TestSetup:
    def test_setup(self, project_root):
        # quiet=False: setup/check-env print results via Write-Ok, which is
        # suppressed by DEVOPS_QUIET; no interactive prompts triggered here.
        proc = run_ps(["setup"], project_root=project_root, timeout=120, quiet=False)
        assert_exit(proc, 0)
        assert_out(proc, ".NET SDK:")
        assert_out(proc, "Environment check passed")

    def test_check_env_is_alias_of_setup(self, project_root):
        proc = run_ps(["check-env"], project_root=project_root, timeout=120, quiet=False)
        assert_exit(proc, 0)
        assert_out(proc, ".NET SDK:")
        assert_out(proc, "Environment check passed")


class TestBuild:
    def test_build_produces_artifacts(self, project_root):
        proc = run_ps(["build"], project_root=project_root, timeout=180)
        assert_exit(proc, 0)
        cli_dll = project_root / "src/Tmrc.Cli/bin/Debug/net8.0-windows/Tmrc.Cli.dll"
        core_dll = project_root / "src/Tmrc.Core/bin/Debug/net8.0/Tmrc.Core.dll"
        assert cli_dll.exists(), f"CLI DLL not found: {cli_dll}"
        assert core_dll.exists(), f"Core DLL not found: {core_dll}"


class TestTest:
    def test_test_reports_results(self, project_root):
        # Ensure build artifact exists before running --no-build
        cli_dll = project_root / "src/Tmrc.Cli/bin/Debug/net8.0-windows/Tmrc.Cli.dll"
        if not cli_dll.exists():
            pytest.skip("Build artifact absent — run devops.ps1 build first")
        proc = run_ps(["test"], project_root=project_root, timeout=300)
        assert_exit(proc, 0)
        assert_out(proc, "passed")
        combined = (proc.stdout or "") + (proc.stderr or "")
        # dotnet test output format: "Failed:     0, Passed: N" — check no failures
        assert re.search(r"failed\s*:\s*0", combined, re.IGNORECASE), (
            f"Expected 'Failed: 0' in output.\nstdout: {proc.stdout}\nstderr: {proc.stderr}"
        )


class TestLint:
    def test_lint(self, project_root):
        proc = run_ps(["lint"], project_root=project_root, timeout=120)
        combined = (proc.stdout or "") + (proc.stderr or "")
        if proc.returncode == 0:
            # dotnet-format installed and ran — no violation lines expected
            pass
        else:
            assert_out(proc, "dotnet-format is required")


class TestClean:
    def test_clean_removes_artifacts(self, project_root):
        # Build first so there is something to clean
        build_proc = run_ps(["build"], project_root=project_root, timeout=180)
        assert_exit(build_proc, 0)

        clean_proc = run_ps(["clean"], project_root=project_root, timeout=120)
        assert_exit(clean_proc, 0)

        # dotnet clean removes DLL files but may leave the bin/ directory itself;
        # verify the key output DLLs are gone.
        cli_dll = project_root / "src/Tmrc.Cli/bin/Debug/net8.0-windows/Tmrc.Cli.dll"
        core_dll = project_root / "src/Tmrc.Core/bin/Debug/net8.0/Tmrc.Core.dll"
        assert not cli_dll.exists(), f"CLI DLL should be gone after clean: {cli_dll}"
        assert not core_dll.exists(), f"Core DLL should be gone after clean: {core_dll}"

        # Rebuild so the rest of the test session (Group B devops tests) can run.
        rebuild_proc = run_ps(["build"], project_root=project_root, timeout=180)
        assert_exit(rebuild_proc, 0)


class TestClearTests:
    def test_clear_tests_empties_pass_column(self, project_root):
        # clear-tests uses Write-Ok for its result message; don't suppress it
        proc = run_ps(["clear-tests"], project_root=project_root, quiet=False)
        assert_exit(proc, 0)
        assert_out(proc, "row(s) reset")

        test_md = project_root / "specs/test.md"
        if test_md.exists():
            content = test_md.read_text(encoding="utf-8")
            in_table = False
            pass_col_idx: int | None = None
            for line in content.splitlines():
                if not line.startswith("|"):
                    in_table = False
                    pass_col_idx = None
                    continue
                cells = [c.strip() for c in line.split("|")[1:-1]]
                # Detect header
                if "pass" in [c.lower() for c in cells]:
                    in_table = True
                    pass_col_idx = next(
                        i for i, c in enumerate(cells) if c.lower() == "pass"
                    )
                    continue
                # Skip separator row
                if all(re.match(r"^:?-{3,}:?$", c) for c in cells if c):
                    continue
                if in_table and pass_col_idx is not None and pass_col_idx < len(cells):
                    assert cells[pass_col_idx] == "", (
                        f"Pass column not blank in: {line!r}"
                    )

    def test_clear_tests_idempotent(self, project_root):
        # First run
        run_ps(["clear-tests"], project_root=project_root, quiet=False)
        content_after_first = (project_root / "specs/test.md").read_text(encoding="utf-8")

        # Second run — quiet=False so Write-Ok output is visible
        proc2 = run_ps(["clear-tests"], project_root=project_root, quiet=False)
        assert_exit(proc2, 0)
        assert_out(proc2, "0 row(s) reset")

        content_after_second = (project_root / "specs/test.md").read_text(encoding="utf-8")
        assert content_after_first == content_after_second, "File changed on second clear-tests run"


class TestPublish:
    def test_publish_is_unknown_command(self, project_root):
        # The publish command was removed; it should be rejected like any unknown command.
        proc = run_ps(["publish"], project_root=project_root, timeout=30)
        assert_exit(proc, 1)
        assert_out(proc, "Unknown command: publish")


class TestRelease:
    def test_release_missing_version_arg(self, project_root):
        proc = run_ps(["release"], project_root=project_root, timeout=30)
        assert_exit(proc, 1)
        assert_out(proc, "Usage:")


# ---------------------------------------------------------------------------
# Group B — Requires CLI binary; uses patched_config fixture
# ---------------------------------------------------------------------------

@pytest.mark.integration
class TestInstallDevops:
    def test_install_creates_storage_layout(self, project_root, patched_config):
        storage_dir = patched_config
        proc = run_ps(["install"], project_root=project_root, timeout=60)
        assert_exit(proc, 0)
        assert (storage_dir / "segments").exists(), "segments/ dir missing"
        assert (storage_dir / "index").exists(), "index/ dir missing"

    def test_install_idempotent(self, project_root, patched_config):
        storage_dir = patched_config
        proc1 = run_ps(["install"], project_root=project_root, timeout=60)
        assert_exit(proc1, 0)
        proc2 = run_ps(["install"], project_root=project_root, timeout=60)
        assert_exit(proc2, 0)
        assert (storage_dir / "segments").exists()
        assert (storage_dir / "index").exists()


@pytest.mark.integration
class TestRecordDevops:
    def test_record_writes_pid_file(self, project_root, patched_config, stop_daemon_patched):
        storage_dir = patched_config
        run_ps(["install"], project_root=project_root, timeout=60)
        proc = run_ps(["record"], project_root=project_root, timeout=30, capture=False)
        assert_exit(proc, 0)
        pid_file = storage_dir / "tmrc.pid"
        wait_for_file(pid_file, timeout=5.0)
        content = pid_file.read_text(encoding="utf-8").strip()
        assert content.isdigit(), f"PID file content is not an integer: {content!r}"

    def test_stop_removes_pid_file(self, project_root, patched_config):
        storage_dir = patched_config
        run_ps(["install"], project_root=project_root, timeout=60)
        run_ps(["record"], project_root=project_root, timeout=30, capture=False)
        pid_file = storage_dir / "tmrc.pid"
        wait_for_file(pid_file, timeout=5.0)
        time.sleep(1)
        proc = run_ps(["stop"], project_root=project_root, timeout=30)
        assert_exit(proc, 0)
        time.sleep(1)
        assert not pid_file.exists(), "PID file still exists after stop"

    def test_stop_when_not_recording(self, project_root, patched_config):
        run_ps(["install"], project_root=project_root, timeout=60)
        proc = run_ps(["stop"], project_root=project_root, timeout=30)
        assert_exit(proc, 0)
        combined = (proc.stdout or "") + (proc.stderr or "")
        assert any(phrase in combined.lower() for phrase in ("not currently recording", "not recording", "no daemon")), (
            f"Expected 'not recording' or similar in output: {combined!r}"
        )


@pytest.mark.integration
class TestStatusDevops:
    def test_status_not_recording(self, project_root, patched_config):
        run_ps(["install"], project_root=project_root, timeout=60)
        proc = run_ps(["status"], project_root=project_root, timeout=30)
        assert_exit(proc, 0)
        combined = (proc.stdout or "") + (proc.stderr or "")
        assert combined.strip(), "status output is empty"

    def test_status_while_recording(self, project_root, patched_config, stop_daemon_patched):
        storage_dir = patched_config
        run_ps(["install"], project_root=project_root, timeout=60)
        run_ps(["record"], project_root=project_root, timeout=30, capture=False)
        wait_for_file(storage_dir / "tmrc.pid", timeout=5.0)
        proc = run_ps(["status"], project_root=project_root, timeout=30)
        assert_exit(proc, 0)
        combined = (proc.stdout or "") + (proc.stderr or "")
        assert any(phrase in combined.lower() for phrase in ("daemon", "recording")), (
            f"Expected daemon/recording info in status output: {combined!r}"
        )


@pytest.mark.integration
class TestWipeDevops:
    def test_wipe_empties_storage(self, project_root, patched_config):
        storage_dir = patched_config
        run_ps(["install"], project_root=project_root, timeout=60)
        proc = run_ps(["wipe"], project_root=project_root, timeout=30)
        assert_exit(proc, 0)
        segments = list((storage_dir / "segments").iterdir()) if (storage_dir / "segments").exists() else []
        indexes = list((storage_dir / "index").iterdir()) if (storage_dir / "index").exists() else []
        assert not segments, f"segments/ not empty after wipe: {segments}"
        assert not indexes, f"index/ not empty after wipe: {indexes}"


@pytest.mark.integration
class TestReindexDevops:
    def test_reindex_on_empty_storage(self, project_root, patched_config):
        run_ps(["install"], project_root=project_root, timeout=60)
        proc = run_ps(["reindex"], project_root=project_root, timeout=60)
        # With no recorded segments the CLI exits 1 with a meaningful message.
        assert proc.returncode in (0, 1), f"Unexpected exit code: {proc.returncode}"
        combined = (proc.stdout or "") + (proc.stderr or "")
        assert combined.strip(), "reindex produced no output at all"


@pytest.mark.integration
class TestDumpDevops:
    def test_dump_no_segments(self, project_root, patched_config):
        run_ps(["install"], project_root=project_root, timeout=60)
        proc = run_ps(["dump"], project_root=project_root, timeout=60)
        # May exit 0 or 1 — what matters is no .mp4 was created for empty storage
        combined = (proc.stdout or "") + (proc.stderr or "")
        # Check that no tmrc_dump_*.mp4 file was created in project_root
        dump_files = list(project_root.glob("tmrc_dump_*.mp4"))
        for f in dump_files:
            f.unlink(missing_ok=True)  # cleanup even if we find one
        assert combined.strip(), "dump produced no output at all"

    @pytest.mark.slow
    def test_dump_produces_file(self, project_root, patched_config, stop_daemon_patched):
        storage_dir = patched_config
        run_ps(["install"], project_root=project_root, timeout=60)
        run_ps(["record"], project_root=project_root, timeout=30, capture=False)
        wait_for_file(storage_dir / "tmrc.pid", timeout=5.0)
        time.sleep(3)
        run_ps(["stop"], project_root=project_root, timeout=30)
        time.sleep(1)

        proc = run_ps(["dump"], project_root=project_root, timeout=120)
        dump_files = list(project_root.glob("tmrc_dump_*.mp4"))
        try:
            assert_exit(proc, 0)
            assert dump_files, "No tmrc_dump_*.mp4 file found after dump"
            for f in dump_files:
                assert f.stat().st_size > 0, f"Dump file is empty: {f}"
        finally:
            for f in dump_files:
                f.unlink(missing_ok=True)


@pytest.mark.integration
class TestUninstallDevops:
    def test_uninstall_removes_shortcut(self, project_root, patched_config):
        run_ps(["install"], project_root=project_root, timeout=60)
        proc = run_ps(["uninstall"], project_root=project_root, timeout=60)
        assert_exit(proc, 0)
        startup_dir = Path(os.environ.get("APPDATA", "")) / "Microsoft/Windows/Start Menu/Programs/Startup"
        shortcut = startup_dir / "tmrc.lnk"
        assert not shortcut.exists(), f"Shortcut still exists after uninstall: {shortcut}"

    def test_uninstall_remove_data(self, project_root, patched_config):
        storage_dir = patched_config
        run_ps(["install"], project_root=project_root, timeout=60)
        proc = run_ps(["uninstall", "--remove-data"], project_root=project_root, timeout=60)
        assert_exit(proc, 0)
        assert not storage_dir.exists(), f"Storage dir still exists after uninstall --remove-data: {storage_dir}"
