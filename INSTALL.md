# Bay Installation Guide

Steps to set up a new SimGolf bay machine from scratch.

## Prerequisites

- Windows 11
- GSPro installed at `C:\GSProV1\`
- AutoHotkey v2 installed
- OnTopReplica installed
- Git installed and available on PATH
- `C:\start\copy_gspro_settings.bat` and `C:\start\start-overlay.bat` in place

## Installation

### 1. Run the installer

This clones the repo to `C:\SimGolf\sig-facility\` and places `supervisor.ps1` at `C:\SimGolf\`:

```powershell
powershell -ExecutionPolicy Bypass -File "\\path\to\install.ps1"
```

Or copy `install/install.ps1` to the machine and run it locally.

### 2. Create the master GSPro desktop shortcut

Create a Windows shortcut with:
- **Target:** `C:\SimGolf\sig-facility\scripts\gspro-automation\gspro-start-v2.ahk`
- **Name:** `GSPro`

Save it to:

```
C:\SimGolf\GSPro.lnk
```

This is the master copy. The startup launcher will copy it to the desktop automatically.

### 3. Create the shell:startup shortcut

Create a Windows shortcut with:
- **Target:** `C:\SimGolf\sig-facility\scripts\startup-launcher.bat`

Place it in the Startup folder:

```
shell:startup
```

(Full path: `C:\Users\<user>\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup`)

### 4. Reboot and verify

After reboot you should see:

1. "Vänligen vänta, systemet startar..." overlay appears
2. After ~30 seconds the overlay disappears
3. GSPro desktop shortcut appears
4. GSPro launches and the automation script takes over

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
