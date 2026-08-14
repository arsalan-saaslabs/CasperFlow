import Combine
import Foundation

/// Personal names and jargon stored on this Mac and applied during polish.
@MainActor
final class VocabularyStore: ObservableObject {
  static let shared = VocabularyStore()

  static let maxTermCount = 200
  static let maxFieldLength = 80

  private static let fileName = "vocabulary.json"

  @Published private(set) var terms: [VocabularyTerm] = []

  private init() {
    terms = Self.load()
  }

  /// Adds a term. Returns an error message when the input is invalid.
  func add(heard: String, replacement: String) -> String? {
    guard terms.count < Self.maxTermCount else {
      return "You can save up to \(Self.maxTermCount) terms."
    }
    switch Self.normalizedPair(heard: heard, replacement: replacement) {
    case .invalid(let message):
      return message
    case .ok(let pair):
      if let index = terms.firstIndex(where: { $0.heard.caseInsensitiveCompare(pair.heard) == .orderedSame }) {
        terms[index].replacement = pair.replacement
      } else {
        terms.insert(VocabularyTerm(heard: pair.heard, replacement: pair.replacement), at: 0)
      }
      persist()
      return nil
    }
  }

  func update(id: UUID, heard: String, replacement: String) -> String? {
    guard let index = terms.firstIndex(where: { $0.id == id }) else {
      return "That term is gone."
    }
    switch Self.normalizedPair(heard: heard, replacement: replacement) {
    case .invalid(let message):
      return message
    case .ok(let pair):
      if terms.contains(where: {
        $0.id != id && $0.heard.caseInsensitiveCompare(pair.heard) == .orderedSame
      }) {
        return "That heard-as phrase is already in the list."
      }
      terms[index].heard = pair.heard
      terms[index].replacement = pair.replacement
      persist()
      return nil
    }
  }

  func delete(id: UUID) {
    terms.removeAll { $0.id == id }
    persist()
  }

  private enum NormalizedPair {
    case ok((heard: String, replacement: String))
    case invalid(String)
  }

  private static func normalizedPair(
    heard: String,
    replacement: String
  ) -> NormalizedPair {
    let heardValue = collapseWhitespace(heard)
    let replacementValue = collapseWhitespace(replacement)
    guard !heardValue.isEmpty else { return .invalid("Enter what Hear usually writes.") }
    guard !replacementValue.isEmpty else { return .invalid("Enter the name or jargon to paste.") }
    guard heardValue.count <= maxFieldLength else {
      return .invalid("Heard-as must be \(maxFieldLength) characters or fewer.")
    }
    guard replacementValue.count <= maxFieldLength else {
      return .invalid("Replacement must be \(maxFieldLength) characters or fewer.")
    }
    return .ok((heardValue, replacementValue))
  }

  private func persist() {
    guard let url = Self.fileURL(),
          let data = try? JSONEncoder().encode(terms)
    else { return }
    try? data.write(to: url, options: .atomic)
  }

  private static func load() -> [VocabularyTerm] {
    guard let url = fileURL(),
          let data = try? Data(contentsOf: url),
          let decoded = try? JSONDecoder().decode([VocabularyTerm].self, from: data)
    else {
      return []
    }
    return decoded
  }

  private static func fileURL() -> URL? {
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    guard let folder = root?.appendingPathComponent("CasperFlow", isDirectory: true) else {
      return nil
    }
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.appendingPathComponent(fileName)
  }

  private static func collapseWhitespace(_ text: String) -> String {
    text
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
