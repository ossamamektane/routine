// Routine apps: the part shared by the Mac app and the iPhone/iPad app.
// The app is a window around the website. It never needs rebuilding for changes to the site:
// - The page is shown from the app's own copy (routine://app/...), so it opens instantly and offline.
// - Site: on opening, on coming back, and every 5 minutes, the app downloads the site's files.
//   If anything changed it swaps in the new copy and the page reloads when nothing is being edited.
// - Safety: a new copy must say "ready" within 20 seconds; if it doesn't (broken update), the app goes
//   back to the previous copy and skips that version until the site changes again.
// - Data: localStorage lives in the app (storage.json plus a backup of the last good one), so the data
//   never depends on the browser engine keeping it. The page reads it fresh on every load.
// - Reminders are real notifications (they ring when the app is closed); the badge is the Today count.
// Bump SHELL (and SHELL_LATEST in app.js) only when files in apps/ change; then Settings offers the new app.
import Foundation
import WebKit
import UserNotifications
import CryptoKit

let SHELL = 1
let SITE = "https://ossamamektane.github.io/routine/"

@MainActor
final class Core: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKURLSchemeHandler {
    let platform: String
    var web: WKWebView!
    // Filled in by the Mac or iPhone part.
    var onBadge: (Int) -> Void = { _ in }
    var onExport: (String, String) -> Void = { _, _ in }
    var onOpen: (URL) -> Void = { _ in }
    var onSiteChanged: () -> Void = {}
    var isActive: () -> Bool = { true }
    let notifier = Notifier()

    private var store: [String: String] = [:]
    private var saveLater: DispatchWorkItem?
    private let dir: URL
    private let fetcher = SiteFetcher()
    private var awaitingReady = false
    private var loadCount = 0
    private var checking = false
    private var lastCheck = Date.distantPast
    private var timer: Timer?
    private let defaults = UserDefaults.standard

    private var storeURL: URL { dir.appendingPathComponent("storage.json") }
    private var backupURL: URL { dir.appendingPathComponent("storage-backup.json") }
    private var siteDir: URL { dir.appendingPathComponent("site", isDirectory: true) }
    private var currentDir: URL { siteDir.appendingPathComponent("current", isDirectory: true) }
    private var previousDir: URL { siteDir.appendingPathComponent("previous", isDirectory: true) }
    private var bundleDir: URL { Bundle.main.resourceURL!.appendingPathComponent("web", isDirectory: true) }
    // The copy being shown: the newest download, or the one inside the app.
    var root: URL { FileManager.default.fileExists(atPath: currentDir.appendingPathComponent("index.html").path) ? currentDir : bundleDir }

    init(platform: String) {
        self.platform = platform
        dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Routine", isDirectory: true)
        super.init()
        try? FileManager.default.createDirectory(at: siteDir, withIntermediateDirectories: true)
        loadStore()
    }

    // ---------- Saved data ----------
    private func loadStore() {
        let fm = FileManager.default
        if let d = try? Data(contentsOf: storeURL), let s = try? JSONDecoder().decode([String: String].self, from: d) {
            store = s
            try? fm.removeItem(at: backupURL)
            try? fm.copyItem(at: storeURL, to: backupURL)
        } else if let d = try? Data(contentsOf: backupURL), let s = try? JSONDecoder().decode([String: String].self, from: d) {
            store = s
        }
    }
    private func storeJSON() -> String {
        guard let d = try? JSONEncoder().encode(store), let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s
    }
    func saveSoon() {
        saveLater?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveLater = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
    func saveNow() {
        saveLater?.cancel()
        saveLater = nil
        if let d = try? JSONEncoder().encode(store) { try? d.write(to: storeURL, options: .atomic) }
    }
    // The page asks for the data with prompt("routine:storage") (see bridge.js), so it is always current.
    func answerPrompt(_ text: String) -> String? { text == "routine:storage" ? storeJSON() : nil }

    // ---------- Web view ----------
    func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(self, forURLScheme: "routine")
        config.userContentController.add(self, name: "routine")
        let w = WKWebView(frame: .zero, configuration: config)
        w.navigationDelegate = self
        if #available(macOS 13.3, iOS 16.4, *) { w.isInspectable = true }
        web = w
        refreshScript()
        return w
    }
    // Before the page runs: the data (as a fallback for prompt) and bridge.js.
    private func refreshScript() {
        let c = web.configuration.userContentController
        c.removeAllUserScripts()
        let bridge = (try? String(contentsOf: bundleDir.appendingPathComponent("bridge.js"), encoding: .utf8)) ?? ""
        let source = "var ROUTINE_SAVED = " + storeJSON() + ";\nvar ROUTINE_APP = {\"platform\":\"" + platform + "\",\"shell\":" + String(SHELL) + "};\n" + bridge
        c.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }
    func load() {
        refreshScript()
        web.load(URLRequest(url: URL(string: "routine://app/index.html")!))
    }
    func start() {
        load()
        notifier.onTap = { [weak self] in self?.onTapNotification() }
        UNUserNotificationCenter.current().delegate = notifier
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.checkSite(force: true) }
        timer = Timer.scheduledTimer(timeInterval: 300, target: self, selector: #selector(everyFiveMinutes), userInfo: nil, repeats: true)
    }
    var onTapNotification: () -> Void = {}
    @objc private func everyFiveMinutes() { if isActive() { checkSite() } }
    // Coming back to the app: catch up on the time, sync, and look for a newer site.
    func resume() {
        web?.evaluateJavaScript("window.routineNative && routineNative.resume && routineNative.resume()", completionHandler: nil)
        reportPermission()
        checkSite()
    }

