---
name: tmrc-safe-build
description: Enforces a safe build and run workflow for the tmrc project. Use this skill before building the solution or running the tmrc executable to ensure the background daemon is stopped, preventing file access locks on output binaries.
---

# Tmrc Safe Build

## Overview
This skill ensures a conflict-free development experience by preventing common file-locking issues caused by the `tmrc` recording daemon during build and run cycles.

## Safe Build & Run Workflow
Before executing any build or run command (e.g., `dotnet build`, `dotnet run`, or `./devops.ps1 build`), you MUST follow this sequence:

### 1. Check Daemon Status
Identify if the recorder is currently active:
```powershell
./devops.ps1 status
# OR
dotnet run --project src/Tmrc.Cli/Tmrc.Cli.csproj -- status
```

### 2. Stop the Daemon
If `Recording: yes` is shown, terminate the process gracefully:
```powershell
./devops.ps1 stop
# OR
dotnet run --project src/Tmrc.Cli/Tmrc.Cli.csproj -- stop
```

### 3. Verify Termination
Ensure the file locks are released:
- Check that `tmrc.pid` (usually in `%USERPROFILE%\.tmrc\tmrc.pid`) is deleted.
- If the stop command fails or hangs, check for any orphaned `.NET Host` processes that might be locking `Tmrc.Cli.dll`.

### 4. Proceed with Task
Only after confirming the daemon is stopped should you proceed with building or running the project.

## Troubleshooting
If you encounter "The process cannot access the file because it is being used by another process" during a build:
1. Run `Get-Process | Where-Object { $_.ProcessName -like "*Tmrc*" }` in PowerShell to find hidden instances.
2. Manually kill any remaining processes if `./devops.ps1 stop` was insufficient.
