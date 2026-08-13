import AppKit
import ApplicationServices
import Foundation

/// Global hold hotkey: Control + Option.
/// Works over any app when Accessibility is granted to **this** CasperFlow.app bundle.
@MainActor
final class GlobalHoldHotKey {
  var onPress: (() -> Void)?
  var onRelease: (() -> Void)?
  /// Fired when trust / monitor status changes.
  var onStatusChange: ((Bool) -> Void)?

  private var localMonitor: Any?
  private var globalMonitor: Any?
  private var pollTimer: Timer?
  private var isArmed = false
  private(set) var isGlobalActive = false

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
    onStatusChange?(canInterceptOtherApps)
  }

  func stop() {
    pollTimer?.invalidate()
    pollTimer = nil
    stopMonitorsOnly()
    isArmed = false
    isGlobalActive = false
  }

  /// Call after user toggles Accessibility in System Settings.
  func reinstall() {
    stopMonitorsOnly()
    installMonitors()
    onStatusChange?(canInterceptOtherApps)
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

  private func startPollingTrust() {
    pollTimer?.invalidate()
    // While Settings is open, trust can flip; reinstall global monitor when it does.
    pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        let trusted = Self.isProcessTrusted
        let needsGlobal = trusted && !self.isGlobalActive
        let lostGlobal = !trusted && self.isGlobalActive
        if needsGlobal || lostGlobal {
          self.reinstall()
        }
      }
    }
  }

  private func handleFlags(_ flags: NSEvent.ModifierFlags) {
    let mods = flags.intersection(.deviceIndependentFlagsMask)
    let hold =
      mods.contains(.control)
      && mods.contains(.option)
      && !mods.contains(.command)
      && !mods.contains(.shift)

    if hold, !isArmed {
      isArmed = true
      onPress?()
    } else if !hold, isArmed {
      isArmed = false
      onRelease?()
    }
  }
}
