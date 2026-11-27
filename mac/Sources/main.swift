// Routine for Mac: the same plain HTML app (index.html, app.js, model.js) in a native window.
// The page is inside the app (works offline). The app adds what a browser tab can't do:
// - reminders scheduled with macOS notifications (they ring even when the window is closed),
// - the count on the Dock icon,
// - a copy of the saved data (localStorage) in ~/Library/Application Support/Routine/storage.json,
// - alerts, confirms, Import (open panel) and Export (save panel).
// Messages from the page arrive in userContentController (see "toNative" in app.js).
import Cocoa
import WebKit
import UserNotifications

// Serves the page's files from the app (routine://app/...), never cached.
final class FileServer: NSObject, WKURLSchemeHandler {
    let root: URL
    init(root: URL) { self.root = root }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }
        let file = root.appendingPathComponent(String(path.dropFirst())).standardizedFileURL
        let types = ["html": "text/html; charset=utf-8", "js": "text/javascript; charset=utf-8", "json": "application/json; charset=utf-8"]
        if file.path.hasPrefix(root.standardizedFileURL.path), let data = try? Data(contentsOf: file) {
            let headers = ["Content-Type": types[file.pathExtension] ?? "application/octet-stream", "Cache-Control": "no-store"]
            task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!)
            task.didReceive(data)
        } else {
            task.didReceive(HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: [:])!)
            task.didReceive(Data())
        }
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate, UNUserNotificationCenterDelegate {
    var window: NSWindow!
    var web: WKWebView!
    var store: [String: String] = [:]
    var saveLater: DispatchWorkItem?
    let storeURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Routine", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("storage.json")
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let data = try? Data(contentsOf: storeURL), let saved = try? JSONDecoder().decode([String: String].self, from: data) { store = saved }

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(FileServer(root: Bundle.main.resourceURL!.appendingPathComponent("web")), forURLScheme: "routine")
        config.userContentController.add(self, name: "routine")
        // Before the page runs: put back the saved data, and send every later change to the app.
        let saved = String(data: (try? JSONEncoder().encode(store)) ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
        let script = """
        (function () {
          var saved = \(saved);
          try { for (var k in saved) localStorage.setItem(k, saved[k]); } catch (e) {}
          var set = Storage.prototype.setItem, remove = Storage.prototype.removeItem;
          function send(m) { try { webkit.messageHandlers.routine.postMessage(m); } catch (e) {} }
          Storage.prototype.setItem = function (k, v) { set.call(this, k, v); if (this === window.localStorage) send({ type: "store", key: String(k), value: String(v) }); };
          Storage.prototype.removeItem = function (k) { remove.call(this, k); if (this === window.localStorage) send({ type: "unstore", key: String(k) }); };
        })();
        """
        config.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        web = WKWebView(frame: .zero, configuration: config)
        web.uiDelegate = self
        web.navigationDelegate = self

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 860), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Routine"
        window.contentView = web
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("Routine")
        window.makeKeyAndOrderFront(nil)

        UNUserNotificationCenter.current().delegate = self
        buildMenu()
        web.load(URLRequest(url: URL(string: "routine://app/index.html")!))
        NSApp.activate(ignoringOtherApps: true)
    }

    // Closing the window keeps Routine running (like Mail); click the Dock icon to bring it back.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { window.makeKeyAndOrderFront(nil) }
        return true
    }
    func applicationDidBecomeActive(_ notification: Notification) { reportPermission() }
    func applicationWillTerminate(_ notification: Notification) { saveNow() }

    // ---------- Messages from the page ----------
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "store":
            if let k = body["key"] as? String, let v = body["value"] as? String { store[k] = v; saveSoon() }
        case "unstore":
            if let k = body["key"] as? String { store.removeValue(forKey: k); saveSoon() }
        case "reminders":
            schedule(body["items"] as? [[String: Any]] ?? [])
        case "badge":
            let n = (body["count"] as? NSNumber)?.intValue ?? 0
            NSApp.dockTile.badgeLabel = n > 0 ? String(n) : nil
        case "askPermission":
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in self.reportPermission() }
        case "export":
            export(name: body["name"] as? String ?? "routine.json", text: body["text"] as? String ?? "")
        case "open":
            if let s = body["url"] as? String, let url = URL(string: s) { NSWorkspace.shared.open(url) }
        default:
            break
        }
    }

    // Saves the data copy half a second after the last change (and right away when quitting).
    func saveSoon() {
        saveLater?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveLater = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
    func saveNow() {
        saveLater?.cancel()
        if let data = try? JSONEncoder().encode(store) { try? data.write(to: storeURL, options: .atomic) }
    }

    // Replaces all scheduled reminders with the page's list ({ id, date (ms), title, body }).
    func schedule(_ items: [[String: Any]]) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        for item in items.prefix(60) {
            guard let id = item["id"] as? String, let ms = (item["date"] as? NSNumber)?.doubleValue else { continue }
            let date = Date(timeIntervalSince1970: ms / 1000)
            if date <= Date() { continue }
            let content = UNMutableNotificationContent()
            content.title = item["title"] as? String ?? ""
            content.body = item["body"] as? String ?? ""
            content.sound = .default
            let when = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false)))
        }
    }

    // Tells the page whether notifications are allowed.
    func reportPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let p: String
            switch settings.authorizationStatus {
            case .authorized, .provisional: p = "granted"
            case .denied: p = "denied"
            default: p = "default"
            }
            DispatchQueue.main.async { self.web?.evaluateJavaScript("window.routineNative && routineNative.permission('\(p)')", completionHandler: nil) }
        }
    }

    // Shows reminders even while Routine is in front.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
    // Clicking a reminder opens the window.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        completionHandler()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { reportPermission() }

    // Links to websites open in the browser.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = action.request.url, url.scheme == "http" || url.scheme == "https", action.targetFrame?.isMainFrame ?? true {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
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

    // ---------- Menu (needed for Quit, Copy and Paste in text fields, Reload) ----------
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
        menu("View", [item("Reload", #selector(WKWebView.reload(_:)), "r")])
        menu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Close", #selector(NSWindow.performClose(_:)), "w")
        ])
        NSApp.mainMenu = main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
