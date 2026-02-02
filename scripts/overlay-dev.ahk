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

; --- Hotkeys ---
^+r:: mgr._startup._overlay.Reload()  ; Ctrl+Shift+R -- reload
^+x::
Escape:: {
    mgr.Cleanup()
    ExitApp()
}
