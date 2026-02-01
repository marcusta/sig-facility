#Requires AutoHotkey v2.0
Persistent

; --- Configuration ---
REPO_ROOT := "C:\SimGolf\sig-facility"
IDENTITY_PATH := "C:\SimGolf\bay-identity.json"
IMAGE_PATH := REPO_ROOT "\scripts\popup\dialog-image.jpg"
POLL_INTERVAL_MS := 60000

; Read bay identity and court ID at startup
matchiCourtId := ReadCourtId(IDENTITY_PATH, REPO_ROOT "\config\bays.json")
if !matchiCourtId {
    MsgBox("Failed to resolve matchiCourtId from bay identity / bays.json")
    ExitApp
}

downloadUrl := "https://app.swedenindoorgolf.se/bookings/matchi-courts/" matchiCourtId "/show-image"

; Poll every 60 seconds
SetTimer(CheckAndShow, POLL_INTERVAL_MS)
CheckAndShow()  ; run immediately on startup

CheckAndShow() {
    global downloadUrl, IMAGE_PATH

    ; Always delete old image first so a failed download means no file
    if FileExist(IMAGE_PATH)
        FileDelete(IMAGE_PATH)

    ; Download image via WinHTTP to inspect status code
    try {
        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        whr.Open("GET", downloadUrl, false)
        whr.Send()

        if whr.Status != 200
            return

        ; Write response body to file
        stream := ComObject("ADODB.Stream")
        stream.Type := 1  ; binary
        stream.Open()
        stream.Write(whr.ResponseBody)
        stream.SaveToFile(IMAGE_PATH, 2)  ; overwrite
        stream.Close()
    } catch {
        return
    }

    ; Verify download was 200, file exists, and has content
    if whr.Status != 200
        return
    if !FileExist(IMAGE_PATH)
        return
    if FileGetSize(IMAGE_PATH) < 100
        return

    ShowDialog(IMAGE_PATH)
}

ShowDialog(imagePath) {
    ; Destroy any previous dialog
    static dlg := false
    if dlg {
        dlg.Destroy()
        dlg := false
    }

    if !FileExist(imagePath)
        return

    dlg := Gui("+AlwaysOnTop -SysMenu +Owner -Caption")
    dlg.MarginX := 0
    dlg.MarginY := 0
    try
        dlg.AddPicture("x0 y0 w700 h400", imagePath)
    catch {
        dlg.Destroy()
        return
    }
    dlg.OnEvent("Close", (*) => dlg.Destroy())

    ; Click anywhere to dismiss
    dlg.OnEvent("Close", (*) => dlg.Destroy())
    clickHandler := ObjBindMethod(dlg, "Destroy")
    dlg.AddText("x0 y0 w700 h400 +0x201 BackgroundTrans", "")
        .OnEvent("Click", (*) => dlg.Destroy())

    WinSetTransparent(0, dlg)
    dlg.Show("NoActivate w700 h400 x100 y300")
    dlg.Title := "Sweden Indoor Golf"

    ; Fade in
    opacity := 0
    loop {
        opacity += 7
        if opacity > 255
            opacity := 255
        try WinSetTransparent(opacity, dlg)
        catch
            return
        if opacity >= 255
            break
        Sleep(10)
    }
}

ReadCourtId(identityPath, baysPath) {
    if !FileExist(identityPath) || !FileExist(baysPath)
        return 0

    ; Read bay identity
    identityJson := FileRead(identityPath)
    if !RegExMatch(identityJson, '"bayId"\s*:\s*"(\w+)"', &m)
        return 0
    bayId := m[1]

    ; Read bays.json and find the matchiCourtId for this bay
    baysJson := FileRead(baysPath)

    ; Find the section for this bay and extract matchiCourtId
    ; Pattern: "BAYxx": { ... "matchiCourtId": NNN ... }
    if !RegExMatch(baysJson, '"' bayId '"\s*:\s*\{[^}]*"matchiCourtId"\s*:\s*(\d+)', &m2)
        return 0

    return m2[1]
}
