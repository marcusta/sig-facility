$procs = Get-CimInstance Win32_Process -Filter "CommandLine LIKE '%supervisor.ps1%'"
if ($procs) {
    $procs | ForEach-Object {
        Write-Host "Killing PID $($_.ProcessId): $($_.CommandLine)"
        Stop-Process -Id $_.ProcessId -Force
    }
    Write-Host "Done." -ForegroundColor Green
} else {
    Write-Host "No supervisor processes found." -ForegroundColor DarkGray
}
