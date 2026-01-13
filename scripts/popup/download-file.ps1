$url = "https://simple-sgt.fly.dev/matchi/courts/5/show-image"  # Replace this with your actual URL
$filePath = "C:\start\popup\dialog-image.jpg"

# Check if the file already exists and delete it if it does
if (Test-Path $filePath) {
    Remove-Item $filePath
}

# Try to download the file
try {
    Invoke-WebRequest -Uri $url -OutFile $filePath
}
catch {
    Write-Host "Failed to download the image: $_"
}