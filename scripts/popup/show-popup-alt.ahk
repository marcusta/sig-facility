#Persistent
global opacity := 0  ; Startar opacitet vid 0 (helt transparent)
global lastDisplayedHour := -1  ; Sätter lastDisplayedHour till -1 för att säkerställa att GUI visas första gången

TimerLoop() {
    Sleep, 1000 * 60  * 15  ; Sleepar i 15 minuter
    minuteToCheck := 55
    while true {
        FormatTime, CurrentMinute, , mm
        FormatTime, CurrentHour, , HH
        if (CurrentMinute = minuteToCheck && CurrentHour != lastDisplayedHour) {
            ; check if the gui is already visible and only show it once per minute
            if !WinExist("ahk_class AutoHotkeyGUI") {
                lastDisplayedHour := CurrentHour
                InitGui()
            }
        }
        Sleep, 3000
    }
}

InitGui() {
    global opacity := 0
    Gui, +AlwaysOnTop -SysMenu +Owner +LastFound -Caption ; Konfigurerar GUI
    Gui, Margin, 0, 0
    Gui, Add, Picture, x0 y0 w600 h343 gGuiClose, C:\start\popup\sim-golf2-popup.png
    WinSet, Transparent, 0
    Gui, Show, NoActivate w600 h343 x100 y300, Sweden Indoor Golf
    
    IncreaseOpacity()
}

IncreaseOpacity() {
    global opacity
    opacity += 7  ; Ökar opaciteten med 10 vid varje tick
    if (opacity > 255) {
        opacity := 255  ; Säkerställer att opaciteten inte överstiger 255
        WinSet, Transparent, 255  ; Anpassar fönstrets opacitet    
        return
    }
    WinSet, Transparent, %opacity%  ; Anpassar fönstrets opacitet
    Sleep, 10
    IncreaseOpacity()  ; Anropar sig själv för att öka opaciteten
}

GuiClose() {
    Gui, Destroy
}

TimerLoop()  ; Anropar InitGui för att starta processen
