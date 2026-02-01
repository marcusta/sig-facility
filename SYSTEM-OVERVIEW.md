# Sweden Indoor Golf — Facility Management System Overview

## What This System Does

This system fully automates 8 unmanned sim golf hitting bays (BAY01–BAY08) at Sweden Indoor Golf. Each bay is a standalone Windows 11 PC running GSPro golf simulator software. The system handles:

- **Automated startup** — from Windows boot to a fully running, monitored GSPro session with no human intervention
- **Self-healing** — detects and recovers from crashed processes, lost connections, and missing windows
- **Self-updating** — pulls code changes from GitHub every 30 minutes and restarts affected services
- **Health monitoring** — reports disk space to a central server that sends alerts
- **Booking display** — shows contextual booking messages (welcome, time warnings) to customers
- **Course distribution** — syncs golf course files from a central network share to each bay

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Central Services                          │
│                                                             │
│  sig-booking API (Bun/Elysia, port 3001)                   │
│    ← Matchi webhooks (booking created/moved/cancelled)      │
│    → GET /courts/:court/show-image (PNG with message)       │
│                                                             │
│  sig-status API                                             │
│    ← POST /status (disk space JSON from each bay)           │
│    → Dashboard, email alerts (<30GB warn, <10GB critical)   │
│                                                             │
│  GitHub repo (sig-facility, main branch)                    │
│    → Pulled by each bay's supervisor every 30 min           │
│                                                             │
│  Network share (\\SIGBAY1\sig\gspro-prefetcher\sgt)        │
│    → Course files synced to each bay                        │
└─────────────────────────────────────────────────────────────┘
         │              │              │
         ▼              ▼              ▼
┌──────────────┐ ┌──────────────┐     ...  (×8 bays)
│    BAY01     │ │    BAY02     │
│  Windows 11  │ │  Windows 11  │
│              │ │              │
│  supervisor  │ │  supervisor  │  ← outside repo, pulls updates
│  gspro-start │ │  gspro-start │  ← main automation (AHK v2)
│  check-status│ │  check-status│  ← disk space reporter
│  show-dialog │ │  show-dialog │  ← booking popup
│  USB relay   │ │  USB relay   │  ← physical indicator lamp
└──────────────┘ └──────────────┘
```

### Two-Layer Deployment

1. **Supervisor** (`C:\SimGolf\supervisor.ps1`) — lives **outside** the repository so it can update everything else without overwriting itself. Cloned once during installation.
2. **Repository** (`C:\SimGolf\sig-facility\`) — all scripts, configs, and business logic. Updated automatically via `git pull`.

### Configuration

Settings merge two layers via `lib/Config.ps1`:

- `config/shared.json` — base settings shared by all bays (URLs, paths, intervals)
- `config/bays.json` — per-hostname overrides (logical bay number, drive letters, relay presence)

Bay identity is determined by `$env:COMPUTERNAME` matching entries in `bays.json`. A `bay-identity.json` file at `C:\SimGolf\` records which bay ID was assigned at install time.

---

## Lifecycle

### 1. Installation (one-time)

`install/install.ps1` sets up a bay from scratch:

1. Creates `C:\SimGolf\` directory structure
2. Writes `bay-identity.json` with the bay ID
3. Clones the repository to `C:\SimGolf\sig-facility\`
4. Copies `supervisor.ps1` to `C:\SimGolf\` (outside the repo)
5. Creates a startup shortcut in `shell:startup` pointing to `startup-launcher.bat`
6. Creates a desktop shortcut for manual GSPro launch

Separately, `install/install-dotnet-runtime.ps1` installs .NET 8.0 for the external `gs-checker.exe` tool.

### 2. Boot Sequence (every Windows login)

`scripts/startup-launcher.bat` orchestrates the full startup:

```
Windows login
  → startup-launcher.bat (via shell:startup shortcut)
      1. Remove desktop shortcut (prevent premature click)
      2. Show "Please wait" splash screen (startup-overlay.ps1)
      3. Start supervisor.ps1 (hidden window)
      4. Wait 30 seconds for initial git pull
      5. Close splash screen
      6. Restore desktop shortcut
      7. Start check-status.ps1 (disk space monitor)
      8. Start download-show-dialog.ahk (booking popup)
      9. Write relay config flag (C:\SimGolf\no-relay if bay lacks hardware)
     10. Start gspro-start-v2.ahk (main GSPro automation)
