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
    didSet { persistRephraseHotkey() }
  }

  private init() {
    let defaults = UserDefaults.standard
    let fromEnv = ProcessInfo.processInfo.environment["PYAI_API_KEY"] ?? ""
    let fromFile = Self.loadPyaiFromRepoEnv() ?? ""
    let stored = defaults.string(forKey: Keys.pyai) ?? ""
    pyaiApiKey = [fromEnv, fromFile, stored].first { !$0.isEmpty } ?? ""
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
    rephraseHotkey = Self.loadRephraseHotkey(from: defaults)
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

  func resetRephraseHotkey() {
    rephraseHotkey = .defaultRephrase
  }

  private func persistRephraseHotkey() {
    guard let data = try? JSONEncoder().encode(rephraseHotkey) else { return }
    UserDefaults.standard.set(data, forKey: Keys.rephraseHotkey)
  }

  private static func loadRephraseHotkey(from defaults: UserDefaults) -> HotkeyCombo {
    guard let data = defaults.data(forKey: Keys.rephraseHotkey),
          let combo = try? JSONDecoder().decode(HotkeyCombo.self, from: data),
          combo.isValidRephraseShortcut
    else {
      return .defaultRephrase
    }
    if combo == .legacyDefaultRephrase {
      return .defaultRephrase
    }
    return combo
  }

  private static func loadPyaiFromRepoEnv() -> String? {
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let candidates = [
      cwd.appendingPathComponent(".env"),
      cwd.appendingPathComponent("../.env"),
      URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("../.env"),
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
