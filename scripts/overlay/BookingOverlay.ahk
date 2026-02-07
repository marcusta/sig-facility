#Requires AutoHotkey v2.0

/**
 * BookingOverlay -- booking message overlay (WebView2).
 * Driven by JSON payload from bookings service.
 *
 * Rules:
 *   - Show on HTTP 200 from server
 *   - Only close on explicit user click
 *   - Replace content if already shown and new poll returns data
 *
 * On first show the page loads async, so the setMessage() call is
 * deferred until the page sends a "booking-ready" postMessage.
 */
class BookingOverlay {
    _overlay := ""
    _overlayMgr := ""
    _open := false
    _pendingScript := ""

    __New(overlayMgr) {
        this._overlayMgr := overlayMgr
    }

    ShowMessage(jsonBody) {
        ; Pass raw JSON to JS for parsing -- escape for single-quoted JS string
        escaped := StrReplace(jsonBody, "\", "\\")
        escaped := StrReplace(escaped, "'", "\'")
        escaped := StrReplace(escaped, "`r", "")
        escaped := StrReplace(escaped, "`n", "\n")
        script := "setMessage('" . escaped . "')"

        if !this._overlay {
            ov := Overlay()
            ov.Show("", {w: 1200, h: 840, x: 60, y: 120, cornerRadius: 18})
            ov.OnMessage(ObjBindMethod(this, "_onMessage"))
            url := this._overlayMgr.GetPagesDir() . "booking.html"
            ov.Navigate(url)
            this._overlay := ov
            ; Page not loaded yet -- defer script until "booking-ready"
            this._pendingScript := script
        } else if !this._overlay.IsVisible {
            this._overlay.Show("")
            this._overlay.ExecuteScript(script)
        } else {
            ; Already visible -- replace content
            this._overlay.ExecuteScript(script)
        }
        this._open := true
    }

    Hide() {
        if this._overlay
            this._overlay.Hide()
        this._open := false
    }

    Destroy() {
        this._open := false
        this._pendingScript := ""
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
        if (msg = "booking-close") {
            this.Hide()
        } else if (msg = "booking-ready") {
            if (this._pendingScript != "") {
                this._overlay.ExecuteScript(this._pendingScript)
                this._pendingScript := ""
            }
        }
    }

}