    // Serves the copy's files (routine://app/...). Never cached.
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }
        let base = root.standardizedFileURL
        let file = base.appendingPathComponent(String(path.dropFirst())).standardizedFileURL
        let types = ["html": "text/html; charset=utf-8", "js": "text/javascript; charset=utf-8", "json": "application/json; charset=utf-8",
                     "css": "text/css; charset=utf-8", "png": "image/png", "jpg": "image/jpeg", "svg": "image/svg+xml", "ico": "image/x-icon", "txt": "text/plain; charset=utf-8"]
        if file.path.hasPrefix(base.path), let data = try? Data(contentsOf: file) {
            let headers = ["Content-Type": types[file.pathExtension.lowercased()] ?? "application/octet-stream", "Cache-Control": "no-store", "Content-Length": String(data.count)]
            task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!)
            task.didReceive(data)
        } else {
            task.didReceive(HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "0"])!)
            task.didReceive(Data())
        }
        task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    // A new page load (not a #tab change): a copy that was never confirmed must say "ready" in time.
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadCount += 1
        awaitingReady = root == currentDir && defaults.string(forKey: "goodSite") != hashOf(dir: currentDir)
        if awaitingReady { watch(loadCount, tries: 0) }
    }
    private func watch(_ n: Int, tries: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self = self, n == self.loadCount, self.awaitingReady else { return }
            if !self.isActive() && tries < 100 { self.watch(n, tries: tries + 1); return }
            self.rollBack()
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { reportPermission() }
    // If the page's process stops (low memory), show it again.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { load() }
    // Links to websites open in the browser; the app's own pages stay here.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        let scheme = (url.scheme ?? "").lowercased()
        if scheme == "routine" || scheme == "about" || scheme == "blob" || scheme == "data" { decisionHandler(.allow); return }
        onOpen(url)
        decisionHandler(.cancel)
    }

    // ---------- Messages from the page (toNative in app.js, bridge.js) ----------
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "store":
            if let k = body["key"] as? String, let v = body["value"] as? String { store[k] = v; saveSoon() }
        case "unstore":
            if let k = body["key"] as? String { store.removeValue(forKey: k); saveSoon() }
        case "ready":
            if awaitingReady { awaitingReady = false; defaults.set(hashOf(dir: currentDir), forKey: "goodSite") }
        case "reminders":
            schedule(body["items"] as? [[String: Any]] ?? [])
        case "badge":
            onBadge((body["count"] as? NSNumber)?.intValue ?? 0)
        case "askPermission":
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                DispatchQueue.main.async { self.reportPermission() }
            }
        case "export":
            onExport(body["name"] as? String ?? "routine.json", body["text"] as? String ?? "")
        case "open":
            if let s = body["url"] as? String, let url = URL(string: s) { onOpen(url) }
        case "checkSite":
            checkSite(force: true)
        default:
            break
        }
    }

    // ---------- Reminders ----------
    // Replaces all scheduled reminders with the page's list ({ id, date (ms), title, body }), at most 60.
    private func schedule(_ items: [[String: Any]]) {
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
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false)), withCompletionHandler: nil)
        }
    }
    // Tells the page whether notifications are allowed ("granted", "denied" or "default").
    func reportPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let p: String
            switch settings.authorizationStatus {
            case .authorized, .provisional: p = "granted"
            case .denied: p = "denied"
            default: p = "default"
            }
            DispatchQueue.main.async { self.web?.evaluateJavaScript("window.routineNative && routineNative.permission('" + p + "')", completionHandler: nil) }
        }
    }

    // ---------- Site updates ----------
    func checkSite(force: Bool = false) {
        if checking || (!force && Date().timeIntervalSince(lastCheck) < 120) { return }
        checking = true
        lastCheck = Date()
        let fetcher = self.fetcher, siteDir = self.siteDir, current = root, bad = defaults.string(forKey: "badSite") ?? ""
        DispatchQueue.global(qos: .utility).async {
            let fresh = fetcher.download(site: SITE, into: siteDir, comparedWith: current, skipHash: bad)
            DispatchQueue.main.async {
                self.checking = false
                if let fresh = fresh { self.install(fresh) }
            }
        }
    }
    private func install(_ fresh: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: previousDir)
        if fm.fileExists(atPath: currentDir.path) { try? fm.moveItem(at: currentDir, to: previousDir) }
        do { try fm.moveItem(at: fresh, to: currentDir) } catch {
            try? fm.removeItem(at: fresh)
            if fm.fileExists(atPath: previousDir.path) { try? fm.moveItem(at: previousDir, to: currentDir) }
            return
        }
        onSiteChanged()
        // The page reloads itself when nothing is being edited (routineNative.updateReady in app.js).
        web.evaluateJavaScript("window.routineNative && routineNative.updateReady ? routineNative.updateReady() : location.reload()", completionHandler: nil)
    }
    // The new copy didn't start: go back to the previous one and skip this version.
    private func rollBack() {
        let fm = FileManager.default
        defaults.set(hashOf(dir: currentDir), forKey: "badSite")
        try? fm.removeItem(at: currentDir)
        if fm.fileExists(atPath: previousDir.path) { try? fm.moveItem(at: previousDir, to: currentDir) }
        awaitingReady = false
        onSiteChanged()
        load()
    }
}

