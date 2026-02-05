#Requires AutoHotkey v2.0

/**
 * BookingOverlay -- booking message overlay (WebView2).
 * Driven by JSON payload from bookings service.
 */
class BookingOverlay {
    _overlay := ""
    _overlayMgr := ""
    _open := false

    __New(overlayMgr) {
        this._overlayMgr := overlayMgr
    }

    ShowMessage(jsonBody) {
        msg := this._parseMessage(jsonBody)
        if !msg.type
            return

        if !this._overlay {
            ov := Overlay()
            ov.Show("", {w: 1200, h: 840, x: 60, y: 120})
            ov.OnMessage(ObjBindMethod(this, "_onMessage"))
            url := this._overlayMgr.GetPagesDir() . "booking.html"
            ov.Navigate(url)
            this._overlay := ov
        } else if !this._overlay.IsVisible {
            this._overlay.Show()
        }

        script := "setMessage(" .
            this._jsStr(msg.type) . "," .
            this._jsStr(msg.customerName) . "," .
            this._jsStr(msg.startTime) . "," .
            this._jsStr(msg.endTime) . "," .
            this._jsStr(msg.level) . "," .
            this._jsStr(msg.courseSuggestion) . ")"
        this._overlay.ExecuteScript(script)
        this._open := true
    }

    Hide() {
        if this._overlay
            this._overlay.Hide()
        this._open := false
    }

    Destroy() {
        this._open := false
        if this._overlay {
            this._overlay.Destroy()
            this._overlay := ""
        }
    }

    IsOpen() {
        return this._open
    }

    ; --- internal ---

    _onMessage(msg) {
        if (msg = "booking-close")
            this.Hide()
    }

    _parseMessage(jsonBody) {
        msg := {}
        msg.type := this._jsonStringValue(jsonBody, "type")
        msg.customerName := this._jsonStringValue(jsonBody, "customerName")
        msg.startTime := this._jsonStringValue(jsonBody, "startTime")
        msg.endTime := this._jsonStringValue(jsonBody, "endTime")
        msg.level := this._jsonStringValue(jsonBody, "level")
        msg.courseSuggestion := this._jsonStringValue(jsonBody, "courseSuggestion")
        return msg
    }

    _jsonStringValue(jsonBody, key) {
        if RegExMatch(jsonBody, '"' key '"\s*:\s*"((?:\\.|[^"])*)"', &m)
            return this._unescapeJson(m[1])
        return ""
    }

    _unescapeJson(s) {
        s := StrReplace(s, "\/", "/")
        s := StrReplace(s, "\r", "`r")
        s := StrReplace(s, "\n", "`n")
        s := StrReplace(s, '\"', '"')
        s := StrReplace(s, "\\", "\")
        return s
    }

    _jsStr(s) {
        s := StrReplace(s, "\", "\\")
        s := StrReplace(s, "`r", "")
        s := StrReplace(s, "`n", "\n")
        s := StrReplace(s, '"', '\"')
        return '"' . s . '"'
    }
}
