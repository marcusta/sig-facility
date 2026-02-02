#Requires AutoHotkey v2.0
#SingleInstance Force

#Include "overlay\OverlayManager.ahk"

; --- Read bay ID (default BAY01 for dev) ---
bayId := "BAY01"
try {
    bayJson := FileRead("C:\SimGolf\bay-identity.json")
    if RegExMatch(bayJson, '"bayId"\s*:\s*"(\w+)"', &m)
        bayId := m[1]
}

mgr := OverlayManager(bayId)
mgr.ShowStartup()

; Auto-hide startup after 5s and show help button (for dev testing)
SetTimer(() {
    mgr.HideStartup()
    mgr.ShowHelpButton()
}, -5000)

; --- Hotkeys ---
^+r:: {
    ; Reload whichever overlay is active
    if mgr._helpOv.IsOpen() && mgr._helpOv._overlay
        mgr._helpOv._overlay.Reload()
    else if mgr._startup.IsActive() && mgr._startup._overlay
        mgr._startup._overlay.Reload()
}

^+a:: mgr.SetHelpAlert(true)   ; Ctrl+Shift+A -- test alert
^+s:: mgr.SetHelpAlert(false)  ; Ctrl+Shift+S -- clear alert

^+x::
Escape:: {
    mgr.Cleanup()
    ExitApp()
}
