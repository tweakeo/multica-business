import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves the bundled desktop renderer at `tls-app://app/`, so the UI never
/// depends on a dev server or `file://`. Only files under Resources/renderer
/// are reachable.
final class AppSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "tls-app"
    static let host = "app"
    static let origin = "\(scheme)://\(host)"
    static var entryURL: URL { URL(string: "\(origin)/index.html")! }

    private let root: URL

    init(root: URL) {
        self.root = root.standardizedFileURL
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, url.host == Self.host else {
            task.didFailWithError(URLError(.badURL))
            return
        }
        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }
        let file = root.appendingPathComponent(String(path.dropFirst())).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"),
              let data = try? Data(contentsOf: file)
        else {
            respond(task, url: url, status: 404, mime: "text/plain", data: Data("Not found".utf8))
            return
        }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        respond(task, url: url, status: 200, mime: mime, data: data)
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    private func respond(_ task: WKURLSchemeTask, url: URL, status: Int, mime: String, data: Data) {
        let headers = [
            "Content-Type": mime == "text/javascript" ? "application/javascript" : mime,
            "Content-Length": "\(data.count)",
            "Cache-Control": "no-cache",
            "Access-Control-Allow-Origin": Self.origin,
        ]
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }
}
