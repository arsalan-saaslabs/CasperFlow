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
  static let accent = Color(red: 0.07, green: 0.55, blue: 0.52)
  static let accentSoft = Color(red: 0.07, green: 0.55, blue: 0.52).opacity(0.14)
  static let ink = Color(red: 0.12, green: 0.16, blue: 0.18)
  static let mist = Color(red: 0.94, green: 0.96, blue: 0.96)
  static let panel = Color(nsColor: .controlBackgroundColor)
}
