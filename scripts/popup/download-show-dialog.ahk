#Requires AutoHotkey v2.0
#Include "..\overlay\Overlay.ahk"
Persistent

; --- Configuration ---
REPO_ROOT := "C:\SimGolf\sig-facility"
IDENTITY_PATH := "C:\SimGolf\bay-identity.json"
POLL_INTERVAL_MS := 60000
OVERLAY_W := 980
OVERLAY_H := 520
OVERLAY_X := 100
OVERLAY_Y := 300

; Read bay identity and court ID at startup
matchiCourtId := ReadCourtId(IDENTITY_PATH, REPO_ROOT "\config\bays.json")
if !matchiCourtId {
    MsgBox("Failed to resolve matchiCourtId from bay identity / bays.json")
    ExitApp
}

downloadUrl := "https://app.swedenindoorgolf.se/bookings/matchi-courts/" matchiCourtId "/show-message"

global bookingOverlay := ""
global bookingOverlayUrl := BuildBookingPageUrl()

; Poll every 60 seconds
SetTimer(CheckAndShow, POLL_INTERVAL_MS)
CheckAndShow()  ; run immediately on startup

CheckAndShow() {
    global downloadUrl
    res := FetchMessage(downloadUrl)

    if (res.status = 200 && res.body != "")
        ShowMessage(res.body)
    else
        HideMessage()
}

FetchMessage(url) {
    try {
        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        whr.Open("GET", url, false)
        whr.Send()
        return { status: whr.Status, body: whr.ResponseText }
    } catch {
        return { status: 0, body: "" }
    }
}

ShowMessage(jsonBody) {
    global bookingOverlay, bookingOverlayUrl

    msg := ParseMessage(jsonBody)
    if !msg.type
        return

    if !bookingOverlay {
        bookingOverlay := Overlay()
        bookingOverlay.Show("", {w: OVERLAY_W, h: OVERLAY_H, x: OVERLAY_X, y: OVERLAY_Y})
        bookingOverlay.OnMessage(Func("_OnBookingMessage"))
        bookingOverlay.Navigate(bookingOverlayUrl)
    } else if !bookingOverlay.IsVisible {
        bookingOverlay.Show(bookingOverlayUrl)
    }

    script := "setMessage(" . _
        JsStr(msg.type) . "," . _
        JsStr(msg.customerName) . "," . _
        JsStr(msg.startTime) . "," . _
        JsStr(msg.endTime) . "," . _
        JsStr(msg.level) . "," . _
        JsStr(msg.courseSuggestion) . ")"
    bookingOverlay.ExecuteScript(script)
}

HideMessage() {
    global bookingOverlay
    if bookingOverlay
        bookingOverlay.Hide()
}

_OnBookingMessage(msg) {
    if (msg = "booking-close")
        HideMessage()
}

BuildBookingPageUrl() {
    pagesDir := RegExReplace(A_ScriptDir, "\\popup$", "\\overlay\\pages\\")
    pagesDir := StrReplace(pagesDir, "\", "/")
    return "file:///" . pagesDir . "booking.html"
}

ParseMessage(jsonBody) {
    msg := {}
    msg.type := JsonStringValue(jsonBody, "type")
    msg.customerName := JsonStringValue(jsonBody, "customerName")
    msg.startTime := JsonStringValue(jsonBody, "startTime")
    msg.endTime := JsonStringValue(jsonBody, "endTime")
    msg.level := JsonStringValue(jsonBody, "level")
    msg.courseSuggestion := JsonStringValue(jsonBody, "courseSuggestion")
    return msg
}

JsonStringValue(jsonBody, key) {
    if RegExMatch(jsonBody, '"' key '"\s*:\s*"((?:\\.|[^"])*)"', &m)
        return UnescapeJson(m[1])
    return ""
}

UnescapeJson(s) {
    s := StrReplace(s, "\/", "/")
    s := StrReplace(s, "\r", "`r")
    s := StrReplace(s, "\n", "`n")
    s := StrReplace(s, "\\\"", """")
    s := StrReplace(s, "\\", "\")
    return s
}

JsStr(s) {
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, "`r", "")
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, """", "\""")
    return """" . s . """"
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
