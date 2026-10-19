#if DEBUG
import AppKit
import WebKit

/// Debug-build-only automation hooks so the host can be verified headlessly:
///
///   osascript -l JavaScript -e "ObjC.import('Foundation'); $.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately('com.leonmag.tls.debug', 'snapshot', $(), true)"
///
/// Commands (notification object): `snapshot` writes debug/snapshot.png;
/// `eval` runs debug/eval.js in the key window and writes debug/eval-result.json.
/// Files live in ~/Library/Application Support/TLS/debug. Compiled out of Release.
enum DebugHooks {
    private static var observer: NSObjectProtocol?
    static var directory: URL { AppPaths.support.appendingPathComponent("debug", isDirectory: true) }

    static func install(webViewProvider: @escaping () -> WKWebView?) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.leonmag.tls.debug"), object: nil, queue: .main
        ) { note in
            guard let command = note.object as? String, let webView = webViewProvider() else { return }
            switch command {
            case "snapshot":
                webView.takeSnapshot(with: nil) { image, _ in
                    guard let image, let tiff = image.tiffRepresentation,
                          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
                    else { return }
                    try? png.write(to: directory.appendingPathComponent("snapshot.png"))
                }
            case "eval":
                guard let source = try? String(contentsOf: directory.appendingPathComponent("eval.js"), encoding: .utf8) else { return }
                webView.callAsyncJavaScript(source, arguments: [:], in: nil, in: .page) { result in
                    let output: Any
                    switch result {
                    case let .success(value): output = ["ok": true, "value": value]
                    case let .failure(error): output = ["ok": false, "error": "\(error)"]
                    }
                    try? JSONText.encode(output).write(to: directory.appendingPathComponent("eval-result.json"), atomically: true, encoding: .utf8)
                }
            default:
                break
            }
        }
    }
}
#endif
