# Overlay System Roadmap

## Goal

Replace the current basic overlays with a polished, interactive WebView2-based overlay system that guides customers through the experience — from boot splash to in-game help.

## Principles

- Each increment ships something testable and useful on its own
- Build infrastructure first, features on top
- Never break the existing flow — new overlays run alongside old ones until proven, then swap in

---

## Phase 0: Developer Tooling

**What:** A standalone test harness for developing overlay scripts without restarting GSPro or the full automation chain.

- `scripts/overlay-dev.ahk` — launches a WebView2 overlay window in isolation
- Accepts a command-line argument for which HTML file/URL to load
- Hotkey to reload content (e.g. Ctrl+Shift+R)
- Hotkey to toggle between "simulated states" (boot, welcome, help) so you can test transitions
- Runs completely independently of `gspro-start-v2.ahk`

**Value:** All subsequent phases can be developed and iterated on a bay without touching the running system. Push HTML changes, hit reload, see results.

**Ships:** Dev tool only, no user-facing changes.

---

## Phase 1: WebView2 Foundation

**What:** Minimal AHK v2 + WebView2 integration that can show a borderless overlay with HTML content.

- Bundle `thqby/ahk2-webview2` library in repo (e.g. `lib/ahk/WebView2/`)
- `scripts/overlay/Overlay.ahk` — reusable class that creates a borderless, always-on-top WebView2 GUI
  - `Show(url, options)` — display overlay at given size/position
  - `Hide()` / `Destroy()`
  - `Navigate(url)` — swap content
  - JS→AHK callback bridge for button clicks (close, navigate, etc.)
- Simple test HTML page to verify it works

**Value:** Foundation that all phases build on. Testable via Phase 0 harness.

**Ships:** Infrastructure only, no user-facing changes yet.

---

## Phase 2: Boot Splash Replacement

**What:** Replace the plain "Vänligen vänta" PowerShell overlay with a full-screen branded splash.

- Design a visually appealing HTML splash page (golf-themed, welcoming, "Vänligen vänta — vi förbereder din upplevelse!")
- `scripts/overlay/pages/boot-splash.html` — self-contained HTML/CSS with embedded or local images
- Modify `startup-launcher.bat` to launch the new overlay instead of `startup-overlay.ps1`
- Same lifecycle: shown at boot, killed after supervisor finishes

**Value:** First visible improvement for customers. Immediate "this feels professional" upgrade. Low risk since it's a simple show/kill lifecycle — identical to what exists today, just prettier.

**Ships:** User-facing. Replaces existing boot splash.

---

## Phase 3: Startup Instruction Slides

**What:** A large overlay shown during GSPro startup that hides the window shuffling and shows how-to-play slides.

- `scripts/overlay/pages/instructions.html` — auto-rotating slides (3–5 screens)
  - How to use the simulator
  - How to start a round
  - Safety/etiquette
  - Contact info / QR code for support
- Content is static HTML/CSS with JS auto-advance (e.g. 8 seconds per slide, progress indicator)
- `gspro-start-v2.ahk` shows this overlay after launching GSPro, hides it when the system reaches "ready" state (connection stable, ball tracking active)
- Overlay covers the game area so customers don't see the connector/addon window dance

**Value:** Hides the ugly startup sequence. Educates customers before they start playing. Reduces "what do I do?" confusion.

**Ships:** User-facing. Additive — doesn't replace anything, just covers the startup period.

---

## Phase 4: Enhanced Booking Welcome

**What:** Extend the booking popup with a "Hur funkar det?" button that opens the instruction slides in interactive mode.

- Rework `download-show-dialog.ahk` (currently AHK v1) as a WebView2 overlay
- Fetch the booking image from the API, display it in the overlay
- Add a "Hur funkar det?" button below/beside the image
- Clicking the button navigates to the instruction slides from Phase 3, but with manual prev/next controls instead of auto-advance
- Back button returns to the welcome screen
- Click-to-dismiss still works (tap anywhere outside the controls)

**Value:** Customers who missed the startup slides (or want a refresher) can access them on demand. Replaces the AHK v1 popup with the unified WebView2 system.

**Ships:** User-facing. Replaces existing booking popup.

---

## Phase 5: Persistent Help Button + Help Center

**What:** A small unobtrusive floating button that opens a full help/troubleshooting overlay.

- Small semi-transparent button — bottom-left or bottom-right corner, always visible during gameplay
- Clicking opens a larger overlay (say 80% of screen) with:
  - **Left nav:** Quick links to sections (Getting Started, Troubleshooting, Course Selection, Settings, Contact)
  - **Main content area:** HTML content for each section
  - **Top bar:** Title + close button
- Content is local HTML files, updatable via git
- Sections cover:
  - How to play (reuses Phase 3 content)
  - "Ball not tracking" troubleshooting
  - "Game froze" — what to do
  - How to change course / settings
  - Contact info, QR code to book more time

**Value:** Self-service support reduces the need for staff intervention at an unmanned facility. Customers can solve common problems themselves.

**Ships:** User-facing. New feature.

---

## Content & Design (parallel track)

The HTML/CSS content for each phase can be developed independently once Phase 0 and 1 are in place:

- Boot splash design (Phase 2)
- Instruction slide content and imagery (Phase 3, reused in 4 and 5)
- Help center content (Phase 5)

This can happen on any machine with a browser — no bay PC needed. The Phase 0 dev harness then verifies it looks right in the actual overlay context.

---

## Migration Path

| Phase | Replaces | Removes |
|---|---|---|
| 2 | `startup-overlay.ps1` | Old PowerShell splash |
| 4 | `download-show-dialog.ahk` + `download-file.ps1` | AHK v1 popup system |
| 5 | Nothing (new feature) | — |

---

## Open Questions

- **Hosted vs local HTML?** Starting with local files in the repo (works offline, updates via git). Can add remote loading later if instant content updates become important.
- **Instruction slide content** — needs copywriting and possibly photography/illustrations from the facility.
- **Help content** — needs to be written based on actual common customer issues.
- **Overlay sizing** — needs testing on the actual bay monitors (resolution, aspect ratio).
