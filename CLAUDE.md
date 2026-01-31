# CLAUDE.md

## Project Overview

SimGolf Facility Management System for **Sweden Indoor Golf** — manages 8 unmanned sim golf hitting bays (BAY01–BAY08). Automates GSPro golf simulator startup, monitoring, window management, course synchronization, and self-updating deployment across distributed Windows 11 machines.

## Architecture

**Two-layer deployment:**
1. **Supervisor** (`C:\SimGolf\supervisor.ps1`) — lives outside the repo, auto-pulls every 30 min, restarts processes on changes
2. **Repository** (`C:\SimGolf\sig-facility\`) — all scripts, configs, business logic; auto-updated via git

**Configuration** merges `config/shared.json` (base) with `config/bays.json` (per-hostname overrides) via `lib/Config.ps1`. Bay identity is resolved from `$env:COMPUTERNAME`.

## Key Technologies

- **PowerShell** — installation, supervisor, monitoring, course sync
- **AutoHotkey v2** — GSPro window automation, state machine, USB relay control
- **Batch scripts** — legacy launchers
- **JSON** — configuration
- **Git** — deployment mechanism

## Directory Structure

```
config/          JSON configuration (shared.json, bays.json)
lib/             PowerShell modules (Config.ps1)
install/         One-time installer, supervisor template, .NET runtime installer
scripts/
  monitoring/    Disk space reporting to API
  course-sync/   Network share sync with staging
  gspro-automation/  GSPro control scripts (AHK v1 & v2)
  gspro-settings/    Settings backup/restore
  popup/             Booking info display
  assets/            Icons and external binaries (not in repo)
```

## Critical File

**`scripts/gspro-automation/gspro-start-v2.ahk`** — the primary GSPro automation script (AHK v2.0). Features:
- Timer-based state machine with debounced signal sampling
- Pixel color detection for connection/link/ball status (BGR format, via PrintWindow)
- Automatic recovery: reconnects lost LM connections, restarts crashed connector
- Addon & overlay window repair: detects missing "Advanced Connect Add On" and OnTopReplica windows
- USB relay control (CP210x) for physical indicator lamp with blink patterns
- Debug overlay GUI (auto-collapse when stable)
- Window hierarchy management (game fullscreen, overlay always-on-top, connector behind)

### Key windows monitored:
- `ahk_exe GSPro.exe` — the game
- `ahk_exe GSPconnect.exe` — the connector
- `Advanced Connect Add On` — visual data addon (opened via "Open Visual Data" button)
- `OnTopReplica` — overlay replicating the addon window

### State flags: `SystemState.isRecovering`, `isRestarting`, `isRepairingAddon`

## External Dependencies

- GSPro golf simulator (`C:\GSProV1\`)
- OnTopReplica (window overlay)
- .NET 8 Runtime (for gs-checker.exe)
- Network share `\\SIGBAY1\sig\gspro-prefetcher\sgt` (course files)
- API: `https://app.swedenindoorgolf.se/sig-status/status`

## Development Notes

- Main branch is `main` — all bays pull from it
- Never commit: license files, credentials, executables, `.orig` settings backups
- AHK v2 scripts use `#Requires AutoHotkey v2.0`
- The older `gspro-start.ahk` is AHK v1; `gspro-start-v2.ahk` is the active version
- Do NOT add `Co-Authored-By` lines to commit messages
