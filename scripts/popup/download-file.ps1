# Load configuration
$scriptRoot = $PSScriptRoot
$repoRoot = Split-Path (Split-Path $scriptRoot -Parent) -Parent
. "$repoRoot\lib\Config.ps1"
$config = Get-SimGolfConfig

$logicalBay = $config.logicalBay
if (-not $logicalBay) {
    Write-Host "ERROR: logicalBay not set in config"
    exit 1
}

$url = "https://app.swedenindoorgolf.se/bookings/courts/$logicalBay/show-image"
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
