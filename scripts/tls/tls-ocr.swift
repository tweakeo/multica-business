// OCR for the-last-fechas.mjs: tls-ocr <image> prints the recognised text
// (macOS Vision, Spanish and English). Compiled on first use into
// ~/Library/Application Support/TLS/bin/tls-ocr.
import Foundation
import Vision
import AppKit

let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let img = NSImage(contentsOf: url), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { exit(1) }
let req = VNRecognizeTextRequest()
req.recognitionLevel = .accurate
req.recognitionLanguages = ["es-ES", "en-US"]
try VNImageRequestHandler(cgImage: cg).perform([req])
for o in req.results ?? [] { if let t = o.topCandidates(1).first { print(t.string) } }
