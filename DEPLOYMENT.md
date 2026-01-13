# Deployment Guide

Complete guide for deploying the SimGolf facility management system to bay machines.

## Prerequisites

Before deploying to any bay, ensure the following software is installed:

### Required Software

1. **Windows 11** - All bay machines run Windows 11
2. **Git for Windows** - Download from https://git-scm.com/download/win
3. **PowerShell 5.1+** - Included with Windows 11
4. **AutoHotkey v1** - Download from https://www.autohotkey.com/
5. **GSPro** - Golf simulator software (installed at `C:\GSProV1\`)
6. **OnTopReplica** - Window overlay tool (install to `C:\Program Files (x86)\OnTopReplica\`)

### Network Requirements

- Network share accessible at: `\\SIGBAY1\sig\gspro-prefetcher\sgt`
- Internet access for:
  - Git repository: https://github.com/marcusta/sig-facility.git
  - Status API: https://app.swedenindoorgolf.se/sig-status/status
  - Booking API: https://simple-sgt.fly.dev/matchi/courts/

### PowerShell Execution Policy

Run this command in PowerShell as Administrator:
```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## Initial Bay Setup

### Step 1: Set Computer Name

Ensure the computer has the correct hostname (e.g., BAY01, BAY02, etc.):

```powershell
# Check current name
$env:COMPUTERNAME

# To rename (requires admin and restart):
Rename-Computer -NewName "BAY01" -Restart
```

### Step 2: Update Bay Configuration

Before deploying, update `config/bays.json` with the bay's configuration:

```json
{
  "BAY01": {
    "logicalBay": 1,
    "description": "Left corner bay - standard setup",
    "networkDrive": "Z:",
    "hasHighSpeedCamera": true,
    "displayResolution": "3840x2160",
    "popupImageUrl": "https://simple-sgt.fly.dev/matchi/courts/1/show-image"
  }
}
```

Commit and push changes to the repository before installing.

### Step 3: Run Installer

1. **Download install.ps1** to the bay machine (via USB drive or download from GitHub)

2. **Run the installer:**
   ```powershell
   # Navigate to the directory containing install.ps1
   cd C:\path\to\installer

   # Run installation (replace 1 with actual bay number)
   powershell -ExecutionPolicy Bypass -File .\install.ps1 -BayNumber 1
   ```

3. **What the installer does:**
   - Creates `C:\SimGolf\` directory structure
   - Clones repository to `C:\SimGolf\sig-facility\`
   - Copies supervisor to `C:\SimGolf\supervisor.ps1`
   - Creates scheduled task "SimGolf-Supervisor" (runs at login)
   - Validates installation

4. **Verify installation:**
   - Check `C:\SimGolf\sig-facility\` exists and has the latest code
   - Check `C:\SimGolf\supervisor.ps1` exists
   - Open Task Scheduler and verify "SimGolf-Supervisor" task exists

### Step 4: Deploy License Files

GSPro license files are NOT in the repository. Deploy manually:

```powershell
# Copy gsp.lic to the appropriate location
# (Check GSPro documentation for exact path)
Copy-Item "\\NetworkShare\licenses\gsp.lic" "C:\GSProV1\gsp.lic"
```

### Step 5: Install .NET Runtime and Deploy Executables

**A. Install .NET Runtime**

gs-checker.exe requires .NET runtime (no longer self-contained to reduce size):

```powershell
# Install .NET runtime (adjust version if needed)
C:\SimGolf\sig-facility\install\install-dotnet-runtime.ps1 -RuntimeVersion "8.0"
```

**B. Deploy gs-checker.exe**

The executable is NOT in git (too large). Deploy from an existing bay:

**Option 1: Copy from another bay**
```powershell
# From your dev machine or a working bay, copy to new bay
# Ensure C:\start exists
New-Item -ItemType Directory -Path C:\start -Force

# Copy from another bay (via network share or remote session)
Copy-Item "\\SIGBAY1\start\gs-checker.exe" "C:\start\gs-checker.exe"
Copy-Item "\\SIGBAY1\start\sgt.exe" "C:\start\sgt.exe" -ErrorAction SilentlyContinue
```

**Option 2: Rebuild from source**
If you have the C# source code and want to rebuild:
```powershell
# Build as framework-dependent (smaller) instead of self-contained
dotnet publish -c Release -r win-x64 --no-self-contained
# Then copy the output to C:\start\
```

### Step 6: Configure GSPro Settings

1. **Create initial settings backup:**
   ```powershell
   C:\SimGolf\sig-facility\scripts\gspro-settings\preserve-settings.bat
   ```

2. **Verify backup files exist:**
   - `%USERPROFILE%\AppData\LocalLow\GSPro\GSPro\dpsV2x3.gss.orig`
   - `%USERPROFILE%\AppData\LocalLow\GSPro\GSPro\Settings.vgs.orig`

### Step 7: Configure AutoHotkey Startup

Set GSPro to auto-start at Windows login:

**Option A: Create Startup Shortcut**
```powershell
$ahkScript = "C:\SimGolf\sig-facility\scripts\gspro-automation\GS Pro startup-gamechanger_lampor.ahk"
$startupFolder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut("$startupFolder\GSPro-Startup.lnk")
$shortcut.TargetPath = "C:\Program Files\AutoHotkey\AutoHotkey.exe"
$shortcut.Arguments = "`"$ahkScript`""
$shortcut.WorkingDirectory = "C:\SimGolf\sig-facility\scripts\gspro-automation"
$shortcut.Save()
```

**Option B: Manual Setup**
1. Right-click on `GS Pro startup-gamechanger_lampor.ahk`
2. Create shortcut
3. Move shortcut to: `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup`

### Step 8: Start the Supervisor

**Option A: Start Now**
```powershell
Start-ScheduledTask -TaskName "SimGolf-Supervisor"
```

**Option B: Restart Computer**
The supervisor will start automatically at next login.

### Step 9: Verify Everything Works

1. **Check supervisor is running:**
   ```powershell
   Get-Process -Name powershell | Where-Object { $_.CommandLine -like "*supervisor.ps1*" }
   ```

2. **Check monitoring script is running:**
   ```powershell
   Get-Process -Name powershell | Where-Object { $_.CommandLine -like "*check-status.ps1*" }
   ```

3. **Check logs:**
   ```powershell
   Get-Content C:\SimGolf\logs\supervisor-*.log -Tail 20
   Get-Content C:\SimGolf\logs\monitor_error.log -Tail 20 -ErrorAction SilentlyContinue
   ```

4. **Test course sync:**
   ```powershell
   C:\SimGolf\sig-facility\scripts\course-sync\sync-courses2.ps1
   ```

5. **Restart computer and verify GSPro auto-starts**

## Updating an Existing Bay

The beauty of this system is that updates are automatic!

### Automatic Updates

1. **Push changes** to the git repository
2. **Within 30 minutes**, the supervisor on each bay will:
   - Pull the latest changes
   - Restart the monitoring script if code changed
   - Log all activities

### Manual Update (if needed)

If you need to force an update immediately:

```powershell
# SSH or RDP to the bay
cd C:\SimGolf\sig-facility
git pull --ff-only origin main

# Restart supervisor
Stop-ScheduledTask -TaskName "SimGolf-Supervisor"
Start-ScheduledTask -TaskName "SimGolf-Supervisor"
```

### Updating the Supervisor Itself

The supervisor script lives OUTSIDE the repository and doesn't auto-update:

```powershell
# Option 1: Re-run installer (safe, idempotent)
C:\path\to\install.ps1

# Option 2: Manual copy
Copy-Item "C:\SimGolf\sig-facility\install\supervisor.ps1" "C:\SimGolf\supervisor.ps1" -Force

# Restart the supervisor
Stop-ScheduledTask -TaskName "SimGolf-Supervisor"
Start-ScheduledTask -TaskName "SimGolf-Supervisor"
```

## Directory Structure on Bay Machines

After installation, each bay will have:

```
C:\SimGolf\
├── supervisor.ps1           # Auto-update supervisor (OUTSIDE repo)
├── restart-requested        # Signal file for graceful restarts
├── logs\                    # Log files
│   ├── supervisor-*.log
│   └── monitor_error.log
├── data\                    # Local data (if used)
└── sig-facility\            # Git repository (auto-updated)
    ├── README.md
    ├── config\
    ├── install\
    ├── lib\
    └── scripts\

C:\start\                     # Legacy location for some scripts
├── application_log.txt      # gs-checker logs
├── error_log.txt
└── popup\
    └── dialog-image.jpg     # Downloaded booking image

C:\Courses\                   # Synced golf courses
C:\course_staging\            # Temporary sync staging area
```

## Troubleshooting

### Supervisor Not Running

1. Check Task Scheduler: "SimGolf-Supervisor" task exists and is enabled
2. Check task history for errors
3. Try running manually:
   ```powershell
   C:\SimGolf\supervisor.ps1
   ```

### Git Conflicts Preventing Updates

If local changes conflict with remote:

```powershell
cd C:\SimGolf\sig-facility

# Check status
git status

# Option 1: Discard local changes
git reset --hard origin/main

# Option 2: Delete and re-clone
cd C:\SimGolf
Remove-Item sig-facility -Recurse -Force
git clone https://github.com/marcusta/sig-facility.git
```

### Monitoring Script Not Reporting

1. Check if script is running:
   ```powershell
   Get-Process -Name powershell | Where-Object { $_.CommandLine -like "*check-status.ps1*" }
   ```

2. Check error log:
   ```powershell
   Get-Content C:\SimGolf\logs\monitor_error.log -Tail 50
   ```

3. Test API connectivity:
   ```powershell
   Invoke-RestMethod -Uri "https://app.swedenindoorgolf.se/sig-status/status" -Method Get
   ```

### Course Sync Fails

1. Test network share access:
   ```powershell
   Test-Path "\\SIGBAY1\sig\gspro-prefetcher\sgt"
   ls "\\SIGBAY1\sig\gspro-prefetcher\sgt"
   ```

2. Check permissions on local directories:
   ```powershell
   Test-Path "C:\Courses"
   Test-Path "C:\course_staging"
   ```

3. Run sync manually to see errors:
   ```powershell
   C:\SimGolf\sig-facility\scripts\course-sync\sync-courses2.ps1
   ```

### GSPro Doesn't Auto-Start

1. Check startup shortcut exists:
   ```powershell
   ls "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
   ```

2. Check AutoHotkey is installed:
   ```powershell
   Get-Command autohotkey -ErrorAction SilentlyContinue
   ```

3. Test the AHK script manually:
   ```powershell
   C:\SimGolf\sig-facility\scripts\gspro-automation\GS Pro startup-gamechanger_lampor.ahk
   ```

## Maintenance Tasks

### Weekly

- Review supervisor logs for errors
- Check disk space on all bays
- Verify all bays are reporting to status API

### Monthly

- Update bay configuration as hardware changes
- Review and rotate log files if needed
- Test course sync on all bays

### As Needed

- Update GSPro when new versions are released
- Update OnTopReplica if needed
- Adjust sync intervals in config based on usage patterns
- Add new bays to `config/bays.json` as facility expands

## Configuration Reference

### Shared Configuration (`config/shared.json`)

Settings that apply to all bays:

- `gsproPath`, `gsproLauncherPath`, etc. - GSPro paths
- `courseSyncSource` - Network share path for courses
- `statusMonitorUrl` - API endpoint for status updates
- `syncIntervalSeconds` - How often to check for changes
- Network drives, log settings, etc.

### Bay-Specific Configuration (`config/bays.json`)

Override shared settings per bay:

- `logicalBay` - Physical bay number (for hardware moves)
- `description` - Human-readable description
- `networkDrive` - Different drive letter if needed
- `popupImageUrl` - Bay-specific booking API URL
- `displayResolution`, `hasHighSpeedCamera`, etc. - Hardware specs
- Any shared setting can be overridden

### Example Bay Config

```json
{
  "BAY03-OLD": {
    "_comment": "This computer moved from Bay 3 to Bay 5 due to hardware failure",
    "logicalBay": 5,
    "description": "Bay 5 - older hardware (originally BAY03)",
    "networkDrive": "Z:",
    "hasHighSpeedCamera": false,
    "displayResolution": "1920x1080",
    "syncIntervalSeconds": 120,
    "enableDebugLogging": true,
    "notes": "Older machine, runs slower. Increased sync interval."
  }
}
```

## Security Notes

- **Never commit license files** to the repository
- **Never commit API keys or passwords** in config files
- Use `.gitignore` to exclude sensitive files
- Network share should have read-only access for bay machines
- Status API should use authentication (implement if not already done)

## Support

For issues or questions:
- Check logs in `C:\SimGolf\logs\`
- Review scripts in `scripts/README.md`
- Check GitHub repository issues
- Contact facility administrator
