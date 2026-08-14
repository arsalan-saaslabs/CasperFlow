import Foundation

enum HistoryTaskKind: String, Codable, CaseIterable, Identifiable, Sendable {
  case dictate
  case ask
  case rephrase

  var id: String { rawValue }

  var title: String {
    switch self {
    case .dictate: return "Dictate"
    case .ask: return "Ask ChatGPT"
    case .rephrase: return "Rephrase"
    }
  }

  var systemImage: String {
    switch self {
    case .dictate: return "mic.fill"
    case .ask: return "sparkles"
    case .rephrase: return "text.quote"
    }
  }
}

struct HistoryItem: Codable, Identifiable, Equatable, Hashable, Sendable {
  var id: UUID
  var text: String
  var kind: HistoryTaskKind
  var appName: String
  var createdAt: Date
  var isSaved: Bool

  init(
    id: UUID = UUID(),
    text: String,
    kind: HistoryTaskKind,
    appName: String,
    createdAt: Date = Date(),
    isSaved: Bool = false
  ) {
    self.id = id
    self.text = text
    self.kind = kind
    self.appName = appName
    self.createdAt = createdAt
    self.isSaved = isSaved
  }
}
