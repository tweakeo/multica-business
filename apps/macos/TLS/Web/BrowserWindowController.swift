import AppKit
import WebKit

/// Which renderer a window hosts. Mirrors DesktopWindowContext in
/// apps/desktop/src/shared/issue-window.ts.
enum WindowContext {
    case main
    case issue(path: String, title: String, workspaceSlug: String, issueId: String)

    var isIssue: Bool {
        if case .issue = self { return true }
        return false
    }

    var json: [String: Any] {
        switch self {
        case .main:
            return ["kind": "main"]
        case let .issue(path, title, workspaceSlug, issueId):
            return ["kind": "issue", "path": path, "title": title, "workspaceSlug": workspaceSlug, "issueId": issueId]
        }
    }

    /// Accepts only `/<workspace>/issues/<id>`, like parseIssueWindowRequest.
    static func issue(fromRequest payload: [String: Any]) -> WindowContext? {
        guard let path = payload["path"] as? String, path.count <= 512, path.hasPrefix("/"), !path.hasPrefix("//") else { return nil }
        let pathOnly = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
        let segments = pathOnly.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard segments.count == 4, segments[0].isEmpty, segments[2] == "issues",
              let slug = segments[1].removingPercentEncoding, !slug.isEmpty,
              let issueId = segments[3].removingPercentEncoding, !issueId.isEmpty
        else { return nil }
        let rawTitle = (payload["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = rawTitle.isEmpty ? "Issue" : String(rawTitle.prefix(200))
        return .issue(path: pathOnly, title: title, workspaceSlug: slug, issueId: issueId)
    }
}

final class BrowserWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    let context: WindowContext
    var onClose: (() -> Void)?

    private(set) var webView: WKWebView!
    private let bridge = NativeBridge()
    private static let trafficLightOrigin = NSPoint(x: 16, y: 13)

    init(context: WindowContext) {
        self.context = context
        let isIssue = context.isIssue
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: isIssue ? 900 : 1360, height: isIssue ? 760 : 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: isIssue ? 560 : 900, height: 600)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName(isIssue ? "TLSIssueWindow" : "TLSMainWindow")
        if case let .issue(_, title, _, _) = context { window.title = title } else { window.title = "TLS" }
        super.init(window: window)
        window.delegate = self
        bridge.controller = self
        webView = makeWebView()
        window.contentView = webView
        if window.frameAutosaveName.isEmpty || !window.setFrameUsingName(window.frameAutosaveName) {
            window.center()
        }
        layoutTrafficLights()
        webView.load(URLRequest(url: AppSchemeHandler.entryURL))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Web view

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let rendererRoot = Bundle.main.resourceURL!.appendingPathComponent("renderer", isDirectory: true)
        config.setURLSchemeHandler(AppSchemeHandler(root: rendererRoot), forURLScheme: AppSchemeHandler.scheme)

        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: bootScript(), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        if let url = Bundle.main.url(forResource: "bridge", withExtension: "js"),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        controller.addScriptMessageHandler(bridge, contentWorld: .page, name: "tls")
        config.userContentController = controller

        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = false
        view.allowsMagnification = false
        view.setValue(false, forKey: "drawsBackground")
        if #available(macOS 13.3, *) { view.isInspectable = true }
        return view
    }

    /// Values the Electron preload read synchronously; injected before any
    /// renderer script runs.
    private func bootScript() -> String {
        let runtimeConfig: [String: Any]
        switch RuntimeConfigStore.load() {
        case let .success(config):
            runtimeConfig = ["ok": true, "config": [
                "schemaVersion": config.schemaVersion, "apiUrl": config.apiUrl, "wsUrl": config.wsUrl, "appUrl": config.appUrl,
            ]]
        case let .failure(error):
            runtimeConfig = ["ok": false, "error": ["message": error.message]]
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let boot: [String: Any] = [
            "appInfo": ["version": version, "os": "macos"],
            "systemLocale": Locale.preferredLanguages.first ?? "en",
            "runtimeConfig": runtimeConfig,
            "windowContext": context.json,
        ]
        return "Object.defineProperty(window, '__TLS_BOOT__', { value: Object.freeze(\(JSONText.encode(boot))) });"
    }

    /// Pushes a main → renderer event (see bridge.js `__tlsEmit`).
    func emit(_ channel: String, _ payload: Any?) {
        let script = "window.__tlsEmit && window.__tlsEmit(\(JSONText.encode(channel)), \(JSONText.encode(payload ?? NSNull())));"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    // MARK: Window chrome

    func setImmersive(_ immersive: Bool) {
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach {
            window?.standardWindowButton($0)?.isHidden = immersive
        }
    }

    func beginWindowDrag() {
        guard let window, let event = NSApp.currentEvent ?? window.currentEvent else { return }
        window.performDrag(with: event)
    }

    func titlebarDoubleClick() {
        let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize"
        if action == "Minimize" { window?.performMiniaturize(nil) } else if action != "None" { window?.zoom(nil) }
    }

    /// Places the traffic lights where the renderer leaves room for them
    /// (Electron's `trafficLightPosition`).
    private func layoutTrafficLights() {
        guard let window,
              let close = window.standardWindowButton(.closeButton),
              let mini = window.standardWindowButton(.miniaturizeButton),
              let zoom = window.standardWindowButton(.zoomButton),
              let container = close.superview?.superview,
              !window.styleMask.contains(.fullScreen)
        else { return }
        let origin = Self.trafficLightOrigin
        let buttonHeight = close.frame.height
        let spacing = mini.frame.minX - close.frame.minX
        var frame = container.frame
        frame.size.height = buttonHeight + origin.y * 2
        frame.origin.y = window.frame.height - frame.height
        container.frame = frame
        for (index, button) in [close, mini, zoom].enumerated() {
            button.setFrameOrigin(NSPoint(x: origin.x + CGFloat(index) * spacing, y: origin.y))
        }
    }

    func windowDidResize(_ notification: Notification) { layoutTrafficLights() }
    func windowDidExitFullScreen(_ notification: Notification) { layoutTrafficLights() }

    func windowWillClose(_ notification: Notification) {
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        onClose?()
    }

    // MARK: Navigation policy

    func webView(
        _ webView: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = action.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.cancel)
            return
        }
        let isMainFrame = action.targetFrame?.isMainFrame ?? true
        if scheme == AppSchemeHandler.scheme || scheme == "about" || scheme == "blob" || scheme == "data" {
            decisionHandler(.allow)
        } else if isMainFrame {
            // The app shell never navigates away; external pages go to the browser.
            if scheme == "http" || scheme == "https" || scheme == "mailto" { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for action: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = action.request.url, ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        }
        return nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.load(URLRequest(url: AppSchemeHandler.entryURL))
    }

    @available(macOS 12.0, *)
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.deny)
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        guard let window else { completionHandler(nil); return }
        panel.beginSheetModal(for: window) { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "Aceptar")
        alert.addButton(withTitle: "Cancelar")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
        completionHandler()
    }
}

enum JSONText {
    /// JSON literal safe to splice into a script (fragments allowed).
    static func encode(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject([value]),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
              let text = String(data: data, encoding: .utf8)
        else { return "null" }
        // U+2028/2029 are valid JSON but terminate JS string literals in old engines.
        return text.replacingOccurrences(of: "\u{2028}", with: "\\u2028").replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }
}
