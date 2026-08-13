import Foundation

/// User-selectable writing tone applied after STT (local rules; optional LLM later).
enum WritingTone: String, CaseIterable, Codable, Identifiable, Sendable {
  case casual
  case professional
  case developer
  case general

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .casual: return "Casual"
    case .professional: return "Professional"
    case .developer: return "Developer"
    case .general: return "General"
    }
  }

  var detail: String {
    switch self {
    case .casual: return "Relaxed caps, no forced periods"
    case .professional: return "Sentence caps + trailing period"
    case .developer: return "Light punctuation, skip spellcheck"
    case .general: return "Balanced punctuation"
    }
  }
}

/// Built-in app profile the user can override with a custom tone.
struct AppToneProfile: Identifiable, Hashable, Sendable {
  let id: String
  let displayName: String
  /// Substrings matched against bundle identifier (lowercased).
  let bundleMatchers: [String]
  /// Substrings matched against localized app name (lowercased).
  let nameMatchers: [String]
  let defaultTone: WritingTone

  static let catalog: [AppToneProfile] = [
    AppToneProfile(
      id: "slack",
      displayName: "Slack",
      bundleMatchers: ["slack"],
      nameMatchers: ["slack"],
      defaultTone: .casual
    ),
    AppToneProfile(
      id: "mail",
      displayName: "Mail",
      bundleMatchers: ["mail", "outlook", "spark"],
      nameMatchers: ["mail", "outlook", "spark"],
      defaultTone: .professional
    ),
    AppToneProfile(
      id: "cursor",
      displayName: "Cursor",
      // Cursor.app bundle id is ToDesktop-based and does not contain "cursor".
      bundleMatchers: ["cursor", "todesktop.230313mzl4w4u92"],
      nameMatchers: ["cursor"],
      defaultTone: .developer
    ),
    AppToneProfile(
      id: "vscode",
      displayName: "Visual Studio Code",
      bundleMatchers: ["com.microsoft.vscode"],
      nameMatchers: ["visual studio code", "code"],
      defaultTone: .developer
    ),
    AppToneProfile(
      id: "chrome",
      displayName: "Google Chrome",
      bundleMatchers: ["chrome", "google.chrome"],
      nameMatchers: ["google chrome", "chrome"],
      defaultTone: .general
    ),
    AppToneProfile(
      id: "safari",
      displayName: "Safari",
      bundleMatchers: ["safari"],
      nameMatchers: ["safari"],
      defaultTone: .general
    ),
    AppToneProfile(
      id: "notes",
      displayName: "Notes",
      bundleMatchers: ["notes", "notion", "obsidian"],
      nameMatchers: ["notes", "notion", "obsidian"],
      defaultTone: .general
    ),
    AppToneProfile(
      id: "general",
      displayName: "Other apps",
      bundleMatchers: [],
      nameMatchers: [],
      defaultTone: .general
    ),
  ]

  static func matching(
    bundleIdentifier: String?,
    localizedName: String? = nil
  ) -> AppToneProfile {
    let bundle = bundleIdentifier?.lowercased() ?? ""
    let name = localizedName?.lowercased() ?? ""

    // Prefer bundle id (more specific), then display name.
    // Cursor before VS Code so name "Code" doesn't steal Cursor.
    let ordered = catalog.filter { $0.id != "general" }

    for profile in ordered {
      if !bundle.isEmpty,
         profile.bundleMatchers.contains(where: { bundle.contains($0) }) {
        return profile
      }
    }

    for profile in ordered {
      if !name.isEmpty,
         profile.nameMatchers.contains(where: { name == $0 || name.contains($0) }) {
        // Avoid mapping every app named "... Code ..." except VS Code / Cursor handled above.
        if profile.id == "vscode", name.contains("cursor") { continue }
        if profile.id == "vscode", name != "code", !name.contains("visual studio") {
          continue
        }
        return profile
      }
    }

    return catalog.first { $0.id == "general" }!
  }
}

/// Appearance preference for the settings window.
enum AppAppearance: String, CaseIterable, Codable, Identifiable, Sendable {
  case system
  case light
  case dark

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .system: return "System"
    case .light: return "Light"
    case .dark: return "Dark"
    }
  }
}
