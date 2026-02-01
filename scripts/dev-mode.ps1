param(
    [string]$Branch = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $repoRoot
try {
    # Check for uncommitted changes
    $status = git status --porcelain
    if ($status) {
        Write-Host "ERROR: Uncommitted local changes detected. Commit or stash them first." -ForegroundColor Red
        git status --short
        exit 1
    }

    # Determine branch
    if (-not $Branch) {
        $Branch = git rev-parse --abbrev-ref HEAD
        if ($Branch -eq "main") {
            Write-Host "ERROR: Specify a dev branch with -Branch. Don't use main." -ForegroundColor Red
            exit 1
        }
        Write-Host "Using current branch: $Branch"
    }

    if ($Branch -eq "main") {
        Write-Host "ERROR: Don't use main as your dev branch." -ForegroundColor Red
        exit 1
    }

    # Stop the supervisor so it doesn't interfere
    $supervisorProcess = Get-Process -Name pwsh, powershell -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -like "*supervisor.ps1*"
    }
    if ($supervisorProcess) {
        Write-Host "Stopping supervisor..." -ForegroundColor Yellow
        $supervisorProcess | Stop-Process -Force
        Start-Sleep -Seconds 2
        Write-Host "Supervisor stopped." -ForegroundColor Green
    } else {
        Write-Host "No supervisor process found (OK)." -ForegroundColor DarkGray
    }

    # Switch to the dev branch
    $localExists = git branch --list $Branch
    if ($localExists) {
        git checkout $Branch
    } else {
        # Try to track from origin
        git fetch origin
        $remoteExists = git branch -r --list "origin/$Branch"
        if ($remoteExists) {
            git checkout -b $Branch "origin/$Branch"
        } else {
            Write-Host "ERROR: Branch 'origin/$Branch' not found. Push it from your dev machine first." -ForegroundColor Red
            exit 1
        }
    }

    git fetch origin 2>&1 | Out-Null
    git reset --hard "origin/$Branch" 2>&1 | Out-Null

    Write-Host ""
    Write-Host "=== DEV MODE ACTIVE ===" -ForegroundColor Green
    Write-Host "Branch: $Branch"
    Write-Host "Polling every 5 seconds. Press Ctrl+C to exit."
    Write-Host ""

    $lastCommit = git rev-parse HEAD

    try {
        while ($true) {
            Start-Sleep -Seconds 5
            git fetch origin 2>&1 | Out-Null
            $remoteCommit = git rev-parse "origin/$Branch" 2>&1 | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }
            if ($remoteCommit -and $remoteCommit -ne $lastCommit) {
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] New commits detected, pulling..." -ForegroundColor Yellow
                git reset --hard "origin/$Branch" 2>&1 | Out-Null
                $lastCommit = git rev-parse HEAD
                $msg = git log -1 --pretty=format:"%s"
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Updated to: $lastCommit ($msg)" -ForegroundColor Green
            } else {
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] No changes" -ForegroundColor DarkGray
            }
        }
    } finally {
        Write-Host ""
        Write-Host "=== EXITING DEV MODE ===" -ForegroundColor Yellow
        Write-Host "Switching back to main..."
        git checkout main
        git pull --ff-only
        Write-Host "Restored to main branch." -ForegroundColor Green

        # Restart the supervisor
        $supervisorPath = "C:\SimGolf\supervisor.ps1"
        if (Test-Path $supervisorPath) {
            Write-Host "Restarting supervisor..."
            Start-Process -FilePath "powershell.exe" `
                -ArgumentList "-ExecutionPolicy", "Bypass", "-File", $supervisorPath `
                -WindowStyle Hidden
            Write-Host "Supervisor restarted." -ForegroundColor Green
        } else {
            Write-Host "Supervisor not found at $supervisorPath -skipping restart." -ForegroundColor Yellow
        }
    }
} finally {
    Pop-Location
}
