#Requires AutoHotkey v2.0
#SingleInstance Force
#Include "..\overlay\OverlayManager.ahk"

; ##################################################################
; CONFIGURATION
; ##################################################################

global GSP_PATH      := "C:\GSProV1\Core\GSP\GSPro.exe"
global SETTINGS_BAT  := "C:\SimGolf\sig-facility\scripts\gspro-settings\copy_gspro_settings.bat"
global OVERLAY_BAT   := "C:\SimGolf\sig-facility\scripts\gspro-automation\start-overlay.bat"

global GAME_WINDOW      := "ahk_exe GSPro.exe"
global CONNECTOR_WINDOW := "ahk_exe GSPconnect.exe"
global ADDON_WINDOW     := "Advanced Connect Add On"
global REPLICA_WINDOW   := "OnTopReplica"

global CONNECTOR_EXE_PATH := "C:\GSProV1\Core\GSPC\GSPconnect.exe"

; Koordinater (Relativa till Connector-fönstret)
global TAB_CONN_MGR  := "x280 y40"
global TAB_SHOT_DATA := "x90 y40"
global BTN_SEARCH    := "x140 y230"

; Pixel locations for status checks
global STATUS_X := 700
global STATUS_Y := 35
global LINKBAR_X := 322
global LINKBAR_Y := 35
global BALL_TRACKED_X := 1051
global BALL_TRACKED_Y := 624

; Colors in BGR format (GetPixel returns BGR)
global BGR_RED         := 0x00008B
global BGR_GREEN       := 0x008000
global BGR_READY_GREEN := 0x008000
global BGR_READY_RED   := 0x00008B

; ##################################################################
; DEBOUNCE CONFIGURATION
; ##################################################################

global DEBOUNCE_SAMPLES := 3  ; Require N consecutive samples before acting
global SIGNAL_SAMPLE_MS := 250  ; Sample signals every 250ms
global UI_ENFORCE_MS    := 2000  ; UI enforcement every 2s
global BLINK_TICK_MS    := 150   ; Blink engine tick rate
global BOOKING_POLL_MS  := 60000 ; Booking message poll interval

; ##################################################################
; STATE MACHINE
; ##################################################################

class SystemState {
    ; Raw signal counters (for debouncing)
    static linkGreenCount := 0
    static linkRedCount := 0
    static connGreenCount := 0
    static connRedCount := 0
    static ballGreenCount := 0
    static ballRedCount := 0
    static connectorMissingCount := 0

    ; Debounced stable states
    static linkStable := false
    static connectionStable := false
    static ballTracked := false
    static connectorPresent := false

    ; First-time flags (allow initial red without triggering recovery)
    static linkEverGreen := false
    static connectionEverGreen := false

    ; Recovery state machine
    static recoveryPhase := 0  ; 0=idle, 1=searching, 2=connecting, 3=waiting
    static recoveryStartTime := 0
    static recoveryStepTime := 0

    ; System flags
    static isRecovering := false
    static isRestarting := false
    static isRepairingAddon := false

    ; Window presence counters (for debouncing)
    static addonMissingCount := 0
    static replicaMissingCount := 0
}

; Indicator modes for the lamp
class IndicatorMode {
    static Off := 0
    static SolidGreen := 1
    static SolidRed := 2
    static BlinkSlow := 3      ; System recovering
    static BlinkFast := 4      ; Multiple errors
    static BlinkCodeGspro := 5
    static BlinkCodeLM := 6
}

global currentIndicatorMode := IndicatorMode.SolidRed
global blinkState := false  ; Current on/off state for blinking
global blinkStep := 0       ; Step counter for complex patterns

; ##################################################################
; BOOKING OVERLAY
; ##################################################################

global bookingPollEnabled := false
global bookingUrl := ""

; ##################################################################
; USB RELAY
; ##################################################################

global relayEnabled := !FileExist("C:\SimGolf\no-relay")
global relayPort := 0
global relayPortName := ""

; ##################################################################
; DEBUG OVERLAY
; ##################################################################

global debugExpanded := true
global debugCollapseTimer := 0
global DEBUG_COLLAPSE_DELAY := 5000  ; Collapse after 5 seconds of stability

; Create the GUI with both expanded and collapsed elements
DebugGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
DebugGui.BackColor := "000000"

; Expanded view: text area (6 lines)
DebugGui.SetFont("s10 cGreen", "Consolas")
DebugText := DebugGui.Add("Text", "w350 h108 vExpandedText", "Initializing...")

; Start expanded (lower left corner)
debugY := A_ScreenHeight - 130
DebugGui.Show("x10 y" . debugY . " NoActivate")

ExpandDebugOverlay() {
    global debugExpanded, debugCollapseTimer, DebugGui, DebugText

    if (debugExpanded)
        return

    debugExpanded := true
    debugCollapseTimer := 0

    DebugText.Visible := true
    debugY := A_ScreenHeight - 130
    DebugGui.Show("x10 y" . debugY . " w358 h116 NoActivate")
}

