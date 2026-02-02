#Requires AutoHotkey v2.0
#Include "Overlay.ahk"
#Include "StartupOverlay.ahk"
#Include "HelpButton.ahk"
#Include "HelpOverlay.ahk"

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
        this._helpBtn := HelpButton(this, ObjBindMethod(this, "_onHelpClick"))
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

    /**
     * Destroy all overlays (call in CleanupAndExit).
     */
    Cleanup() {
        this._startup.Destroy()
        this._helpBtn.Destroy()
        this._helpOv.Destroy()
    }

    /**
     * Returns file:/// URL prefix for the pages directory.
     */
    GetPagesDir() {
        return this._pagesDir
    }

    ; --- internal callbacks ---

    _onHelpClick() {
        this._helpOv.Toggle()
    }
}
