// Routine for Mac: a window around the website (see Shared/Core.swift for how updates and data work).
// Adds the Mac parts: the window and menus, Mac alerts, Import (open panel), Export (save panel),
// the Today count on the Dock icon, and the Dock icon drawn from the site's icon.png.
import Cocoa
import WebKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, WKUIDelegate {
    let core = Core(platform: "mac")
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let web = core.makeWebView()
        web.uiDelegate = self
        core.onBadge = { n in NSApp.dockTile.badgeLabel = n > 0 ? String(n) : nil }
        core.onOpen = { url in NSWorkspace.shared.open(url) }
        core.onExport = { [weak self] name, text in self?.export(name: name, text: text) }
        core.onSiteChanged = { [weak self] in self?.setIcon() }
        core.onTapNotification = { [weak self] in self?.show() }

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 860), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Routine"
        window.contentView = web
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("Routine")
        window.makeKeyAndOrderFront(nil)

        buildMenu()
        setIcon()
        core.start()
        NSApp.activate(ignoringOtherApps: true)
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    // Closing the window keeps Routine running (like Mail); click the Dock icon to bring it back.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { show() }
        return true
    }
    func applicationDidBecomeActive(_ notification: Notification) { core.resume() }
    func applicationDidResignActive(_ notification: Notification) { core.saveNow() }
    func applicationWillTerminate(_ notification: Notification) { core.saveNow() }

    // The Dock icon: the site's icon.png on a rounded white tile, like other Mac apps.
    func setIcon() {
        guard let image = NSImage(contentsOf: core.root.appendingPathComponent("icon.png")) else { return }
        let icon = NSImage(size: NSSize(width: 1024, height: 1024))
        icon.lockFocus()
        let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
        let tile = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = 20
        shadow.shadowOffset = NSSize(width: 0, height: -8)
        shadow.set()
        NSColor.white.setFill()
        tile.fill()
        NSGraphicsContext.restoreGraphicsState()
        tile.addClip()
        image.draw(in: rect)
        icon.unlockFocus()
        NSApp.applicationIconImage = icon
    }

    // ---------- alert(), confirm(), Import and Export ----------
    // "Title\nMessage" from the page becomes a Mac alert with a bold title.
    func makeAlert(_ message: String) -> NSAlert {
        let alert = NSAlert()
        let lines = message.components(separatedBy: "\n")
        alert.messageText = lines.first ?? ""
        alert.informativeText = lines.dropFirst().joined(separator: "\n")
        return alert
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = makeAlert(message)
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completionHandler()
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = makeAlert(message)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        completionHandler(core.answerPrompt(prompt))
    }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.begin { result in completionHandler(result == .OK ? panel.urls : nil) }
    }
    func export(name: String, text: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.begin { result in
            if result == .OK, let url = panel.url { try? text.write(to: url, atomically: true, encoding: .utf8) }
        }
    }

    @objc func reloadPage(_ sender: Any?) { core.load() }

    // ---------- Menu (Quit, Copy and Paste in text fields, Reload) ----------
    func buildMenu() {
        let main = NSMenu()
        func menu(_ title: String, _ items: [NSMenuItem]) {
            let holder = NSMenuItem()
            let m = NSMenu(title: title)
            items.forEach { m.addItem($0) }
            holder.submenu = m
            main.addItem(holder)
        }
        func item(_ title: String, _ action: Selector?, _ key: String, _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            return i
        }
        let reload = item("Reload", #selector(reloadPage(_:)), "r")
        reload.target = self
        menu("Routine", [
            item("About Routine", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""),
            .separator(),
            item("Hide Routine", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:)), ""),
            .separator(),
            item("Quit Routine", #selector(NSApplication.terminate(_:)), "q")
        ])
        menu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a")
        ])
        menu("View", [reload])
        menu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Close", #selector(NSWindow.performClose(_:)), "w")
        ])
        NSApp.mainMenu = main
    }
}

@main
@MainActor
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