CollapseDebugOverlay() {
    global debugExpanded, DebugGui, DebugText

    if (!debugExpanded)
        return

    debugExpanded := false
    DebugText.Visible := false
    debugY := A_ScreenHeight - 30
    DebugGui.Show("x10 y" . debugY . " w16 h16 NoActivate")
}

global LOG_FILE := "C:\SimGolf\gspro-debug.log"
; Rotate log on startup: keep previous as .prev, start fresh
try {
    if FileExist(LOG_FILE . ".prev")
        FileDelete(LOG_FILE . ".prev")
    if FileExist(LOG_FILE)
        FileMove(LOG_FILE, LOG_FILE . ".prev")
}

LogStatus(msg, expand := true) {
    global DebugText, debugCollapseTimer, LOG_FILE

    ; Only expand overlay for important messages
    if (expand) {
        ExpandDebugOverlay()
        debugCollapseTimer := A_TickCount
    }

    logLine := FormatTime(, "HH:mm:ss") . ": " . msg
    try FileAppend(logLine . "`n", LOG_FILE)

    try {
        current := DebugText.Value
        lines := StrSplit(current, "`n")
        if (lines.Length >= 6)
            lines.RemoveAt(1)
        lines.Push(logLine)
        DebugText.Value := ""
        for line in lines
            DebugText.Value .= (A_Index > 1 ? "`n" : "") . line
    }
}

UpdateDebugOverlayState() {
    global debugExpanded, debugCollapseTimer, DEBUG_COLLAPSE_DELAY

    ; Don't collapse during startup, recovery, or restart
    if (SystemState.isRestarting || SystemState.isRecovering)
        return

    ; Don't collapse if not all systems are stable
    if (!SystemState.connectionStable || !SystemState.linkStable || !SystemState.connectorPresent)
        return

    ; Collapse if stable for long enough
    if (debugExpanded && debugCollapseTimer > 0) {
        if (A_TickCount - debugCollapseTimer > DEBUG_COLLAPSE_DELAY) {
            CollapseDebugOverlay()
        }
    }
}

; ##################################################################
; HOTKEYS
; ##################################################################

; Ctrl+Shift+X to force-quit
^+x:: {
    if OverlayMgr
        OverlayMgr.Cleanup()
    ExitApp()
}

; Ctrl+Shift+D to toggle debug overlay
^+d:: {
    global debugExpanded
    if (debugExpanded)
        CollapseDebugOverlay()
    else
        ExpandDebugOverlay()
}

; ##################################################################
; STARTUP
; ##################################################################

LogStatus("Starting System v2 (Timer-based)...")
if (relayEnabled)
    InitializeRelay()
else
    LogStatus("Relay disabled (no-relay flag)")

; Read bay identity and create overlay manager
global OverlayMgr := ""
try {
    bayJson := FileRead("C:\SimGolf\bay-identity.json")
    if RegExMatch(bayJson, '"bayId"\s*:\s*"(\w+)"', &bayMatch)
        OverlayMgr := OverlayManager(bayMatch[1])
}
if !OverlayMgr
    LogStatus("Warning: Could not read bay identity for overlay")
InitBooking()

; Show startup overlay before boot sequence
if OverlayMgr
    OverlayMgr.ShowStartup()

InitializeSystem()
StartTimers()

InitializeSystem() {
    RunWait(SETTINGS_BAT, , "Hide")
    Run(GSP_PATH)

    LogStatus("Waiting for Connector...")
    if !WinWait(CONNECTOR_WINDOW, , 60) {
        LogStatus("Connector window not found!")
        return
    }

    LogStatus("Connector found, waiting for connection...")
}

global startupComplete := false
global setupComplete := false
global startupStableSince := 0
CheckStartupComplete() {
    global startupComplete, startupStableSince
    if startupComplete
        return
    if !SystemState.connectionStable || !SystemState.linkStable {
        startupStableSince := 0
        return
    }
    ; Require 5 seconds of sustained stability before dismissing
    if (startupStableSince = 0) {
        startupStableSince := A_TickCount
        return
    }
    if (A_TickCount - startupStableSince < 5000)
        return
    startupComplete := true
    LogStatus("Connection stable - waiting for GSPro menu...")
    SetTimer(WaitForGsproReady, 500)
}

; Pixel on GSPro logo text - white (FFFFFF) when main menu is loaded
global GSPRO_READY_X := 1098
global GSPRO_READY_Y := 58
global GSPRO_READY_COLOR := 0xFFFFFF  ; BGR white

WaitForGsproReady() {
    if !WinExist(GAME_WINDOW) {
        SetTimer(WaitForGsproReady, 0)
        return
    }

    hwnd := WinExist(GAME_WINDOW)
    color := GetPixelColorHidden(hwnd, GSPRO_READY_X, GSPRO_READY_Y)

    if (color = GSPRO_READY_COLOR) {
        SetTimer(WaitForGsproReady, 0)
        LogStatus("GSPro menu detected - ready!")
        if OverlayMgr
            OverlayMgr.HideStartup()
        SetTimer(OpenVisualDataAndSetup, -500)
    }
}

