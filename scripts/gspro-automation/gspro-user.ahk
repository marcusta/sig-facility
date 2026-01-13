WinActivate, GSPro
MouseMove, 545, 345
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

MouseMove, 545, 500
Click
Send ^a
Send, %value% 
Send, {Enter}