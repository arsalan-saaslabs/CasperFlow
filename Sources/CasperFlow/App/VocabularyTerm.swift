import Foundation

/// One user-taught mishear → preferred spelling (names, product jargon).
struct VocabularyTerm: Codable, Identifiable, Equatable, Hashable, Sendable {
  var id: UUID
  var heard: String
  var replacement: String

  init(id: UUID = UUID(), heard: String, replacement: String) {
    self.id = id
    self.heard = heard
    self.replacement = replacement
  }
}