OpenVisualDataAndSetup() {
    LogStatus("Opening Visual Data...")

    WinActivate(CONNECTOR_WINDOW)
    Sleep(500)

    visualDataOpened := false
    Loop 15 {
        if !WinExist(GAME_WINDOW) {
            LogStatus("Game window closed during startup")
            ExitApp()
        }

        if !WinExist(CONNECTOR_WINDOW) {
            LogStatus("Connector window lost during startup")
            break
        }

        try {
            ControlClick("Open Visual Data", CONNECTOR_WINDOW)
            LogStatus("Clicked Open Visual Data (" . A_Index . ")")
        } catch as e {
            LogStatus("Click failed: " . e.Message)
        }

        if WinWait(ADDON_WINDOW, , 2) {
            LogStatus("Visual Data window opened!")
            visualDataOpened := true
            break
        }
        Sleep(1000)
    }

    if (!visualDataOpened)
        LogStatus("Warning: Visual Data window not opened")

    Run(OVERLAY_BAT, "C:\SimGolf\sig-facility\scripts\gspro-automation")
    Sleep(1500)

    LogStatus("Setting window hierarchy...")
    SetWindowHierarchy()
    LogStatus("Window hierarchy set")
    global setupComplete := true

    ; Show help button now that system is ready
    if OverlayMgr
        OverlayMgr.ShowHelpButton()

    ; Startup is complete here, so trigger a one-shot booking poll now.
    SetTimer(BookingPollTick, -300)

    LogStatus("System Ready")
}

StartTimers() {
    ; Fast timer: sample signals and update state
    SetTimer(SignalSampleTick, SIGNAL_SAMPLE_MS)

    ; Slow timer: UI enforcement
    SetTimer(UIEnforcementTick, UI_ENFORCE_MS)

    ; Blink engine timer
    SetTimer(BlinkEngineTick, BLINK_TICK_MS)

    ; Recovery state machine timer (runs when recovering)
    SetTimer(RecoveryTick, 500)

    ; Booking message polling (suppressed during startup/recovery/help)
    SetTimer(BookingPollTick, BOOKING_POLL_MS)
}

; ##################################################################
; SIGNAL SAMPLING (runs every 250ms)
; ##################################################################

SignalSampleTick() {
    ; Check if game is still running
    if !WinExist(GAME_WINDOW) {
        LogStatus("GSPro Closed - Exiting...")
        CleanupAndExit()
        return
    }

    ; Don't sample during restart sequence
    if (SystemState.isRestarting)
        return

    hwnd := WinExist(CONNECTOR_WINDOW)

    ; Sample connector presence
    SampleConnectorPresence(hwnd)

    if (!hwnd)
        return

    ; Sample all pixel-based signals
    SampleLinkBar(hwnd)
    SampleConnection(hwnd)
    SampleBallTracking(hwnd)

    ; Check if startup is complete (needs repeated calls for stability timer)
    if !startupComplete
        CheckStartupComplete()

    ; Update indicator mode based on current state
    UpdateIndicatorMode()
}

SampleConnectorPresence(hwnd) {
    if (hwnd) {
        SystemState.connectorMissingCount := 0
        if (!SystemState.connectorPresent) {
            SystemState.connectorPresent := true
            LogStatus("Connector window found")
        }
    } else {
        SystemState.connectorMissingCount++
        if (SystemState.connectorMissingCount >= 32) {  ; ~8 seconds at 250ms
            if (SystemState.connectorPresent) {
                SystemState.connectorPresent := false
                LogStatus("Connector missing - will restart")
                TriggerConnectorRestart("window missing")
            }
        }
    }
}

SampleLinkBar(hwnd) {
    color := GetPixelColorHidden(hwnd, LINKBAR_X, LINKBAR_Y)

    if (color = BGR_GREEN) {
        SystemState.linkGreenCount++
        SystemState.linkRedCount := 0

        if (SystemState.linkGreenCount >= DEBOUNCE_SAMPLES && !SystemState.linkStable) {
            SystemState.linkStable := true
            SystemState.linkEverGreen := true
            LogStatus("Link bar: STABLE (debounced)")
            CheckStartupComplete()
        }
    }
    else if (color = BGR_RED) {
        SystemState.linkRedCount++
        SystemState.linkGreenCount := 0

        if (SystemState.linkRedCount >= DEBOUNCE_SAMPLES && SystemState.linkStable) {
            SystemState.linkStable := false
            LogStatus("Link bar: LOST (debounced)")
            if (SystemState.linkEverGreen && !SystemState.isRecovering)
                TriggerConnectorRestart("link bar red")
        }
    }
}

SampleConnection(hwnd) {
    color := GetPixelColorHidden(hwnd, STATUS_X, STATUS_Y)

    if (color = BGR_GREEN) {
        SystemState.connGreenCount++
        SystemState.connRedCount := 0

        if (SystemState.connGreenCount >= DEBOUNCE_SAMPLES && !SystemState.connectionStable) {
            SystemState.connectionStable := true
            if !SystemState.connectionEverGreen
                SystemState.connectionEverGreen := true
            CheckStartupComplete()
            LogStatus("Connection: STABLE (debounced)")

            ; If we were recovering, end recovery and restore UI
            if (SystemState.isRecovering)
                EndRecovery()
        }
    }
    else if (color = BGR_RED) {
        SystemState.connRedCount++
        SystemState.connGreenCount := 0

        if (SystemState.connRedCount >= DEBOUNCE_SAMPLES && SystemState.connectionStable) {
            SystemState.connectionStable := false
            LogStatus("Connection: LOST (debounced)")
            if (SystemState.connectionEverGreen && !SystemState.isRecovering)
                TriggerConnectionRecovery()
        }
    }
}

