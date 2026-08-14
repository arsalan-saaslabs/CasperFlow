import Foundation

enum NoteAudioSource: String, CaseIterable, Identifiable, Sendable {
  case microphone
  case system
  case both

  var id: String { rawValue }

  var title: String {
    switch self {
    case .microphone: return "Microphone"
    case .system: return "System audio"
    case .both: return "Mic + system"
    }
  }

  var detail: String {
    switch self {
    case .microphone: return "Your voice only."
    case .system: return "YouTube and app playback. Needs Screen Recording."
    case .both: return "Meetings: your mic plus what the Mac plays. Best accuracy in calls."
    }
  }

  var usesMicrophone: Bool {
    self == .microphone || self == .both
  }

  var usesSystemAudio: Bool {
    self == .system || self == .both
  }
}

struct NoteEntry: Codable, Identifiable, Equatable, Hashable, Sendable {
  var id: UUID
  var title: String
  var body: String
  var createdAt: Date
  var updatedAt: Date
  var source: String

  init(
    id: UUID = UUID(),
    title: String,
    body: String = "",
    createdAt: Date = Date(),
    updatedAt: Date = Date(),
    source: String
  ) {
    self.id = id
    self.title = title
    self.body = body
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.source = source
  }
}

/// Local note-taker sessions (not pasted into other apps).
@MainActor
final class NoteStore: ObservableObject {
  static let shared = NoteStore()

  private static let fileName = "notes.json"
  private static let maxNotes = 80

  @Published private(set) var notes: [NoteEntry] = []
  @Published private(set) var activeNoteId: UUID?

  var activeNote: NoteEntry? {
    guard let activeNoteId else { return nil }
    return notes.first { $0.id == activeNoteId }
  }

  private init() {
    notes = Self.load()
  }

  func beginSession(source: NoteAudioSource) {
    let stamp = Date().formatted(date: .abbreviated, time: .shortened)
    let note = NoteEntry(title: "Note · \(stamp)", source: source.rawValue)
    notes.insert(note, at: 0)
    activeNoteId = note.id
    prune()
    persist()
  }

  func append(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let id = activeNoteId,
          let index = notes.firstIndex(where: { $0.id == id })
    else { return }
    if notes[index].body.isEmpty {
      notes[index].body = trimmed
    } else {
      notes[index].body += " " + trimmed
    }
    notes[index].updatedAt = Date()
    persist()
  }

  func endSession() {
    activeNoteId = nil
    persist()
  }

  func cancelIfEmpty() {
    guard let id = activeNoteId else { return }
    if let note = notes.first(where: { $0.id == id }), note.body.isEmpty {
      delete(id: id)
      return
    }
    endSession()
  }

  func delete(id: UUID) {
    if activeNoteId == id {
      activeNoteId = nil
    }
    notes.removeAll { $0.id == id }
    persist()
  }

  func updateTitle(id: UUID, title: String) {
    guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    notes[index].title = String(trimmed.prefix(120))
    notes[index].updatedAt = Date()
    persist()
  }

  private func prune() {
    if notes.count > Self.maxNotes {
      notes = Array(notes.prefix(Self.maxNotes))
    }
  }

  private func persist() {
    guard let url = Self.fileURL(),
          let data = try? JSONEncoder().encode(notes)
    else { return }
    try? data.write(to: url, options: .atomic)
  }

  private static func load() -> [NoteEntry] {
    guard let url = fileURL(),
          let data = try? Data(contentsOf: url),
          let decoded = try? JSONDecoder().decode([NoteEntry].self, from: data)
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
}
