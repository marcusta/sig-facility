#Requires AutoHotkey v2.0

/**
 * HelpButton -- small "?" button overlay, always visible.
 * Fires onClicked callback when user clicks the button.
 * Supports alert pulsing via SetAlert().
 */
class HelpButton {
    _overlay := ""
    _overlayMgr := ""
    _onClicked := ""

    /**
     * @param {OverlayManager} overlayMgr  Parent manager
     * @param {Func}           onClicked   Callback when button is clicked
     */
    __New(overlayMgr, onClicked) {
        this._overlayMgr := overlayMgr
        this._onClicked := onClicked
    }

    /**
     * Show the help button overlay.
     */
    Show() {
        if this._overlay
            return

        ov := Overlay()
        ov.Show("", {w: 40, h: 40, x: 0, y: 1138, opacity: 230})
        ov.OnMessage(ObjBindMethod(this, "_onMessage"))
        url := this._overlayMgr.GetPagesDir() . "help-button.html"
        ov.Navigate(url)
        this._overlay := ov
    }

    /**
     * Set alert state (CSS pulsing).
     * @param {Boolean} active  true = pulsing red, false = normal
     */
    SetAlert(active) {
        if this._overlay
            this._overlay.ExecuteScript("setAlert(" . (active ? "true" : "false") . ")")
    }

    Destroy() {
        if this._overlay {
            this._overlay.Destroy()
            this._overlay := ""
        }
    }

    ; --- internal ---

    _onMessage(msg) {
        if (msg = "help-click" && this._onClicked)
            this._onClicked.Call()
    }
}
