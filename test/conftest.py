"""Shared pytest fixtures for TMRC integration tests."""
from __future__ import annotations

import time
from pathlib import Path

import pytest

from helpers import run_ps, run_cli


# ---------------------------------------------------------------------------
# Session-scoped fixtures
# ---------------------------------------------------------------------------

@pytest.fixture(scope="session")
def project_root() -> Path:
    return Path(__file__).parent.parent


@pytest.fixture(scope="session")
def cli_dll(project_root: Path) -> Path:
    dll = project_root / "src/Tmrc.Cli/bin/Debug/net8.0-windows/Tmrc.Cli.dll"
    if not dll.exists():
        pytest.skip("CLI not built — run ./devops.ps1 build first")
    return dll


@pytest.fixture(scope="session")
def ensure_built(project_root: Path, cli_dll: Path) -> None:  # noqa: F811
    """No-op: cli_dll already skips if absent. Kept for explicit dependency."""
    pass


# ---------------------------------------------------------------------------
# Function-scoped fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def isolated_storage(tmp_path: Path):
    """Write a temp config.ini pointing to a temp storage dir.

    CLI must be invoked with cwd=config_dir so LoadConfig() picks up the file.
    Yields (config_dir, storage_dir).
    """
    config_dir = tmp_path / "cfg"
    storage_dir = tmp_path / "storage"
    config_dir.mkdir()
    storage_dir.mkdir()
    (config_dir / "config.ini").write_text(
        f"[storage]\nstorage_root = {storage_dir}\n",
        encoding="utf-8",
    )
    yield config_dir, storage_dir
    # tmp_path is auto-cleaned by pytest


@pytest.fixture
def patched_config(tmp_path: Path, project_root: Path):
    """Temporarily swap project-root config.ini to isolate devops CLI tests.

    Restores the original in a finally block to survive test failures.
    Yields storage_dir.
    """
    real = project_root / "config.ini"
    backup: bytes | None = real.read_bytes() if real.exists() else None

    storage_dir = tmp_path / "storage"
    storage_dir.mkdir()
    real.write_text(
        f"[storage]\nstorage_root = {storage_dir}\n",
        encoding="utf-8",
    )
    try:
        yield storage_dir
    finally:
        if backup is not None:
            real.write_bytes(backup)
        else:
            real.unlink(missing_ok=True)


@pytest.fixture
def stop_daemon(cli_dll: Path, isolated_storage):
    """Teardown fixture: stop any daemon left running by the test."""
    config_dir, storage_dir = isolated_storage
    yield
    try:
        run_cli(cli_dll, ["stop"], cwd=config_dir, timeout=15)
    except Exception:
        pass


@pytest.fixture
def stop_daemon_patched(project_root: Path, patched_config):
    """Teardown fixture for patched_config tests: stop daemon via devops.ps1."""
    yield
    try:
        run_ps(["stop"], project_root=project_root, timeout=15)
    except Exception:
        pass
