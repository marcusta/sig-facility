#Requires AutoHotkey v2.0
#SingleInstance Force

; ##################################################################
; CONFIGURATION
; ##################################################################

global GSP_PATH      := "C:\GSProV1\Core\GSP\GSPro.exe"
global SETTINGS_BAT  := "C:\start\copy_gspro_settings.bat"
global OVERLAY_BAT   := "C:\start\start-overlay.bat"

global GAME_WINDOW      := "ahk_exe GSPro.exe"
global CONNECTOR_WINDOW := "GSPro x Foresight"
global ADDON_WINDOW     := "Advanced Connect Add On"
global REPLICA_WINDOW   := "OnTopReplica"

; Koordinater (Relativa till Connector-fönstret)
global TAB_CONN_MGR := "x280 y40"  ; Mitten på "Connection Manager"-fliken
global TAB_SHOT_DATA := "x90 y40"   ; Mitten på "Shot Data"-fliken
global BTN_SEARCH    := "x140 y230" ; Mitten på "Search"-knappen
global BTN_CONNECT    := "x380 y230" ;

global STATUS_X := 700
global STATUS_Y := 35

global CONNECTOR_WINDOW := "ahk_exe GSPconnect.exe"  ; recommended: target by exe

; Pixel on the top bar (client coords in the connector window)
global LINKBAR_X := 322
global LINKBAR_Y := 35  ; use 2 instead of 1 to avoid border quirks

global linkWasStable := false

; Exakta färger i BGR-format (eftersom vi använder GetPixel DLL)
global BGR_RED   := 0x00008B
global BGR_GREEN := 0x008000

; Ball tracking (Ready/Not Ready label) - BGR format
global BGR_READY_GREEN := 0x008000  ; #008000 in RGB
global BGR_READY_RED   := 0x00008B  ; #8B0000 in RGB (dark red)

; Ball tracking pixel location (client coords in connector window)
global BALL_TRACKED_X := 1051
global BALL_TRACKED_Y := 624

global connectionWasStable := false
global ballWasTracked := false

; ##################################################################
; USB RELAY CONFIGURATION
; ##################################################################

global relayPort := 0  ; Will hold the file handle
global relayPortName := ""  ; Will hold COM port name like "COM3"
global currentRelayState := -1  ; -1=unknown, 0=green, 1=red

global CONNECTOR_EXE_PATH := "C:\GSProV1\Core\GSPC\GSPconnect.exe"

; How long the connector window is allowed to be missing before restart (ms)
global CONNECTOR_MISSING_TIMEOUT_MS := 8000

global connectorMissingSince := 0
global connectorRestarting   := false

; ##################################################################
; DEBUG OVERLAY SETUP
; ##################################################################

global debugExpanded := true
global debugCollapseTimer := 0
global DEBUG_COLLAPSE_DELAY := 5000  ; Collapse after 5 seconds of stability

DebugGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
DebugGui.BackColor := "000000"
DebugGui.SetFont("s10 cGreen", "Consolas")
DebugText := DebugGui.Add("Text", "w300 h60", "Initializing...")
DebugGui.Show("x10 y10 NoActivate")

ExpandDebugOverlay() {
    global debugExpanded, debugCollapseTimer, DebugGui, DebugText

    if (debugExpanded)
        return

    debugExpanded := true
    debugCollapseTimer := 0

    DebugText.Visible := true
    DebugGui.Show("x10 y10 w308 h68 NoActivate")
}

CollapseDebugOverlay() {
    global debugExpanded, DebugGui, DebugText

    if (!debugExpanded)
        return

    debugExpanded := false
    DebugText.Visible := false
    DebugGui.Show("x10 y10 w16 h16 NoActivate")
}

LogStatus(msg) {
    global debugCollapseTimer

    ; Always expand when logging
    ExpandDebugOverlay()

    ; Reset collapse timer
    debugCollapseTimer := A_TickCount

    try {
        current := DebugText.Value
        lines := StrSplit(current, "`n")
        if (lines.Length >= 3)
            lines.RemoveAt(1)
        lines.Push(FormatTime(, "HH:mm:ss") . ": " . msg)
        DebugText.Value := ""
        for line in lines
            DebugText.Value .= (A_Index > 1 ? "`n" : "") . line
    }
}

UpdateDebugOverlayState() {
    global debugExpanded, debugCollapseTimer, DEBUG_COLLAPSE_DELAY
    global connectionWasStable, linkWasStable, connectorRestarting

    ; Don't collapse during restart
    if (connectorRestarting)
        return

    ; Don't collapse if not stable
    if (!connectionWasStable || !linkWasStable)
        return

    ; Collapse if stable for long enough
    if (debugExpanded && debugCollapseTimer > 0) {
        if (A_TickCount - debugCollapseTimer > DEBUG_COLLAPSE_DELAY) {
            CollapseDebugOverlay()
        }
    }
}

