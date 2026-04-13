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
$Script:SessionRefreshHints = @()

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

# Returns .NET SDK version string, or $null if dotnet cannot be run (e.g. not installed or failed to load).
# When dotnet exists but fails, writes a descriptive message so the user knows what to do.
function Get-DotNetVersionOrNull {
    if (-not (Has-Command 'dotnet')) {
        return $null
    }
    try {
        $ver = & dotnet --version 2>&1 | Out-String
        $ver = ($ver -replace '\s+', ' ').Trim()
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($ver)) {
            Write-DotNetFailureMessage
            return $null
        }
        return $ver
    } catch {
        Write-DotNetFailureMessage
        return $null
    }
}

function Write-DotNetFailureMessage {
    if ($env:DEVOPS_QUIET) { return }
    Write-Err ".NET SDK check failed: the 'dotnet' command could not be run."
    Write-Host ""
    Write-Host "This usually means:" -ForegroundColor Yellow
    Write-Host "  - .NET SDK is not installed, or the installation is broken."
    Write-Host "  - You are using 32-bit PowerShell while .NET is 64-bit (or the opposite)."
    Write-Host "  - PATH points to a leftover or invalid dotnet executable."
    Write-Host ""
    Write-Host "What to do:" -ForegroundColor Cyan
    Write-Host "  1. Install or repair .NET SDK 8+ from: https://dotnet.microsoft.com/download"
    Write-Host "  2. If already installed, open a new PowerShell window (match architecture, e.g. use 64-bit)."
    Write-Host "  3. Run 'dotnet --version' in that terminal; if it still fails, reinstall the SDK."
    Write-Host ""
}

function Confirm-Install {
    param(
        [string]$ToolName,
        [string]$Reason
    )

    if ($env:DEVOPS_QUIET) {
        return $false
    }

    Write-Host ""
    Write-Host "Tool missing: $ToolName" -ForegroundColor Yellow
    if ($Reason) {
        Write-Host "Reason: $Reason"
    }
    $answer = Read-Host "Install now? [Y/n]"
    if ([string]::IsNullOrWhiteSpace($answer)) {
        return $true
    }

    return $answer.Trim().ToLowerInvariant() -in @('y', 'yes')
}

