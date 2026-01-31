# Bay Installation Guide

Steps to set up a new SimGolf bay machine from scratch.

## Prerequisites

- Windows 11
- GSPro installed at `C:\GSProV1\`
- AutoHotkey v2 installed
- OnTopReplica installed
- Git installed and available on PATH
- `C:\start\copy_gspro_settings.bat` and `C:\start\start-overlay.bat` in place

## Before installing

Ensure the bay has an entry in `config/bays.json`. The key is the bay ID you'll use during installation (e.g. `BAY01`).

Add an entry like:

```json
"BAY09": {
  "logicalBay": 9,
  "description": "Bay 9 - description",
  "networkDrive": "Z:",
  "hasHighSpeedCamera": true,
  "displayResolution": "3840x2160"
}
```

Key fields:
- **logicalBay** — the physical bay number (may differ from bay ID if hardware was swapped)
- **networkDrive** — drive letter for the network share
- **displayResolution** — monitor resolution
- **hasHighSpeedCamera** — whether the bay has a high-speed camera

Bay-specific values override the defaults in `config/shared.json`. See existing entries in `bays.json` for examples.

**Commit and push to `main` before running the installer**, so the bay can pull its config.

## Installation

### 1. Run the installer

```powershell
powershell -ExecutionPolicy Bypass -File "\\path\to\install.ps1"
```

Or copy `install/install.ps1` to the machine and run it locally.

The installer will:
1. Prompt for the bay ID (e.g. `BAY01`) — must match a key in `config/bays.json`
2. Write `C:\SimGolf\bay-identity.json` with the bay ID
3. Clone the repo to `C:\SimGolf\sig-facility\`
4. Copy `supervisor.ps1` to `C:\SimGolf\`
5. Create the master GSPro shortcut at `C:\SimGolf\GSPro.lnk`
6. Create a startup shortcut in `shell:startup`
7. Create a scheduled task for the supervisor

You can also pass the bay ID directly:

```powershell
powershell -ExecutionPolicy Bypass -File "install.ps1" -BayId BAY01
```

### 2. Reboot and verify

After reboot you should see:

1. "Vänligen vänta, systemet startar..." overlay appears
2. After ~30 seconds the overlay disappears
3. GSPro desktop shortcut appears
4. GSPro launches and the automation script takes over

## Configuration

Configuration is resolved by merging two layers:

1. `config/shared.json` — defaults for all bays
2. `config/bays.json` — per-bay overrides, keyed by bay ID

The bay ID is read from `C:\SimGolf\bay-identity.json` (the only local file outside the repo). This file contains:

```json
{"bayId": "BAY01"}
```

All other configuration lives in the repo and is managed via git.

## What runs on boot

The startup launcher (`startup-launcher.bat`) does the following in order:

1. Removes the GSPro desktop shortcut (prevents manual start during update)
2. Shows a "please wait" overlay
3. Starts the supervisor (pulls latest code from `main`)
4. Waits 30 seconds for the update to complete
5. Closes the overlay
6. Restores the GSPro desktop shortcut
7. Launches `gspro-start-v2.ahk`

The supervisor continues running in the background and checks for updates every 30 minutes.