SampleBallTracking(hwnd) {
    ; Only track ball if connection is stable
    if (!SystemState.connectionStable) {
        SystemState.ballTracked := false
        SystemState.ballGreenCount := 0
        SystemState.ballRedCount := 0
        return
    }

    color := GetPixelColorHidden(hwnd, BALL_TRACKED_X, BALL_TRACKED_Y)

    if (color = BGR_READY_GREEN) {
        SystemState.ballGreenCount++
        SystemState.ballRedCount := 0

        if (SystemState.ballGreenCount >= DEBOUNCE_SAMPLES && !SystemState.ballTracked) {
            SystemState.ballTracked := true
            LogStatus("Ball: READY (debounced)", false)
        }
    }
    else if (color = BGR_READY_RED) {
        SystemState.ballRedCount++
        SystemState.ballGreenCount := 0

        if (SystemState.ballRedCount >= DEBOUNCE_SAMPLES && SystemState.ballTracked) {
            SystemState.ballTracked := false
            LogStatus("Ball: NOT READY (debounced)", false)
        }
    }
}

; ##################################################################
; INDICATOR MODE LOGIC
; ##################################################################

UpdateIndicatorMode() {
    global currentIndicatorMode
    newMode := IndicatorMode.SolidRed  ; Default

    if (SystemState.isRestarting) {
        newMode := IndicatorMode.BlinkSlow
    }
    else if (SystemState.isRecovering) {
        newMode := IndicatorMode.BlinkSlow
    }
    else if (!SystemState.connectorPresent) {
        newMode := IndicatorMode.BlinkSlow
    }
    else if (!SystemState.connectionStable) {
        if (!SystemState.linkStable)
            newMode := IndicatorMode.BlinkFast  ; Both down
        else
            newMode := IndicatorMode.BlinkCodeLM  ; Just LM down
    }
    else if (!SystemState.linkStable) {
        newMode := IndicatorMode.BlinkCodeGspro  ; Just GSPro link down
    }
    else if (SystemState.ballTracked) {
        newMode := IndicatorMode.SolidGreen
    }
    else {
        newMode := IndicatorMode.SolidRed  ; Connected but no ball
    }

    if (newMode != currentIndicatorMode) {
        ; Only expand overlay for error/recovery modes
        isQuiet := (newMode = IndicatorMode.SolidGreen || newMode = IndicatorMode.SolidRed)
        LogStatus("Indicator: " . IndicatorModeName(currentIndicatorMode) . " -> " . IndicatorModeName(newMode), !isQuiet)
        currentIndicatorMode := newMode
        blinkStep := 0  ; Reset blink pattern

        ; Alert the help button during error states
        if OverlayMgr {
            isError := (newMode = IndicatorMode.BlinkSlow || newMode = IndicatorMode.BlinkFast || newMode = IndicatorMode.BlinkCodeGspro || newMode = IndicatorMode.BlinkCodeLM)
            OverlayMgr.SetHelpAlert(isError)
        }
    }
}

IndicatorModeName(mode) {
    switch mode {
        case IndicatorMode.Off: return "Off"
        case IndicatorMode.SolidGreen: return "SolidGreen"
        case IndicatorMode.SolidRed: return "SolidRed"
        case IndicatorMode.BlinkSlow: return "BlinkSlow"
        case IndicatorMode.BlinkFast: return "BlinkFast"
        case IndicatorMode.BlinkCodeGspro: return "BlinkCodeGspro"
        case IndicatorMode.BlinkCodeLM: return "BlinkCodeLM"
        default: return "Unknown(" . mode . ")"
    }
}

; ##################################################################
; BLINK ENGINE (runs every 150ms)
; ##################################################################

BlinkEngineTick() {
    global currentIndicatorMode, blinkState, blinkStep

    switch currentIndicatorMode {
        case IndicatorMode.SolidGreen:
            SetRelayGreen()

        case IndicatorMode.SolidRed, IndicatorMode.Off:
            SetRelayRed()

        case IndicatorMode.BlinkSlow:
            ; Toggle every ~5 ticks (750ms on, 750ms off)
            blinkStep++
            if (blinkStep >= 5) {
                blinkStep := 0
                blinkState := !blinkState
                if (blinkState)
                    SetRelayGreen()
                else
                    SetRelayRed()
            }

        case IndicatorMode.BlinkFast:
            ; Toggle every ~2 ticks (300ms)
            blinkStep++
            if (blinkStep >= 2) {
                blinkStep := 0
                blinkState := !blinkState
                if (blinkState)
                    SetRelayGreen()
                else
                    SetRelayRed()
            }

        case IndicatorMode.BlinkCodeGspro:
            ; Pattern: Green-Red-Red-pause (GSPro issue)
            blinkStep++
            switch blinkStep {
                case 1: SetRelayGreen()
                case 2: SetRelayRed()
                case 3: SetRelayRed()
                case 10: blinkStep := 0  ; Pause then repeat
            }

        case IndicatorMode.BlinkCodeLM:
            ; Pattern: Green-Green-Red-pause (LM issue)
            blinkStep++
            switch blinkStep {
                case 1: SetRelayGreen()
                case 2: SetRelayGreen()
                case 3: SetRelayRed()
                case 10: blinkStep := 0
            }
    }
}

