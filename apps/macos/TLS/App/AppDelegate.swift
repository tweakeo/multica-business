import AppKit
import UserNotifications
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private(set) var mainWindow: BrowserWindowController?
    private var issueWindows: [BrowserWindowController] = []
    private var mouseMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install()
        UNUserNotificationCenter.current().delegate = self
        DaemonManager.shared.onStatusChange = { [weak self] status in
            self?.mainWindow?.emit("daemon:status", status)
        }
        DaemonManager.shared.onLogLine = { [weak self] line in
            self?.mainWindow?.emit("daemon:log-line", line)
        }
        installMouseNavigationMonitor()
        if RuntimeConfigStore.isEmbedded {
            startEmbeddedStack()
        } else {
            showMainWindow()
        }
        #if DEBUG
        DebugHooks.install { [weak self] in
            (NSApp.keyWindow?.windowController as? BrowserWindowController)?.webView ?? self?.mainWindow?.webView
        }
        #endif
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Embedded mode owns the server: stop the daemon, the API and the
        // database together. Otherwise only stop the daemon when the user opted
        // into it, as Electron's build does.
        let embedded = RuntimeConfigStore.isEmbedded
        guard embedded || DaemonManager.shared.prefs.autoStop else { return .terminateNow }
        Task { @MainActor in
            await DaemonManager.shared.stopForQuit()
            if embedded { LocalStack.shared.stop() }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    // MARK: Embedded stack

    private var startupWindow: StartupWindowController?
    /// Session token from the automatic local login, consumed by the first window.
    var bootToken: String?

    private func startEmbeddedStack() {
        let startup = StartupWindowController()
        startupWindow = startup
        startup.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            do {
                bootToken = try await LocalStack.shared.start { startup.setStatus($0) }
                startup.close()
                startupWindow = nil
                showMainWindow()
            } catch {
                startup.close()
                startupWindow = nil
                let alert = NSAlert()
                alert.messageText = "TLS no ha podido arrancar"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "Abrir registros")
                alert.addButton(withTitle: "Salir")
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(LocalStack.logsDir)
                }
                NSApp.terminate(nil)
            }
        }
    }

    func showMainWindow() {
        if let mainWindow {
            mainWindow.showWindow(nil)
            mainWindow.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = BrowserWindowController(context: .main)
        controller.onClose = { [weak self] in self?.mainWindow = nil }
        mainWindow = controller
        controller.showWindow(nil)
    }

    func openIssueWindow(_ context: WindowContext) {
        let controller = BrowserWindowController(context: context)
        controller.onClose = { [weak self, weak controller] in
            self?.issueWindows.removeAll { $0 === controller }
        }
        issueWindows.append(controller)
        controller.showWindow(nil)
    }

    /// Closes issue windows that belong to a different account than the one
    /// now signed in to the main window.
    func authSessionChanged(userId: String?) {
        guard userId == nil else { return }
        issueWindows.forEach { $0.close() }
    }

    /// Routes a menu command to the main window renderer.
    func emitToMain(_ channel: String, _ payload: Any? = nil) {
        showMainWindow()
        mainWindow?.emit(channel, payload)
    }

    private func installMouseNavigationMonitor() {
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { event in
            guard let controller = NSApp.keyWindow?.windowController as? BrowserWindowController else { return event }
            switch event.buttonNumber {
            case 3: controller.emit("navigation:gesture", "back")
            case 4: controller.emit("navigation:gesture", "forward")
            default: return event
            }
            return nil
        }
    }

    // MARK: Notifications

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        if let slug = info["slug"] as? String, let itemId = info["itemId"] as? String {
            emitToMain("inbox:open", ["slug": slug, "itemId": itemId, "issueKey": info["issueKey"] as? String ?? ""])
            NSApp.activate(ignoringOtherApps: true)
        }
        completionHandler()
    }
}
