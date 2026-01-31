#Requires -Version 5.1

<#
.SYNOPSIS
    One-time installation script for SimGolf facility management system

.DESCRIPTION
    Sets up a bay machine with:
    - Writes bay identity to C:\SimGolf\bay-identity.json
    - Clones the sig-facility repo to C:\SimGolf\sig-facility\
    - Copies supervisor.ps1 to C:\SimGolf\supervisor.ps1
    - Creates shortcuts (GSPro desktop + shell:startup)
    - Safe to run multiple times (idempotent)

.PARAMETER BayId
    The bay identifier (e.g. BAY01, BAY02). Must match a key in config/bays.json.
    If not provided, the script will prompt for it.

.PARAMETER RepoUrl
    Git repository URL. Defaults to the sig-facility repo.

.EXAMPLE
    .\install.ps1 -BayId BAY01

.EXAMPLE
    .\install.ps1
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$BayId,

    [Parameter(Mandatory = $false)]
    [string]$RepoUrl = "https://github.com/marcusta/sig-facility.git"
)

# Configuration
$InstallRoot = "C:\SimGolf"
$RepoPath = "$InstallRoot\sig-facility"
$SupervisorDestPath = "$InstallRoot\supervisor.ps1"
$SupervisorSourcePath = "$PSScriptRoot\supervisor.ps1"
$IdentityPath = "$InstallRoot\bay-identity.json"
$LogPath = "$InstallRoot\logs"

