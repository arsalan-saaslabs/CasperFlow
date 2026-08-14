import Combine
import Foundation

/// Persisted app preferences (keys, theme, per-app tones, tone toggle, hotkeys).
@MainActor
final class AppSettingsStore: ObservableObject {
  static let shared = AppSettingsStore()

  private enum Keys {
    static let pyai = "settings.pyaiApiKey"
    static let openAI = "settings.openAIApiKey"
    static let appearance = "settings.appearance"
    static let toneEnabled = "settings.tonePolishEnabled"
    static let toneOverrides = "settings.toneOverrides"
    static let rephraseHotkey = "settings.rephraseHotkey"
    static let dictateHotkey = "settings.dictateHotkey"
    static let askHotkey = "settings.askHotkey"
    static let historyHotkey = "settings.historyHotkey"
    static let notesHotkey = "settings.notesHotkey"
    static let paletteHotkey = "settings.paletteHotkey"
    static let noteAudioSource = "settings.noteAudioSource"
    static let engineEnabled = "settings.engineEnabled"
    static let pushToTalkStyle = "settings.pushToTalkStyle"
  }

  @Published var pyaiApiKey: String {
    didSet { UserDefaults.standard.set(pyaiApiKey, forKey: Keys.pyai) }
  }

  @Published var openAIApiKey: String {
    didSet { UserDefaults.standard.set(openAIApiKey, forKey: Keys.openAI) }
  }

