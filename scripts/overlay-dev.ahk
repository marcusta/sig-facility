#Requires AutoHotkey v2.0
#SingleInstance Force

#Include "overlay\Overlay.ahk"

; --- Config ---
overlayDir := A_ScriptDir "\overlay\pages"
defaultPage := overlayDir "\test.html"

; Accept CLI arg for HTML file path
htmlPath := A_Args.Length ? A_Args[1] : defaultPage
if !FileExist(htmlPath) {
    MsgBox("File not found: " htmlPath)
    ExitApp
}

; Convert to file:/// URL
fileUrl := "file:///" StrReplace(htmlPath, "\", "/")

; --- Create wnd ---
wnd := Overlay()
wnd.Show(fileUrl, {w: 800, h: 600})

; --- Hotkeys ---
^+r:: wnd.Reload()                                              ; Ctrl+Shift+R — reload

^+1:: wnd.Navigate("file:///" StrReplace(overlayDir "\test.html", "\", "/"))   ; test page
^+2:: {                                                              ; placeholder boot page
    wnd.Navigate("file:///" StrReplace(overlayDir "\test.html", "\", "/"))
}
^+3:: {                                                              ; placeholder help page
    wnd.Navigate("file:///" StrReplace(overlayDir "\test.html", "\", "/"))
}

Escape:: {
    wnd.Destroy()
    ExitApp
}
