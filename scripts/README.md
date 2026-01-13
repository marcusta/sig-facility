# Scripts Directory

All business logic scripts for the SimGolf facility management system.

## Directory Structure

```
scripts/
├── monitoring/          # System status and health monitoring
├── course-sync/         # Golf course synchronization from network share
├── gspro-settings/      # GSPro configuration backup/restore
├── gspro-automation/    # AutoHotkey automation for GSPro startup and management
├── popup/               # Booking information popup dialogs
└── assets/              # Executables and binary assets
```

## Script Categories

### Monitoring (`monitoring/`)

**check-status.ps1**
- Monitors disk space on C: and D: drives
- Sends status updates to central API endpoint
- Runs continuously (60-second intervals)
- Configuration: `statusMonitorUrl`, `statusMonitorIntervalSeconds` in config
- Should be started by the supervisor as a background process

### Course Synchronization (`course-sync/`)

**sync-courses2.ps1**
- PowerShell-based sync with staging directory approach
- Compares remote vs local files (by timestamp and size) before copying
- Uses atomic move operations to prevent corruption during active use
- Syncs from network share to local courses directory
- Shows nested progress bars (folder-level and file-level)
- Safe to run while GSPro is accessing course files
- Hardcoded configuration at top of file:
  - `$remote`: Network source (default: `\\SIGBAY1\sig\gspro-prefetcher\sgt`)
  - `$local`: Local destination (default: `C:\Courses`)
  - `$staging`: Temporary staging directory (default: `C:\course_staging`)
- Configuration from `config/shared.json`:
  - `courseSyncSource`, `courseSyncDestination`, `courseSyncStagingPath`

### GSPro Settings Management (`gspro-settings/`)

**preserve-settings.bat**
- Backs up GSPro configuration files before they get overwritten
- Creates .orig copies of:
  - `dpsV2x3.gss` (display settings)
  - `Settings.vgs` (game settings)
- Run this manually before making risky changes

**copy_gspro_settings.bat**
- Restores GSPro settings from backed-up .orig files
- Called automatically during GSPro startup (see automation scripts)
- Ensures consistent settings across restarts
- Location: `%USERPROFILE%\AppData\LocalLow\GSPro\GSPro`

### GSPro Automation (`gspro-automation/`)

AutoHotkey scripts for automated GSPro startup and window management:

**GS Pro startup-gamechanger_lampor.ahk** (Primary startup script)
- Main startup sequence for GSPro
- Dependencies:
  - `copy_gspro_settings.bat` (from gspro-settings/)
  - `gs-checker.exe` (from assets/)
  - `start-overlay.bat` (same directory)
- Startup sequence:
  1. Restore GSPro settings (calls `C:\start\copy_gspro_settings.bat`)
  2. Launch GSPro via `C:\GSProV1\GSPLauncher.exe`
  3. Wait for GSPro windows to appear
  4. Click "Open Visual Data" in Foresight window (x1080, y190)
  5. Delete old log files (`application_log.txt`, `error_log.txt`)
  6. Start `gs-checker.exe --mode Prod` (bay status checker)
  7. Start overlay via `start-overlay.bat`
  8. Manage window z-order (GSPro on top, Foresight behind)
  9. Monitor for GSPro closure, then clean up overlays and kill gs-checker
- Note: `repair-connector.ahk` is commented out but available if needed

**start-overlay.bat**
- Launches two OnTopReplica windows for displaying game info
- Window 1: Advanced stats (430x? at position 1500,850)
- Window 2: Foresight data region (255x60 cropped to 150x? at position 483,0)
- Required by: lampor startup script, repair-connector
- Dependency: OnTopReplica must be installed at `C:\Program Files (x86)\OnTopReplica\OnTopReplica`

**start-overlay.ahk**
- Closes any existing OnTopReplica windows (cleanup)
- Then calls `start-overlay.bat`
- Used for restarting overlays if they get messed up

**repair-connector.ahk** (Auto-restart connector - currently not used)
- Monitors GSPro connector window continuously
- If "GSPro x Foresight" window disappears (connection lost):
  - Wait to confirm it's really gone
  - Restart `C:\GSProV1\Core\GSPC\GSPconnect.exe`
  - Wait for reconnection
  - Click "Open Visual Data" (x1059, y182)
  - Restart overlay via `start-overlay.bat`
- Continues monitoring until GSPro closes
- Currently commented out in lampor script but available for unattended operation
- Essential if you have connection stability issues

**gspro-user.ahk**
- In-game user interface automation
- Used during gameplay for various user interactions
- Details: TBD (document specific functionality)

**open-data.ahk**
- Opens data folder for quick access/debugging
- Utility script for future robustness work
- Details: TBD