; ##################################################################
; UI ENFORCEMENT (runs every 2s)
; ##################################################################

UIEnforcementTick() {
    ; Don't enforce UI during restart, recovery, or startup
    if (SystemState.isRestarting || SystemState.isRecovering || !setupComplete)
        return

    EnsureFullscreen(GAME_WINDOW)
    EnsureAddonWindow()
    EnsureOverlayWindow()
    UpdateDebugOverlayState()
}

; ##################################################################
; RECOVERY STATE MACHINE (non-blocking)
; ##################################################################

TriggerConnectionRecovery() {
    if (SystemState.isRecovering || SystemState.isRestarting)
        return

    SystemState.isRecovering := true
    SystemState.recoveryPhase := 1
    SystemState.recoveryStartTime := A_TickCount
    SystemState.recoveryStepTime := A_TickCount
    LogStatus("Starting connection recovery...")
}

TriggerConnectorRestart(reason) {
    if (SystemState.isRestarting)
        return

    SystemState.isRestarting := true
    SystemState.isRecovering := false
    SystemState.recoveryPhase := 0

    ; Reset all state flags
    SystemState.linkStable := false
    SystemState.connectionStable := false
    SystemState.ballTracked := false
    SystemState.linkEverGreen := false
    SystemState.connectionEverGreen := false

    LogStatus("Restarting connector: " . reason)

    ; Close addon and connector
    if WinExist(ADDON_WINDOW)
        WinClose(ADDON_WINDOW)
    if (pid := ProcessExist("GSPconnect.exe"))
        ProcessClose(pid)

    ; Use a one-shot timer to continue restart after delay
    SetTimer(ConnectorRestartContinue, -1000)
}

ConnectorRestartContinue() {
    Run(CONNECTOR_EXE_PATH)

    LogStatus("Waiting for Connector...")
    SetTimer(ConnectorRestartWait, -100)
}

ConnectorRestartWait() {
    static waitCount := 0

    if WinExist(CONNECTOR_WINDOW) {
        waitCount := 0
        WinActivate(CONNECTOR_WINDOW)
        SetTimer(ConnectorRestartOpenVisual, -1000)
        return
    }

    waitCount++
    if (waitCount > 300) {  ; 30 second timeout
        waitCount := 0
        LogStatus("Connector restart timeout")
        SystemState.isRestarting := false
        return
    }

    SetTimer(ConnectorRestartWait, -100)
}

ConnectorRestartOpenVisual() {
    static clickCount := 0

    if WinExist(ADDON_WINDOW) {
        clickCount := 0
        RestartOverlay()
        LogStatus("Connector restart complete")
        SystemState.isRestarting := false
        return
    }

    if !WinExist(GAME_WINDOW) {
        clickCount := 0
        CleanupAndExit()
        return
    }

    if !WinExist(CONNECTOR_WINDOW) {
        ; Connector window gone, abort
        clickCount := 0
        LogStatus("Connector window gone during Visual Data open")
        SystemState.isRestarting := false
        return
    }

    try {
        ControlClick("Open Visual Data", CONNECTOR_WINDOW)
    } catch as e {
        LogStatus("ControlClick failed: " . e.Message)
    }

    clickCount++

    if (clickCount > 10) {
        clickCount := 0
        LogStatus("Failed to open Visual Data")
        SystemState.isRestarting := false
        return
    }

    SetTimer(ConnectorRestartOpenVisual, -1000)
}