function Install-ToolWithPackageManager {
    param(
        [string]$ToolName,
        [string[]]$WingetCmd,
        [string[]]$ChocoCmd
    )

    if (Has-Command 'winget') {
        Show-Cmd -Cmd $WingetCmd
        & $WingetCmd[0] $WingetCmd[1..($WingetCmd.Length - 1)]
        return
    }

    if (Has-Command 'choco') {
        Show-Cmd -Cmd $ChocoCmd
        & $ChocoCmd[0] $ChocoCmd[1..($ChocoCmd.Length - 1)]
        return
    }

    throw "No supported package manager (winget/choco) found for $ToolName."
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

Development Commands:
  setup       Validate local Windows development prerequisites
  check-env   Alias of setup
  build       Run dotnet build for the Windows solution
  test        Run dotnet test for the Windows solution
  lint        Run dotnet format (if installed)
  clear-tests Clear all values in Pass column of specs/test.md
  release     Build for production, zip, and upload to GitHub (-NoUpload to skip)
  clean       Run dotnet clean for the Windows solution

Application Commands (tmrc):
  install     Set up tmrc storage and add startup shortcut
  uninstall   Stop daemon, remove startup shortcut (add --remove-data to also delete recordings)
  record      Start recording (no-op with notice if already recording)
  stop        Stop recording (no-op with notice if not recording)
  status      Run tmrc status (Windows CLI)
  query       Natural language recall query via tmrc query
  export      Forward to tmrc export (MP4/GIF export)
  dump        Export all recordings to a single MP4 via tmrc export
  wipe        Remove all recordings and index via tmrc wipe
  reindex     Re-run OCR on existing segments (tmrc reindex; optional --force)
  help        Show this help message

Examples:
  ./devops.ps1 setup
  ./devops.ps1 build
  ./devops.ps1 record
  ./devops.ps1 query "What was I working on yesterday?"
  ./devops.ps1 export --query "meeting" -o meeting.mp4
  ./devops.ps1 dump
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

function Ensure-TesseractInPath {
    if (Has-Command 'tesseract') {
        return
    }

    $candidateDirs = @()
    if ($env:TESSERACT_EXE) {
        $candidate = Split-Path -Parent $env:TESSERACT_EXE
        if ($candidate) {
            $candidateDirs += $candidate
        }
    }
    if ($Env:ProgramFiles) {
        $candidateDirs += (Join-Path $Env:ProgramFiles 'Tesseract-OCR')
    }
    if (${Env:ProgramFiles(x86)}) {
        $candidateDirs += (Join-Path ${Env:ProgramFiles(x86)} 'Tesseract-OCR')
    }

    foreach ($dir in ($candidateDirs | Select-Object -Unique)) {
        if (-not $dir) { continue }
        if (-not (Test-Path (Join-Path $dir 'tesseract.exe'))) { continue }
        if (-not ($Env:PATH -split ';' | Where-Object { $_ -ieq $dir })) {
            $Env:PATH = "$dir;$Env:PATH"
        }
    }
}

function Install-DotNetSdk {
    # Try to ensure it's already reachable first.
    Ensure-DotNetInPath
    if (Has-Command 'dotnet') {
        return
    }

    if (-not (Confirm-Install -ToolName '.NET SDK 8' -Reason 'Required to build and run tmrc.')) {
        Write-Err ".NET SDK installation declined."
        return
    }

    Write-Warn ".NET SDK (dotnet) not found in PATH. Attempting installation..."

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

    # After install, try to pick it up in this session.
    Ensure-DotNetInPath
    if (Has-Command 'dotnet') {
        Write-Ok ".NET SDK detected after installation."
    } else {
        Write-Warn "dotnet still not found in PATH in this session."
        Write-Warn "You may need to open a new terminal, or ensure the dotnet install directory is added to PATH."
    }
}

function Ensure-OptionalFfmpeg {
    if (Has-Command 'ffprobe' -and Has-Command 'ffmpeg') {
        Write-Ok "ffmpeg/ffprobe found (used by recording/export validation)"
        return
    }

    Write-Warn "ffmpeg and/or ffprobe not found (optional, recommended)."
    if (-not (Confirm-Install -ToolName 'FFmpeg' -Reason 'Needed for MP4 recording/export and ffprobe-based media checks.')) {
        Write-Warn "Skipped FFmpeg installation by user choice."
        return
    }

    try {
        Install-ToolWithPackageManager `
            -ToolName 'FFmpeg' `
            -WingetCmd @('winget', 'install', '--id', 'Gyan.FFmpeg', '-e', '--source', 'winget') `
            -ChocoCmd @('choco', 'install', 'ffmpeg', '-y')
    } catch {
        Write-Warn "FFmpeg install failed: $($_.Exception.Message)"
    }

    if (Has-Command 'ffprobe' -and Has-Command 'ffmpeg') {
        Write-Ok "ffmpeg/ffprobe installed and available."
    } else {
        Write-Warn "ffmpeg/ffprobe still not found in current session."
        $Script:SessionRefreshHints += 'ffmpeg/ffprobe'
    }
}

function Ensure-OptionalDotnetFormat {
    if (Has-Command 'dotnet-format') {
        Write-Ok "dotnet-format (code formatter) found"
        return
    }

    Write-Warn "dotnet-format not found (optional)."
    if (-not (Confirm-Install -ToolName 'dotnet-format' -Reason 'Used by devops lint command.')) {
        Write-Warn "Skipped dotnet-format installation by user choice."
        return
    }

    $cmd = @('dotnet', 'tool', 'install', '-g', 'dotnet-format')
    Show-Cmd -Cmd $cmd
    try {
        & $cmd[0] $cmd[1..($cmd.Length - 1)]
    } catch {
        Write-Warn "dotnet-format install failed: $($_.Exception.Message)"
    }

    if (Has-Command 'dotnet-format') {
        Write-Ok "dotnet-format installed."
    } else {
        Write-Warn "dotnet-format not found in current session after install."
        $Script:SessionRefreshHints += 'dotnet-format'
    }
}

function Ensure-OptionalTesseract {
    Ensure-TesseractInPath
    if (Has-Command 'tesseract') {
        Write-Ok "Tesseract found (OCR/reindex support)"
        return
    }

    Write-Warn "Tesseract not found (optional, needed for OCR/reindex)."
    if (-not (Confirm-Install -ToolName 'Tesseract OCR' -Reason 'Required for tmrc reindex and OCR text indexing.')) {
        Write-Warn "Skipped Tesseract installation by user choice."
        return
    }

    try {
        Install-ToolWithPackageManager `
            -ToolName 'Tesseract' `
            -WingetCmd @('winget', 'install', '--id', 'UB-Mannheim.TesseractOCR', '-e', '--source', 'winget') `
            -ChocoCmd @('choco', 'install', 'tesseract', '-y')
    } catch {
        Write-Warn "Tesseract install failed: $($_.Exception.Message)"
    }

    Ensure-TesseractInPath
    if (Has-Command 'tesseract') {
        Write-Ok "Tesseract installed and available."
    } else {
        Write-Warn "Tesseract still not found in current session."
        $Script:SessionRefreshHints += 'tesseract'
    }
}

function Check-Env {
    param(
        [switch]$Quiet
    )

    if ($Quiet) {
        $env:DEVOPS_QUIET = '1'
    }
    $Script:SessionRefreshHints = @()

    Assert-Windows

    $failures = 0

    Write-Ok "Operating system: Windows"

    if (Has-Command 'dotnet') {
        $ver = Get-DotNetVersionOrNull
        if ($ver) {
            Write-Ok ".NET SDK: $ver"
        } else {
            $failures++
        }
    } else {
        Install-DotNetSdk
        if (-not (Has-Command 'dotnet')) {
            $failures++
        } else {
            $ver = Get-DotNetVersionOrNull
            if ($ver) {
                Write-Ok ".NET SDK: $ver"
            } else {
                $failures++
            }
        }
    }

    # Check that the net8.0 runtime is actually installed (SDK ≠ runtime).
    $requiredRuntime = '8.'
    $runtimes = & dotnet --list-runtimes 2>&1 | Out-String
    $hasNet8Runtime = $runtimes -match "Microsoft\.NETCore\.App $requiredRuntime"
    if ($hasNet8Runtime) {
        Write-Ok ".NET 8 runtime present (required by project targets)"
    } else {
        Write-Err ".NET 8 runtime not found. Installed runtimes:"
        $runtimes -split "`n" | Where-Object { $_.Trim() } | ForEach-Object { Write-Host "  $_" }
        Write-Host ""
        Write-Host "The project targets net8.0 but the SDK alone is not enough - the runtime must also be installed." -ForegroundColor Yellow
        Write-Host "Install .NET 8 runtime from: https://dotnet.microsoft.com/download/dotnet/8.0" -ForegroundColor Cyan
        $failures++
    }

    if (Test-Path (Join-Path $ProjectRoot 'config.ini')) {
        Write-Ok "config.ini found at project root"
    } else {
        Write-Warn "config.ini not found at project root"
    }

    Ensure-OptionalFfmpeg
    Ensure-OptionalDotnetFormat
    Ensure-OptionalTesseract

    if ($failures -gt 0) {
        Write-Err "Environment check failed with $failures blocking issue(s)."
        exit 1
    }

    if ($Script:SessionRefreshHints.Count -gt 0) {
        $tools = ($Script:SessionRefreshHints | Select-Object -Unique) -join ', '
        Write-Warn "Installed tool(s) not visible in current session: $tools"
        Write-Warn "Open a new PowerShell window, then re-run: .\devops.ps1 setup"
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

    # No implicit build outside the build target: run existing CLI output directly.
    # This also avoids dotnet-run project pipeline and apphost file-lock behavior.
    $cliDll = Join-Path $ProjectRoot 'src\Tmrc.Cli\bin\Debug\net8.0-windows\Tmrc.Cli.dll'
    if (-not (Test-Path $cliDll)) {
        Write-Err "CLI build output not found: $cliDll"
        Write-Err "Run ./devops.ps1 build first."
        exit 1
    }
    $cmd = @('dotnet', $cliDll) + $CliArgs
    Invoke-DotNet -Cmd $cmd
}

function Cmd-Build {
    Check-Env -Quiet
    Assert-DotNetSolution
    $sln = Join-Path $ProjectRoot 'src\Tmrc.sln'
    Invoke-DotNet -Cmd @('dotnet', 'build', $sln)
}

function Cmd-Test {
    Check-Env -Quiet
    Assert-DotNetSolution
    $sln = Join-Path $ProjectRoot 'src\Tmrc.sln'
    Invoke-DotNet -Cmd @('dotnet', 'test', '--no-build', $sln)
}

function Cmd-Lint {
    Check-Env -Quiet
    Assert-DotNetSolution

    if (Has-Command 'dotnet-format') {
        $sln = Join-Path $ProjectRoot 'src\Tmrc.sln'
        Invoke-DotNet -Cmd @('dotnet-format', $sln)
    } else {
        Write-Err "dotnet-format is required for lint command."
        Write-Host "Install with: dotnet tool install -g dotnet-format"
        exit 1
    }
}

function Cmd-Install {
    Invoke-TmrcCli -CliArgs @('install')
}

function Cmd-Uninstall {
    Invoke-TmrcCli -CliArgs (@('uninstall') + $Args)
}

function Cmd-Record {
    Invoke-TmrcCli -CliArgs @('record')
}

function Cmd-Stop {
    Invoke-TmrcCli -CliArgs @('stop')
}

function Cmd-Status {
    Invoke-TmrcCli -CliArgs @('status')
}

function Cmd-Dump {
    $timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $outPath = Join-Path $ProjectRoot "tmrc_dump_${timestamp}.mp4"
    Invoke-TmrcCli -CliArgs (@('export', '--from', '1000d ago', '--to', 'now', '-o', $outPath) + $Args)
}

function Cmd-Wipe {
    Invoke-TmrcCli -CliArgs @('wipe')
}

function Cmd-Reindex {
    Invoke-TmrcCli -CliArgs (@('reindex') + $Args)
}

function Cmd-Query {
    Invoke-TmrcCli -CliArgs (@('query') + $Args)
}

function Cmd-Export {
    Invoke-TmrcCli -CliArgs (@('export') + $Args)
}

# PAT embedded in https://user:token@github.com/... (gh does not read this; set GH_TOKEN for API calls).
function Get-GitHubPatFromRemote {
    param([string]$Remote = 'origin')

    if (-not (Has-Command 'git')) {
        return $null
    }
    $prevEa = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        $url = (git remote get-url $Remote 2>$null | Out-String).Trim()
    } finally {
        $ErrorActionPreference = $prevEa
    }
    if ([string]::IsNullOrWhiteSpace($url) -or $url -match '^git@') {
        return $null
    }
    if ($url -notmatch '^https?://([^/:]+):([^@]+)@([^/]+)/') {
        return $null
    }
    if ($matches[3] -notmatch 'github\.com') {
        return $null
    }
    try {
        return [Uri]::UnescapeDataString($matches[2])
    } catch {
        return $matches[2]
    }
}

function Get-LatestVersionOrNull {
    if (-not (Has-Command 'gh')) {
        return $null
    }
    $pat = $null
    if (-not $env:GH_TOKEN -and -not $env:GITHUB_TOKEN) {
        $pat = Get-GitHubPatFromRemote
        if ($pat) {
            $env:GH_TOKEN = $pat
        }
    }
    try {
        $release = gh release list --limit 1 2>$null | Select-Object -First 1
        if ($release -match 'v?(\d+\.\d+\.\d+)') {
            return $matches[1]
        }
    } catch { } finally {
        if ($null -ne $pat) {
            Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue
        }
    }
    return $null
}

function Cmd-Release {
    param(
        [string]$Version,
        [switch]$NoUpload
    )

    Check-Env -Quiet
    Assert-DotNetSolution

    if (-not $Version) {
        $latest = Get-LatestVersionOrNull
        if ($latest -and $latest -match '^v?(\d+)\.(\d+)\.(\d+)$') {
            $major = [int]$matches[1]
            $minor = [int]$matches[2]
            $patch = [int]$matches[3]

            $minorBump = "$major.$($minor + 1).0"
            $patchBump = "$major.$minor.$($patch + 1)"

            Write-Host ""
            Write-Host "Latest version from GitHub: v$latest" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "Suggested next versions:" -ForegroundColor Yellow
            Write-Host "  [1] v$minorBump  (minor bump: $minor -> $($minor + 1))"
            Write-Host "  [2] v$patchBump  (patch bump: $patch -> $($patch + 1))"
            Write-Host "  [3] Custom version"
            Write-Host ""
            $choice = Read-Host "Select version [1]: "
            if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "1" }

            switch ($choice) {
                "1" { $Version = $minorBump }
                "2" { $Version = $patchBump }
                "3" {
                    $custom = Read-Host "Enter version (e.g. v2.0.0): "
                    $Version = $custom.TrimStart('v')
                }
                default {
                    Write-Err "Invalid selection: $choice"
                    exit 1
                }
            }
        } else {
            Write-Err "No previous release found. Please specify version: .\devops.ps1 release <vX.Y.Z>"
            exit 1
        }
    }

    $os = "windows"
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "x64" }
    $bundleName = "tmrc-$Version-$os-$arch"
    $distDir = Join-Path $ProjectRoot "dist\$bundleName"
    $zipFile = Join-Path $ProjectRoot "dist\$bundleName.zip"

    Write-Ok "Building tmrc $Version for $os-$arch in release mode..."
    $proj = Join-Path $ProjectRoot 'src\Tmrc.Cli\Tmrc.Cli.csproj'
    $runtime = if ($arch -eq "arm64") { "win-arm64" } else { "win-x64" }

    Invoke-DotNet -Cmd @(
        'dotnet', 'publish', $proj,
        '-r', $runtime,
        '--self-contained', 'true',
        '-p:PublishSingleFile=true',
        "-p:Version=$Version",
        '-c', 'Release',
        '-o', $distDir
    )

    Write-Ok "Preparing distribution bundle in $distDir..."
    if (-not (Test-Path $distDir)) { New-Item -ItemType Directory -Path $distDir -Force | Out-Null }
    if (Test-Path $zipFile) { Remove-Item $zipFile }

    $configPath = Join-Path $ProjectRoot "config.yaml"
    if (Test-Path $configPath) { Copy-Item $configPath $distDir }

    $readmePath = Join-Path $ProjectRoot "README.md"
    if (Test-Path $readmePath) { Copy-Item $readmePath $distDir }

    Copy-Item (Join-Path $ProjectRoot "devops.ps1") $distDir

    Write-Ok "Creating zip archive: $zipFile"
    Compress-Archive -Path "$distDir\*" -DestinationPath $zipFile -Force

    if ($NoUpload) {
        Write-Ok "Release bundle is ready at: $zipFile (upload skipped)"
    } elseif (-not (Has-Command 'gh')) {
        Write-Warn "gh (GitHub CLI) not found. Skipping upload."
        Write-Ok "Release bundle is ready at: $zipFile"
    } else {
        $patForGh = $null
        if (-not $env:GH_TOKEN -and -not $env:GITHUB_TOKEN) {
            $patForGh = Get-GitHubPatFromRemote
            if ($patForGh) {
                $env:GH_TOKEN = $patForGh
                Write-Ok "Using GitHub token from git remote URL for gh (set GH_TOKEN or GITHUB_TOKEN to override)."
            }
        }
        try {
        $tag = "v$Version"
        Write-Ok "Checking if tag $tag exists..."
        # refs/tags/ avoids ambiguity with paths like "1.3.0"; SilentlyContinue avoids stderr from native git/gh terminating under $ErrorActionPreference Stop
        $prevEa = $ErrorActionPreference
        $ErrorActionPreference = 'SilentlyContinue'
        try {
            git show-ref --verify --quiet "refs/tags/$tag" 2>$null | Out-Null
            $tagMissing = ($LASTEXITCODE -ne 0)
        } finally {
            $ErrorActionPreference = $prevEa
        }
        if ($tagMissing) {
            Write-Ok "Tagging $tag..."
            $prevEa = $ErrorActionPreference
            $ErrorActionPreference = 'SilentlyContinue'
            try {
                git tag -a $tag -m "Release $Version"
                if ($LASTEXITCODE -ne 0) {
                    Write-Err "git tag failed."
                    exit 1
                }
                git push origin $tag
                if ($LASTEXITCODE -ne 0) {
                    Write-Err "git push failed."
                    exit 1
                }
            } finally {
                $ErrorActionPreference = $prevEa
            }
        }

        Write-Ok "Creating/Updating GitHub release and uploading $zipFile..."
        $prevEa = $ErrorActionPreference
        $ErrorActionPreference = 'SilentlyContinue'
        $ghExit = 0
        try {
            gh release view $tag 2>$null | Out-Null
            $releaseExists = ($LASTEXITCODE -eq 0)
            if ($releaseExists) {
                gh release upload $tag "$zipFile#tmrc-$Version-$os-$arch.zip" --clobber
                $ghExit = $LASTEXITCODE
            } else {
                gh release create $tag $zipFile --title $tag --notes "Release $Version for $os-$arch"
                $ghExit = $LASTEXITCODE
            }
        } finally {
            $ErrorActionPreference = $prevEa
        }
        if ($ghExit -ne 0) {
            Write-Err "GitHub release step failed (gh exit code $ghExit)."
            Write-Host "If you use a PAT in the remote URL, ensure it has repo + workflow (or Contents/Metadata) permissions." -ForegroundColor Yellow
            Write-Host "Or refresh gh OAuth: gh auth refresh -h github.com -s repo -s workflow" -ForegroundColor Cyan
            Write-Host "Then run: gh release create $tag `"$zipFile`" --title $tag --notes `"Release $Version for $os-$arch`"" -ForegroundColor Yellow
            Write-Host "Or re-run: .\devops.ps1 release v$Version" -ForegroundColor Yellow
            exit 1
        }
        Write-Ok "Release $tag published."
        } finally {
            if ($null -ne $patForGh) {
                Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue
            }
        }
    }
}