  @Published var appearance: AppAppearance {
    didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Keys.appearance) }
  }

  /// When false, STT uses raw Hear + lexicon only (no tone punctuation rules).
  @Published var tonePolishEnabled: Bool {
    didSet { UserDefaults.standard.set(tonePolishEnabled, forKey: Keys.toneEnabled) }
  }

  /// profileId → tone raw value overrides.
  @Published var toneOverrides: [String: String] {
    didSet { UserDefaults.standard.set(toneOverrides, forKey: Keys.toneOverrides) }
  }

  /// Global shortcut that rephrases the current selection in any app.
  @Published var rephraseHotkey: HotkeyCombo {
    didSet { persistCombo(rephraseHotkey, key: Keys.rephraseHotkey) }
  }

  /// Hold to dictate into the focused app.
  @Published var dictateHotkey: HotkeyCombo {
    didSet { persistCombo(dictateHotkey, key: Keys.dictateHotkey) }
  }

  /// Hold to ask ChatGPT, then paste the reply.
  @Published var askHotkey: HotkeyCombo {
    didSet { persistCombo(askHotkey, key: Keys.askHotkey) }
  }

  /// Toggle the history overlay over any app.
  @Published var historyHotkey: HotkeyCombo {
    didSet { persistCombo(historyHotkey, key: Keys.historyHotkey) }
  }

  @Published var notesHotkey: HotkeyCombo {
    didSet { persistCombo(notesHotkey, key: Keys.notesHotkey) }
  }

  @Published var paletteHotkey: HotkeyCombo {
    didSet { persistCombo(paletteHotkey, key: Keys.paletteHotkey) }
  }

  @Published var noteAudioSource: NoteAudioSource {
    didSet { UserDefaults.standard.set(noteAudioSource.rawValue, forKey: Keys.noteAudioSource) }
  }

  /// When false, menu-bar Disable pauses global hotkeys until enabled again.
  @Published var engineEnabled: Bool {
    didSet { UserDefaults.standard.set(engineEnabled, forKey: Keys.engineEnabled) }
  }

  /// Hold: keep keys down to talk. Toggle: press once to start, press again to stop.
  @Published var pushToTalkStyle: PushToTalkStyle {
    didSet { UserDefaults.standard.set(pushToTalkStyle.rawValue, forKey: Keys.pushToTalkStyle) }
  }

  private init() {
    let defaults = UserDefaults.standard
    let stored = defaults.string(forKey: Keys.pyai) ?? ""
    let fromEnv = ProcessInfo.processInfo.environment["PYAI_API_KEY"] ?? ""
    let fromFile = Self.loadPyaiFromRepoEnv() ?? ""
    // App Settings (API Keys) wins; .env / process env are optional fallbacks.
    pyaiApiKey = [stored, fromEnv, fromFile].first { !$0.isEmpty } ?? ""
    openAIApiKey = defaults.string(forKey: Keys.openAI) ?? ""
    if let raw = defaults.string(forKey: Keys.appearance),
       let value = AppAppearance(rawValue: raw) {
      appearance = value
    } else {
      appearance = .system
    }
    if defaults.object(forKey: Keys.toneEnabled) == nil {
      tonePolishEnabled = true
    } else {
      tonePolishEnabled = defaults.bool(forKey: Keys.toneEnabled)
    }
    toneOverrides = defaults.dictionary(forKey: Keys.toneOverrides) as? [String: String] ?? [:]
    rephraseHotkey = Self.loadCombo(
      from: defaults,
      key: Keys.rephraseHotkey,
      fallback: .defaultRephrase,
      migratingFrom: .legacyDefaultRephrase
    )
    dictateHotkey = Self.loadCombo(
      from: defaults,
      key: Keys.dictateHotkey,
      fallback: .pushToTalk
    )
    askHotkey = Self.loadCombo(
      from: defaults,
      key: Keys.askHotkey,
      fallback: .askChat
    )
    historyHotkey = Self.loadCombo(
      from: defaults,
      key: Keys.historyHotkey,
      fallback: .defaultHistory
    )
    notesHotkey = Self.loadCombo(
      from: defaults,
      key: Keys.notesHotkey,
      fallback: .defaultNotes
    )
    paletteHotkey = Self.loadCombo(
      from: defaults,
      key: Keys.paletteHotkey,
      fallback: .defaultPalette
    )
    if let raw = defaults.string(forKey: Keys.noteAudioSource),
       let source = NoteAudioSource(rawValue: raw) {
      noteAudioSource = source
    } else {
      noteAudioSource = .system
    }
    if defaults.object(forKey: Keys.engineEnabled) == nil {
      engineEnabled = true
    } else {
      engineEnabled = defaults.bool(forKey: Keys.engineEnabled)
    }
    if let raw = defaults.string(forKey: Keys.pushToTalkStyle),
       let style = PushToTalkStyle(rawValue: raw) {
      pushToTalkStyle = style
    } else {
      pushToTalkStyle = .hold
    }
  }

  func tone(for profile: AppToneProfile) -> WritingTone {
    if let raw = toneOverrides[profile.id], let tone = WritingTone(rawValue: raw) {
      return tone
    }
    return profile.defaultTone
  }

  func setTone(_ tone: WritingTone, for profile: AppToneProfile) {
    var next = toneOverrides
    if tone == profile.defaultTone {
      next.removeValue(forKey: profile.id)
    } else {
      next[profile.id] = tone.rawValue
    }
    toneOverrides = next
  }

  func resolvedTone(bundleIdentifier: String?, localizedName: String? = nil) -> WritingTone {
    let profile = AppToneProfile.matching(
      bundleIdentifier: bundleIdentifier,
      localizedName: localizedName
    )
    return tone(for: profile)
  }

  func resetToneOverrides() {
    toneOverrides = [:]
  }

  func combo(for action: HotkeyAction) -> HotkeyCombo {
    switch action {
    case .dictate: return dictateHotkey
    case .ask: return askHotkey
    case .rephrase: return rephraseHotkey
    case .history: return historyHotkey
    case .notes: return notesHotkey
    case .palette: return paletteHotkey
    }
  }

  /// - Returns: Error message if the combo is invalid or already used.
  func assign(_ combo: HotkeyCombo, to action: HotkeyAction) -> String? {
    guard combo.isValidShortcut else {
      return "Press a key or a modifier (Esc is reserved)."
    }
    for other in HotkeyAction.allCases where other != action {
      if combo.conflicts(with: self.combo(for: other)) {
        return "That shortcut is already used for \(other.title)."
      }
    }
    switch action {
    case .dictate: dictateHotkey = combo
    case .ask: askHotkey = combo
    case .rephrase: rephraseHotkey = combo
    case .history: historyHotkey = combo
    case .notes: notesHotkey = combo
    case .palette: paletteHotkey = combo
    }
    return nil
  }

  func resetHotkey(_ action: HotkeyAction) {
    switch action {
    case .dictate: dictateHotkey = .pushToTalk
    case .ask: askHotkey = .askChat
    case .rephrase: rephraseHotkey = .defaultRephrase
    case .history: historyHotkey = .defaultHistory
    case .notes: notesHotkey = .defaultNotes
    case .palette: paletteHotkey = .defaultPalette
    }
  }

  func resetRephraseHotkey() {
    resetHotkey(.rephrase)
  }

  private func persistCombo(_ combo: HotkeyCombo, key: String) {
    guard let data = try? JSONEncoder().encode(combo) else { return }
    UserDefaults.standard.set(data, forKey: key)
  }

  private static func loadCombo(
    from defaults: UserDefaults,
    key: String,
    fallback: HotkeyCombo,
    migratingFrom legacy: HotkeyCombo? = nil
  ) -> HotkeyCombo {
    guard let data = defaults.data(forKey: key),
          let combo = try? JSONDecoder().decode(HotkeyCombo.self, from: data),
          combo.isValidShortcut
    else {
      return fallback
    }
    if let legacy, combo == legacy {
      return fallback
    }
    return combo
  }

  private static func loadPyaiFromRepoEnv() -> String? {
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let packageRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent() // App
      .deletingLastPathComponent() // CasperFlow
      .deletingLastPathComponent() // Sources
    let candidates = [
      packageRoot.appendingPathComponent(".env"),
      cwd.appendingPathComponent(".env"),
    ]
    for url in candidates {
      guard let raw = try? String(contentsOf: url.standardizedFileURL, encoding: .utf8) else {
        continue
      }
      for line in raw.split(whereSeparator: \.isNewline) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("PYAI_API_KEY=") {
          return String(trimmed.dropFirst("PYAI_API_KEY=".count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
      }
    }
    return nil
  }
}