RecoveryTick() {
    if (!SystemState.isRecovering)
        return

    ; Timeout after 60 seconds
    if (A_TickCount - SystemState.recoveryStartTime > 60000) {
        LogStatus("Recovery timeout")
        EndRecovery()
        return
    }

    if (!WinExist(CONNECTOR_WINDOW)) {
        TriggerConnectorRestart("connector gone during recovery")
        return
    }

    ; Keep connector window in front during recovery
    WinActivate(CONNECTOR_WINDOW)

    switch SystemState.recoveryPhase {
        case 1:  ; Go to Connection Manager tab
            try {
                ControlClick(TAB_CONN_MGR, CONNECTOR_WINDOW)
            }
            SystemState.recoveryPhase := 2
            SystemState.recoveryStepTime := A_TickCount
            LogStatus("Recovery: Connection Manager tab")

        case 2:  ; Click Search
            if (A_TickCount - SystemState.recoveryStepTime > 500) {
                try {
                    ControlClick(BTN_SEARCH, CONNECTOR_WINDOW)
                }
                SystemState.recoveryPhase := 3
                SystemState.recoveryStepTime := A_TickCount
                LogStatus("Recovery: Searching...")
            }

        case 3:  ; Wait for device and click Connect
            if (A_TickCount - SystemState.recoveryStepTime > 2000) {
                try {
                    deviceText := ControlGetText("Edit1", CONNECTOR_WINDOW)
                    if (InStr(deviceText, "Quad") || InStr(deviceText, "Falcon")) {
                        LogStatus("Recovery: Device found - " . deviceText)
                        SystemState.recoveryPhase := 4
                        SystemState.recoveryStepTime := A_TickCount
                    }
                }
            }

        case 4:  ; Click Connect button
            if (A_TickCount - SystemState.recoveryStepTime > 1000) {
                TryClickConnect()
                SystemState.recoveryPhase := 5
                SystemState.recoveryStepTime := A_TickCount
                LogStatus("Recovery: Connecting...")
            }

        case 5:  ; Wait for green status (handled by SampleConnection)
            if (A_TickCount - SystemState.recoveryStepTime > 5000) {
                ; Go back to Shot Data tab and retry
                try {
                    ControlClick(TAB_SHOT_DATA, CONNECTOR_WINDOW)
                }
                ; Stay in recovery mode, SampleConnection will clear it when green
                SystemState.recoveryPhase := 3  ; Keep trying
                SystemState.recoveryStepTime := A_TickCount
                LogStatus("Recovery: Retrying...")
            }
    }
}

EndRecovery() {
    SystemState.isRecovering := false
    SystemState.recoveryPhase := 0

    ; Return to Shot Data tab and restore game window
    if WinExist(CONNECTOR_WINDOW) {
        try {
            ControlClick(TAB_SHOT_DATA, CONNECTOR_WINDOW)
        }
    }
    Sleep(200)
    if WinExist(GAME_WINDOW)
        WinActivate(GAME_WINDOW)

    ; Recovery ended, allow a fresh booking poll immediately.
    SetTimer(BookingPollTick, -300)

    LogStatus("Recovery ended")
}

TryClickConnect() {
    win := CONNECTOR_WINDOW
    btn := "WindowsForms10.BUTTON.app.0.13965fa_r6_ad18"

    if !WinExist(win)
        return false

    try {
        ControlClick(btn, win, , "Left", 1, "NA")
        return true
    } catch {
        return false
    }
}

; ##################################################################
; HELPER FUNCTIONS
; ##################################################################

RestartOverlay() {
    LogStatus("Restarting Overlay...")
    if WinExist(REPLICA_WINDOW)
        WinClose(REPLICA_WINDOW)
    Run(OVERLAY_BAT, "C:\SimGolf\sig-facility\scripts\gspro-automation")
    Sleep(1200)
    SetWindowHierarchy()
}

; ##################################################################
; ADDON & OVERLAY REPAIR
; ##################################################################

EnsureAddonWindow() {
    ; Skip during startup, recovery, restart, or ongoing repair
    if (SystemState.isRestarting || SystemState.isRecovering || SystemState.isRepairingAddon)
        return

    ; Only check if connector is present
    if (!SystemState.connectorPresent)
        return

    if WinExist(ADDON_WINDOW) {
        SystemState.addonMissingCount := 0
        return
    }

    SystemState.addonMissingCount++
    if (SystemState.addonMissingCount < 3)  ; ~6 seconds at 2s tick
        return

    SystemState.addonMissingCount := 0
    SystemState.isRepairingAddon := true
    LogStatus("Addon window missing - repairing...")

    ; Switch to Shot Data tab first (standard tab)
    try {
        ControlClick(TAB_SHOT_DATA, CONNECTOR_WINDOW)
    }

    ; Start non-blocking retry to open Visual Data
    SetTimer(AddonRepairTick, -1000)
}

AddonRepairTick() {
    static clickCount := 0

    if WinExist(ADDON_WINDOW) {
        clickCount := 0
        SystemState.isRepairingAddon := false
        LogStatus("Addon window restored")
        ; Restart overlay since it depends on addon
        RestartOverlay()
        return
    }

    if !WinExist(CONNECTOR_WINDOW) {
        clickCount := 0
        SystemState.isRepairingAddon := false
        LogStatus("Connector gone during addon repair")
        return
    }

    try {
        ControlClick("Open Visual Data", CONNECTOR_WINDOW)
    } catch as e {
        LogStatus("Addon repair click failed: " . e.Message)
    }

    clickCount++
    if (clickCount > 10) {
        clickCount := 0
        SystemState.isRepairingAddon := false
        LogStatus("Addon repair failed after retries")
        return
    }

    SetTimer(AddonRepairTick, -1000)
}

EnsureOverlayWindow() {
    ; Skip during startup, recovery, restart, or addon repair
    if (SystemState.isRestarting || SystemState.isRecovering || SystemState.isRepairingAddon)
        return

    ; Overlay depends on addon - don't check if addon isn't there
    if !WinExist(ADDON_WINDOW)
        return

    if WinExist(REPLICA_WINDOW) {
        SystemState.replicaMissingCount := 0
        return
    }

    SystemState.replicaMissingCount++
    if (SystemState.replicaMissingCount < 3)  ; ~6 seconds at 2s tick
        return

    SystemState.replicaMissingCount := 0
    LogStatus("Overlay missing - restarting...")
    RestartOverlay()
}

