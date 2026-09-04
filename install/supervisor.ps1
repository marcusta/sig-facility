#Requires -Version 5.1

<#
.SYNOPSIS
    SimGolf Facility Supervisor - Auto-update and process management

.DESCRIPTION
    This script lives at C:\SimGolf\supervisor.ps1 (OUTSIDE the repo).
    It runs continuously and:
    - Pulls updates from git every 30 minutes
    - Tracks commit hash changes
    - Restarts background processes (check-status, shot-watcher) when code changes
    - Handles initial repo clone if needed

.NOTES
    Self-updates from the repo copy (install/supervisor.ps1) after each git pull.
    Also updated by startup-launcher.bat on each reboot.
#>

# Configuration
$RepoPath = "C:\SimGolf\sig-facility"
$RepoUrl = "https://github.com/marcusta/sig-facility.git"
# Background scripts managed by this supervisor. Each one exits when its
# Signal file appears (and deletes it), so restarts are graceful per script.
$BackgroundScripts = @(
    @{ Name = "check-status";  Path = "$RepoPath\scripts\monitoring\check-status.ps1";   Signal = "C:\SimGolf\restart-requested" },
    @{ Name = "shot-watcher";  Path = "$RepoPath\scripts\shot-watcher\shot-watcher.ps1"; Signal = "C:\SimGolf\restart-requested-shot-watcher" }
)
$SupervisorRepoPath = "$RepoPath\install\supervisor.ps1"
$SupervisorRunningPath = "C:\SimGolf\supervisor.ps1"
$CheckIntervalSeconds = 1800  # 30 minutes
$LogPath = "C:\SimGolf\logs"
$LogFile = "$LogPath\supervisor-$(Get-Date -Format 'yyyy-MM-dd').log"
$DevModeLockFile = "C:\SimGolf\dev-mode-active"

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

        if (Test-Path $DevModeLockFile) {
            Write-Log "Dev mode lock detected at $DevModeLockFile - skipping branch enforcement and git pull" -Level "INFO"
            Pop-Location
            return $false
        }

        # Ensure we're on main branch (could be on a dev branch after unclean shutdown)
        $currentBranch = git rev-parse --abbrev-ref HEAD 2>$null
        if ($currentBranch -ne "main") {
            Write-Log "Not on main branch (on '$currentBranch'), switching to main" -Level "WARN"
            git checkout main 2>&1 | Out-String | Write-Log
        }

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

# Processes running a given background script (matched on the script file name)
function Get-BackgroundProcesses {
    param($Script)
    $fileName = Split-Path $Script.Path -Leaf
    return @(Get-CimInstance Win32_Process -Filter "CommandLine LIKE '%$fileName%'")
}

function Test-BackgroundProcessRunning {
    param($Script)
    return ((Get-BackgroundProcesses -Script $Script).Count -gt 0)
}

# Start one background script hidden
function Start-BackgroundProcess {
    param($Script)

    if (-not (Test-Path $Script.Path)) {
        Write-Log "Background script not found at $($Script.Path)" -Level "WARN"
        return $false
    }

    Write-Log "Starting background process: $($Script.Name)" -Level "INFO"

    try {
        # Change -WindowStyle to 'Normal' for debugging, 'Hidden' for production
        Start-Process -FilePath "powershell.exe" `
                      -ArgumentList "-ExecutionPolicy", "Bypass", "-File", "`"$($Script.Path)`"" `
                      -WindowStyle Hidden

        Write-Log "Background process started: $($Script.Name)" -Level "INFO"
        return $true
    } catch {
        Write-Log "Failed to start background process $($Script.Name): $_" -Level "ERROR"
        return $false
    }
}

# Request graceful restart of one background script, force kill after 30 s
function Request-BackgroundRestart {
    param($Script)

    if (-not (Test-BackgroundProcessRunning -Script $Script)) {
        return $true
    }

    Write-Log "Requesting graceful stop of $($Script.Name)" -Level "INFO"
    Set-Content -Path $Script.Signal -Value (Get-Date) -Force

    $timeout = 30
    $waited = 0
    while ($waited -lt $timeout) {
        if (-not (Test-BackgroundProcessRunning -Script $Script)) {
            Write-Log "$($Script.Name) stopped gracefully" -Level "INFO"
            Remove-Item $Script.Signal -ErrorAction SilentlyContinue
            return $true
        }
        Start-Sleep -Seconds 2
        $waited += 2
    }

    Write-Log "$($Script.Name) did not stop gracefully, force killing" -Level "WARN"
    Get-BackgroundProcesses -Script $Script |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Remove-Item $Script.Signal -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    return $true
}

# Restart every background script (used after code changes and on supervisor start)
function Restart-AllBackgroundProcesses {
    foreach ($script in $BackgroundScripts) {
        Request-BackgroundRestart -Script $script | Out-Null
    }
    Start-Sleep -Seconds 3
    foreach ($script in $BackgroundScripts) {
        Start-BackgroundProcess -Script $script | Out-Null
    }
}

# Self-update: replace running supervisor if repo version differs, then restart
function Update-Supervisor {
    if (-not (Test-Path $SupervisorRepoPath)) {
        return
    }

    $repoHash = (Get-FileHash $SupervisorRepoPath -Algorithm SHA256).Hash
    $runningHash = (Get-FileHash $SupervisorRunningPath -Algorithm SHA256).Hash

    if ($repoHash -ne $runningHash) {
        Write-Log "Supervisor update detected, replacing and restarting..." -Level "INFO"
        Copy-Item -Path $SupervisorRepoPath -Destination $SupervisorRunningPath -Force
        Start-Process -FilePath "powershell.exe" `
                      -ArgumentList "-ExecutionPolicy", "Bypass", "-File", "`"$SupervisorRunningPath`"" `
                      -WindowStyle Hidden
        Write-Log "New supervisor instance started, exiting old instance" -Level "INFO"
        exit 0
    }
}

# Main supervisor loop
function Start-Supervisor {
    Write-Log "===== SimGolf Supervisor Started =====" -Level "INFO"
    Write-Log "Repository: $RepoPath" -Level "INFO"
    Write-Log "Computer: $env:COMPUTERNAME" -Level "INFO"
    Write-Log "Check interval: $CheckIntervalSeconds seconds" -Level "INFO"

    # A supervisor start means boot or self-update; either way the background
    # scripts should run the code that is in the repo now.
    Restart-AllBackgroundProcesses

    while ($true) {
        try {
            Write-Log "Running update check..." -Level "INFO"

            # Pull updates and check if anything changed
            $changesDetected = Update-Repository -Path $RepoPath -Url $RepoUrl

            # Self-update supervisor if repo version changed (exits if updated;
            # the new instance restarts the background scripts on start)
            if ($changesDetected) {
                Update-Supervisor
            }

            if ($changesDetected) {
                Write-Log "Changes detected, restarting background processes" -Level "INFO"
                Restart-AllBackgroundProcesses
            } else {
                foreach ($script in $BackgroundScripts) {
                    if (-not (Test-BackgroundProcessRunning -Script $script)) {
                        Write-Log "$($script.Name) not running, starting it" -Level "INFO"
                        Start-BackgroundProcess -Script $script | Out-Null
                    }
                }
                Write-Log "No changes detected" -Level "INFO"
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