; ##################################################################
; STARTUP
; ##################################################################

LogStatus("Starting System...")
InitializeRelay()
InitializeSystem()

InitializeSystem() {
    RunWait(SETTINGS_BAT, , "Hide")
    Run(GSP_PATH)
    
    LogStatus("Waiting for Connector...")
    if WinWait(CONNECTOR_WINDOW, , 30) {
        WinActivate(CONNECTOR_WINDOW)
        Sleep(1000)
        
        LogStatus("Opening Visual Data...")
        Loop 10 {
            if !WinExist(GAME_WINDOW)
                ExitApp()
            try {
                ControlClick("Open Visual Data", CONNECTOR_WINDOW)
            } catch {
                ; Control not ready yet, will retry
            }
            if WinWait(ADDON_WINDOW, , 3)
                break
            Sleep(1000)
        }
    }



    Run(OVERLAY_BAT, "C:\start")
    LogStatus("System Ready - Monitoring")
    SetWindowHierarchy()
}

; ##################################################################
; MAIN WATCHDOG LOOP
; ##################################################################

Loop {
    if !WinExist(GAME_WINDOW) {
        LogStatus("GSPro Closed - Exiting...")
        CleanupAndExit()
    }

    MonitorConnectorPresence()  ; restarts if window is gone
    MonitorGsproLinkBar()       ; restarts if bar goes red
    MonitorConnection()         ; your existing USB/WiFi device status logic
    MonitorBallTracking()       ; Ready/Not Ready label -> USB relay

    EnsureFullscreen(GAME_WINDOW)
    UpdateDebugOverlayState()   ; collapse overlay when stable
    Sleep(2000)
}

; ##################################################################
; FUNCTIONS
; ##################################################################

OpenVisualDataFromConnector() {
    if !WinExist(CONNECTOR_WINDOW)
        return false

    WinActivate(CONNECTOR_WINDOW)
    Sleep(800)

    LogStatus("Opening Visual Data...")
    Loop 10 {
        if !WinExist(GAME_WINDOW)
            CleanupAndExit()

        ; Click menu item/button inside the Connector window
        try {
            ControlClick("Open Visual Data", CONNECTOR_WINDOW)
        } catch {
            ; Control not ready yet, will retry
        }

        if WinWait(ADDON_WINDOW, , 3)
            return true

        Sleep(1000)
    }
    return false
}

RestartOverlay() {
    LogStatus("Restarting Overlay...")

    ; Close any existing overlay window (OnTopReplica)
    if WinExist(REPLICA_WINDOW)
        WinClose(REPLICA_WINDOW)

    ; Start it again
    Run(OVERLAY_BAT, "C:\start")

    ; Give it a moment to show, then re-assert hierarchy
    Sleep(1200)
    SetWindowHierarchy()
}

MonitorGsproLinkBar() {
    global linkWasStable

    hwnd := WinExist(CONNECTOR_WINDOW)
    if !hwnd
        return

    barColor := GetPixelColorHidden(hwnd, LINKBAR_X, LINKBAR_Y)

    if (barColor = BGR_GREEN) {
        if (!linkWasStable) {
            LogStatus("GSPro link bar: GRÖN (stabil)")
            linkWasStable := true
        }
        return
    }

    if (barColor = BGR_RED) {
        if (linkWasStable) {
            LogStatus("GSPro link bar: RÖD! Restartar connector...")
            linkWasStable := false
            RestartConnector()   ; your existing “missing window” restart path
        } else {
            ; startup case: red before first green is allowed
            LogStatus("GSPro link bar: initial röd (väntar på första grön)")
        }
    }
}

MonitorConnection() {
    global connectionWasStable
    
    hwnd := WinExist(CONNECTOR_WINDOW)
    if !hwnd
        return

    color := GetPixelColorHidden(hwnd, STATUS_X, STATUS_Y)

    if (color == BGR_GREEN) {
        if (!connectionWasStable) {
            LogStatus("Status: GRÖN (Stabil)")
            connectionWasStable := true
        }
    } 
    else if (color == BGR_RED) {
        if (connectionWasStable) {
            LogStatus("Status: RÖD! Startar Recovery...")
            RecoverConnection()
        } else {
            LogStatus("Initial röd (väntar på första anslutning)")
        }
    }
}