# Color output functions
function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Main installation function
function Install-SimGolfSystem {
    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host "  SimGolf Facility Installation" -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host ""

    # Prompt for bay ID if not provided
    if (-not $BayId) {
        Write-Host ""
        Write-Info "Available bay IDs are defined in config/bays.json (e.g. BAY01, BAY02, ...)"
        $BayId = Read-Host "Enter the bay ID for this machine"
        if (-not $BayId) {
            Write-Fail "Bay ID is required."
            return $false
        }
    }

    # Display computer info
    Write-Info "Computer Name: $env:COMPUTERNAME"
    Write-Info "Bay ID: $BayId"
    Write-Info "Current User: $env:USERNAME"
    Write-Info "Install Root: $InstallRoot"
    Write-Host ""

    # Step 1: Ensure base directory exists
    Write-Info "Step 1: Creating base directory structure..."
    if (-not (Test-Path $InstallRoot)) {
        New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
        Write-Success "Created $InstallRoot"
    } else {
        Write-Success "Directory $InstallRoot already exists"
    }

    if (-not (Test-Path $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
        Write-Success "Created $LogPath"
    } else {
        Write-Success "Log directory already exists"
    }
    Write-Host ""

    # Step 2: Write bay identity file
    Write-Info "Step 2: Writing bay identity..."
    $identityJson = @{ bayId = $BayId } | ConvertTo-Json
    Set-Content -Path $IdentityPath -Value $identityJson -Force
    Write-Success "Bay identity written to $IdentityPath (bayId: $BayId)"
    Write-Host ""

    # Step 3: Clone or update repository
    Write-Info "Step 3: Setting up repository..."

    # Check if git is available
    $gitAvailable = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitAvailable) {
        Write-Fail "Git is not installed or not in PATH. Please install Git and try again."
        Write-Fail "Download from: https://git-scm.com/download/win"
        return $false
    }

    if (-not (Test-Path $RepoPath)) {
        Write-Info "Cloning repository from $RepoUrl..."
        try {
            git clone $RepoUrl $RepoPath
            Write-Success "Repository cloned successfully"
        } catch {
            Write-Fail "Failed to clone repository: $_"
            return $false
        }
    } else {
        Write-Info "Repository already exists at $RepoPath"

        # Check if it's a valid git repo
        if (Test-Path "$RepoPath\.git") {
            Write-Info "Pulling latest changes..."
            try {
                Push-Location $RepoPath
                git pull --ff-only origin main 2>&1 | Out-Null
                Pop-Location
                Write-Success "Repository updated"
            } catch {
                Pop-Location
                Write-Warn "Could not pull updates (may have local changes): $_"
            }
        } else {
            Write-Warn "Directory exists but is not a git repository. Skipping clone."
        }
    }
    Write-Host ""

    # Step 4: Copy supervisor script
    Write-Info "Step 4: Installing supervisor script..."

    # If supervisor.ps1 doesn't exist locally, download it from GitHub
    if (-not (Test-Path $SupervisorSourcePath)) {
        Write-Info "Supervisor not found locally, downloading from GitHub..."

        $supervisorUrl = "https://raw.githubusercontent.com/marcusta/sig-facility/main/install/supervisor.ps1"
        $tempSupervisorPath = "$env:TEMP\supervisor.ps1"

        try {
            Invoke-WebRequest -Uri $supervisorUrl -OutFile $tempSupervisorPath -UseBasicParsing
            $SupervisorSourcePath = $tempSupervisorPath
            Write-Success "Downloaded supervisor.ps1 from GitHub"
        } catch {
            Write-Fail "Failed to download supervisor.ps1: $_"
            Write-Fail "You can manually download it from: $supervisorUrl"
            return $false
        }
    }

    try {
        Copy-Item -Path $SupervisorSourcePath -Destination $SupervisorDestPath -Force
        Write-Success "Supervisor copied to $SupervisorDestPath"
    } catch {
        Write-Fail "Failed to copy supervisor: $_"
        return $false
    }
    Write-Host ""

    # Step 5: Create shortcuts
    Write-Info "Step 5: Creating shortcuts..."

    $WshShell = New-Object -ComObject WScript.Shell

    # Master GSPro desktop shortcut at C:\SimGolf\GSPro.lnk
    $gsproLnk = $WshShell.CreateShortcut("$InstallRoot\GSPro.lnk")
    $gsproLnk.TargetPath = "$RepoPath\scripts\gspro-automation\gspro-start-v2.ahk"
    $gsproLnk.WorkingDirectory = "$RepoPath\scripts\gspro-automation"
    $gsproLnk.Description = "Start GSPro"
    $gsproLnk.Save()
    Write-Success "Created master shortcut: $InstallRoot\GSPro.lnk"

    # Startup launcher shortcut in shell:startup
    $startupFolder = [System.Environment]::GetFolderPath("Startup")
    $startupLnk = $WshShell.CreateShortcut("$startupFolder\SimGolf.lnk")
    $startupLnk.TargetPath = "$RepoPath\scripts\startup-launcher.bat"
    $startupLnk.WorkingDirectory = "$RepoPath\scripts"
    $startupLnk.Description = "SimGolf Startup Launcher"
    $startupLnk.WindowStyle = 7  # 7 = Minimized
    $startupLnk.Save()
    Write-Success "Created startup shortcut: $startupFolder\SimGolf.lnk"
    Write-Host ""

    # Remove legacy scheduled task if it exists
    $legacyTask = Get-ScheduledTask -TaskName "SimGolf-Supervisor" -ErrorAction SilentlyContinue
    if ($legacyTask) {
        Write-Info "Removing legacy scheduled task..."
        Unregister-ScheduledTask -TaskName "SimGolf-Supervisor" -Confirm:$false
        Write-Success "Legacy scheduled task removed"
    }

    # Step 6: Validation
    Write-Info "Step 6: Validating installation..."

    $validationPassed = $true

    # Check identity file
    if (Test-Path $IdentityPath) {
        Write-Success "Bay Identity: OK ($BayId)"
    } else {
        Write-Fail "Bay Identity: FAILED"
        $validationPassed = $false
    }

    # Check repo exists
    if (Test-Path "$RepoPath\.git") {
        Write-Success "Repository: OK"
    } else {
        Write-Fail "Repository: FAILED"
        $validationPassed = $false
    }

    # Check supervisor exists
    if (Test-Path $SupervisorDestPath) {
        Write-Success "Supervisor: OK"
    } else {
        Write-Fail "Supervisor: FAILED"
        $validationPassed = $false
    }

    # Check startup shortcut
    $startupFolder = [System.Environment]::GetFolderPath("Startup")
    if (Test-Path "$startupFolder\SimGolf.lnk") {
        Write-Success "Startup Shortcut: OK"
    } else {
        Write-Fail "Startup Shortcut: FAILED"
        $validationPassed = $false
    }

    Write-Host ""

    # Summary
    if ($validationPassed) {
        Write-Host "=====================================" -ForegroundColor Green
        Write-Host "  Installation Complete!" -ForegroundColor Green
        Write-Host "=====================================" -ForegroundColor Green
        Write-Host ""
        Write-Success "Everything will start automatically at next login via the startup shortcut."
        Write-Info "Reboot the machine to verify the full startup sequence."
        Write-Host ""
        Write-Info "Next steps:"
        Write-Info "  1. Ensure '$BayId' exists in config/bays.json (commit and push to main)"
        Write-Info "  2. Reboot the machine to verify the full startup sequence"
        Write-Host ""
        return $true
    } else {
        Write-Host "=====================================" -ForegroundColor Red
        Write-Host "  Installation Incomplete" -ForegroundColor Red
        Write-Host "=====================================" -ForegroundColor Red
        Write-Host ""
        Write-Fail "Some validation checks failed. Please review errors above."
        Write-Host ""
        return $false
    }
}

# Run installation
$success = Install-SimGolfSystem
exit $(if ($success) { 0 } else { 1 })