function Cmd-Clean {
    Assert-DotNetSolution
    $sln = Join-Path $ProjectRoot 'src\Tmrc.sln'
    Invoke-DotNet -Cmd @('dotnet', 'clean', $sln)
    Write-Ok "dotnet artifacts cleaned."
}

function Cmd-ClearTests {
    $testPlanPath = Join-Path $ProjectRoot 'specs\test.md'
    if (-not (Test-Path $testPlanPath)) {
        Write-Err "Test plan not found at $testPlanPath"
        exit 1
    }

    $lines = Get-Content -LiteralPath $testPlanPath
    $updatedLines = @()
    $clearedRows = 0
    $passCellIndex = $null

    function Test-IsMarkdownSeparatorRow {
        param([string[]]$Cells)
        if ($Cells.Length -eq 0) {
            return $false
        }

        foreach ($cell in $Cells) {
            if ($cell -notmatch '^\s*:?-{3,}:?\s*$') {
                return $false
            }
        }

        return $true
    }

    foreach ($line in $lines) {
        if ($line -notmatch '^\|') {
            $passCellIndex = $null
            $updatedLines += $line
            continue
        }

        $parts = $line -split '\|', -1
        if ($parts.Length -lt 3) {
            $updatedLines += $line
            continue
        }

        $cells = @()
        for ($i = 1; $i -lt ($parts.Length - 1); $i++) {
            $cells += $parts[$i]
        }

        $trimmedCells = @($cells | ForEach-Object { $_.Trim() })
        $isSeparator = Test-IsMarkdownSeparatorRow -Cells $trimmedCells

        if (-not $isSeparator) {
            $headerPassPos = -1
            for ($i = 0; $i -lt $trimmedCells.Length; $i++) {
                if ($trimmedCells[$i] -ieq 'Pass') {
                    $headerPassPos = $i
                    break
                }
            }

            if ($headerPassPos -ge 0) {
                # parts has leading and trailing empty segments due to outer '|'
                $passCellIndex = $headerPassPos + 1
                $updatedLines += $line
                continue
            }
        }

        if ($isSeparator) {
            $updatedLines += $line
            continue
        }

        if ($null -ne $passCellIndex -and $passCellIndex -lt ($parts.Length - 1)) {
            if ($parts[$passCellIndex].Trim().Length -gt 0) {
                $clearedRows++
            }
            $parts[$passCellIndex] = ' '
            $updatedLines += ($parts -join '|')
            continue
        }

        $updatedLines += $line
    }

    Set-Content -LiteralPath $testPlanPath -Value $updatedLines
    Write-Ok "Cleared Pass column in specs/test.md ($clearedRows row(s) reset)."
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
    'clear-tests' { Cmd-ClearTests; break }
    'install'   { Cmd-Install; break }
    'uninstall' { Cmd-Uninstall @Args; break }
    'record' { Cmd-Record; break }
    'stop'   { Cmd-Stop; break }
    'status' { Cmd-Status; break }
    'query'  { Cmd-Query @Args; break }
    'export' { Cmd-Export @Args; break }
    'dump' { Cmd-Dump @Args; break }
    'wipe' { Cmd-Wipe; break }
    'reindex' { Cmd-Reindex @Args; break }
    'release' {
        $v = $null
        $nu = $false
        foreach ($a in $Args) {
            if ($a -ieq "-NoUpload") { $nu = $true }
            elseif ($a -match '^(v?\d+\.\d+\.\d+)$') { $v = $a.TrimStart('v') }
        }
        Cmd-Release -Version $v -NoUpload:$nu
        break
    }
    'clean' { Cmd-Clean; break }
    'help' { Show-Usage; break }
    default {
        Write-Err "Unknown command: $Command"
        Show-Usage
        exit 1
    }
}