```

### 3. GSPro Automation (continuous)

`scripts/gspro-automation/gspro-start-v2.ahk` is the core of the system — a 1100+ line AutoHotkey v2 state machine. On launch it:

1. Detects and connects to the USB relay (CP210x serial device) for the physical indicator lamp
2. Restores GSPro settings from `.orig` backups
3. Launches `GSPro.exe` and waits for the connector window
4. Clicks "Open Visual Data" to open the stats addon window
5. Starts `OnTopReplica` to mirror the addon as an always-on-top overlay
6. Arranges the window hierarchy (game fullscreen, connector behind, overlay on top)
7. Enters the main timer loop

**Timer loop (runs indefinitely):**

| Timer | Interval | Purpose |
|---|---|---|
| SignalSampleTick | 250ms | Reads pixel colors from the connector window via `PrintWindow` API to detect connection/link/ball status. Uses debounced sampling (3–32 samples) to avoid false triggers. |
| RecoveryTick | 500ms | Runs the recovery state machine when problems are detected. |
| UIEnforcementTick | 2000ms | Checks that all windows exist and are correctly arranged. Repairs missing addon/overlay windows. Re-fullscreens the game if it lost fullscreen. |
| BlinkEngineTick | 150ms | Drives the USB relay lamp pattern based on system state. |

**What it detects and recovers from:**

| Problem | Detection | Recovery |
|---|---|---|
| Lost LM connection | Link bar pixel turns red (debounced 3 samples) | Opens Connection Manager, searches for device, reconnects |
| Lost connection status | Status pixel turns red | Same reconnection sequence |
| Connector crashed | Window missing for 8+ seconds | Kills process, relaunches `GSPconnect.exe`, reopens addon and overlay |
| Addon window missing | Window gone for 6+ seconds | Re-clicks "Open Visual Data" button on connector |
| Overlay missing | `OnTopReplica` gone for 6+ seconds | Restarts via `start-overlay.bat` |
| Game lost fullscreen | Window style includes border bits | Sends F11 to re-fullscreen |

**USB relay indicator lamp patterns:**

| Pattern | Meaning |
|---|---|
| Solid green | Ball tracked, ready to hit |
| Solid red | Connected but no ball detected |
| Slow blink (750ms) | System recovering |
| Fast blink (300ms) | Multiple errors |
| Code: green-red-red-pause | GSPro link down |
| Code: green-green-red-pause | Launch monitor connection down |

### 4. Auto-Update Cycle (every 30 minutes)

`supervisor.ps1` runs in a continuous loop:

1. `git pull --ff-only origin main`
2. If the commit hash changed:
   - Writes a `C:\SimGolf\restart-requested` signal file
   - Waits up to 30 seconds for `check-status.ps1` to notice the signal and exit gracefully
   - Force-kills if it doesn't exit in time
   - Restarts `check-status.ps1`
3. If the background process died for any reason, restarts it

The signal-file mechanism allows graceful restarts — `check-status.ps1` checks for the file each iteration and exits cleanly when it appears.

### 5. Health Monitoring (every 60 seconds)

`scripts/monitoring/check-status.ps1` reports to the central server:

```
POST https://app.swedenindoorgolf.se/sig-status/status
{
  "machine": "BAY01",
  "logicalBay": 1,
  "cDriveSpace": 45.2,
  "dDriveSpace": 120.5
}
```

The server (not in this repo) stores status in SQLite, serves a dashboard, and sends email alerts when drives drop below 30 GB (warning) or 10 GB (critical).

### 6. Booking Display (polled every 60 seconds)

`scripts/popup/download-show-dialog.ahk` (AHK v1) polls the booking API:

1. Runs `download-file.ps1` which fetches `GET /courts/{logicalBay}/show-image`
2. If the server returns a 200 with a PNG image, displays it as a borderless always-on-top window with a fade-in animation
3. Customer can click the image to dismiss it

The booking server (not in this repo) decides what message to show based on:
- Booking starting → welcome greeting with customer name
- Booking ending soon → time warning
- Next slot booked by someone else → "bay occupied" notice
- Next slot free → prompt to book more time
- Same customer back-to-back → no interruption

### 7. Course Sync (on-demand)

`scripts/course-sync/sync-courses2.ps1` copies golf course files from a network share:

1. Scans the remote share (`\\SIGBAY1\sig\gspro-prefetcher\sgt`) for new or changed files
2. Copies changed files to a staging directory first
3. Atomically moves them to the final location (prevents GSPro from reading partial files)
4. Only syncs files with different timestamps or sizes

---

## Directory Layout

```
C:\SimGolf\                          ← Base directory on each bay PC
├── supervisor.ps1                   ← Auto-updater (outside repo)
├── bay-identity.json                ← {"bayId": "BAY01"}
├── no-relay                         ← Flag file (present = no USB relay)
├── restart-requested                ← Signal file for graceful restarts
├── logs\                            ← Log files
│   ├── supervisor-YYYY-MM-DD.log
│   └── monitor_error.log
└── sig-facility\                    ← This repository
    ├── config\
    │   ├── shared.json              ← Global settings
    │   └── bays.json                ← Per-bay overrides
    ├── lib\
    │   └── Config.ps1               ← Config loader module
    ├── install\
    │   ├── install.ps1              ← One-time installer
    │   ├── supervisor.ps1           ← Supervisor template
    │   └── install-dotnet-runtime.ps1
    ├── scripts\
    │   ├── startup-launcher.bat     ← Boot orchestrator
    │   ├── startup-overlay.ps1      ← "Please wait" splash
    │   ├── dev-mode.ps1             ← Fast dev iteration tool
    │   ├── gspro-automation\
    │   │   ├── gspro-start-v2.ahk   ← Main automation (AHK v2)
    │   │   ├── start-overlay.bat     ← OnTopReplica launcher
    │   │   └── dump-controls.ahk    ← Debug tool
    │   ├── gspro-settings\
    │   │   ├── copy_gspro_settings.bat   ← Restore settings
    │   │   └── preserve-settings.bat     ← Backup settings
    │   ├── monitoring\
    │   │   └── check-status.ps1     ← Disk space reporter
    │   ├── course-sync\
    │   │   └── sync-courses2.ps1    ← Course file sync
    │   └── popup\
    │       ├── download-show-dialog.ahk  ← Booking display (AHK v1)
    │       └── download-file.ps1         ← Image fetcher
    └── scripts\assets\              ← Icons, external binaries (not in git)
```

## External Dependencies

| Component | Location | Purpose |
|---|---|---|
| GSPro | `C:\GSProV1\` | Golf simulator software |
| GSPconnect | `C:\GSProV1\Core\GSPC\` | Launch monitor connector |
| OnTopReplica | `C:\Program Files (x86)\OnTopReplica\` | Window overlay tool |
| .NET 8 Runtime | System-wide | Required by `gs-checker.exe` |
| Network share | `\\SIGBAY1\sig\gspro-prefetcher\sgt` | Course file source |
| sig-booking API | `https://simple-sgt.fly.dev` | Booking info images |
| sig-status API | `https://app.swedenindoorgolf.se/sig-status/` | Health monitoring |

## Developer Workflow

For rapid iteration on a bay, `scripts/dev-mode.ps1`:

1. Stops the supervisor
2. Switches the bay to a dev branch
3. Polls `git fetch` every 5 seconds and auto-pulls changes
4. On exit (Ctrl+C), switches back to `main` and restarts the supervisor

This replaces the normal 30-minute update cycle with a ~5-second feedback loop during development.