### Popup System (`popup/`)

Booking information display system:

**download-file.ps1**
- Downloads current booking image from API
- URL: `popupImageUrl` from config (per-bay)
- Saves to: `C:\start\popup\dialog-image.jpg`
- Deletes old image first to ensure fresh download
- Should run before showing popup

**download-show-dialog.ahk**
- Combined script: downloads image and displays dialog
- Calls download-file.ps1 then shows the image

**show-popup-alt.ahk**
- Alternative popup display method

**popup.png, sim-golf2-popup.png**
- Default placeholder images if download fails

### Assets (`assets/`)

Binary executables and resources - icons and other small assets only.

**sgt.ico**
- Icon for SGT application

### Executables (NOT in Repository)

The following executables are deployed separately (too large for GitHub):

**gs-checker.exe** (C# application)
- **Location:** `C:\start\gs-checker.exe` on each bay
- **Purpose:** Bay status checker application written in C#
- **Usage:** Started by lampor startup script with `--mode Prod` flag
- **Logs:** `C:\start\application_log.txt` and `error_log.txt`
- **Lifecycle:** Runs in background, killed automatically when GSPro closes
- **Deployment:**
  - Copy from existing bay or rebuild from source
  - Requires .NET runtime (use `install/install-dotnet-runtime.ps1`)
  - NOT in git (too large when self-contained)

**sgt.exe** (AutoHotkey application)
- **Location:** `C:\start\sgt.exe` on each bay
- **Purpose:** TBD (SimGolf Tool?)
- **Note:** Compiled AHK .exe files are portable across Windows machines

## Configuration Usage

All scripts should use the centralized config system:

```powershell
# In your PowerShell scripts:
. "$PSScriptRoot\..\lib\Config.ps1"
$config = Get-SimGolfConfig

# Access settings:
$gsproPath = $config.gsproLauncherPath
$courseSyncSource = $config.courseSyncSource
$statusUrl = $config.statusMonitorUrl
$logicalBay = $config.logicalBay
```

For batch files and AutoHotkey scripts:
- Currently use hardcoded paths like `C:\GSProV1\`, `C:\start\`
- Future enhancement: Add PowerShell wrapper to read JSON config and pass to scripts
- Or generate bay-specific scripts from templates during deployment

## Deployment Notes

### License Files
GSPro license file (`gsp.lic`) should be deployed separately:
- Not in version control (excluded in .gitignore)
- Deploy manually to each bay
- Location: TBD (check GSPro documentation)

### Per-Bay Customization
Scripts can be customized per-bay using `config/bays.json`:
- Different popup URLs (booking images)
- Different network drive letters
- Different sync intervals
- Bay-specific settings and hardware flags

### Startup Integration
The supervisor (`install/supervisor.ps1`) should start background processes:
- **monitoring/check-status.ps1** - Continuous disk space monitoring
- **Course sync** - Run on-demand or scheduled (not continuous)
- **GSPro automation** - Started manually or via Windows startup (AutoHotkey)
  - Set `GS Pro startup-gamechanger_lampor.ahk` to run at Windows login
  - Or create shortcut in Startup folder

### Required Manual Setup
These items must be deployed/configured manually on each bay:

1. **GSPro License** (`gsp.lic`) - Not in version control
2. **OnTopReplica** - Install to `C:\Program Files (x86)\OnTopReplica\`
3. **AutoHotkey** - Required to run .ahk scripts (or compile to .exe)
4. **Network Share Access** - Ensure bay can reach `\\SIGBAY1\sig\gspro-prefetcher\sgt`
5. **Windows Startup** - Configure lampor script to run at login

## Script Dependencies Summary

**lampor startup script depends on:**
- `copy_gspro_settings.bat` → needs `.orig` backup files
- `gs-checker.exe` → standalone executable
- `start-overlay.bat` → needs OnTopReplica installed
- GSPro installed at `C:\GSProV1\`

**Course sync depends on:**
- Network share accessible at `\\SIGBAY1\sig\gspro-prefetcher\sgt`
- Local directories: `C:\Courses`, `C:\course_staging`

**Status monitoring depends on:**
- API endpoint: `https://app.swedenindoorgolf.se/sig-status/status`
- Writable log directory: `C:\start\logs\`

## TODO

- [ ] Document exact purpose of sgt.exe
- [ ] Document gspro-user.ahk functionality in detail
- [ ] Document open-data.ahk functionality when implemented
- [ ] Test course sync with new config system (refactor hardcoded paths)
- [ ] Create PowerShell wrapper to bridge AHK with JSON config (optional)
- [ ] Document GSPro license file deployment location and process
- [ ] Consider uncommenting repair-connector.ahk if connection stability is an issue
