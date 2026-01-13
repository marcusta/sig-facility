# --- Configuration ---
# Load configuration from centralized config system
$scriptRoot = $PSScriptRoot
$repoRoot = Split-Path (Split-Path $scriptRoot -Parent) -Parent
. "$repoRoot\lib\Config.ps1"
$config = Get-SimGolfConfig

# Get paths from config (with fallback to defaults if not set)
$remote  = if ($config.courseSyncSource) { $config.courseSyncSource } else { "\\SIGBAY1\sig\gspro-prefetcher\sgt" }
$local   = if ($config.courseSyncDestination) { $config.courseSyncDestination } else { "C:\Courses" }
$staging = if ($config.courseSyncStagingPath) { $config.courseSyncStagingPath } else { "C:\course_staging" }

Write-Host "Bay: $($config._hostname) (Logical Bay $($config.logicalBay))" -ForegroundColor Cyan
Write-Host "Remote: $remote" -ForegroundColor Cyan
Write-Host "Local: $local" -ForegroundColor Cyan

$timer = [System.Diagnostics.Stopwatch]::StartNew()

# 1. Connection Check
Write-Host "Connecting to network share..." -ForegroundColor Cyan
if (!(Test-Path $remote)) {
    Write-Error "CRITICAL: Cannot reach $remote."
    exit
}

# 2. Preparation
if (Test-Path $staging) { Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $staging -Force | Out-Null

Write-Host "--- Phase 1: Analyzing Differences ---" -ForegroundColor Cyan

# 3. Cataloging Remote Files
$remoteFiles = Get-ChildItem -Path $remote -Recurse | Where-Object { !$_.PSIsContainer }
$filesToSync = New-Object System.Collections.Generic.List[PSObject]

foreach ($rFile in $remoteFiles) {
    $relative = $rFile.FullName.Replace($remote, "").TrimStart("\")
    $lFile = Join-Path $local $relative
    
    if (!(Test-Path $lFile) -or (Get-Item $lFile).LastWriteTime -lt $rFile.LastWriteTime -or (Get-Item $lFile).Length -ne $rFile.Length) {
        $filesToSync.Add($rFile)
    }
}

if ($filesToSync.Count -eq 0) {
    $timer.Stop()
    Write-Host "Everything is already in sync. (Time: $($timer.Elapsed.ToString('mm\:ss')))" -ForegroundColor Green
    exit
}

Write-Host "Detected $($filesToSync.Count) items to update." -ForegroundColor Yellow
Write-Host "`n--- Phase 2: Robust Staging & Move ---" -ForegroundColor Cyan

# 4. Processing Folders with Nested Progress
$folders = $filesToSync | Group-Object DirectoryName
$folderCount = 0

foreach ($folder in $folders) {
    $folderCount++
    $sourceDir = $folder.Name
    $relative = $sourceDir.Replace($remote, "").TrimStart("\")
    
    $currentStagingDir = Join-Path $staging $relative
    $currentLocalDir   = Join-Path $local $relative

    # Main Progress Bar (Folders)
    $folderPercent = ($folderCount / $folders.Count) * 100
    Write-Progress -Id 1 -Activity "Overall Sync Progress" -Status "Folder $folderCount of $($folders.Count): $relative" -PercentComplete $folderPercent

    if (!(Test-Path $currentStagingDir)) { New-Item -ItemType Directory -Path $currentStagingDir -Force | Out-Null }
    if (!(Test-Path $currentLocalDir)) { New-Item -ItemType Directory -Path $currentLocalDir -Force | Out-Null }

    # Robocopy into staging
    robocopy "$sourceDir" "$currentStagingDir" /XO /Z /LEV:1 /NJH /NJS /NDL /NFL /NC /NS /NP /R:3 /W:5 | Out-Null

    # Atomic Move with Sub-Progress
    $stagedFiles = Get-ChildItem -Path $currentStagingDir | Where-Object { !$_.PSIsContainer }
    $fileIndex = 0
    foreach ($file in $stagedFiles) {
        $fileIndex++
        $filePercent = ($fileIndex / $stagedFiles.Count) * 100
        
        # Sub-Progress Bar (Files within current folder)
        Write-Progress -Id 2 -ParentId 1 -Activity "Swapping Files" -Status "Moving: $($file.Name)" -PercentComplete $filePercent
        
        $destFile = Join-Path $currentLocalDir $file.Name
        Move-Item -Path $file.FullName -Destination $destFile -Force
    }
}

# Cleanup Progress Bars
Write-Progress -Id 2 -Activity "Swapping Files" -Completed
Write-Progress -Id 1 -Activity "Overall Sync Progress" -Completed

$timer.Stop()
if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
Write-Host "`n[Success] Sync finished safely in $($timer.Elapsed.ToString('mm\:ss'))." -ForegroundColor Green