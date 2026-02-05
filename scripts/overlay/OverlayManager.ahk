#Requires AutoHotkey v2.0
#Include "Overlay.ahk"
#Include "StartupOverlay.ahk"
#Include "HelpButton.ahk"
#Include "HelpOverlay.ahk"
#Include "BookingOverlay.ahk"

/**
 * OverlayManager -- registry of overlays, z-order, cleanup.
 *
 * The main script (#Includes this file) and calls high-level methods.
 * Wires inter-module callbacks internally.
 */
class OverlayManager {
    _bayId := ""
    _pagesDir := ""
    _startup := ""
    _helpBtn := ""
    _helpOv := ""
    _booking := ""

    /**
     * @param {String} bayId  e.g. "BAY03"
     */
    __New(bayId) {
        this._bayId := bayId

        ; Build file:/// path to pages directory
        ; A_LineFile resolves to this file's location (scripts/overlay/)
        thisDir := RegExReplace(A_LineFile, "\\[^\\]+$", "")
        pagesPath := thisDir . "\pages\"
        ; Convert backslashes to forward slashes for file:/// URL
        pagesPath := StrReplace(pagesPath, "\", "/")
        this._pagesDir := "file:///" . pagesPath

        this._startup := StartupOverlay(this)
        this._helpOv := HelpOverlay(this)
        this._helpOv.Init()
        this._helpBtn := HelpButton(this, ObjBindMethod(this, "_onHelpClick"))
        this._booking := BookingOverlay(this)
    }

    /**
     * Show the startup overlay (call before InitializeSystem).
     */
    ShowStartup() {
        this._startup.Show(this._bayId)
    }

    /**
     * Hide the startup overlay.
     */
    HideStartup() {
        this._startup.Hide()
    }

    /**
     * Show the help button (call after startup completes).
     */
    ShowHelpButton() {
        this._helpBtn.Show()
    }

    /**
     * Set alert state on the help button (pulsing red during errors).
     * @param {Boolean} active
     */
    SetHelpAlert(active) {
        this._helpBtn.SetAlert(active)
    }

    ShowBookingMessage(jsonBody) {
        if this._booking
            this._booking.ShowMessage(jsonBody)
    }

    HideBooking() {
        if this._booking
            this._booking.Hide()
    }

    IsBookingOpen() {
        return this._booking ? this._booking.IsOpen() : false
    }

    /**
     * Destroy all overlays (call in CleanupAndExit).
     */
    Cleanup() {
        this._startup.Destroy()
        this._helpBtn.Destroy()
        this._helpOv.Destroy()
        this._booking.Destroy()
    }

    /**
     * Returns file:/// URL prefix for the pages directory.
     */
    GetPagesDir() {
        return this._pagesDir
    }

    IsHelpOpen() {
        return this._helpOv ? this._helpOv.IsOpen() : false
    }

    IsStartupActive() {
        return this._startup ? this._startup.IsActive() : false
    }

    ; --- internal callbacks ---

    _onHelpClick() {
        if this._booking
            this._booking.Hide()
        this._helpOv.Toggle()
    }
}
