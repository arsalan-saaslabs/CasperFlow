import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
  case dictation
  case keys
  case appTones
  case appearance
  case permissions

  var id: String { rawValue }

  var title: String {
    switch self {
    case .dictation: return "Dictation"
    case .keys: return "API Keys"
    case .appTones: return "App tones"
    case .appearance: return "Appearance"
    case .permissions: return "Permissions"
    }
  }

  var systemImage: String {
    switch self {
    case .dictation: return "waveform"
    case .keys: return "key.fill"
    case .appTones: return "text.bubble"
    case .appearance: return "circle.lefthalf.filled"
    case .permissions: return "lock.shield"
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
