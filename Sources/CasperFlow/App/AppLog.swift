import AppKit
import Foundation

/// Local rolling error log. Never writes secrets (API keys, Bearer tokens).
enum AppLog {
  private static let lock = NSLock()
  private static let maxBytes = 400_000
  private static let fileName = "casperflow.log"

  static var fileURL: URL? {
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    guard let folder = root?.appendingPathComponent("CasperFlow", isDirectory: true) else {
      return nil
    }
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.appendingPathComponent(fileName)
  }

  static func info(_ message: String, file: String = #fileID, line: Int = #line) {
    append("INFO  \(stamp()) \(file):\(line) \(sanitize(message))")
  }

  static func error(
    _ message: String,
    error: Error? = nil,
    file: String = #fileID,
    line: Int = #line
  ) {
    var text = "ERROR \(stamp()) \(file):\(line) \(sanitize(message))"
    if let error {
      let ns = error as NSError
      text += " | \(sanitize(ns.localizedDescription)) [\(ns.domain) \(ns.code)]"
    }
    append(text)
  }

  static func readSanitized() -> String {
    lock.lock()
    defer { lock.unlock() }
    guard let url = fileURL, let data = try? Data(contentsOf: url),
          let raw = String(data: data, encoding: .utf8)
    else {
      return "No log file yet."
    }
    return sanitize(raw)
  }

  /// Opens Mail with the log attached. Recipient comes from Info.plist `CasperFlowSupportEmail` if set.
  @MainActor
  static func sendToSupport() {
    guard let url = fileURL else { return }
    if !FileManager.default.fileExists(atPath: url.path) {
      append("INFO  \(stamp()) log created for support send")
    }
    let service = NSSharingService(named: .composeEmail)
    service?.subject = "CasperFlow error logs"
    if let email = Bundle.main.object(forInfoDictionaryKey: "CasperFlowSupportEmail") as? String,
       !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      service?.recipients = [email]
    }
    if service?.canPerform(withItems: [url]) == true {
      service?.perform(withItems: [url])
      return
    }
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  @MainActor
  static func revealInFinder() {
    guard let url = fileURL else { return }
    if !FileManager.default.fileExists(atPath: url.path) {
      append("INFO  \(stamp()) log created")
    }
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  @MainActor
  static func copyToPasteboard() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(readSanitized(), forType: .string)
  }

  private static func append(_ line: String) {
    lock.lock()
    defer { lock.unlock() }
    guard let url = fileURL else { return }
    let payload = (line + "\n").data(using: .utf8) ?? Data()
    if !FileManager.default.fileExists(atPath: url.path) {
      FileManager.default.createFile(atPath: url.path, contents: payload)
      return
    }
    guard let handle = try? FileHandle(forWritingTo: url) else { return }
    defer { try? handle.close() }
    _ = try? handle.seekToEnd()
    try? handle.write(contentsOf: payload)
    if let size = try? handle.offset(), size > maxBytes {
      try? handle.close()
      trimFile(at: url)
    }
  }

  private static func trimFile(at url: URL) {
    guard let data = try? Data(contentsOf: url), data.count > maxBytes / 2 else { return }
    let keep = data.suffix(maxBytes / 2)
    try? keep.write(to: url, options: .atomic)
  }

  private static func stamp() -> String {
    ISO8601DateFormatter().string(from: Date())
  }

  static func sanitize(_ text: String) -> String {
    var output = text
    let patterns = [
      #"(?i)(sk-[A-Za-z0-9_-]{8,})"#,
      #"(?i)(Bearer\s+)\S+"#,
      #"(?i)((?:PYAI_API_KEY|OPENAI_API_KEY|api[_-]?key)\s*[=:]\s*)\S+"#,
    ]
    let replacements = ["[redacted-key]", "$1[redacted]", "$1[redacted]"]
    for (pattern, replacement) in zip(patterns, replacements) {
      output = output.replacingOccurrences(
        of: pattern,
        with: replacement,
        options: .regularExpression
      )
    }
    return output
  }
}