SetWindowHierarchy() {
    if !WinExist(GAME_WINDOW)
        return

    ; Ensure connector and addon are not always-on-top
    if WinExist(CONNECTOR_WINDOW) {
        WinSetAlwaysOnTop(0, CONNECTOR_WINDOW)
        WinMoveBottom(CONNECTOR_WINDOW)
    }
    if WinExist(ADDON_WINDOW) {
        WinSetAlwaysOnTop(0, ADDON_WINDOW)
        WinMoveBottom(ADDON_WINDOW)
    }

    ; Bring game window to front
    try WinActivate(GAME_WINDOW)
    Sleep(100)
    try WinMoveTop(GAME_WINDOW)

    ; Overlay should be always on top
    if WinExist(REPLICA_WINDOW)
        WinSetAlwaysOnTop(1, REPLICA_WINDOW)
}

EnsureFullscreen(winTitle) {
    try {
        style := WinGetStyle(winTitle)
        if (style & 0xC00000) {
            LogStatus("Fixing Fullscreen...")
            WinActivate(winTitle)
            Sleep(150)
            Send("{F11}")
        }
    }
}

GetPixelColorHidden(hwnd, x, y) {
    hdc := DllCall("GetDC", "Ptr", hwnd)
    hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdc)
    hbm := DllCall("CreateCompatibleBitmap", "Ptr", hdc, "Int", x+1, "Int", y+1)
    obj := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hbm)

    DllCall("PrintWindow", "Ptr", hwnd, "Ptr", hdcMem, "UInt", 2)
    color := DllCall("GetPixel", "Ptr", hdcMem, "Int", x, "Int", y, "UInt")

    DllCall("SelectObject", "Ptr", hdcMem, "Ptr", obj)
    DllCall("DeleteObject", "Ptr", hbm)
    DllCall("DeleteDC", "Ptr", hdcMem)
    DllCall("ReleaseDC", "Ptr", hwnd, "Ptr", hdc)

    return color
}

CleanupAndExit() {
    SetTimer(SignalSampleTick, 0)
    SetTimer(UIEnforcementTick, 0)
    SetTimer(BlinkEngineTick, 0)
    SetTimer(RecoveryTick, 0)
    SetTimer(BookingPollTick, 0)

    if OverlayMgr
        OverlayMgr.Cleanup()

    if (relayEnabled) {
        SetRelayRed()
        Sleep(100)
        CloseSerialPort(relayPort)
    }

    if WinExist(REPLICA_WINDOW)
        WinClose(REPLICA_WINDOW)
    ExitApp()
}

; ##################################################################
; BOOKING POLLING
; ##################################################################

InitBooking() {
    global bookingPollEnabled, bookingUrl

    matchiCourtId := ReadMatchiCourtId("C:\SimGolf\bay-identity.json", "C:\SimGolf\sig-facility\config\bays.json")
    if !matchiCourtId {
        LogStatus("Booking overlay disabled (missing matchiCourtId)")
        return
    }

    bookingUrl := "https://app.swedenindoorgolf.se/bookings/matchi-courts/" matchiCourtId "/show-message?debug=1"
    bookingPollEnabled := true
    LogStatus("Booking overlay enabled for court " . matchiCourtId)
}

BookingPollTick() {
    global bookingPollEnabled, bookingUrl

    if !bookingPollEnabled || !OverlayMgr
        return

    ; Always suppress during startup/recovery/restart to avoid UI interference.
    if OverlayMgr.IsStartupActive() || SystemState.isRecovering || SystemState.isRestarting
        return

    res := FetchBookingMessage(bookingUrl)
    if (res.status = 200 && res.body != "") {
        if !InStr(res.body, '"type"')
            LogStatus("Booking poll returned JSON without type field")
        OverlayMgr.ShowBookingMessage(res.body)
    }
}

FetchBookingMessage(url) {
    try {
        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        whr.Open("GET", url, false)
        whr.Send()
        return { status: whr.Status, body: whr.ResponseText }
    } catch {
        return { status: 0, body: "" }
    }
}

ReadMatchiCourtId(identityPath, baysPath) {
    if !FileExist(identityPath) || !FileExist(baysPath)
        return 0

    identityJson := FileRead(identityPath)
    if !RegExMatch(identityJson, '"bayId"\s*:\s*"(\w+)"', &m)
        return 0
    bayId := m[1]

    baysJson := FileRead(baysPath)
    if !RegExMatch(baysJson, '"' bayId '"\s*:\s*\{[^}]*"matchiCourtId"\s*:\s*(\d+)', &m2)
        return 0

    return m2[1]
}

; ##################################################################
; USB RELAY FUNCTIONS
; ##################################################################

