import AppKit
import Foundation

/// Persisted keyboard shortcut (modifiers + optional key).
struct HotkeyCombo: Codable, Equatable, Sendable {
  var usesControl: Bool
  var usesOption: Bool
  var usesCommand: Bool
  var usesShift: Bool
  /// NSEvent key code. `nil` means a modifier-only chord.
  var keyCode: UInt16?
  /// Human label for the non-modifier key, e.g. `"R"`.
  var keyLabel: String

  static let defaultRephrase = HotkeyCombo(
    usesControl: true,
    usesOption: false,
    usesCommand: true,
    usesShift: false,
    keyCode: nil,
    keyLabel: ""
  )

  /// Previous default (⌃⌥⌘). Migrated to `defaultRephrase` on load.
  static let legacyDefaultRephrase = HotkeyCombo(
    usesControl: true,
    usesOption: true,
    usesCommand: true,
    usesShift: false,
    keyCode: nil,
    keyLabel: ""
  )

  /// Built-in push-to-talk: Control + Option, no Command/Shift, no key.
  static let pushToTalk = HotkeyCombo(
    usesControl: true,
    usesOption: true,
    usesCommand: false,
    usesShift: false,
    keyCode: nil,
    keyLabel: ""
  )

  static let defaultHistory = HotkeyCombo(
    usesControl: true,
    usesOption: false,
    usesCommand: false,
    usesShift: true,
    keyCode: 4,
    keyLabel: "H"
  )

  /// Toggle command palette: Control + Shift + O.
  static let defaultPalette = HotkeyCombo(
    usesControl: true,
    usesOption: false,
    usesCommand: false,
    usesShift: true,
    keyCode: 31,
    keyLabel: "O"
  )

  /// Toggle note taker: Control + Shift + N.
  static let defaultNotes = HotkeyCombo(
    usesControl: true,
    usesOption: false,
    usesCommand: false,
    usesShift: true,
    keyCode: 45,
    keyLabel: "N"
  )

  /// Hold to dictate a ChatGPT writing command: Option + Command.
  static let askChat = HotkeyCombo(
    usesControl: false,
    usesOption: true,
    usesCommand: true,
    usesShift: false,
    keyCode: nil,
    keyLabel: ""
  )

  var displayName: String {
    var parts: [String] = []
    if usesControl { parts.append("⌃") }
    if usesOption { parts.append("⌥") }
    if usesShift { parts.append("⇧") }
    if usesCommand { parts.append("⌘") }
    let label = keyLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    if !label.isEmpty {
      parts.append(label.uppercased())
    }
    return parts.isEmpty ? "None" : parts.joined(separator: " + ")
  }

  var modifierCount: Int {
    [usesControl, usesOption, usesCommand, usesShift].filter { $0 }.count
  }

  /// A shortcut is valid if it has a key, a modifier, or both. Esc is reserved to cancel recording.
  var isValidShortcut: Bool {
    if keyCode == 53 { return false }
    return modifierCount >= 1 || keyCode != nil
  }

  /// Hold actions may be a modifier chord or a single key held down.
  var isValidHoldShortcut: Bool {
    isValidShortcut
  }

  /// Reject empty shortcuts and chords reserved for dictate / Ask ChatGPT.
  var isValidRephraseShortcut: Bool {
    isValidShortcut
  }

  func conflicts(with other: HotkeyCombo) -> Bool {
    self == other
  }

  func matches(flags: NSEvent.ModifierFlags, keyCode eventKeyCode: UInt16?) -> Bool {
    let mods = flags.intersection(.deviceIndependentFlagsMask)
    guard mods.contains(.control) == usesControl else { return false }
    guard mods.contains(.option) == usesOption else { return false }
    guard mods.contains(.command) == usesCommand else { return false }
    guard mods.contains(.shift) == usesShift else { return false }
    if let requiredKey = self.keyCode {
      return eventKeyCode == requiredKey
    }
    return eventKeyCode == nil
  }

  static func from(event: NSEvent) -> HotkeyCombo? {
    if event.type == .keyDown {
      guard !event.isARepeat else { return nil }
      guard !Self.isModifierKeyCode(event.keyCode) else { return nil }
      let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      return HotkeyCombo(
        usesControl: mods.contains(.control),
        usesOption: mods.contains(.option),
        usesCommand: mods.contains(.command),
        usesShift: mods.contains(.shift),
        keyCode: event.keyCode,
        keyLabel: Self.label(forKeyCode: event.keyCode, event: event)
      )
    }
    if event.type == .flagsChanged {
      let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      let combo = HotkeyCombo(
        usesControl: mods.contains(.control),
        usesOption: mods.contains(.option),
        usesCommand: mods.contains(.command),
        usesShift: mods.contains(.shift),
        keyCode: nil,
        keyLabel: ""
      )
      return combo.modifierCount >= 1 ? combo : nil
    }
    return nil
  }

  private static func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
    switch keyCode {
    case 54, 55, 56, 57, 58, 59, 60, 61, 62, 63:
      return true
    default:
      return false
    }
  }

  private static func label(forKeyCode keyCode: UInt16, event: NSEvent) -> String {
    if let chars = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespaces),
       !chars.isEmpty {
      return chars.uppercased()
    }
    return "Key \(keyCode)"
  }
}

enum HotkeyAction: String, CaseIterable, Identifiable {
  case dictate
  case ask
  case rephrase
  case history
  case notes
  case palette

  var id: String { rawValue }

  var title: String {
    switch self {
    case .dictate: return "Dictate"
    case .ask: return "Ask ChatGPT"
    case .rephrase: return "Rephrase selection"
    case .history: return "History overlay"
    case .notes: return "Note taker"
    case .palette: return "Command overlay"
    }
  }

  var detail: String {
    switch self {
    case .dictate:
      return "Hold or tap this shortcut (see Talk style above). Release or tap again to paste."
    case .ask:
      return "Hold or tap to ask ChatGPT. Same Talk style as Dictate. Needs an OpenAI key."
    case .rephrase:
      return "Select text, then press this shortcut. One key is enough, or add modifiers (for example ⌃⌘R)."
    case .history:
      return "Show or hide the history palette. Drag the header to move it, Esc to close. Default ⌃⇧H."
    case .notes:
      return "Start or stop Note taker from anywhere (meeting or YouTube). Default ⌃⇧N. Choose mic vs system audio in the menu bar or overlay."
    case .palette:
      return "Show a small overlay with all actions and tone chips. Default ⌃⇧O. Same controls are in the menu bar."
    }
  }

  var defaultCombo: HotkeyCombo {
    switch self {
    case .dictate: return .pushToTalk
    case .ask: return .askChat
    case .rephrase: return .defaultRephrase
    case .history: return .defaultHistory
    case .notes: return .defaultNotes
    case .palette: return .defaultPalette
    }
  }
}
