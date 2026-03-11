"""Shared helpers for TMRC integration tests."""
from __future__ import annotations

import configparser
import os
import subprocess
import time
from pathlib import Path


def run_ps(
    args: list[str],
    *,
    project_root: Path,
    env: dict | None = None,
    timeout: int = 180,
    quiet: bool = True,
    capture: bool = True,
) -> subprocess.CompletedProcess:
    """Run powershell.exe -NonInteractive -File devops.ps1 <args>.

    Sets DEVOPS_QUIET=1 by default to suppress interactive prompts.
    Pass quiet=False to preserve Write-Ok output for commands that don't
    trigger interactive prompts (e.g. clear-tests).

    Pass capture=False when the command spawns a long-lived daemon subprocess.
    On Windows, daemon processes inherit the parent's stdout/stderr pipe
    handles; if those are pipes back to Python, subprocess.run() never gets
    EOF and hangs. Using capture=False (DEVNULL) avoids inheritable pipe
    handles entirely while still returning the exit code.
    """
    merged_env = {**os.environ}
    if quiet:
        merged_env["DEVOPS_QUIET"] = "1"
    if env:
        merged_env.update(env)

    devops = str(project_root / "devops.ps1")
    cmd = ["powershell.exe", "-NonInteractive", "-File", devops] + args

    if capture:
        return subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=merged_env,
            cwd=str(project_root),
        )
    else:
        result = subprocess.run(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=timeout,
            env=merged_env,
            cwd=str(project_root),
        )
        return subprocess.CompletedProcess(result.args, result.returncode, stdout="", stderr="")


def run_cli(
    cli_dll: Path,
    args: list[str],
    *,
    cwd: Path,
    env: dict | None = None,
    timeout: int = 30,
    capture: bool = True,
) -> subprocess.CompletedProcess:
    """Run dotnet <cli_dll> <args> with cwd for config.ini isolation.

    Pass capture=False when the command spawns a long-lived daemon subprocess.
    See run_ps() for a full explanation of the Windows pipe-inheritance issue.
    """
    merged_env = {**os.environ}
    if env:
        merged_env.update(env)

    cmd = ["dotnet", str(cli_dll)] + args

    if capture:
        return subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=merged_env,
            cwd=str(cwd),
        )
    else:
        result = subprocess.run(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=timeout,
            env=merged_env,
            cwd=str(cwd),
        )
        return subprocess.CompletedProcess(result.args, result.returncode, stdout="", stderr="")


def assert_exit(proc: subprocess.CompletedProcess, expected_code: int) -> None:
    """Fail with a readable message if exit code doesn't match."""
    if proc.returncode != expected_code:
        combined = (proc.stdout or "") + (proc.stderr or "")
        raise AssertionError(
            f"Expected exit code {expected_code}, got {proc.returncode}.\n"
            f"stdout: {proc.stdout!r}\n"
            f"stderr: {proc.stderr!r}\n"
            f"combined: {combined[:2000]}"
        )


def assert_out(proc: subprocess.CompletedProcess, *fragments: str) -> None:
    """Assert all fragments appear in stdout+stderr combined (case-insensitive)."""
    combined = ((proc.stdout or "") + (proc.stderr or "")).lower()
    missing = [f for f in fragments if f.lower() not in combined]
    if missing:
        raise AssertionError(
            f"Output missing fragments: {missing!r}\n"
            f"stdout: {proc.stdout!r}\n"
            f"stderr: {proc.stderr!r}"
        )


def read_storage_root_from_config(config_ini_path: Path) -> Path:
    """Parse config.ini and return the storage_root value."""
    parser = configparser.ConfigParser()
    parser.read(str(config_ini_path))
    raw = parser.get("storage", "storage_root")
    if raw.startswith("~"):
        raw = str(Path.home()) + raw[1:]
    return Path(raw)


def wait_for_file(path: Path, timeout: float = 5.0, interval: float = 0.25) -> None:
    """Poll until path exists or timeout; raise AssertionError if not found."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.exists():
            return
        time.sleep(interval)
    raise AssertionError(f"File did not appear within {timeout}s: {path}")
