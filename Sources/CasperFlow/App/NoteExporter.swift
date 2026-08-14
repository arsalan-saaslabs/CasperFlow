import AppKit
import Foundation
import UniformTypeIdentifiers

enum NoteExportFormat: String, CaseIterable, Identifiable {
  case markdown
  case plainText

  var id: String { rawValue }

  var menuTitle: String {
    switch self {
    case .markdown: return "Markdown (.md)"
    case .plainText: return "Plain text (.txt)"
    }
  }

  var fileExtension: String {
    switch self {
    case .markdown: return "md"
    case .plainText: return "txt"
    }
  }

  var contentType: UTType {
    switch self {
    case .markdown:
      return UTType(filenameExtension: "md") ?? .text
    case .plainText:
      return .plainText
    }
  }
}

/// Builds note files for the save panel. User picks the destination.
enum NoteExporter {
  static func document(for note: NoteEntry, format: NoteExportFormat) -> String {
    switch format {
    case .markdown: return markdown(note)
    case .plainText: return plainText(note)
    }
  }

  static func suggestedFileName(for note: NoteEntry, format: NoteExportFormat) -> String {
    "\(fileBaseName(note.title)).\(format.fileExtension)"
  }

  static func presentSavePanel(for note: NoteEntry, format: NoteExportFormat) {
    let panel = NSSavePanel()
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    panel.allowedContentTypes = [format.contentType]
    panel.nameFieldStringValue = suggestedFileName(for: note, format: format)
    panel.title = "Export note"

    guard panel.runModal() == .OK, let url = panel.url else { return }
    let body = document(for: note, format: format)
    do {
      try body.write(to: url, atomically: true, encoding: .utf8)
    } catch {
      let alert = NSAlert()
      alert.messageText = "Could not export note"
      alert.informativeText = error.localizedDescription
      alert.alertStyle = .warning
      alert.runModal()
    }
  }

  private static func markdown(_ note: NoteEntry) -> String {
    var lines: [String] = [
      "# \(note.title)",
      "",
      "- Captured: \(note.createdAt.formatted(date: .long, time: .shortened))",
      "- Source: \(note.sourceTitle)",
      "",
    ]
    if !note.summary.isEmpty {
      lines.append(contentsOf: ["## Summary", "", note.summary, ""])
    }
    if !note.actionItems.isEmpty {
      lines.append("## Action items")
      lines.append("")
      lines.append(contentsOf: note.actionItems.map { "- \($0)" })
      lines.append("")
    }
    lines.append(contentsOf: ["## Transcript", "", note.body.isEmpty ? "_Empty_" : note.body, ""])
    return lines.joined(separator: "\n")
  }

  private static func plainText(_ note: NoteEntry) -> String {
    var lines: [String] = [
      note.title,
      "Captured: \(note.createdAt.formatted(date: .long, time: .shortened))",
      "Source: \(note.sourceTitle)",
      "",
    ]
    if !note.summary.isEmpty {
      lines.append(contentsOf: ["Summary", note.summary, ""])
    }
    if !note.actionItems.isEmpty {
      lines.append("Action items")
      lines.append(contentsOf: note.actionItems.map { "- \($0)" })
      lines.append("")
    }
    lines.append(contentsOf: ["Transcript", note.body])
    return lines.joined(separator: "\n")
  }

  private static func fileBaseName(_ title: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let mapped = trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
    let collapsed = String(mapped)
      .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "- "))
    let clipped = String(collapsed.prefix(60))
    return clipped.isEmpty ? "note" : clipped
  }
}
