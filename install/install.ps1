#Requires -Version 5.1

<#
.SYNOPSIS
    One-time installation script for SimGolf facility management system

.DESCRIPTION
    Sets up a bay machine with:
    - Clones the sig-facility repo to C:\SimGolf\sig-facility\
    - Copies supervisor.ps1 to C:\SimGolf\supervisor.ps1
    - Creates a scheduled task to run supervisor at login
    - Safe to run multiple times (idempotent)

.PARAMETER BayNumber
    The bay number (1-8) for this machine. Used for validation and documentation.

.PARAMETER RepoUrl
    Git repository URL. Defaults to the placeholder in the script.

.EXAMPLE
    .\install.ps1 -BayNumber 1

.EXAMPLE
    .\install.ps1 -BayNumber 3 -RepoUrl "https://github.com/your-username/sig-facility.git"
#>

param(
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 8)]
    [int]$BayNumber,

    [Parameter(Mandatory = $false)]
    [string]$RepoUrl = "https://github.com/marcusta/sig-facility.git"
)

# Configuration
$InstallRoot = "C:\SimGolf"
$RepoPath = "$InstallRoot\sig-facility"
$SupervisorDestPath = "$InstallRoot\supervisor.ps1"
$SupervisorSourcePath = "$PSScriptRoot\supervisor.ps1"
$TaskName = "SimGolf-Supervisor"
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

    # Display computer info
    Write-Info "Computer Name: $env:COMPUTERNAME"
    if ($BayNumber) {
        Write-Info "Bay Number: $BayNumber"
    }
    Write-Info "Current User: $env:USERNAME"
    Write-Info "Install Root: $InstallRoot"
    Write-Host ""

    # Check if running as administrator (recommended but not required)
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Warn "Not running as Administrator. Scheduled task will run as current user only."
        Write-Host ""
    }

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

    # Step 2: Clone or update repository
    Write-Info "Step 2: Setting up repository..."

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

    # Step 3: Copy supervisor script
    Write-Info "Step 3: Installing supervisor script..."

    if (-not (Test-Path $SupervisorSourcePath)) {
        Write-Fail "Supervisor source script not found at $SupervisorSourcePath"
        Write-Fail "Make sure you're running this from the install directory."
        return $false
    }

    try {
        Copy-Item -Path $SupervisorSourcePath -Destination $SupervisorDestPath -Force
        Write-Success "Supervisor copied to $SupervisorDestPath"
    } catch {
        Write-Fail "Failed to copy supervisor: $_"
        return $false
    }
    Write-Host ""

    # Step 4: Create or update scheduled task
    Write-Info "Step 4: Creating scheduled task..."

    # Check if task already exists
    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

    if ($existingTask) {
        Write-Info "Task '$TaskName' already exists, removing old version..."
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }

    # Create the scheduled task
    try {
        $action = New-ScheduledTaskAction -Execute "powershell.exe" `
                                          -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$SupervisorDestPath`""

        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

        # Task settings
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
                                                  -DontStopIfGoingOnBatteries `
                                                  -StartWhenAvailable `
                                                  -RunOnlyIfNetworkAvailable `
                                                  -ExecutionTimeLimit (New-TimeSpan -Days 0)

        # Register the task
        Register-ScheduledTask -TaskName $TaskName `
                               -Action $action `
                               -Trigger $trigger `
                               -Settings $settings `
                               -Description "SimGolf facility supervisor - auto-updates and process management" `
                               -User $env:USERNAME `
                               -Force | Out-Null

        Write-Success "Scheduled task '$TaskName' created successfully"
        Write-Info "Task will run at login for user: $env:USERNAME"
    } catch {
        Write-Fail "Failed to create scheduled task: $_"
        return $false
    }
    Write-Host ""

    # Step 5: Validation
    Write-Info "Step 5: Validating installation..."

    $validationPassed = $true

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

    # Check scheduled task exists
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Write-Success "Scheduled Task: OK"
    } else {
        Write-Fail "Scheduled Task: FAILED"
        $validationPassed = $false
    }

    Write-Host ""

    # Summary
    if ($validationPassed) {
        Write-Host "=====================================" -ForegroundColor Green
        Write-Host "  Installation Complete!" -ForegroundColor Green
        Write-Host "=====================================" -ForegroundColor Green
        Write-Host ""
        Write-Success "The supervisor will start automatically at next login."
        Write-Info "To start now, run: Start-ScheduledTask -TaskName '$TaskName'"
        Write-Info "Or simply restart this computer."
        Write-Host ""
        Write-Info "Next steps:"
        Write-Info "  1. Update config/bays.json with this bay's specific settings"
        Write-Info "  2. Add your business logic scripts to scripts/"
        Write-Info "  3. Update supervisor.ps1 to reference your main script"
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

if ($success) {
    # Offer to start the supervisor now
    Write-Host ""
    $response = Read-Host "Would you like to start the supervisor now? (Y/N)"
    if ($response -eq 'Y' -or $response -eq 'y') {
        Write-Info "Starting supervisor task..."
        Start-ScheduledTask -TaskName $TaskName
        Write-Success "Supervisor started! Check logs at: $LogPath"
    }
}

exit $(if ($success) { 0 } else { 1 })