RecoverConnection() {
    global connectionWasStable
    
    if !WinExist(GAME_WINDOW)
        CleanupAndExit()

    WinActivate(CONNECTOR_WINDOW)
    Sleep(500)
    
    LogStatus("Går till Connection Manager...")
    ControlClick(TAB_CONN_MGR, CONNECTOR_WINDOW)
    Sleep(500)
    
    LogStatus("Klickar SEARCH...")
    ControlClick(BTN_SEARCH, CONNECTOR_WINDOW)
    
    startTime := A_TickCount
    Loop {
        if !WinExist(GAME_WINDOW)
            CleanupAndExit()
            
        ; 1. Kontrollera om enhet hittats i Edit-boxen
        try {
            Sleep(2000)
            deviceText := ControlGetText("Edit1", CONNECTOR_WINDOW)
            if (InStr(deviceText, "Quad") || InStr(deviceText, "Falcon")) {
                LogStatus("Enhet hittad: " . deviceText . " -> CONNECT")
                Sleep(6000)
                LogStatus("Försöker klicka Connect")
                TryClickConnect()
                LogStatus("Har klickat Connect")
                Sleep(4000) ; Ge den tid att reagera
            }
        }

        ; 2. Kontrollera om vi blivit gröna
        hwnd := WinExist(CONNECTOR_WINDOW)
        if (GetPixelColorHidden(hwnd, STATUS_X, STATUS_Y) == BGR_GREEN) {
            LogStatus("Återansluten!")
            break
        }

        if (A_TickCount - startTime > 45000) { ; 45 sek timeout
            LogStatus("Recovery Timeout - Försöker igen...")
            break
        }
        
        Sleep(2000)
    }
    
    LogStatus("Återgår till Shot Data...")
    ControlClick(TAB_SHOT_DATA, CONNECTOR_WINDOW)
    Sleep(300)
    
    if WinExist(GAME_WINDOW)
        WinActivate(GAME_WINDOW)
}

TryClickConnect() {
    win := CONNECTOR_WINDOW
    btn := "WindowsForms10.BUTTON.app.0.13965fa_r6_ad18"

    if !WinExist(win)
        return false

    WinActivate(win)
    Sleep(100)

    ; optional: ensure it’s enabled (if disabled, clicking does nothing)
    try {
        if !ControlGetEnabled(btn, win) {
            LogStatus("Connect button is disabled")
            return false
        }
    } catch as e {
        ; ControlGetEnabled can throw if control not found yet
        LogStatus("Connect enabled-check failed: " e.Message)
    }

    try {
        ControlFocus(btn, win)
    } catch {
        ; not fatal
    }

    ; ControlClick on WinForms buttons usually sends the right messages
    try {
        ControlClick(btn, win, , "Left", 1, "NA")
        return true
    } catch as e {
        LogStatus("ControlClick(Connect) failed: " e.Message)
        return false
    }
}

MonitorConnectorPresence() {
    global connectorMissingSince

    if WinExist(CONNECTOR_WINDOW) {
        connectorMissingSince := 0
        return
    }

    ; connector window not found
    if (connectorMissingSince = 0) {
        connectorMissingSince := A_TickCount
        LogStatus("Connector window missing (starting timer)")
        return
    }

    if (A_TickCount - connectorMissingSince > CONNECTOR_MISSING_TIMEOUT_MS) {
        connectorMissingSince := 0
        RestartConnector()
    }
}

RestartConnector(reason := "") {
    global connectionWasStable, connectorRestarting, linkWasStable, connectorMissingSince, ballWasTracked

    if connectorRestarting
        return

    connectorRestarting := true
    connectionWasStable := false
    linkWasStable := false
    ballWasTracked := false
    connectorMissingSince := 0

    ; Set relay to red during restart
    SetRelayRed()

    if (reason != "")
        LogStatus("Restarting connector: " reason)
    else
        LogStatus("Restarting connector...")

    ; Close addon window if it exists (it’s tied to connector visual data)
    if WinExist(ADDON_WINDOW)
        WinClose(ADDON_WINDOW)

    ; Kill any orphan connector process
    if (pid := ProcessExist("GSPconnect.exe"))
        ProcessClose(pid)

    Sleep(800)

    ; Start connector
    Run(CONNECTOR_EXE_PATH)

    LogStatus("Waiting for Connector window...")
    if !WinWait(CONNECTOR_WINDOW, , 30) {
        LogStatus("Connector failed to appear (timeout)")
        connectorRestarting := false
        return
    }

    WinActivate(CONNECTOR_WINDOW)
    Sleep(1000)

    ; Re-open visual data
    if !OpenVisualDataFromConnector() {
        LogStatus("Failed to open Visual Data after restart")
        ; still continue — connection monitor may recover later
    }

    ; Restart overlay too
    RestartOverlay()

    LogStatus("Connector restart sequence done")
    connectorRestarting := false
}


