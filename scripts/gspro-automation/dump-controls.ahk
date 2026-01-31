#Requires AutoHotkey v2.0
#SingleInstance Force

win := "ahk_exe GSPconnect.exe"

if !WinExist(win) {
    MsgBox("GSPconnect.exe not found")
    ExitApp()
}

output := "Controls in GSPconnect.exe`n"
output .= "================================`n`n"

controls := WinGetControls(win)

for classNN in controls {
    text := ""
    try {
        text := ControlGetText(classNN, win)
    } catch {
        text := "<unreadable>"
    }

    ; Truncate long text
    if (StrLen(text) > 80)
        text := SubStr(text, 1, 80) . "..."

    ; Only show controls that have text (skip empty ones)
    if (text != "" && text != "<unreadable>")
        output .= classNN . " = " . text . "`n"
}

output .= "`n================================`n"
output .= "Total controls: " . controls.Length

; Write to file and open it
FileDelete("C:\SimGolf\control-dump.txt")
FileAppend(output, "C:\SimGolf\control-dump.txt")
Run("notepad.exe C:\SimGolf\control-dump.txt")
