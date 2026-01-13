#Requires -Version 5.1

<#
.SYNOPSIS
    SimGolf Facility Supervisor - Auto-update and process management

.DESCRIPTION
    This script lives at C:\SimGolf\supervisor.ps1 (OUTSIDE the repo).
    It runs continuously and:
    - Pulls updates from git every 30 minutes
    - Tracks commit hash changes
    - Restarts background processes when code changes
    - Handles initial repo clone if needed

.NOTES
    This script is installed once and rarely changes. To update it, you must
    manually replace it on each bay or re-run the installer.
#>

# Configuration
$RepoPath = "C:\SimGolf\sig-facility"
$RepoUrl = "https://github.com/marcusta/sig-facility.git"
$BackgroundScriptPath = "$RepoPath\scripts\monitoring\check-status.ps1"
$RestartSignalFile = "C:\SimGolf\restart-requested"
$CheckIntervalSeconds = 1800  # 30 minutes
$LogPath = "C:\SimGolf\logs"
$LogFile = "$LogPath\supervisor-$(Get-Date -Format 'yyyy-MM-dd').log"

# Ensure log directory exists
if (-not (Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

# Logging function
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    Add-Content -Path $LogFile -Value $logMessage
}

# Get current git commit hash
function Get-CurrentCommit {
    param([string]$Path)

    if (-not (Test-Path "$Path\.git")) {
        return $null
    }

    try {
        Push-Location $Path
        $commit = git rev-parse HEAD 2>$null
        Pop-Location
        return $commit
    } catch {
        Pop-Location
        return $null
    }
}

# Clone or pull the repository
function Update-Repository {
    param([string]$Path, [string]$Url)

    if (-not (Test-Path $Path)) {
        Write-Log "Repository not found at $Path, cloning..." -Level "INFO"

        $parentPath = Split-Path $Path -Parent
        if (-not (Test-Path $parentPath)) {
            New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
        }

        try {
            git clone $Url $Path 2>&1 | Out-String | Write-Log
            Write-Log "Repository cloned successfully" -Level "INFO"
            return $true  # Change detected (new clone)
        } catch {
            Write-Log "Failed to clone repository: $_" -Level "ERROR"
            return $false
        }
    }

    # Repository exists, pull updates
    $beforeCommit = Get-CurrentCommit -Path $Path
    Write-Log "Current commit: $beforeCommit" -Level "INFO"

    try {
        Push-Location $Path

        # Fetch and pull with fast-forward only (safer)
        Write-Log "Pulling updates..." -Level "INFO"
        $pullOutput = git pull --ff-only origin main 2>&1 | Out-String
        Write-Log $pullOutput -Level "INFO"

        Pop-Location

        $afterCommit = Get-CurrentCommit -Path $Path
        Write-Log "After pull commit: $afterCommit" -Level "INFO"

        # Return true if commit changed
        return ($beforeCommit -ne $afterCommit)

    } catch {
        Pop-Location
        Write-Log "Failed to pull updates: $_" -Level "ERROR"
        return $false
    }
}

# Check if background process is running
function Test-BackgroundProcessRunning {
    # Look for PowerShell process running our background script
    $processes = Get-Process -Name pwsh, powershell -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -like "*background-monitor.ps1*"
    }

    return ($null -ne $processes -and $processes.Count -gt 0)
}

# Start the background process
function Start-BackgroundProcess {
    param([string]$ScriptPath)

    if (-not (Test-Path $ScriptPath)) {
        Write-Log "Background script not found at $ScriptPath" -Level "WARN"
        return $false
    }

    Write-Log "Starting background process: $ScriptPath" -Level "INFO"

    try {
        # Start the background script in a new window (for debugging) or hidden
        # Change -WindowStyle to 'Normal' for debugging, 'Hidden' for production
        Start-Process -FilePath "powershell.exe" `
                      -ArgumentList "-ExecutionPolicy", "Bypass", "-File", "`"$ScriptPath`"" `
                      -WindowStyle Hidden

        Write-Log "Background process started" -Level "INFO"
        return $true
    } catch {
        Write-Log "Failed to start background process: $_" -Level "ERROR"
        return $false
    }
}

# Request graceful restart of background process
function Request-BackgroundRestart {
    Write-Log "Requesting graceful restart of background process" -Level "INFO"

    # Create restart signal file
    Set-Content -Path $RestartSignalFile -Value (Get-Date) -Force

    # Wait up to 30 seconds for process to exit gracefully
    $timeout = 30
    $waited = 0

    while ($waited -lt $timeout) {
        if (-not (Test-BackgroundProcessRunning)) {
            Write-Log "Background process stopped gracefully" -Level "INFO"
            return $true
        }

        Start-Sleep -Seconds 2
        $waited += 2
    }

    # If still running after timeout, force kill
    Write-Log "Background process did not stop gracefully, force killing" -Level "WARN"
    Get-Process -Name pwsh, powershell -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -like "*background-monitor.ps1*"
    } | Stop-Process -Force

    Start-Sleep -Seconds 2
    return $true
}

# Main supervisor loop
function Start-Supervisor {
    Write-Log "===== SimGolf Supervisor Started =====" -Level "INFO"
    Write-Log "Repository: $RepoPath" -Level "INFO"
    Write-Log "Computer: $env:COMPUTERNAME" -Level "INFO"
    Write-Log "Check interval: $CheckIntervalSeconds seconds" -Level "INFO"

    while ($true) {
        try {
            Write-Log "Running update check..." -Level "INFO"

            # Pull updates and check if anything changed
            $changesDetected = Update-Repository -Path $RepoPath -Url $RepoUrl

            # Restart if changes detected OR background process not running
            $isRunning = Test-BackgroundProcessRunning

            if ($changesDetected) {
                Write-Log "Changes detected, restarting background process" -Level "INFO"
                Request-BackgroundRestart
                Start-Sleep -Seconds 3
                Start-BackgroundProcess -ScriptPath $BackgroundScriptPath
            } elseif (-not $isRunning) {
                Write-Log "Background process not running, starting it" -Level "INFO"
                Start-BackgroundProcess -ScriptPath $BackgroundScriptPath
            } else {
                Write-Log "No changes detected, background process running normally" -Level "INFO"
            }

            Write-Log "Next check in $CheckIntervalSeconds seconds" -Level "INFO"
            Start-Sleep -Seconds $CheckIntervalSeconds

        } catch {
            Write-Log "Supervisor loop error: $_" -Level "ERROR"
            Write-Log "Waiting 60 seconds before retry..." -Level "INFO"
            Start-Sleep -Seconds 60
        }
    }
}

# Start the supervisor
Start-Supervisor
