#Requires -Version 5.1

<#
.SYNOPSIS
    GSPro shot watcher - forwards shots from currentRound.dat to sig-gsp-data

.DESCRIPTION
    Polls GSPro's currentRound.dat (a JSON array that GSPro rewrites after
    every shot) and posts new shots to the sig-gsp-data ingest API. Shots are
    deduplicated by ShotID; a session id is generated when the file starts a
    new round (first ShotID changes). Unsent shots are retried on the next poll.

    Runs as a background process managed by the supervisor. Exits when the
    file C:\SimGolf\restart-requested-shot-watcher appears.

.NOTES
    Configuration (config/shared.json, overridable per bay in bays.json):
      shotWatcherEnabled          true/false (default true)
      shotWatcherUrl              ingest endpoint
      shotWatcherIntervalSeconds  poll interval (default 5)
      shotDataPath                full path to currentRound.dat; empty = auto-detect
                                  under %USERPROFILE%\AppData\LocalLow
      shotWatcherApiKeyFile       file holding the X-Api-Key value (default
                                  C:\SimGolf\shot-api-key.txt, NOT in the repo)
#>

$scriptRoot = $PSScriptRoot
$repoRoot = Split-Path (Split-Path $scriptRoot -Parent) -Parent
. "$repoRoot\lib\Config.ps1"
$config = Get-SimGolfConfig

$enabled = if ($null -ne $config.shotWatcherEnabled) { [bool]$config.shotWatcherEnabled } else { $true }
$serverUrl = if ($config.shotWatcherUrl) { $config.shotWatcherUrl } else { "https://app.swedenindoorgolf.se/sig-gsp-data/api/ingest/shots" }
$intervalSeconds = if ($config.shotWatcherIntervalSeconds) { [int]$config.shotWatcherIntervalSeconds } else { 5 }
$configuredPath = if ($config.shotDataPath) { [string]$config.shotDataPath } else { "" }
$apiKeyFile = if ($config.shotWatcherApiKeyFile) { $config.shotWatcherApiKeyFile } else { "C:\SimGolf\shot-api-key.txt" }
$logPath = if ($config.logPath) { $config.logPath } else { "C:\SimGolf\logs" }
$machineName = $env:COMPUTERNAME
$logicalBay = if ($config.logicalBay) { [int]$config.logicalBay } else { $null }

$stateFile = "C:\SimGolf\shot-watcher-state.json"
$restartSignal = "C:\SimGolf\restart-requested-shot-watcher"
$batchSize = 25
$errorBackoffSeconds = 30
$heartbeatSeconds = 600

if (-not (Test-Path $logPath)) {
    New-Item -ItemType Directory -Path $logPath -Force | Out-Null
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line
    $logFile = Join-Path $logPath "shot-watcher-$(Get-Date -Format 'yyyy-MM-dd').log"
    try { Add-Content -Path $logFile -Value $line -ErrorAction Stop } catch { }
}

# PowerShell 5's ConvertFrom-Json caps input at 2 MB; a full round is larger.
Add-Type -AssemblyName System.Web.Extensions
$serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$serializer.MaxJsonLength = [int]::MaxValue
$serializer.RecursionLimit = 200

function Get-ApiKey {
    if (Test-Path $apiKeyFile) {
        try {
            $key = (Get-Content -Path $apiKeyFile -Raw -ErrorAction Stop).Trim()
            if ($key.Length -gt 0) { return $key }
        } catch {
            Write-Log "Could not read API key file $apiKeyFile : $_" -Level "WARN"
        }
    }
    return $null
}

