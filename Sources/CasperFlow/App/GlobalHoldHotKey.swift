import AppKit
import ApplicationServices
import Foundation

/// Global hold hotkey: Control + Option.
/// Works over any app when Accessibility is granted to **this** CasperFlow.app bundle.
@MainActor
final class GlobalHoldHotKey {
  var onPress: (() -> Void)?
  var onRelease: (() -> Void)?
  /// Hold Option+Command: voice command → ChatGPT → paste.
  var onAskPress: (() -> Void)?
  var onAskRelease: (() -> Void)?
  /// Fired when trust / monitor status changes.
  var onStatusChange: ((Bool) -> Void)?
  /// Ignore chords while the Shortcuts recorder is capturing a new combo.
  var isPaused = false
  var isToggleMode: () -> Bool = { false }
  private var dictateChordHeld = false
  private var askChordHeld = false

  private var localMonitor: Any?
  private var globalMonitor: Any?
  private var localKeyMonitor: Any?
  private var globalKeyMonitor: Any?
  private var pollTimer: Timer?
  private var isArmed = false
  private var isAskArmed = false
  private var armTask: Task<Void, Never>?
  private var lastCapable = false
  private(set) var isGlobalActive = false
  private static let trustPollInterval: TimeInterval = 1.0

  /// When the rephrase shortcut is a longer modifier chord (default ⌃⌥⌘),
  /// wait this long so Command can join before PTT starts.
  private static let pressConfirmDelayNs: UInt64 = 80_000_000

  /// Return the current rephrase shortcut so PTT can yield to a longer chord.
  var rephraseCombo: () -> HotkeyCombo = { .defaultRephrase }
  var dictateCombo: () -> HotkeyCombo = { .pushToTalk }
  var askCombo: () -> HotkeyCombo = { .askChat }

  static var isProcessTrusted: Bool {
    AXIsProcessTrusted()
  }

  /// Effective capability: process trusted AND global monitor installed.
  var canInterceptOtherApps: Bool {
    isGlobalActive && Self.isProcessTrusted
  }

  func start() {
    stopMonitorsOnly()
    _ = Self.requestTrust(prompt: true)
    installMonitors()
    startPollingTrust()
    publishCapability()
  }

  func stop() {
    pollTimer?.invalidate()
    pollTimer = nil
    armTask?.cancel()
    armTask = nil
    stopMonitorsOnly()
    isArmed = false
    isAskArmed = false
    dictateChordHeld = false
    askChordHeld = false
    isGlobalActive = false
  }

  /// Call after user toggles Accessibility in System Settings.
  func reinstall() {
    stopMonitorsOnly()
    installMonitors()
    publishCapability()
  }

  @discardableResult
  static func requestTrust(prompt: Bool) -> Bool {
    if prompt {
      let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
      return AXIsProcessTrustedWithOptions(options)
    }
    return AXIsProcessTrusted()
  }

  static func openAccessibilitySettings() {
    _ = requestTrust(prompt: true)
    let candidates = [
      "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
      "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
    ]
    for raw in candidates {
      if let url = URL(string: raw), NSWorkspace.shared.open(url) {
        return
      }
    }
  }

  /// Reveal the exact .app to add under Accessibility → +.
  static func revealAppInFinder() {
    let url = Bundle.main.bundleURL
    if url.pathExtension == "app" {
      NSWorkspace.shared.activateFileViewerSelecting([url])
      return
    }
    // Running unpackaged: prefer dist/CasperFlow.app next to the package.
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let candidates = [
      executable
        .deletingLastPathComponent() // MacOS or .build/...
        .deletingLastPathComponent() // Contents or release
        .appendingPathComponent("CasperFlow.app"),
      URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("dist/CasperFlow.app"),
      URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("CasperFlow/dist/CasperFlow.app"),
    ]
    for dist in candidates where FileManager.default.fileExists(atPath: dist.path) {
      NSWorkspace.shared.activateFileViewerSelecting([dist])
      return
    }
  }

  static var bundleIdentity: String {
    let id = Bundle.main.bundleIdentifier ?? "unknown.id"
    let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "CasperFlow"
    let path = Bundle.main.bundlePath
    return "\(name) · \(id)\n\(path)"
  }

  private func installMonitors() {
    let flagsHandler: (NSEvent) -> Void = { [weak self] event in
      self?.handleFlags(event.modifierFlags)
    }
    let keyHandler: (NSEvent) -> Bool = { [weak self] event in
      self?.handleKey(event) ?? false
    }

    localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
      flagsHandler(event)
      return event
    }

    localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
      keyHandler(event) ? nil : event
    }

    if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flagsHandler) {
      globalMonitor = monitor
    } else {
      globalMonitor = nil
    }

    globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
      _ = keyHandler(event)
    }

    isGlobalActive = globalMonitor != nil || globalKeyMonitor != nil
  }

  private func stopMonitorsOnly() {
    if let localMonitor {
      NSEvent.removeMonitor(localMonitor)
      self.localMonitor = nil
    }
    if let globalMonitor {
      NSEvent.removeMonitor(globalMonitor)
      self.globalMonitor = nil
    }
    if let localKeyMonitor {
      NSEvent.removeMonitor(localKeyMonitor)
      self.localKeyMonitor = nil
    }
    if let globalKeyMonitor {
      NSEvent.removeMonitor(globalKeyMonitor)
      self.globalKeyMonitor = nil
    }
    isGlobalActive = false
  }

  private func publishCapability() {
    lastCapable = canInterceptOtherApps
    onStatusChange?(lastCapable)
  }

  private func startPollingTrust() {
    pollTimer?.invalidate()
    // While Settings is open, trust can flip; update UI without tearing down monitors
    // every second (that leaked monitors and pegged CPU when untrusted).
    pollTimer = Timer.scheduledTimer(withTimeInterval: Self.trustPollInterval, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        let trusted = Self.isProcessTrusted
        if trusted, !self.isGlobalActive {
          self.reinstall()
          return
        }
        let capable = self.canInterceptOtherApps
        if capable != self.lastCapable {
          self.publishCapability()
        }
      }
    }
  }

  private func handleFlags(_ flags: NSEvent.ModifierFlags) {
    if isPaused {
      if isArmed {
        isArmed = false
        onRelease?()
      }
      if isAskArmed {
        isAskArmed = false
        onAskRelease?()
      }
      armTask?.cancel()
      armTask = nil
      return
    }
    let dictate = dictateCombo()
    let askComboValue = askCombo()

    if dictate.keyCode == nil {
      let hold = dictate.matches(flags: flags, keyCode: nil)
      if isToggleMode() {
        edgeToggleDictate(matching: hold)
      } else if hold, !isArmed {
        if shouldConfirmBeforeArming() {
          scheduleArm()
        } else {
          isArmed = true
          onPress?()
        }
      } else if !hold {
        armTask?.cancel()
        armTask = nil
        if isArmed {
          isArmed = false
          onRelease?()
        }
      }
    }

    if askComboValue.keyCode == nil {
      let ask = askComboValue.matches(flags: flags, keyCode: nil)
      if isToggleMode() {
        edgeToggleAsk(matching: ask)
      } else if ask, !isAskArmed {
        isAskArmed = true
        onAskPress?()
      } else if !ask, isAskArmed {
        isAskArmed = false
        onAskRelease?()
      }
    }
  }

  /// Rising edge of the chord: first tap starts, second tap stops. Release does nothing.
  private func edgeToggleDictate(matching: Bool) {
    if matching {
      guard !dictateChordHeld else { return }
      dictateChordHeld = true
      if isArmed {
        isArmed = false
        onRelease?()
      } else {
        isArmed = true
        onPress?()
      }
    } else {
      dictateChordHeld = false
    }
  }

  private func edgeToggleAsk(matching: Bool) {
    if matching {
      guard !askChordHeld else { return }
      askChordHeld = true
      if isAskArmed {
        isAskArmed = false
        onAskRelease?()
      } else {
        isAskArmed = true
        onAskPress?()
      }
    } else {
      askChordHeld = false
    }
  }

  @discardableResult
  private func handleKey(_ event: NSEvent) -> Bool {
    if isPaused { return false }
    if event.isARepeat { return false }

    let dictate = dictateCombo()
    let ask = askCombo()
    let down = event.type == .keyDown

    var consumed = false

    if let expected = dictate.keyCode,
       dictate.matches(flags: event.modifierFlags, keyCode: expected) {
      if down {
        if isToggleMode() {
          if isArmed {
            isArmed = false
            onRelease?()
          } else {
            isArmed = true
            onPress?()
          }
        } else if !isArmed {
          isArmed = true
          onPress?()
        }
      } else if !isToggleMode(), isArmed {
        isArmed = false
        onRelease?()
      }
      consumed = true
    }

    if let expected = ask.keyCode,
       ask.matches(flags: event.modifierFlags, keyCode: expected) {
      if down {
        if isToggleMode() {
          if isAskArmed {
            isAskArmed = false
            onAskRelease?()
          } else {
            isAskArmed = true
            onAskPress?()
          }
        } else if !isAskArmed {
          isAskArmed = true
          onAskPress?()
        }
      } else if !isToggleMode(), isAskArmed {
        isAskArmed = false
        onAskRelease?()
      }
      consumed = true
    }

    return consumed
  }

  private func shouldConfirmBeforeArming() -> Bool {
    let dictate = dictateCombo()
    let rephrase = rephraseCombo()
    guard rephrase.keyCode == nil else { return false }
    guard rephrase.modifierCount > dictate.modifierCount else { return false }
    if dictate.usesControl && !rephrase.usesControl { return false }
    if dictate.usesOption && !rephrase.usesOption { return false }
    if dictate.usesCommand && !rephrase.usesCommand { return false }
    if dictate.usesShift && !rephrase.usesShift { return false }
    return true
  }

  private func scheduleArm() {
    armTask?.cancel()
    armTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: Self.pressConfirmDelayNs)
      guard !Task.isCancelled else { return }
      guard self.dictateCombo().matches(flags: NSEvent.modifierFlags, keyCode: nil), !self.isArmed else { return }
      self.isArmed = true
      self.onPress?()
    }
  }
}
