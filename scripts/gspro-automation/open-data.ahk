WinWait, GSPro x Foresight ; Wait for the window to appear
WinActivate, GSPro x Foresight
;; ControlClick, x1059 y182, GSPro x Foresight, , , , , , , Text, Open Visual Data
CoordMode, Mouse, Window
Click, 291, 74
ControlGetText, buttonText, WindowsForms10.BUTTON.app.0.13965fa_r7_ad13, GSPro x Foresight

; Display the text in a message box or use it as needed

if (buttonText = "Enable club Data") 
    {
        ; Click the button
        Click, 957, 170  
    }


Click, 104, 74