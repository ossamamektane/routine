// Routine for iPhone and iPad: a full-screen view around the website (see Shared/Core.swift for how
// updates and data work). Adds the iPhone parts: alerts, Export (share sheet), the badge on the
// Home Screen icon, and a few extra seconds in the background to finish saving to GitHub.
import UIKit
import WebKit
import UserNotifications

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    let core = Core(platform: "ios")
    var background: UIBackgroundTaskIdentifier = .invalid

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let controller = WebController(core: core)
        core.onBadge = { n in
            if #available(iOS 16.0, *) { UNUserNotificationCenter.current().setBadgeCount(n, withCompletionHandler: nil) }
            else { UIApplication.shared.applicationIconBadgeNumber = n }
        }
        core.onOpen = { url in UIApplication.shared.open(url) }
        core.onExport = { [weak controller] name, text in controller?.share(name: name, text: text) }
        core.isActive = { UIApplication.shared.applicationState == .active }
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = controller
        w.makeKeyAndVisible()
        window = w
        core.start()
        return true
    }
    func applicationDidBecomeActive(_ application: UIApplication) { core.resume() }
    func applicationWillResignActive(_ application: UIApplication) { core.saveNow() }
    // Gives the page up to 25 seconds to finish a sync after leaving the app.
    func applicationDidEnterBackground(_ application: UIApplication) {
        core.saveNow()
        endBackground()
        background = application.beginBackgroundTask(withName: "Sync") { [weak self] in self?.endBackground() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            self?.core.saveNow()
            self?.endBackground()
        }
    }
    func applicationWillTerminate(_ application: UIApplication) { core.saveNow() }
    func endBackground() {
        if background != .invalid { UIApplication.shared.endBackgroundTask(background); background = .invalid }
    }
}

final class WebController: UIViewController, WKUIDelegate {
    let core: Core
    init(core: Core) {
        self.core = core
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        let web = core.makeWebView()
        web.uiDelegate = self
        web.backgroundColor = .white
        web.scrollView.backgroundColor = .white
        web.allowsBackForwardNavigationGestures = false
        view = web
    }
    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    // The view on top, so alerts never fail to show.
    var top: UIViewController {
        var c: UIViewController = self
        while let p = c.presentedViewController { c = p }
        return c
    }
    // "Title\nMessage" from the page becomes an alert with a bold title.
    func makeAlert(_ message: String) -> UIAlertController {
        let lines = message.components(separatedBy: "\n")
        let rest = lines.dropFirst().joined(separator: "\n")
        return UIAlertController(title: lines.first, message: rest.isEmpty ? nil : rest, preferredStyle: .alert)
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = makeAlert(message)
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        top.present(a, animated: true)
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = makeAlert(message)
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        top.present(a, animated: true)
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        completionHandler(core.answerPrompt(prompt))
    }
    // Export: the file goes to the share sheet (Save to Files, AirDrop, Mail...).
    func share(name: String, text: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { return }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        sheet.popoverPresentationController?.permittedArrowDirections = []
        top.present(sheet, animated: true)
    }
}