// Downloads the site (index.html and every file it uses) into a new folder.
// Returns nil when nothing changed, when offline, or when a needed file is missing.
final class Box: @unchecked Sendable { var data: Data? }
final class SiteFetcher {
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        c.urlCache = nil
        c.timeoutIntervalForRequest = 20
        c.timeoutIntervalForResource = 60
        return URLSession(configuration: c)
    }()

    private func get(_ site: String, _ path: String) -> Data? {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        guard let url = URL(string: site + encoded + "?t=" + String(Int(Date().timeIntervalSince1970 * 1000))) else { return nil }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let result = Box()
        let done = DispatchSemaphore(value: 0)
        session.dataTask(with: request) { data, response, _ in
            if let r = response as? HTTPURLResponse, r.statusCode == 200, let data = data { result.data = data }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 70)
        return result.data
    }

    // Files the page uses: src="..." are needed, href="..." (manifest, icon) are optional.
    static func references(_ html: String) -> [(String, Bool)] {
        guard let re = try? NSRegularExpression(pattern: "\\b(src|href)\\s*=\\s*[\"']([^\"']+)[\"']", options: [.caseInsensitive]) else { return [] }
        var out: [(String, Bool)] = [], seen = Set<String>()
        let ns = html as NSString
        for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let attr = ns.substring(with: m.range(at: 1)).lowercased()
            var v = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
            if let i = v.firstIndex(where: { $0 == "?" || $0 == "#" }) { v = String(v[..<i]) }
            if v.hasPrefix("./") { v = String(v.dropFirst(2)) }
            if v.isEmpty || v.contains(":") || v.hasPrefix("/") || v.contains("..") || v.hasSuffix("/") || seen.contains(v) { continue }
            seen.insert(v)
            out.append((v, attr == "src"))
        }
        return out
    }

    func download(site: String, into parent: URL, comparedWith current: URL, skipHash: String) -> URL? {
        guard let index = get(site, "index.html"), let html = String(data: index, encoding: .utf8), html.lowercased().contains("<html") else { return nil }
        var files: [String: Data] = ["index.html": index]
        for (path, needed) in SiteFetcher.references(html) {
            if let d = get(site, path) { files[path] = d } else if needed { return nil }
        }
        if files["manifest.json"] == nil, let d = get(site, "manifest.json") { files["manifest.json"] = d }
        if files["icon.png"] == nil, let d = get(site, "icon.png") { files["icon.png"] = d }
        // Nothing changed?
        if files.allSatisfy({ (try? Data(contentsOf: current.appendingPathComponent($0.key))) == $0.value }) { return nil }
        if hashOf(files: files) == skipHash { return nil }
        let fresh = parent.appendingPathComponent("new-" + UUID().uuidString, isDirectory: true)
        do {
            for (path, data) in files {
                let url = fresh.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            }
        } catch {
            try? FileManager.default.removeItem(at: fresh)
            return nil
        }
        return fresh
    }
}

// One fingerprint for a set of files (used to remember good and broken versions).
func hashOf(files: [String: Data]) -> String {
    var h = SHA256()
    for key in files.keys.sorted() {
        h.update(data: Data(key.utf8))
        h.update(data: Data([0]))
        h.update(data: files[key]!)
    }
    return h.finalize().map { String(format: "%02x", $0) }.joined()
}
func hashOf(dir: URL) -> String {
    var files: [String: Data] = [:]
    let base = dir.resolvingSymlinksInPath().standardizedFileURL.path
    if let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) {
        for case let url as URL in e {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true, let d = try? Data(contentsOf: url) else { continue }
            var rel = url.resolvingSymlinksInPath().standardizedFileURL.path
            if rel.hasPrefix(base) { rel = String(rel.dropFirst(base.count)) }
            while rel.hasPrefix("/") { rel = String(rel.dropFirst()) }
            files[rel] = d
        }
    }
    return hashOf(files: files)
}

// Shows reminders while the app is in front; tapping one opens the app.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    var onTap: () -> Void = {}
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { self.onTap() }
        completionHandler()
    }
}
