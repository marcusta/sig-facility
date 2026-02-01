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

if (Test-Path $filePath) {
    Remove-Item $filePath
}

try {
    Invoke-WebRequest -Uri $url -OutFile $filePath
} catch {
    Write-Host "Failed to download the image: $_"
}
