#Persistent ; Keeps the script running
global opacity := 0  ; Startar opacitet vid 0 (helt transparent)

; Set the path to save the image
filePath := "C:\start\popup\dialog-image.jpg"

; Set a timer to run CheckAndDownloadImage every minute (60000 milliseconds)
SetTimer, CheckAndDownloadImage, 60000

CheckAndDownloadImage:
    ; Ensure the directory exists
    If FileExist(filePath) {
        FileDelete, %filePath%
    }
    psScriptPath := "C:\start\popup\download-file.ps1"  ; Modify this to your actual PowerShell script path
    RunWait, powershell.exe -ExecutionPolicy Bypass -File "%psScriptPath%", , Hide
 
    ; Check if the file exists after the batch script has run
    If FileExist(filePath) {
      InitGui()        
    }
return

InitGui() {
    global opacity := 0
    Gui, +AlwaysOnTop -SysMenu +Owner +LastFound -Caption ; Konfigurerar GUI
    Gui, Margin, 0, 0
    Gui, Add, Picture, x0 y0 w700 h400 gGuiClose, C:\start\popup\dialog-image.jpg
    WinSet, Transparent, 0
    Gui, Show, NoActivate w700 h400 x100 y300, Sweden Indoor Golf
    
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


GuiClose:
    Gui, Destroy  ; Destroy the GUI when closed
return
