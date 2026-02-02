#Requires AutoHotkey v2.0
#Include "Overlay.ahk"
#Include "StartupOverlay.ahk"

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

    /**
     * @param {String} bayId  e.g. "BAY03"
     */
    __New(bayId) {
        this._bayId := bayId

        ; Build file:/// path to pages directory
        pagesPath := A_ScriptDir . "\overlay\pages\"
        ; Convert backslashes to forward slashes for file:/// URL
        pagesPath := StrReplace(pagesPath, "\", "/")
        this._pagesDir := "file:///" . pagesPath

        this._startup := StartupOverlay(this)
    }

    /**
     * Show the startup overlay (call before InitializeSystem).
     */
    ShowStartup() {
        this._startup.Show(this._bayId)
    }

    /**
     * Hide the startup overlay (call when LM connection goes green).
     */
    HideStartup() {
        this._startup.Hide()
    }

    /**
     * Destroy all overlays (call in CleanupAndExit).
     */
    Cleanup() {
        this._startup.Destroy()
    }

    /**
     * Returns file:/// URL prefix for the pages directory.
     */
    GetPagesDir() {
        return this._pagesDir
    }
}