InitializeRelay() {
    global relayPort, relayPortName

    LogStatus("Detecting USB relay via WMI...")

    ; Query WMI for COM port devices
    allPorts := []
    cp210xPorts := []

    try {
        wmi := ComObject("WbemScripting.SWbemLocator").ConnectServer(".", "root\cimv2")
        query := wmi.ExecQuery("SELECT * FROM Win32_PnPEntity WHERE Name LIKE '%(COM%)'")

        for device in query {
            name := device.Name
            if !name
                continue

            ; Extract COM port name from friendly name like "Silicon Labs CP210x (COM3)"
            if (RegExMatch(name, "\(COM\d+\)", &match)) {
                portName := SubStr(match[], 2, -1)  ; Remove parentheses
                allPorts.Push({port: portName, name: name})

                ; Check if this is a CP210x device
                if (InStr(name, "CP210x")) {
                    cp210xPorts.Push({port: portName, name: name})
                }
            }
        }

        ; Log all found COM ports
        if (allPorts.Length = 0) {
            LogStatus("WMI: No COM ports found")
        } else {
            LogStatus("WMI: Found " . allPorts.Length . " COM port(s)")
            for device in allPorts {
                LogStatus("  " . device.port . ": " . device.name)
            }
        }

    } catch as e {
        LogStatus("WMI query failed: " . e.Message)
        return false
    }

    if (cp210xPorts.Length = 0) {
        LogStatus("No CP210x devices in list!")
        return false
    }

    LogStatus("Found " . cp210xPorts.Length . " CP210x device(s)")

    ; Try to open each CP210x port
    for device in cp210xPorts {
        LogStatus("Trying " . device.port . "...")
        handle := OpenSerialPort(device.port)
        if (handle = -1) {
            LogStatus("  Failed to open port")
            continue
        }

        if SendRelayCommand(handle, "AT+CH1=0") {
            relayPort := handle
            relayPortName := device.port
            LogStatus("Relay connected on " . device.port)
            return true
        } else {
            LogStatus("  Failed to send command")
            CloseSerialPort(handle)
        }
    }

    LogStatus("Failed to connect to CP210x relay!")
    return false
}

OpenSerialPort(portName) {
    GENERIC_READ := 0x80000000
    GENERIC_WRITE := 0x40000000
    OPEN_EXISTING := 3

    handle := DllCall("CreateFile"
        , "Str", "\\.\" . portName
        , "UInt", GENERIC_READ | GENERIC_WRITE
        , "UInt", 0
        , "Ptr", 0
        , "UInt", OPEN_EXISTING
        , "UInt", 0
        , "Ptr", 0
        , "Ptr")

    if (handle = -1)
        return -1

    dcb := Buffer(28, 0)
    NumPut("UInt", 28, dcb, 0)

    if !DllCall("GetCommState", "Ptr", handle, "Ptr", dcb) {
        CloseSerialPort(handle)
        return -1
    }

    NumPut("UInt", 9600, dcb, 4)   ; BaudRate
    NumPut("UChar", 8, dcb, 18)    ; ByteSize
    NumPut("UChar", 0, dcb, 19)    ; Parity (None)
    NumPut("UChar", 0, dcb, 20)    ; StopBits (1)

    if !DllCall("SetCommState", "Ptr", handle, "Ptr", dcb) {
        CloseSerialPort(handle)
        return -1
    }

    timeouts := Buffer(20, 0)
    NumPut("UInt", 500, timeouts, 0)
    NumPut("UInt", 500, timeouts, 4)
    NumPut("UInt", 500, timeouts, 8)
    NumPut("UInt", 500, timeouts, 12)
    NumPut("UInt", 500, timeouts, 16)

    DllCall("SetCommTimeouts", "Ptr", handle, "Ptr", timeouts)

    return handle
}

CloseSerialPort(handle) {
    if (handle != -1 && handle != 0)
        DllCall("CloseHandle", "Ptr", handle)
}

SendRelayCommand(handle, cmd) {
    if (handle = -1 || handle = 0)
        return false

    cmdBytes := cmd . "`r`n"
    bytesWritten := 0

    result := DllCall("WriteFile"
        , "Ptr", handle
        , "AStr", cmdBytes
        , "UInt", StrLen(cmdBytes)
        , "UInt*", &bytesWritten
        , "Ptr", 0)

    return result && (bytesWritten > 0)
}

global lastRelayState := -1

SetRelayGreen() {
    global relayPort, lastRelayState, relayEnabled
    if (!relayEnabled)
        return true
    if (lastRelayState = 0)
        return true
    LogStatus("Relay -> GREEN (port:" . relayPort . ")", false)
    if SendRelayCommand(relayPort, "AT+CH1=1") {
        lastRelayState := 0
        return true
    }
    LogStatus("Relay GREEN failed!")
    return false
}

SetRelayRed() {
    global relayPort, lastRelayState, relayEnabled
    if (!relayEnabled)
        return true
    if (lastRelayState = 1)
        return true
    LogStatus("Relay -> RED (port:" . relayPort . ")", false)
    if SendRelayCommand(relayPort, "AT+CH1=0") {
        lastRelayState := 1
        return true
    }
    LogStatus("Relay RED failed!")
    return false
}
