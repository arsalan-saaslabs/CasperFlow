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

  /// Reject empty shortcuts and chords reserved for dictate / Ask ChatGPT.
  var isValidRephraseShortcut: Bool {
    guard modifierCount >= 2 else { return false }
    return self != .pushToTalk && self != .askChat
  }

  func matches(flags: NSEvent.ModifierFlags, keyCode eventKeyCode: UInt16?) -> Bool {
    let mods = flags.intersection(.deviceIndependentFlagsMask)
    guard mods.contains(.control) == usesControl else { return false }
    guard mods.contains(.option) == usesOption else { return false }
    guard mods.contains(.command) == usesCommand else { return false }
    guard mods.contains(.shift) == usesShift else { return false }
    if let expected = keyCode {
      return eventKeyCode == expected
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
      return combo.modifierCount >= 2 ? combo : nil
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
