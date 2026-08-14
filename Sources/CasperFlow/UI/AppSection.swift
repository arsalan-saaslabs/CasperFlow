import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
  case dictation
  case notes
  case keys
  case shortcuts
  case history
  case vocabulary
  case appTones
  case appearance
  case permissions
  case diagnostics

  var id: String { rawValue }

  var title: String {
    switch self {
    case .dictation: return "Dictation"
    case .notes: return "Note taker"
    case .keys: return "API Keys"
    case .shortcuts: return "Shortcuts"
    case .history: return "History"
    case .vocabulary: return "Vocabulary"
    case .appTones: return "App tones"
    case .appearance: return "Appearance"
    case .permissions: return "Permissions"
    case .diagnostics: return "Diagnostics"
    }
  }

  var systemImage: String {
    switch self {
    case .dictation: return "waveform"
    case .notes: return "note.text"
    case .keys: return "key.fill"
    case .shortcuts: return "keyboard"
    case .history: return "clock.arrow.circlepath"
    case .vocabulary: return "textformat.abc"
    case .appTones: return "text.bubble"
    case .appearance: return "circle.lefthalf.filled"
    case .permissions: return "lock.shield"
    case .diagnostics: return "stethoscope"
    }
  }
}

enum WFTheme {
  /// Voice bars / accent — Casper teal `#2DD4BF`.
  static let accent = Color(red: 45 / 255, green: 212 / 255, blue: 191 / 255)
  static let accentSoft = Color(red: 45 / 255, green: 212 / 255, blue: 191 / 255).opacity(0.16)
  /// Ghost body on light / eyes on dark — `#11100E`.
  static let ink = Color(red: 17 / 255, green: 16 / 255, blue: 14 / 255)
  /// Ghost body on dark — `#F6F1E8`.
  static let cream = Color(red: 246 / 255, green: 241 / 255, blue: 232 / 255)
  static let mist = Color(red: 246 / 255, green: 241 / 255, blue: 232 / 255)
  static let panel = Color(nsColor: .controlBackgroundColor)
  static let wordmarkFont = Font.system(size: 22, weight: .bold, design: .rounded)
  static let endorsementFont = Font.system(size: 11, weight: .semibold, design: .rounded)
}
