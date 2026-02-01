# Booking Dialog Image Downloader
#
# Lifecycle (runs every 60s via download-show-dialog.ahk):
#   1. Delete any existing dialog-image.jpg (prevents stale images from prior cycles)
#   2. Download from booking service to a temp file
#   3. If download succeeded and file is non-empty, swap temp -> dialog-image.jpg
#   4. AHK caller checks if dialog-image.jpg exists; if yes, shows dialog; if no, does nothing
#
# Server responses:
#   200 with image  — new booking to display. File is written, dialog shown.
#   404             — no active booking / already shown. No file on disk, no dialog.
#   4xx/5xx/3xx     — error or redirect failure. Treated same as 404 (silent, retry next cycle).
#   Network failure — same as above. Caught by try/catch, no file left behind.
#
# Key invariant: dialog-image.jpg must ONLY exist after a successful 200 with valid content.
# The old file is always deleted before attempting a new download so that a failed attempt
# (for any reason) results in no file and therefore no dialog.

# Load configuration
$scriptRoot = $PSScriptRoot
$repoRoot = Split-Path (Split-Path $scriptRoot -Parent) -Parent
. "$repoRoot\lib\Config.ps1"
$config = Get-SimGolfConfig

$matchiCourtId = $config.matchiCourtId
if (-not $matchiCourtId) {
    Write-Host "ERROR: matchiCourtId not set in config"
    exit 1
}

$url = "https://app.swedenindoorgolf.se/bookings/matchi-courts/$matchiCourtId/show-image"
$filePath = "$repoRoot\scripts\popup\dialog-image.jpg"

if (Test-Path $filePath) { Remove-Item $filePath }

$tempPath = "$filePath.tmp"

try {
    Invoke-WebRequest -Uri $url -OutFile $tempPath -ErrorAction Stop
    if ((Test-Path $tempPath) -and (Get-Item $tempPath).Length -gt 0) {
        if (Test-Path $filePath) { Remove-Item $filePath }
        Move-Item $tempPath $filePath -Force
    } else {
        if (Test-Path $tempPath) { Remove-Item $tempPath }
    }
} catch {
    Write-Host "Failed to download the image: $_"
    if (Test-Path $tempPath) { Remove-Item $tempPath }
}