function Resolve-ShotDataPath {
    if ($configuredPath -ne "") {
        $expanded = [Environment]::ExpandEnvironmentVariables($configuredPath)
        return $expanded
    }
    $localLow = Join-Path $env:USERPROFILE "AppData\LocalLow"
    $default = Join-Path $localLow "GSPro\currentRound.dat"
    if (Test-Path $default) { return $default }
    if (Test-Path $localLow) {
        $found = Get-ChildItem -Path $localLow -Filter "currentRound.dat" -Recurse -Depth 3 -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    return $default
}

function Load-State {
    $empty = @{ sessionId = $null; firstShotId = $null; sentShotIds = @() }
    if (-not (Test-Path $stateFile)) { return $empty }
    try {
        $raw = Get-Content -Path $stateFile -Raw -ErrorAction Stop
        $obj = $serializer.DeserializeObject($raw)
        $sent = @()
        if ($obj.ContainsKey("sentShotIds") -and $null -ne $obj["sentShotIds"]) { $sent = @($obj["sentShotIds"]) }
        return @{
            sessionId = $obj["sessionId"]
            firstShotId = $obj["firstShotId"]
            sentShotIds = $sent
        }
    } catch {
        Write-Log "Could not read state file, starting fresh: $_" -Level "WARN"
        return $empty
    }
}

function Save-State {
    param($State)
    $payload = @{
        sessionId = $State.sessionId
        firstShotId = $State.firstShotId
        sentShotIds = @($State.sentShotIds)
        updatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fff\Z")
    }
    try {
        Set-Content -Path $stateFile -Value $serializer.Serialize($payload) -Encoding ASCII -Force -ErrorAction Stop
    } catch {
        Write-Log "Could not write state file: $_" -Level "WARN"
    }
}

function Read-Shots {
    param([string]$Path)
    # GSPro rewrites the whole file; a read during the write yields a partial
    # document, which fails to parse and is retried on the next poll.
    $raw = [System.IO.File]::ReadAllText($Path)
    if ($raw.Trim().Length -eq 0) { return @() }
    $parsed = $serializer.DeserializeObject($raw)
    if ($null -eq $parsed) { return @() }
    return @($parsed)
}

function Send-Batch {
    param($State, $Shots, [string]$ApiKey)
    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fff\Z")
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($shot in $Shots) {
        $parts.Add('{"seenAt":"' + $now + '","data":' + $serializer.Serialize($shot) + '}')
    }
    $bayJson = if ($null -ne $logicalBay) { ',"logicalBay":' + $logicalBay } else { "" }
    $body = '{"machine":' + $serializer.Serialize($machineName) + $bayJson +
        ',"sessionId":"' + $State.sessionId + '","shots":[' + ($parts -join ",") + ']}'
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $headers = @{}
    if ($ApiKey) { $headers["X-Api-Key"] = $ApiKey }
    return Invoke-RestMethod -Uri $serverUrl -Method Post -Body $bytes -Headers $headers `
        -ContentType "application/json; charset=utf-8" -TimeoutSec 30
}

if (-not $enabled) {
    Write-Log "Shot watcher disabled by config (shotWatcherEnabled=false), idling" -Level "INFO"
    while ($true) {
        if (Test-Path $restartSignal) { Remove-Item $restartSignal -ErrorAction SilentlyContinue; exit 0 }
        Start-Sleep -Seconds 60
    }
}

$dataPath = Resolve-ShotDataPath
$state = Load-State

Write-Log "Shot watcher started" -Level "INFO"
Write-Log "Machine: $machineName (Logical Bay: $logicalBay)" -Level "INFO"
Write-Log "Data file: $dataPath (exists: $(Test-Path $dataPath))" -Level "INFO"
Write-Log "API URL: $serverUrl" -Level "INFO"
Write-Log "API key file: $apiKeyFile (present: $(Test-Path $apiKeyFile))" -Level "INFO"
Write-Log "Interval: $intervalSeconds seconds" -Level "INFO"
if ($state.sessionId) {
    Write-Log "Resuming session $($state.sessionId) with $($state.sentShotIds.Count) shots already sent" -Level "INFO"
}

$lastLength = -1
$lastWrite = [DateTime]::MinValue
$lastHeartbeat = Get-Date
$missingLogged = $false
$sleepSeconds = $intervalSeconds

while ($true) {
    try {
        if (-not (Test-Path $dataPath)) {
            if (-not $missingLogged) {
                Write-Log "Data file not found: $dataPath (will keep checking)" -Level "WARN"
                $missingLogged = $true
            }
            # Re-run auto-detection in case GSPro created the folder later.
            if ($configuredPath -eq "") { $dataPath = Resolve-ShotDataPath }
        } else {
            if ($missingLogged) {
                Write-Log "Data file appeared: $dataPath" -Level "INFO"
                $missingLogged = $false
            }
            $info = Get-Item -Path $dataPath
            if ($info.Length -ne $lastLength -or $info.LastWriteTimeUtc -ne $lastWrite) {
                $shots = Read-Shots -Path $dataPath
                # Parse succeeded: remember this version so it is not reparsed.
                $lastLength = $info.Length
                $lastWrite = $info.LastWriteTimeUtc

                if ($shots.Count -gt 0) {
                    $firstId = [string]$shots[0]["ShotID"]
                    if ($firstId -ne $state.firstShotId -or -not $state.sessionId) {
                        $state.sessionId = [guid]::NewGuid().ToString()
                        $state.firstShotId = $firstId
                        $state.sentShotIds = @()
                        Save-State -State $state
                        Write-Log "New session $($state.sessionId): player '$($shots[0]["PlayerName"])', course '$($shots[0]["CourseKey"])', round $($shots[0]["RoundID"])" -Level "INFO"
                    }

                    $sentSet = New-Object System.Collections.Generic.HashSet[string]
                    foreach ($id in $state.sentShotIds) { [void]$sentSet.Add([string]$id) }
                    $pending = New-Object System.Collections.Generic.List[object]
                    foreach ($shot in $shots) {
                        $id = [string]$shot["ShotID"]
                        if ($id -and -not $sentSet.Contains($id)) { $pending.Add($shot) }
                        if ($pending.Count -ge $batchSize) { break }
                    }

                    if ($pending.Count -gt 0) {
                        $response = Send-Batch -State $state -Shots $pending -ApiKey (Get-ApiKey)
                        foreach ($shot in $pending) { $state.sentShotIds += [string]$shot["ShotID"] }
                        Save-State -State $state
                        Write-Log "Sent $($pending.Count) shots (inserted=$($response.inserted), duplicates=$($response.duplicates), rejected=$($response.rejected)); $($shots.Count) in file, $($state.sentShotIds.Count) sent" -Level "INFO"
                        # More may be waiting when a batch was capped.
                        if ($pending.Count -ge $batchSize) { $lastLength = -1 }
                    }
                }
            }
        }
        $sleepSeconds = $intervalSeconds
    } catch {
        Write-Log "Error: $_" -Level "ERROR"
        # Force a reparse next time and back off a little.
        $lastLength = -1
        $sleepSeconds = $errorBackoffSeconds
    }

    if (((Get-Date) - $lastHeartbeat).TotalSeconds -ge $heartbeatSeconds) {
        Write-Log "Heartbeat: file=$dataPath exists=$(Test-Path $dataPath) session=$($state.sessionId) sent=$($state.sentShotIds.Count)" -Level "INFO"
        $lastHeartbeat = Get-Date
    }

    if (Test-Path $restartSignal) {
        Write-Log "Restart signal detected, exiting gracefully..." -Level "INFO"
        Remove-Item $restartSignal -ErrorAction SilentlyContinue
        exit 0
    }

    Start-Sleep -Seconds $sleepSeconds
}
