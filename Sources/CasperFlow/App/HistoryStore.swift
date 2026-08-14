import Combine
import Foundation

/// Task history persisted on this Mac (dictation, Ask ChatGPT, rephrase).
@MainActor
final class HistoryStore: ObservableObject {
  static let shared = HistoryStore()

  private static let maxUnsavedCount = 80
  private static let fileName = "history.json"

  @Published private(set) var items: [HistoryItem] = []

  private init() {
    items = Self.load()
  }

  func add(text: String, kind: HistoryTaskKind, appName: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let item = HistoryItem(text: trimmed, kind: kind, appName: appName)
    items.insert(item, at: 0)
    pruneUnsaved()
    persist()
  }

  func toggleSaved(_ id: UUID) {
    guard let index = items.firstIndex(where: { $0.id == id }) else { return }
    items[index].isSaved.toggle()
    persist()
  }

  func delete(_ id: UUID) {
    items.removeAll { $0.id == id }
    persist()
  }

  func clearUnsaved() {
    items.removeAll { !$0.isSaved }
    persist()
  }

  func items(filter: HistoryFilter) -> [HistoryItem] {
    switch filter {
    case .all:
      return items
    case .saved:
      return items.filter(\.isSaved)
    case .kind(let kind):
      return items.filter { $0.kind == kind }
    }
  }

  private func pruneUnsaved() {
    var unsavedIndexes = items.indices.filter { !items[$0].isSaved }
    while unsavedIndexes.count > Self.maxUnsavedCount, let last = unsavedIndexes.last {
      items.remove(at: last)
      unsavedIndexes = items.indices.filter { !items[$0].isSaved }
    }
  }

  private func persist() {
    guard let url = Self.fileURL(),
          let data = try? JSONEncoder().encode(items)
    else { return }
    try? data.write(to: url, options: .atomic)
  }

  private static func load() -> [HistoryItem] {
    guard let url = fileURL(),
          let data = try? Data(contentsOf: url),
          let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data)
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

enum HistoryFilter: Hashable {
  case all
  case saved
  case kind(HistoryTaskKind)
}