GetPixelColorHidden(hwnd, x, y) {
    ; Skapa en minnes-yta att rita fönstret på
    hdc := DllCall("GetDC", "Ptr", hwnd)
    hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdc)
    hbm := DllCall("CreateCompatibleBitmap", "Ptr", hdc, "Int", x+1, "Int", y+1)
    obj := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hbm)
    
    ; Be fönstret rita sig själv i vår dolda yta
    DllCall("PrintWindow", "Ptr", hwnd, "Ptr", hdcMem, "UInt", 2) ; 2 = PW_RENDERFULLCONTENT
    
    ; Hämta färgen på den specifika punkten
    color := DllCall("GetPixel", "Ptr", hdcMem, "Int", x, "Int", y, "UInt")
    
    ; Städa upp i minnet
    DllCall("SelectObject", "Ptr", hdcMem, "Ptr", obj)
    DllCall("DeleteObject", "Ptr", hbm)
    DllCall("DeleteDC", "Ptr", hdcMem)
    DllCall("ReleaseDC", "Ptr", hwnd, "Ptr", hdc)
    
    return color ; Returnerar BGR
}

CleanupAndExit() {
    global relayPort

    ; Close the relay (set to red) and release port
    SetRelayRed()
    Sleep(100)
    CloseSerialPort(relayPort)

    if WinExist(REPLICA_WINDOW)
        WinClose(REPLICA_WINDOW)
    ExitApp()
}

SetWindowHierarchy() {
    ; Only called during startup and after restarts - not continuously
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
    WinActivate(GAME_WINDOW)
    Sleep(100)
    WinMoveTop(GAME_WINDOW)

    ; Overlay should be always on top
    if WinExist(REPLICA_WINDOW)
        WinSetAlwaysOnTop(1, REPLICA_WINDOW)
}

EnsureFullscreen(winTitle) {
    try {
        style := WinGetStyle(winTitle)
        if (style & 0xC00000) { ; Har titlebar?
            LogStatus("Fixing Fullscreen...")
            WinActivate(winTitle)
            Sleep(150)
            Send("{F11}")
        }
    }
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
    ; Open COM port using CreateFile
    GENERIC_READ := 0x80000000
    GENERIC_WRITE := 0x40000000
    OPEN_EXISTING := 3

    handle := DllCall("CreateFile"
        , "Str", "\\.\" . portName
        , "UInt", GENERIC_READ | GENERIC_WRITE
        , "UInt", 0  ; No sharing
        , "Ptr", 0   ; No security attributes
        , "UInt", OPEN_EXISTING
        , "UInt", 0  ; No flags
        , "Ptr", 0   ; No template
        , "Ptr")

    if (handle = -1)
        return -1

    ; Configure port: 9600 baud, 8N1
    dcb := Buffer(28, 0)
    NumPut("UInt", 28, dcb, 0)  ; DCBlength

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

    ; Set timeouts
    timeouts := Buffer(20, 0)
    NumPut("UInt", 500, timeouts, 0)   ; ReadIntervalTimeout
    NumPut("UInt", 500, timeouts, 4)   ; ReadTotalTimeoutMultiplier
    NumPut("UInt", 500, timeouts, 8)   ; ReadTotalTimeoutConstant
    NumPut("UInt", 500, timeouts, 12)  ; WriteTotalTimeoutMultiplier
    NumPut("UInt", 500, timeouts, 16)  ; WriteTotalTimeoutConstant

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

    ; Add CRLF to command
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

SetRelayGreen() {
    global relayPort, currentRelayState

    if (currentRelayState = 0)  ; Already green
        return true

    if SendRelayCommand(relayPort, "AT+CH1=1") {
        currentRelayState := 0
        return true
    }
    return false
}

SetRelayRed() {
    global relayPort, currentRelayState

    if (currentRelayState = 1)  ; Already red
        return true

    if SendRelayCommand(relayPort, "AT+CH1=0") {
        currentRelayState := 1
        return true
    }
    return false
}

; ##################################################################
; BALL TRACKING MONITOR
; ##################################################################

MonitorBallTracking() {
    global ballWasTracked, connectionWasStable

    hwnd := WinExist(CONNECTOR_WINDOW)
    if !hwnd {
        ; No connector window - set red
        if (ballWasTracked) {
            SetRelayRed()
            ballWasTracked := false
        }
        return
    }

    ; Only check ball tracking if connection is stable
    if (!connectionWasStable) {
        SetRelayRed()
        return
    }

    color := GetPixelColorHidden(hwnd, BALL_TRACKED_X, BALL_TRACKED_Y)

    if (color = BGR_READY_GREEN) {
        if (!ballWasTracked) {
            LogStatus("Ball: READY (Green)")
            ballWasTracked := true
            SetRelayGreen()
        }
    }
    else if (color = BGR_READY_RED) {
        if (ballWasTracked) {
            LogStatus("Ball: NOT READY (Red)")
            ballWasTracked := false
            SetRelayRed()
        }
    }
}