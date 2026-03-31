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

# --- Load course allow/exclude lists ---
$excludedFile = Join-Path $repoRoot "config\excluded-courses.json"
$extrasFile   = Join-Path $repoRoot "config\extra-courses.json"

$excludedFolders = @()
if (Test-Path $excludedFile) {
    $excludedFolders = Get-Content $excludedFile -Raw | ConvertFrom-Json
}
$extraFolders = @()
if (Test-Path $extrasFile) {
    $extraFolders = Get-Content $extrasFile -Raw | ConvertFrom-Json
}

# Build lookup sets for fast membership testing
$excludedSet = @{}
foreach ($f in $excludedFolders) { $excludedSet[$f] = $true }
$extraSet = @{}
foreach ($f in $extraFolders) { $extraSet[$f] = $true }

Write-Host "Excluded courses: $($excludedSet.Count), Extra (protected): $($extraSet.Count)" -ForegroundColor Cyan

$timer = [System.Diagnostics.Stopwatch]::StartNew()

# 1. Connection Check
Write-Host "Connecting to network share..." -ForegroundColor Cyan
if (!(Test-Path $remote)) {
    Write-Error "CRITICAL: Cannot reach $remote."
    exit
}

# --- Fetch course manifest (source of truth for valid courses) ---
$manifestUrl = "https://simulatorgolftour.com/course_manifest.json"
Write-Host "Fetching course manifest..." -ForegroundColor Cyan
try {
    $manifestJson = (New-Object System.Net.WebClient).DownloadString($manifestUrl)
    $manifest = $manifestJson | ConvertFrom-Json
    $manifestFolders = @{}
    foreach ($course in $manifest) {
        if ($course.CourseFolder) {
            $manifestFolders[$course.CourseFolder] = $true
        }
    }
    Write-Host "Manifest: $($manifestFolders.Count) courses" -ForegroundColor Cyan
} catch {
    Write-Warning "Could not fetch manifest: $_"
    Write-Warning "Skipping cleanup phase - will only sync from remote share."
    $manifestFolders = $null
}

# --- Build allowed folder set from manifest ---
# Allowed = (manifest CourseFolder values NOT in excluded) + extras
$allowedSet = @{}
if ($manifestFolders) {
    foreach ($f in $manifestFolders.Keys) {
        if (-not $excludedSet.ContainsKey($f)) {
            $allowedSet[$f] = $true
        }
    }
}
foreach ($f in $extraFolders) {
    $allowedSet[$f] = $true
}

Write-Host "Allowed after exclusions: $($allowedSet.Count)" -ForegroundColor Cyan

# --- Cleanup: remove local folders not in allowed set ---
# Only run cleanup when manifest was fetched successfully (otherwise we don't know what's valid)
if ($manifestFolders -and (Test-Path $local)) {
    $localFolders = Get-ChildItem -Path $local -Directory | Select-Object -ExpandProperty Name
    $removedCount = 0
    foreach ($lf in $localFolders) {
        if (-not $allowedSet.ContainsKey($lf)) {
            $lfPath = Join-Path $local $lf
            Write-Host "  Removing excluded/unknown course: $lf" -ForegroundColor Red
            Remove-Item $lfPath -Recurse -Force -ErrorAction SilentlyContinue
            $removedCount++
        }
    }
    if ($removedCount -gt 0) {
        Write-Host "Removed $removedCount course folder(s)." -ForegroundColor Yellow
    } else {
        Write-Host "No course folders to remove." -ForegroundColor Green
    }
}

# 2. Preparation
if (Test-Path $staging) { Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $staging -Force | Out-Null

Write-Host "--- Phase 1: Analyzing Differences ---" -ForegroundColor Cyan

# 3. Cataloging Remote Files (only allowed folders when manifest is available)
$remoteFiles = Get-ChildItem -Path $remote -Recurse | Where-Object {
    if ($_.PSIsContainer) { return $false }
    if (-not $manifestFolders) { return $true }
    # Get the top-level folder name from the relative path
    $rel = $_.FullName.Replace($remote, "").TrimStart("\")
    $topFolder = $rel.Split("\")[0]
    return $allowedSet.ContainsKey($topFolder)
}
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

    # Remove staging folder for this course immediately after move
    Remove-Item $currentStagingDir -Recurse -Force -ErrorAction SilentlyContinue
}

# Cleanup Progress Bars
Write-Progress -Id 2 -Activity "Swapping Files" -Completed
Write-Progress -Id 1 -Activity "Overall Sync Progress" -Completed

$timer.Stop()
if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
Write-Host "`n[Success] Sync finished safely in $($timer.Elapsed.ToString('mm\:ss'))." -ForegroundColor Green