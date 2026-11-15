CoordMode, Mouse, Screen
WinActivate, ahk_exe GSPro.exe
WinWaitActive, ahk_exe GSPro.exe
; GSPro v4 Player Name field (fullscreen screen coordinates).
MouseMove, 1513, 354
Click
Send ^a
Send ^c
ClipWait
UserName := clipboard
Url := "https://simple-sgt.fly.dev/uid/" UserName
whr := ComObjCreate("WinHttp.WinHttpRequest.5.1")
whr.Open("GET", Url, true)
whr.Send()
; Using 'true' above and the call below allows the script to remain responsive.
whr.WaitForResponse()
value := whr.ResponseText

; GSPro v4 SGT UID field (fullscreen screen coordinates).
MouseMove, 1508, 464
Click
Send ^a
Send, %value% 
Send, {Enter}