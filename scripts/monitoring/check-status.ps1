#Requires -Version 5.1

<#
.SYNOPSIS
    Bay status monitoring - reports disk space and relay status to central API

.DESCRIPTION
    Continuously monitors disk space on all fixed drives and the USB relay
    (indicator lamp) status written by gspro-start-v2.ahk, and sends status
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
$intervalSeconds = if ($config.statusMonitorIntervalSeconds) { $config.statusMonitorIntervalSeconds } else { 600 }
$logPath = if ($config.logPath) { $config.logPath } else { "C:\SimGolf\logs" }
$machineName = $env:COMPUTERNAME
$logicalBay = if ($config.logicalBay) { $config.logicalBay } else { "Unknown" }

# Ensure log directory exists
if (-not (Test-Path $logPath)) {
    New-Item -ItemType Directory -Path $logPath -Force | Out-Null
}

$errorLogFile = Join-Path $logPath "monitor_error.log"
$relayStatusFile = "C:\SimGolf\relay-status.json"

# Read relay status written by gspro-start-v2.ahk. Returns $null if unavailable.
function Get-RelayStatus {
    if (-not (Test-Path $relayStatusFile)) { return $null }
    try {
        $raw = Get-Content -Path $relayStatusFile -Raw -ErrorAction Stop
        return $raw | ConvertFrom-Json
    } catch {
        Write-Log "Could not read relay status: $_" -Level "WARN"
        return $null
    }
}

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
        $cDrive = Get-PSDrive C -ErrorAction SilentlyContinue
        $dDrive = Get-PSDrive D -ErrorAction SilentlyContinue

        $cFree = if ($cDrive) { [math]::Round($cDrive.Free / 1GB, 2) } else { $null }
        $dFree = if ($dDrive) { [math]::Round($dDrive.Free / 1GB, 2) } else { $null }

        # Build status object
        $status = @{
            machine = $machineName
            logicalBay = $logicalBay
            timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fff\Z")
            cDriveSpace = if ($null -ne $cFree) { $cFree } else { 0 }
        }
        if ($null -ne $dFree) {
            $status.dDriveSpace = $dFree
        }

        # Relay (indicator lamp) status
        $relay = Get-RelayStatus
        if ($null -ne $relay) {
            $status.relayEnabled = [bool]$relay.enabled
            $status.relayConnected = [bool]$relay.connected
            $status.relayPort = [string]$relay.port
            $status.relayError = [string]$relay.error
            $status.relayUpdatedAt = [string]$relay.updatedAt
        }

        # Send to API
        $json = $status | ConvertTo-Json
        $response = Invoke-RestMethod -Uri $serverUrl -Method Post -Body $json -ContentType "application/json" -TimeoutSec 10

        $logMsg = "C=$($cFree)GB"
        if ($null -ne $dFree) { $logMsg += ", D=$($dFree)GB" }
        if ($null -ne $relay) {
            $relayMsg = if (-not $relay.enabled) { "disabled" } elseif ($relay.connected) { "connected on $($relay.port)" } else { "MISSING ($($relay.error))" }
            $logMsg += ", relay=$relayMsg"
        } else {
            $logMsg += ", relay=unknown"
        }
        Write-Log "Status sent: $logMsg" -Level "INFO"

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
