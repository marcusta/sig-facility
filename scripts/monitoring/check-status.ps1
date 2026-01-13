#Requires -Version 5.1

<#
.SYNOPSIS
    Bay status monitoring - reports disk space to central API

.DESCRIPTION
    Continuously monitors disk space on C: and D: drives and sends status
    updates to the central API endpoint. Runs as a background process
    managed by the supervisor.

.NOTES
    This script is started by the supervisor and runs continuously.
    Configuration loaded from config/shared.json and config/bays.json
#>

# Load configuration from centralized config system
$scriptRoot = $PSScriptRoot
$repoRoot = Split-Path (Split-Path $scriptRoot -Parent) -Parent
. "$repoRoot\lib\Config.ps1"
$config = Get-SimGolfConfig

# Get configuration values (with fallbacks)
$serverUrl = if ($config.statusMonitorUrl) { $config.statusMonitorUrl } else { "https://app.swedenindoorgolf.se/sig-status/status" }
$intervalSeconds = if ($config.statusMonitorIntervalSeconds) { $config.statusMonitorIntervalSeconds } else { 60 }
$logPath = if ($config.logPath) { $config.logPath } else { "C:\SimGolf\logs" }
$machineName = $env:COMPUTERNAME
$logicalBay = if ($config.logicalBay) { $config.logicalBay } else { "Unknown" }

# Ensure log directory exists
if (-not (Test-Path $logPath)) {
    New-Item -ItemType Directory -Path $logPath -Force | Out-Null
}

$errorLogFile = Join-Path $logPath "monitor_error.log"

# Logging function
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
}

Write-Log "Status monitoring started" -Level "INFO"
Write-Log "Machine: $machineName (Logical Bay: $logicalBay)" -Level "INFO"
Write-Log "API URL: $serverUrl" -Level "INFO"
Write-Log "Interval: $intervalSeconds seconds" -Level "INFO"

# Main monitoring loop
while ($true) {
    try {
        # Get drive information
        $cDrive = Get-PSDrive C -ErrorAction SilentlyContinue | Select-Object Free
        $dDrive = Get-PSDrive D -ErrorAction SilentlyContinue | Select-Object Free

        # Build status object
        $status = @{
            machine = $machineName
            logicalBay = $logicalBay
            timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fff\Z")
            cDriveSpace = if ($cDrive) { [math]::Round($cDrive.Free / 1GB, 2) } else { 0 }
            dDriveSpace = if ($dDrive) { [math]::Round($dDrive.Free / 1GB, 2) } else { 0 }
        }

        # Send to API
        $json = $status | ConvertTo-Json
        $response = Invoke-RestMethod -Uri $serverUrl -Method Post -Body $json -ContentType "application/json" -TimeoutSec 10

        Write-Log "Status sent: C=$($status.cDriveSpace)GB, D=$($status.dDriveSpace)GB" -Level "INFO"

    } catch {
        $errorMsg = "Error sending status: $_"
        Write-Log $errorMsg -Level "ERROR"

        # Log to error file
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path $errorLogFile -Value "[$timestamp] $errorMsg"
    }

    # Check for restart signal
    $restartSignal = "C:\SimGolf\restart-requested"
    if (Test-Path $restartSignal) {
        Write-Log "Restart signal detected, exiting gracefully..." -Level "INFO"
        Remove-Item $restartSignal -ErrorAction SilentlyContinue
        exit 0
    }

    Start-Sleep -Seconds $intervalSeconds
}
