#Requires -Version 5.1

<#
.SYNOPSIS
    Installs .NET runtime for gs-checker.exe

.DESCRIPTION
    Downloads and installs the required .NET runtime version for running
    gs-checker.exe without bundling the runtime in the executable.

.PARAMETER RuntimeVersion
    The .NET runtime version to install (e.g., "8.0", "7.0", "6.0")

.EXAMPLE
    .\install-dotnet-runtime.ps1 -RuntimeVersion "8.0"
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$RuntimeVersion = "8.0"  # Default to .NET 8.0, adjust as needed
)

Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "  .NET Runtime Installation" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Target Runtime Version: .NET $RuntimeVersion" -ForegroundColor Cyan
Write-Host ""

# Check if .NET runtime is already installed
try {
    $installedRuntimes = dotnet --list-runtimes 2>$null | Where-Object { $_ -like "Microsoft.NETCore.App $RuntimeVersion*" }

    if ($installedRuntimes) {
        Write-Host "[OK] .NET $RuntimeVersion runtime is already installed:" -ForegroundColor Green
        $installedRuntimes | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
        Write-Host ""
        Write-Host "No installation needed." -ForegroundColor Green
        exit 0
    }
} catch {
    Write-Host "[INFO] .NET CLI not found, will install runtime..." -ForegroundColor Yellow
}

# Download and run the official .NET installer script
Write-Host "[INFO] Downloading .NET installer script..." -ForegroundColor Cyan

$installerUrl = "https://dot.net/v1/dotnet-install.ps1"
$installerPath = "$env:TEMP\dotnet-install.ps1"

try {
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
    Write-Host "[OK] Installer downloaded" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to download installer: $_" -ForegroundColor Red
    exit 1
}

# Run the installer
Write-Host ""
Write-Host "[INFO] Installing .NET $RuntimeVersion runtime..." -ForegroundColor Cyan
Write-Host "This may take a few minutes..." -ForegroundColor Gray
Write-Host ""

try {
    & $installerPath -Channel $RuntimeVersion -Runtime dotnet -InstallDir "$env:ProgramFiles\dotnet"

    Write-Host ""
    Write-Host "[OK] .NET $RuntimeVersion runtime installed successfully!" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Installation failed: $_" -ForegroundColor Red
    exit 1
}

# Verify installation
Write-Host ""
Write-Host "Verifying installation..." -ForegroundColor Cyan

try {
    $dotnetPath = "$env:ProgramFiles\dotnet\dotnet.exe"

    if (Test-Path $dotnetPath) {
        & $dotnetPath --list-runtimes | Where-Object { $_ -like "Microsoft.NETCore.App $RuntimeVersion*" } | ForEach-Object {
            Write-Host "[OK] $_" -ForegroundColor Green
        }

        Write-Host ""
        Write-Host "=====================================" -ForegroundColor Green
        Write-Host "  Installation Complete!" -ForegroundColor Green
        Write-Host "=====================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "gs-checker.exe can now run without bundled runtime." -ForegroundColor Green
        Write-Host ""
    } else {
        Write-Host "[WARN] Installation completed but dotnet.exe not found at expected location" -ForegroundColor Yellow
        Write-Host "You may need to restart your terminal or add dotnet to PATH manually" -ForegroundColor Yellow
    }
} catch {
    Write-Host "[WARN] Could not verify installation: $_" -ForegroundColor Yellow
}

# Cleanup
Remove-Item $installerPath -ErrorAction SilentlyContinue

exit 0
