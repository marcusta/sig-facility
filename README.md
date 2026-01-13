# SimGolf Facility Management System

Git-based deployment system for managing 8 unmanned sim golf hitting bays (BAY01-BAY08).

## Quick Start

- **New bay setup:** See [DEPLOYMENT.md](DEPLOYMENT.md) for complete installation guide
- **Script documentation:** See [scripts/README.md](scripts/README.md) for details on all scripts
- **Configuration:** Edit `config/shared.json` and `config/bays.json` for settings

## Architecture Overview

This system uses a two-layer architecture:

1. **Supervisor Script** (`C:\SimGolf\supervisor.ps1`) - Lives OUTSIDE the repo, never changes after install
   - Checks for updates every 30 minutes
   - Pulls latest changes from git
   - Restarts background processes when code changes

2. **Everything Else** (this repo at `C:\SimGolf\sig-facility\`)
   - All scripts, configs, and business logic
   - Update by pushing to git - all machines auto-update

## Directory Structure

```
sig-facility/
├── README.md              # This file
├── scripts/               # Your business logic scripts (add them here)
├── config/
│   ├── shared.json        # Settings for all bays
│   └── bays.json          # Per-bay overrides (keyed by hostname)
├── lib/
│   └── Config.ps1         # Helper to load merged config
├── install/
│   ├── install.ps1        # One-time setup script
│   └── supervisor.ps1     # Template for the supervisor (gets copied out)
└── .gitignore
```

## Machine Identity & Hardware Mapping

Each Windows machine has a hostname (like BAY01, BAY02, etc.), accessible via `$env:COMPUTERNAME`.

**Important**: Due to hardware moves, a computer's hostname might not match its physical bay location. For example, the computer named BAY03 might physically be in Bay 5. The `bays.json` config handles this:

- Keys in `bays.json` use the actual computer hostname
- Each bay config includes a `logicalBay` field to specify where it physically is
- Scripts use `$env:COMPUTERNAME` to load the right config

## Installation on a New Bay

1. **Prerequisites**:
   - Windows 11 machine with hostname set (e.g., BAY01, BAY02, etc.)
   - Git installed and in PATH
   - PowerShell execution policy allows scripts: `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`

2. **Run the installer**:
   ```powershell
   # Download install.ps1 from the repo (or copy via USB drive)
   # Then run:
   powershell -ExecutionPolicy Bypass -File .\install.ps1 -BayNumber 1
   ```

3. **What the installer does**:
   - Clones this repo to `C:\SimGolf\sig-facility\`
   - Copies `supervisor.ps1` to `C:\SimGolf\supervisor.ps1`
   - Creates scheduled task "SimGolf-Supervisor" that runs at login
   - Safe to run multiple times (idempotent)

4. **Verify**:
   - Restart the computer (or log out/in)
   - Check that `C:\SimGolf\supervisor.ps1` is running
   - Check logs at `C:\SimGolf\logs\` (if your background scripts create them)

## Configuration System

Configuration is merged from two sources:

1. **`config/shared.json`** - Settings that apply to all bays
2. **`config/bays.json`** - Bay-specific overrides keyed by hostname

The `lib/Config.ps1` module provides `Get-SimGolfConfig` which:
- Loads both files
- Merges them (bay-specific overrides shared)
- Returns the merged config object

Example usage in your scripts:
```powershell
. "$PSScriptRoot\..\lib\Config.ps1"
$config = Get-SimGolfConfig
Write-Host "Repo path: $($config.repoPath)"
Write-Host "Logical bay: $($config.logicalBay)"
```

## How Updates Work

1. **You push changes** to this git repo
2. **Every 30 minutes**, each bay's supervisor:
   - Runs `git pull --ff-only`
   - Checks if the commit hash changed
   - If changed, writes `C:\SimGolf\restart-requested` signal file
   - Background processes should watch for this file and exit gracefully
   - Supervisor then restarts the background processes

3. **Graceful restart pattern** (for your background scripts):
   ```powershell
   while ($true) {
       # Do work...

       # Check for restart signal
       if (Test-Path "C:\SimGolf\restart-requested") {
           Write-Host "Restart requested, exiting gracefully..."
           Remove-Item "C:\SimGolf\restart-requested" -ErrorAction SilentlyContinue
           exit 0
       }

       Start-Sleep -Seconds 10
   }
   ```

## Adding Your Scripts

1. Add your business logic scripts to `scripts/`
2. Update the supervisor to start your main script (edit `install/supervisor.ps1` and re-run install, or manually edit `C:\SimGolf\supervisor.ps1` on each bay)
3. Use the config system to load bay-specific settings
4. Implement the graceful restart pattern shown above

## Troubleshooting

- **Supervisor not running?** Check Task Scheduler for "SimGolf-Supervisor" task
- **Updates not pulling?** Check git status in `C:\SimGolf\sig-facility\` - may have local changes conflicting
- **Need to force update?** SSH/RDP to the bay, delete `C:\SimGolf\sig-facility\`, re-run installer
- **Wrong bay config loading?** Check `$env:COMPUTERNAME` matches a key in `config/bays.json`

## Development Workflow

1. Make changes on your dev machine
2. Test locally if possible
3. Commit and push to repo
4. Within 30 minutes, all bays will auto-update
5. Monitor the first bay that updates to ensure no issues
6. Rollback if needed: `git revert` and push

## Notes

- The supervisor itself is installed ONCE and rarely changes. If you need to update it, you must do so manually on each bay or re-run the installer.
- Use `shared.json` for settings that are the same across all bays
- Use `bays.json` for bay-specific differences (drive letters, hardware quirks, physical location, etc.)
- Computer hostnames are the source of truth for config loading, but use `logicalBay` field to track physical location
