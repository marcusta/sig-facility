#Requires AutoHotkey v2.0

/**
 * StartupOverlay -- startup screen lifecycle.
 *
 * Shows a branded loading screen during GSPro boot sequence.
 * Calls onHidden callback when hidden so other overlays can take over.
 */
class StartupOverlay {
    _overlay := ""
    _overlayMgr := ""
    _onHidden := ""
    _active := false

    /**
     * @param {OverlayManager} overlayMgr  Parent manager (provides GetPagesDir)
     * @param {Func}           onHidden    Optional callback fired after Hide()
     */
    __New(overlayMgr, onHidden := "") {
        this._overlayMgr := overlayMgr
        this._onHidden := onHidden
    }

    /**
     * Create and show the startup overlay.
     * @param {String} bayId  e.g. "BAY03"
     */
    Show(bayId) {
        if this._active
            return

        ov := Overlay()
        url := this._overlayMgr.GetPagesDir() . "startup.html?bay=" . bayId
        ov.Show(url, {w: 1700, h: 1000, opacity: 216})
        this._overlay := ov
        this._active := true
    }

    /**
     * Destroy the startup overlay and fire onHidden callback.
     */
    Hide() {
        if !this._active
            return

        this._active := false
        if this._overlay {
            this._overlay.Destroy()
            this._overlay := ""
        }
        if this._onHidden
            this._onHidden.Call()
    }

    IsActive() {
        return this._active
    }

    Destroy() {
        this._active := false
        if this._overlay {
            this._overlay.Destroy()
            this._overlay := ""
        }
    }
}
