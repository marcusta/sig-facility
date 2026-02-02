# CLAUDE.md

## Project Overview

SimGolf Facility Management System for **Sweden Indoor Golf** — manages 8 unmanned sim golf hitting bays (BAY01–BAY08). Automates GSPro golf simulator startup, monitoring, window management, course synchronization, and self-updating deployment across distributed Windows 11 machines.

## Architecture

**Two-layer deployment:**
1. **Supervisor** (`C:\SimGolf\supervisor.ps1`) — lives outside the repo, auto-pulls every 30 min, restarts processes on changes
2. **Repository** (`C:\SimGolf\sig-facility\`) — all scripts, configs, business logic; auto-updated via git

**Configuration** merges `config/shared.json` (base) with `config/bays.json` (per-hostname overrides) via `lib/Config.ps1`. Bay identity is resolved from `C:\SimGolf\bay-identity.json` (contains `{"bayId": "BAY01"}`). The `bays.json` entry for each bay includes `logicalBay` (integer 1-8) which is the physical bay number.

## Key Technologies

- **PowerShell** — installation, supervisor, monitoring, course sync
- **AutoHotkey v2** — GSPro window automation, state machine, USB relay control
- **Batch scripts** — legacy launchers
- **JSON** — configuration
- **Git** — deployment mechanism

## Directory Structure

```
config/          JSON configuration (shared.json, bays.json)
lib/
  Config.ps1     PowerShell config module
  ahk/           AHK v2 libraries
    WebView2/    thqby's WebView2 wrapper + 64bit DLL
    ComVar.ahk   COM variant helper
    Promise.ahk  Promise/async helper
install/         One-time installer, supervisor template, .NET runtime installer
scripts/
  monitoring/    Disk space reporting to API
  course-sync/   Network share sync with staging
  gspro-automation/  GSPro control scripts (AHK v1 & v2)
  gspro-settings/    Settings backup/restore
  popup/             Booking info display
  overlay/           WebView2 overlay system
    Overlay.ahk      Reusable overlay class
    pages/           HTML content pages
  overlay-dev.ahk    Standalone overlay dev harness
  dev-mode.ps1       Feature branch auto-pull for bay testing
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

## Overlay System (in progress, branch: overlay-phase-0-1)

WebView2-based HTML overlay for displaying content on top of GSPro.

**Status:** Phase 0+1 complete (foundation verified on bay). Startup overlay content built. Next: help system page (Phase 5 in roadmap).

**Structure:**
- `lib/ahk/WebView2/` — thqby's WebView2.ahk library + 64-bit loader DLL
- `lib/ahk/ComVar.ahk`, `lib/ahk/Promise.ahk` — WebView2 dependencies
- `scripts/overlay/Overlay.ahk` — reusable class: borderless always-on-top GUI wrapping WebView2
  - `Show(url, {w, h, x, y})`, `Hide()`, `Destroy()`, `Navigate(url)`, `Reload()`
- `scripts/overlay/pages/` — HTML content pages
- `scripts/overlay-dev.ahk` — standalone dev harness (runs without GSPro)
  - `Ctrl+Shift+R` reload, `Ctrl+Shift+1/2/3` switch pages, `Escape` exit

**Existing pages:**
- `scripts/overlay/pages/startup.html` — shown during GSPro boot sequence
  - Top 75%: 4 auto-rotating slides (20s each): instruction video (sig-start.mp4 autoplay), ball placement with bay-specific mat image, "Kom igang" 3-step guide, troubleshooting
  - Bottom 25%: loading footer with spinner, rotating status messages (mix of funny golf-themed and informative), progress dots
  - Topbar with SIG logo and brand text
  - Golden radial gradient background from top-right corner
  - Bay detection via `?bay=BAY03` query param or `window.setBayId("BAY03")` JS bridge call (bay 3 gets mat-3.jpg, others get mat-1-2.jpg)
  - Assets stored in `scripts/overlay/pages/images/` (logo, mat images, video via Git LFS)

**Design system (shared across overlay pages):**
- Brand colors: `--primary: #eab308` (yellow), `--bg: #020617` (slate-950), `--bg-secondary: #0f172a` (slate-900)
- Font: Inter (Google Fonts), weights 400/500/600/700
- Style matches the sig-web Next.js site: dark theme, yellow accents, rounded corners, clean typography
- Content in Swedish with proper UTF-8 characters

**AHK v2 gotcha:** AHK is case-insensitive. Do not use variable names that match class names (e.g. `overlay := Overlay()` fails).

**Dev workflow:** Use `scripts/dev-mode.ps1 -Branch <name>` on a bay to auto-pull a feature branch every 5s. Push from dev machine, test on bay.

**Related project:** `sig-web/` (gitignored) is a local copy of the Next.js website for reference only. It is NOT part of this project and is not deployed to bays. Never reference files from `sig-web/` in overlay HTML or scripts -- all assets must live within the repo (under `scripts/overlay/pages/images/` or similar).

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
- Never use non-ASCII characters in PowerShell (`.ps1`) or AutoHotkey (`.ahk`) scripts (no em dashes, curly quotes, etc.) - PowerShell 5 on the bays misreads UTF-8 multibyte characters. Use plain ASCII: hyphens (`-`), straight quotes (`"`/`'`), etc. HTML/CSS/JS files are fine with full UTF-8 (Swedish characters, etc.).
