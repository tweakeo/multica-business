import AppKit
import UserNotifications
import WebKit

/// The only native entry point for page scripts. Accepts a closed set of
/// actions, and only from the main frame of the bundled app origin; there is
/// no generic command execution.
final class NativeBridge: NSObject, WKScriptMessageHandlerWithReply {
    weak var controller: BrowserWindowController?

    private enum BridgeError: LocalizedError {
        case forbiddenOrigin, unknownAction(String), invalidPayload(String)

        var errorDescription: String? {
            switch self {
            case .forbiddenOrigin: return "bridge call from a non-app origin"
            case let .unknownAction(name): return "unknown bridge action \(name)"
            case let .invalidPayload(name): return "invalid payload for \(name)"
            }
        }
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        let origin = message.frameInfo.securityOrigin
        guard message.frameInfo.isMainFrame,
              origin.protocol == AppSchemeHandler.scheme,
              origin.host == AppSchemeHandler.host
        else {
            replyHandler(nil, BridgeError.forbiddenOrigin.localizedDescription)
            return
        }
        guard let body = message.body as? [String: Any], let name = body["name"] as? String else {
            replyHandler(nil, BridgeError.invalidPayload("message").localizedDescription)
            return
        }
        let payload = body["payload"] as? [String: Any] ?? [:]
        Task { @MainActor in
            do {
                replyHandler(try await self.handle(name, payload) ?? NSNull(), nil)
            } catch {
                replyHandler(nil, error.localizedDescription)
            }
        }
    }

    @MainActor
    private func handle(_ name: String, _ payload: [String: Any]) async throws -> Any? {
        let daemon = DaemonManager.shared
        switch name {
        case "shell.openExternal", "file.download":
            guard let raw = payload["url"] as? String, let url = URL(string: raw),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "")
            else { throw BridgeError.invalidPayload(name) }
            NSWorkspace.shared.open(url)
            return nil
        case "window.setImmersive":
            controller?.setImmersive(payload["immersive"] as? Bool ?? false)
            return nil
        case "window.close":
            controller?.close()
            return nil
        case "window.drag":
            controller?.beginWindowDrag()
            return nil
        case "window.titlebarDoubleClick":
            controller?.titlebarDoubleClick()
            return nil
        case "window.openIssue":
            guard let context = WindowContext.issue(fromRequest: payload) else {
                return ["ok": false, "reason": "invalid_request"]
            }
            (NSApp.delegate as? AppDelegate)?.openIssueWindow(context)
            return ["ok": true]
        case "auth.session":
            (NSApp.delegate as? AppDelegate)?.authSessionChanged(userId: payload["userId"] as? String)
            return nil
        case "notification.show":
            showNotification(payload)
            return nil
        case "badge.set":
            let count = payload["count"] as? Int ?? 0
            NSApp.dockTile.badgeLabel = count > 0 ? (count > 99 ? "99+" : "\(count)") : nil
            return nil
        case "directory.pick":
            return await pickDirectory(defaultPath: payload["defaultPath"] as? String)
        case "directory.validate":
            guard let path = payload["path"] as? String else { throw BridgeError.invalidPayload(name) }
            return LocalDirectory.validate(path)
        case "daemon.start": return await daemon.start()
        case "daemon.stop": return await daemon.stop()
        case "daemon.restart": return await daemon.restart()
        case "daemon.status": return await daemon.status().json
        case "daemon.probeRuntimes": return await daemon.probeRuntimes()
        case "daemon.hostName": return Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        case "daemon.setTargetApiUrl":
            guard let url = payload["url"] as? String else { throw BridgeError.invalidPayload(name) }
            daemon.setTargetApiUrl(url)
            return nil
        case "daemon.syncToken":
            guard let token = payload["token"] as? String, let userId = payload["userId"] as? String else {
                throw BridgeError.invalidPayload(name)
            }
            try await daemon.syncToken(jwt: token, userId: userId)
            return nil
        case "daemon.reauthenticate":
            guard let token = payload["token"] as? String, let userId = payload["userId"] as? String else {
                throw BridgeError.invalidPayload(name)
            }
            return await daemon.reauthenticate(jwt: token, userId: userId)
        case "daemon.clearToken":
            await daemon.clearToken()
            return nil
        case "daemon.isCliInstalled": return daemon.isCliInstalled
        case "daemon.getPrefs": return daemon.prefs.json
        case "daemon.setPrefs": return daemon.updatePrefs(payload).json
        case "daemon.autoStart":
            await daemon.autoStart()
            return nil
        case "daemon.startLogStream":
            daemon.startLogStream()
            return nil
        case "daemon.stopLogStream":
            daemon.stopLogStream()
            return nil
        case "daemon.openLogFile": return daemon.openLogFile()
        default:
            throw BridgeError.unknownAction(name)
        }
    }

    @MainActor
    private func pickDirectory(defaultPath: String?) async -> [String: Any] {
        guard let window = controller?.window else { return ["ok": false, "reason": "no_window"] }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if let defaultPath { panel.directoryURL = URL(fileURLWithPath: defaultPath, isDirectory: true) }
        let response = await panel.beginSheetModal(for: window)
        guard response == .OK, let url = panel.url else { return ["ok": false, "reason": "cancelled"] }
        return ["ok": true, "path": url.path, "basename": url.lastPathComponent]
    }

    private func showNotification(_ payload: [String: Any]) {
        guard !NSApp.isActive else { return }
        let content = UNMutableNotificationContent()
        content.title = payload["title"] as? String ?? "TLS"
        content.body = payload["body"] as? String ?? ""
        content.userInfo = [
            "slug": payload["slug"] as? String ?? "",
            "itemId": payload["itemId"] as? String ?? "",
            "issueKey": payload["issueKey"] as? String ?? "",
        ]
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let id = (payload["itemId"] as? String) ?? UUID().uuidString
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }
}

enum LocalDirectory {
    /// Mirrors the daemon's check so the user sees problems before submit.
    static func validate(_ path: String) -> [String: Any] {
        guard path.hasPrefix("/") else { return ["ok": false, "reason": "not_absolute"] }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return ["ok": false, "reason": "not_found"] }
        guard isDir.boolValue else { return ["ok": false, "reason": "not_a_directory"] }
        guard fm.isReadableFile(atPath: path) else { return ["ok": false, "reason": "not_readable"] }
        guard fm.isWritableFile(atPath: path) else { return ["ok": false, "reason": "not_writable"] }
        return ["ok": true, "is_git_repo": isInsideGitWorkTree(URL(fileURLWithPath: path, isDirectory: true))]
    }

    private static func isInsideGitWorkTree(_ url: URL) -> Bool {
        var current = url.standardizedFileURL
        while true {
            if FileManager.default.fileExists(atPath: current.appendingPathComponent(".git").path) { return true }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return false }
            current = parent
        }
    }
}
