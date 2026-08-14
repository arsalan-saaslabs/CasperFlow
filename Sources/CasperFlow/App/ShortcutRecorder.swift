import AppKit
import Foundation

/// Captures one keyboard shortcut while other global hotkeys are stopped.
@MainActor
final class ShortcutRecorder {
  var onCapture: ((HotkeyCombo) -> Void)?
  var onCancel: (() -> Void)?

  private var localFlags: Any?
  private var localKeys: Any?
  private var globalFlags: Any?
  private var globalKeys: Any?
  private var pendingModifiers: HotkeyCombo?
  private var isActive = false
  private var didCommit = false

  func start() {
    stopMonitors()
    isActive = true
    didCommit = false
    pendingModifiers = nil

    localFlags = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
      self?.handleFlags(event)
      return event
    }
    globalFlags = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
      self?.handleFlags(event)
    }
    localKeys = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
      let handled = self?.handleKey(event) ?? false
      return handled ? nil : event
    }
    globalKeys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      _ = self?.handleKey(event)
    }
  }

  func stop() {
    isActive = false
    didCommit = false
    pendingModifiers = nil
    stopMonitors()
  }

  func ingest(_ event: NSEvent) {
    if event.type == .flagsChanged {
      handleFlags(event)
    } else if event.type == .keyDown || event.type == .keyUp {
      _ = handleKey(event)
    }
  }

  private func stopMonitors() {
    if let localFlags { NSEvent.removeMonitor(localFlags) }
    if let localKeys { NSEvent.removeMonitor(localKeys) }
    if let globalFlags { NSEvent.removeMonitor(globalFlags) }
    if let globalKeys { NSEvent.removeMonitor(globalKeys) }
    localFlags = nil
    localKeys = nil
    globalFlags = nil
    globalKeys = nil
  }

  private func handleFlags(_ event: NSEvent) {
    guard isActive, !didCommit else { return }
    let combo = Self.modifiers(from: event)
    if combo.modifierCount >= 1 {
      pendingModifiers = combo
      return
    }
    if combo.modifierCount == 0, let pending = pendingModifiers {
      pendingModifiers = nil
      commit(pending)
    }
  }

  private func handleKey(_ event: NSEvent) -> Bool {
    guard isActive, !didCommit else { return false }
    if event.type == .keyUp { return true }
    if event.isARepeat { return true }
    if event.keyCode == 53 {
      pendingModifiers = nil
      onCancel?()
      return true
    }
    if Self.isModifierKeyCode(event.keyCode) { return true }
    if let combo = HotkeyCombo.from(event: event) {
      pendingModifiers = nil
      commit(combo)
    }
    return true
  }

  private func commit(_ combo: HotkeyCombo) {
    guard isActive, !didCommit else { return }
    didCommit = true
    onCapture?(combo)
  }

  private static func modifiers(from event: NSEvent) -> HotkeyCombo {
    let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    return HotkeyCombo(
      usesControl: mods.contains(.control),
      usesOption: mods.contains(.option),
      usesCommand: mods.contains(.command),
      usesShift: mods.contains(.shift),
      keyCode: nil,
      keyLabel: ""
    )
  }

  private static func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
    switch keyCode {
    case 54, 55, 56, 57, 58, 59, 60, 61, 62, 63:
      return true
    default:
      return false
    }
  }
}
