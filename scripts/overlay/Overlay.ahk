#Requires AutoHotkey v2.0
#Include "..\..\lib\ahk\WebView2\WebView2.ahk"

/**
 * Overlay — borderless always-on-top WebView2 window.
 *
 * Usage:
 *   overlay := Overlay()
 *   overlay.Show("file:///" A_ScriptDir "/pages/test.html", {w: 800, h: 600})
 *   overlay.Navigate("file:///" A_ScriptDir "/pages/other.html")
 *   overlay.Hide()
 *   overlay.Destroy()
 */
class Overlay {
    gui := ""
    wvc := ""       ; WebView2.Controller
    wv  := ""       ; WebView2.Core (CoreWebView2)
    _visible := false

    __New() {
    }

    /**
     * Create and display the overlay window.
     * @param {String} url       URL or file:/// path to load
     * @param {Object} options   {w, h, x, y} — width, height, position (defaults: 800x600, centered)
     */
    Show(url, options := {}) {
        if this.gui
            return this._showExisting(url)

        w := options.HasOwnProp("w") ? options.w : 800
        h := options.HasOwnProp("h") ? options.h : 600
        x := options.HasOwnProp("x") ? options.x : (A_ScreenWidth - w) // 2
        y := options.HasOwnProp("y") ? options.y : (A_ScreenHeight - h) // 2

        opacity := options.HasOwnProp("opacity") ? options.opacity : 0

        g := Gui("+AlwaysOnTop -Caption +ToolWindow")
        g.BackColor := "0x000000"
        g.Show("w" w " h" h " x" x " y" y)
        if (opacity > 0 && opacity < 255)
            WinSetTransparent(opacity, g.Hwnd)
        this.gui := g

        ; Create WebView2 synchronously inside the GUI
        wvc := WebView2.create(g.Hwnd)
        this.wvc := wvc
        this.wv := wvc.CoreWebView2

        ; Size the webview to fill the window
        this._resizeWebView(w, h)

        ; Navigate to requested URL
        this.wv.Navigate(url)
        this._visible := true
    }

    /**
     * Navigate to a new URL without recreating the window.
     */
    Navigate(url) {
        if this.wv
            this.wv.Navigate(url)
    }

    /**
     * Reload current content.
     */
    Reload() {
        if this.wv
            this.wv.Reload()
    }

    /**
     * Hide the overlay without destroying it.
     */
    Hide() {
        if this.gui {
            this.gui.Hide()
            this._visible := false
        }
    }

    /**
     * Destroy the overlay and release resources.
     */
    Destroy() {
        if this.wvc {
            this.wvc.Close()
            this.wvc := ""
            this.wv := ""
        }
        if this.gui {
            this.gui.Destroy()
            this.gui := ""
        }
        this._visible := false
    }

    IsVisible => this._visible

    ; --- internal ---

    _showExisting(url) {
        if url
            this.Navigate(url)
        this.gui.Show()
        this._visible := true
    }

    _resizeWebView(w, h) {
        if this.wvc {
            rc := Buffer(16, 0)
            NumPut("int", 0, rc, 0)
            NumPut("int", 0, rc, 4)
            NumPut("int", w, rc, 8)
            NumPut("int", h, rc, 12)
            this.wvc.Bounds := rc
        }
    }
}
