Param(
    [Parameter(Position = 0)]
    [string]$Command,
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Args
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Variable -Name IsWindows -Scope Global -ErrorAction SilentlyContinue)) {
    $osName = [System.Environment]::OSVersion.Platform.ToString()
    $script:IsWindows = $osName -like '*Win*' -or $env:OS -like '*Windows*'
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ProjectRoot = $ScriptDir

function Write-Ok {
    param([string]$Message)
    if ($env:DEVOPS_QUIET) { return }
    Write-Host "[ok] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    if ($env:DEVOPS_QUIET) { return }
    Write-Host "[warn] $Message" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host "[error] $Message" -ForegroundColor Red
}

function Has-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-DotNetVersion {
    # Run via cmd so stderr from dotnet host does not surface as PowerShell NativeCommandError.
    $ver = cmd /c 'dotnet --version 2>nul'
    if ($ver) { return $ver.Trim() }
    return $null
}

function Show-Cmd {
    param([string[]]$Cmd)
    if ($env:DEVOPS_QUIET) { return }
    $joined = $Cmd -join ' '
    Write-Host "$ $joined" -ForegroundColor Yellow
}

function Show-Usage {
    @'
tmrc development command center (Windows)

Usage:
  ./devops.ps1 <command>

Commands:
  setup       Validate local Windows development prerequisites
  check-env   Alias of setup
  build       Run dotnet build for the Windows solution
  test        Run dotnet test for the Windows solution
  lint        Run dotnet format (if installed)
  record      Run tmrc record (Windows CLI)
  status      Run tmrc status (Windows CLI)
  dump        Export all recordings to a single MP4 via tmrc export
  wipe        Remove all recordings and index via tmrc wipe
  reindex     Re-run OCR on existing segments (tmrc reindex; optional --force)
  clean       Run dotnet clean for the Windows solution
  help        Show this help message

Examples:
  ./devops.ps1 setup
  ./devops.ps1 build
  ./devops.ps1 record
  ./devops.ps1 dump
  ./devops.ps1 wipe
'@ | Write-Host
}

function Assert-Windows {
    if (-not $IsWindows) {
        Write-Err "tmrc Windows devops script must be run on Windows."
        exit 1
    }
}

function Assert-DotNetSolution {
    $sln = Join-Path $ProjectRoot 'src\Tmrc.sln'
    if (-not (Test-Path $sln)) {
        Write-Err "Windows solution not found at $sln"
        Write-Err "This repository is likely still in planning mode for the Windows port."
        exit 1
    }
}

function Ensure-DotNetInPath {
    if (Has-Command 'dotnet') {
        return
    }

    # Common install locations for dotnet; add to PATH if present.
    $dotnetDirs = @()
    if ($Env:ProgramFiles) { $dotnetDirs += (Join-Path $Env:ProgramFiles 'dotnet') }
    if (${Env:ProgramFiles(x86)}) { $dotnetDirs += (Join-Path ${Env:ProgramFiles(x86)} 'dotnet') }

    foreach ($dir in $dotnetDirs) {
        if ($dir -and (Test-Path (Join-Path $dir 'dotnet.exe'))) {
            if (-not ($Env:PATH -split ';' | Where-Object { $_ -ieq $dir })) {
                $Env:PATH = "$dir;$Env:PATH"
            }
        }
    }
}

function Install-DotNetSdk {
    Ensure-DotNetInPath
    if ((Has-Command 'dotnet') -and (Get-DotNetVersion)) {
        return
    }

    $reason = if (Has-Command 'dotnet') { "dotnet failed to run" } else { ".NET SDK (dotnet) not found in PATH" }
    Write-Warn "$reason. Attempting installation..."

    if (Has-Command 'winget') {
        $cmd = @('winget', 'install', '--id', 'Microsoft.DotNet.SDK.8', '-e', '--source', 'winget')
        Show-Cmd -Cmd $cmd
        try {
            & $cmd[0] $cmd[1..($cmd.Length - 1)]
        } catch {
            Write-Err "winget-based .NET SDK installation failed: $($_.Exception.Message)"
        }
    } elseif (Has-Command 'choco') {
        $cmd = @('choco', 'install', 'dotnet-8.0-sdk', '-y')
        Show-Cmd -Cmd $cmd
        try {
            & $cmd[0] $cmd[1..($cmd.Length - 1)]
        } catch {
            Write-Err "Chocolatey-based .NET SDK installation failed: $($_.Exception.Message)"
        }
    } else {
        Write-Err "Automatic .NET SDK install not available (no winget/choco)."
        Write-Err "Please install .NET SDK 8+ from https://dotnet.microsoft.com/download and re-run setup."
        return
    }

    Ensure-DotNetInPath
    $ver = Get-DotNetVersion
    if ($ver) {
        Write-Ok ".NET SDK detected after installation: $ver"
    } else {
        Write-Warn "dotnet still not found or not working in this session."
        Write-Warn "Open a new terminal and run setup again, or add the dotnet install directory to PATH."
    }
}

function Check-Env {
    param(
        [switch]$Quiet
    )

    if ($Quiet) {
        $env:DEVOPS_QUIET = '1'
    }

    Assert-Windows
    Assert-DotNetSolution

    $failures = 0

    Write-Ok "Operating system: Windows"

    $ver = $null
    if (Has-Command 'dotnet') {
        $ver = Get-DotNetVersion
    }
    if ($ver) {
        Write-Ok ".NET SDK: $ver"
    } else {
        if (Has-Command 'dotnet') {
            Write-Warn "dotnet is in PATH but failed to run (reinstall .NET SDK if needed)."
        }
        Install-DotNetSdk
        if (Has-Command 'dotnet') {
            $ver = Get-DotNetVersion
        }
        if ($ver) {
            Write-Ok ".NET SDK: $ver"
        } else {
            $failures++
        }
    }

    if (Test-Path (Join-Path $ProjectRoot 'config.yaml')) {
        Write-Ok "config.yaml found at project root"
    } else {
        Write-Warn "config.yaml not found at project root"
    }

    if (Has-Command 'ffprobe') {
        Write-Ok "ffprobe found (useful for export media tests)"
    } else {
        Write-Warn "ffprobe not found (optional, recommended for export validation)"
        if (Has-Command 'choco') {
            Write-Warn "Install with Chocolatey: choco install ffmpeg"
        } elseif (Has-Command 'winget') {
            Write-Warn "Install with winget: winget install --id Gyan.FFmpeg -e --source winget"
        } else {
            Write-Warn "Or download FFmpeg manually from https://ffmpeg.org/download.html"
        }
    }

    if (Has-Command 'dotnet-format') {
        Write-Ok "dotnet-format (code formatter) found"
    } else {
        Write-Warn "dotnet-format not found (optional). Install with: dotnet tool install -g dotnet-format"
    }

    $sln = Join-Path $ProjectRoot 'src\Tmrc.sln'
    if ((Test-Path $sln) -and $ver) {
        Write-Ok "Restoring NuGet packages for solution..."
        try {
            & dotnet restore $sln
            if ($LASTEXITCODE -eq 0) {
                Write-Ok "NuGet packages restored."
            } else {
                Write-Warn "dotnet restore failed; build may fail with NU1100. Check network and NuGet sources."
                $failures++
            }
        } catch {
            Write-Warn "dotnet restore failed: $($_.Exception.Message)"
            $failures++
        }
    }

    if ($failures -gt 0) {
        Write-Err "Environment check failed with $failures blocking issue(s)."
        exit 1
    }

    Write-Ok "Environment check passed."
    Remove-Item Env:DEVOPS_QUIET -ErrorAction SilentlyContinue
}

function Invoke-DotNet {
    param(
        [string[]]$Cmd
    )
    Show-Cmd -Cmd $Cmd
    & $Cmd[0] $Cmd[1..($Cmd.Length - 1)]
    # No return: output flows to the console; callers read $LASTEXITCODE directly.
}

function Invoke-TmrcCli {
    param(
        [string[]]$CliArgs
    )

    Check-Env -Quiet
    Assert-DotNetSolution

    $proj = Join-Path $ProjectRoot 'src\Tmrc.Cli\Tmrc.Cli.csproj'
    if (-not (Test-Path $proj)) {
        Write-Err "Windows CLI project not found at $proj"
        exit 1
    }

    $buildCmd = @('dotnet', 'build', $proj)
    $buildOutput = @(& $buildCmd[0] $buildCmd[1..($buildCmd.Length - 1)] 2>&1)
    
    if ($LASTEXITCODE -ne 0) {
        $joinedOutput = ($buildOutput | ForEach-Object { "$_" }) -join "`n"
        $isKnownCopyLock = $joinedOutput -match 'MSB3027' -and $joinedOutput -match 'MSB3021' -and $joinedOutput -match 'Tmrc\.Core\.dll'
        
        if (-not $isKnownCopyLock) {
            foreach ($line in $buildOutput) { Write-Host $line }
            exit $LASTEXITCODE
        }

        $pidMatches = [regex]::Matches($joinedOutput, '\.NET Host \((\d+)\)')
        $stalePids = @(
            $pidMatches |
            ForEach-Object { $_.Groups[1].Value } |
            Where-Object { $_ -match '^\d+$' } |
            Sort-Object -Unique
        )
        
        if ($stalePids.Count -eq 0) {
            foreach ($line in $buildOutput) { Write-Host $line }
            exit $LASTEXITCODE
        }

        Write-Warn "Detected stale .NET host lock on Tmrc.Core.dll. Terminating stale process(es) and retrying once..."
        foreach ($stalePid in $stalePids) {
            try {
                $null = taskkill /PID $stalePid /F
                Write-Ok "Stopped stale .NET host PID $stalePid"
            } catch {
                Write-Warn "Failed to stop PID ${stalePid}: $($_.Exception.Message)"
            }
        }

        Invoke-DotNet -Cmd $buildCmd
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }

    $cmd = @('dotnet', 'run', '--no-build', '--project', $proj, '--') + $CliArgs
    Invoke-DotNet -Cmd $cmd
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

function Cmd-Build {
    Check-Env -Quiet
    Assert-DotNetSolution
    $sln = Join-Path $ProjectRoot 'src\Tmrc.sln'
    Invoke-DotNet -Cmd @('dotnet', 'build', $sln)
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

function Cmd-Test {
    Check-Env -Quiet
    Assert-DotNetSolution
    $sln = Join-Path $ProjectRoot 'src\Tmrc.sln'
    Invoke-DotNet -Cmd @('dotnet', 'test', $sln)
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

function Cmd-Lint {
    Check-Env -Quiet
    Assert-DotNetSolution

    if (Has-Command 'dotnet-format') {
        $sln = Join-Path $ProjectRoot 'src\Tmrc.sln'
        Invoke-DotNet -Cmd @('dotnet-format', $sln)
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    } else {
        Write-Err "dotnet-format is required for lint command."
        Write-Err "Install with: dotnet tool install -g dotnet-format"
        exit 1
    }
}

function Cmd-Record {
    Invoke-TmrcCli -CliArgs (@('record') + $Args)
}

function Cmd-Status {
    Invoke-TmrcCli -CliArgs @('status')
}

function Cmd-Dump {
    $timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $outPath = Join-Path $ProjectRoot "tmrc_dump_${timestamp}.mp4"
    Invoke-TmrcCli -CliArgs @('export', '--from', '1000d', '--to', 'now', '-o', $outPath)
}

function Cmd-Wipe {
    Invoke-TmrcCli -CliArgs @('wipe')
}

function Cmd-Reindex {
    Invoke-TmrcCli -CliArgs (@('reindex') + $Args)
}

function Cmd-Clean {
    Assert-DotNetSolution
    $sln = Join-Path $ProjectRoot 'src\Tmrc.sln'
    Invoke-DotNet -Cmd @('dotnet', 'clean', $sln)
    Write-Ok "dotnet artifacts cleaned."
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

if (-not $Command) {
    Show-Usage
    exit 0
}

switch ($Command) {
    'setup' { Check-Env; break }
    'check-env' { Check-Env; break }
    'build' { Cmd-Build; break }
    'test' { Cmd-Test; break }
    'lint' { Cmd-Lint; break }
    'record' { Cmd-Record; break }
    'status' { Cmd-Status; break }
    'dump' { Cmd-Dump; break }
    'wipe' { Cmd-Wipe; break }
    'reindex' { Cmd-Reindex; break }
    'clean' { Cmd-Clean; break }
    'help' { Show-Usage; break }
    default {
        Write-Err "Unknown command: $Command"
        Show-Usage
        exit 1
    }
}

