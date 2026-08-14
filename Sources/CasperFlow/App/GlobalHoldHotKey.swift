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

  private var localMonitor: Any?
  private var globalMonitor: Any?
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
    let handler: (NSEvent) -> Void = { [weak self] event in
      self?.handleFlags(event.modifierFlags)
    }

    localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
      handler(event)
      return event
    }

    // Returns nil when this process is not allowed to monitor other apps.
    if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler) {
      globalMonitor = monitor
      isGlobalActive = true
    } else {
      globalMonitor = nil
      isGlobalActive = false
    }
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
    let hold = Self.isPushToTalk(flags)
    let ask = HotkeyCombo.askChat.matches(flags: flags, keyCode: nil)

    if hold, !isArmed {
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

    if ask, !isAskArmed {
      isAskArmed = true
      onAskPress?()
    } else if !ask, isAskArmed {
      isAskArmed = false
      onAskRelease?()
    }
  }

  private static func isPushToTalk(_ flags: NSEvent.ModifierFlags) -> Bool {
    HotkeyCombo.pushToTalk.matches(flags: flags, keyCode: nil)
  }

  private func shouldConfirmBeforeArming() -> Bool {
    let combo = rephraseCombo()
    guard combo.keyCode == nil else { return false }
    return combo.usesControl && combo.usesOption && (combo.usesCommand || combo.usesShift)
  }

  private func scheduleArm() {
    armTask?.cancel()
    armTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: Self.pressConfirmDelayNs)
      guard !Task.isCancelled else { return }
      guard Self.isPushToTalk(NSEvent.modifierFlags), !self.isArmed else { return }
      self.isArmed = true
      self.onPress?()
    }
  }
}
