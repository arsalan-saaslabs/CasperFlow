import AppKit
import Foundation

/// Global tap shortcut that rephrases the current selection in the focused app.
/// Default chord is Control + Option + Command (no extra key).
@MainActor
final class GlobalRephraseHotKey {
  var onFire: (() -> Void)?
  var onRecorded: ((HotkeyCombo) -> Void)?

  private var combo: HotkeyCombo
  private var localFlagsMonitor: Any?
  private var globalFlagsMonitor: Any?
  private var localKeyMonitor: Any?
  private var globalKeyMonitor: Any?
  private var isChordArmed = false
  /// Pending modifier chord while the user is still holding keys during recording.
  private var recordingModifiers: HotkeyCombo?
  /// When true, events are captured for the settings recorder instead of firing.
  var isRecording = false {
    didSet {
      if !isRecording {
        recordingModifiers = nil
      }
    }
  }

  init(combo: HotkeyCombo) {
    self.combo = combo
  }

  func updateCombo(_ combo: HotkeyCombo) {
    self.combo = combo
    isChordArmed = false
  }

  func start() {
    stop()
    installMonitors()
  }

  func stop() {
    removeMonitors()
    isChordArmed = false
    recordingModifiers = nil
  }

  func reinstall() {
    stop()
    installMonitors()
  }

  private func installMonitors() {
    let flagsHandler: (NSEvent) -> Void = { [weak self] event in
      self?.handleFlags(event)
    }
    let keyHandler: (NSEvent) -> Bool = { [weak self] event in
      self?.handleKeyDown(event) ?? false
    }

    localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
      flagsHandler(event)
      return event
    }
    globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: .flagsChanged,
      handler: flagsHandler
    )

    localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      let consumed = self?.handleKeyDown(event) ?? false
      return consumed ? nil : event
    }
    globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
      _ = keyHandler(event)
    }
  }

  private func removeMonitors() {
    if let localFlagsMonitor { NSEvent.removeMonitor(localFlagsMonitor) }
    if let globalFlagsMonitor { NSEvent.removeMonitor(globalFlagsMonitor) }
    if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
    if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor) }
    localFlagsMonitor = nil
    globalFlagsMonitor = nil
    localKeyMonitor = nil
    globalKeyMonitor = nil
  }

  private func handleFlags(_ event: NSEvent) {
    if isRecording {
      handleRecordingFlags(event)
      return
    }

    guard combo.keyCode == nil else {
      isChordArmed = false
      return
    }

    let matches = combo.matches(flags: event.modifierFlags, keyCode: nil)
    if matches, !isChordArmed {
      isChordArmed = true
      onFire?()
    } else if !matches {
      isChordArmed = false
    }
  }

  @discardableResult
  private func handleKeyDown(_ event: NSEvent) -> Bool {
    if isRecording {
      if let recorded = HotkeyCombo.from(event: event), recorded.isValidRephraseShortcut {
        recordingModifiers = nil
        onRecorded?(recorded)
        return true
      }
      return false
    }

    guard let expected = combo.keyCode else { return false }
    guard !event.isARepeat else { return false }
    if combo.matches(flags: event.modifierFlags, keyCode: expected) {
      onFire?()
      return true
    }
    return false
  }

  private func handleRecordingFlags(_ event: NSEvent) {
    let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let held = HotkeyCombo(
      usesControl: mods.contains(.control),
      usesOption: mods.contains(.option),
      usesCommand: mods.contains(.command),
      usesShift: mods.contains(.shift),
      keyCode: nil,
      keyLabel: ""
    )
    if held.modifierCount >= 2 {
      recordingModifiers = held
      return
    }
    if held.modifierCount == 0, let pending = recordingModifiers, pending.isValidRephraseShortcut {
      recordingModifiers = nil
      onRecorded?(pending)
    }
  }
}
