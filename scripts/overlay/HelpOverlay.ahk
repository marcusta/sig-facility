#Requires AutoHotkey v2.0

/**
 * HelpOverlay -- full help page overlay.
 * Transparent WebView2 background for semi-transparent backdrop.
 */
class HelpOverlay {
    _overlay := ""
    _overlayMgr := ""
    _open := false

    /**
     * @param {OverlayManager} overlayMgr  Parent manager
     */
    __New(overlayMgr) {
        this._overlayMgr := overlayMgr
    }

    /**
     * Show the help overlay.
     */
    Open() {
        if this._open
            return

        if !this._overlay {
            ov := Overlay()
            ; Full screen overlay for backdrop effect
            ov.Show("", {w: A_ScreenWidth, h: A_ScreenHeight, x: 0, y: 0})
            ov.OnMessage(ObjBindMethod(this, "_onMessage"))
            url := this._overlayMgr.GetPagesDir() . "help.html"
            ov.Navigate(url)
            this._overlay := ov
        } else {
            this._overlay.gui.Show()
        }
        this._open := true
    }

    /**
     * Hide the help overlay (keep WebView2 alive).
     */
    Close() {
        if !this._open
            return
        this._open := false
        if this._overlay
            this._overlay.Hide()
    }

    Toggle() {
        if this._open
            this.Close()
        else
            this.Open()
    }

    IsOpen() {
        return this._open
    }

    Destroy() {
        this._open := false
        if this._overlay {
            this._overlay.Destroy()
            this._overlay := ""
        }
    }

    ; --- internal ---

    _onMessage(msg) {
        if (msg = "help-close")
            this.Close()
    }
}
