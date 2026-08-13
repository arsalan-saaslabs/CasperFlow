import AppKit
import ApplicationServices
import Foundation

/// Inserts text into the frontmost app (caret focus) without activating CasperFlow.
/// Uses clipboard + Cmd+V, then restores the previous clipboard.
enum FrontmostTextInserter {
  private static let casperFlowBundleId = "com.casperflow.app"
  private static let restoreDelayNs: UInt64 = 350_000_000
  private static let copySettleNs: UInt64 = 80_000_000
  private static let pasteboardSettleUs: useconds_t = 25_000
  private static let activateSettleUs: useconds_t = 120_000
  private static let keyCodeC: CGKeyCode = 8
  private static let keyCodeV: CGKeyCode = 9

  /// - Returns: `true` if a paste was posted to another app.
  @MainActor
  @discardableResult
  static func paste(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }

    guard let target = ensureTargetAppFrontmost() else { return false }
    if target.bundleIdentifier == casperFlowBundleId { return false }

    guard AXIsProcessTrusted() else { return false }

    if insertViaAccessibility(trimmed) {
      return true
    }

    let pasteboard = NSPasteboard.general
    let saved = snapshot(pasteboard)

    pasteboard.clearContents()
    pasteboard.setString(trimmed, forType: .string)

    usleep(pasteboardSettleUs)

    guard postCommandKey(keyCodeV) else {
      restore(saved, onto: pasteboard)
      return false
    }

    Task { @MainActor in
      try? await Task.sleep(nanoseconds: restoreDelayNs)
      restore(saved, onto: NSPasteboard.general)
    }
    return true
  }

  /// Copies the current selection in the frontmost app. Restores the clipboard.
  @MainActor
  static func copySelection() async -> String? {
    guard let target = ensureTargetAppFrontmost() else { return nil }
    if target.bundleIdentifier == casperFlowBundleId { return nil }
    guard AXIsProcessTrusted() else { return nil }

    let pasteboard = NSPasteboard.general
    let saved = snapshot(pasteboard)
    let changeCount = pasteboard.changeCount

    guard postCommandKey(keyCodeC) else {
      restore(saved, onto: pasteboard)
      return nil
    }

    try? await Task.sleep(nanoseconds: copySettleNs)

    let copied: String?
    if pasteboard.changeCount != changeCount {
      copied = pasteboard.string(forType: .string)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    } else {
      copied = nil
    }

    restore(saved, onto: pasteboard)

    guard let copied, !copied.isEmpty else { return nil }
    return copied
  }

  /// Bring the last non-CasperFlow app forward so paste/copy hit the caret.
  @MainActor
  private static func ensureTargetAppFrontmost() -> NSRunningApplication? {
    let front = NSWorkspace.shared.frontmostApplication
    if let front, front.bundleIdentifier != casperFlowBundleId {
      return front
    }
    let target = FrontmostAppTracker.shared.resolveTarget()
    guard let bundleId = target.bundleId, bundleId != casperFlowBundleId else {
      return front
    }
    guard let app = NSWorkspace.shared.runningApplications.first(where: {
      $0.bundleIdentifier == bundleId
    }) else {
      return front
    }
    app.activate()
    usleep(activateSettleUs)
    return NSWorkspace.shared.frontmostApplication ?? app
  }

  /// Insert at the focused field’s caret via Accessibility (no clipboard).
  private static func insertViaAccessibility(_ text: String) -> Bool {
    let system = AXUIElementCreateSystemWide()
    var focusedRef: CFTypeRef?
    let copyErr = AXUIElementCopyAttributeValue(
      system,
      kAXFocusedUIElementAttribute as CFString,
      &focusedRef
    )
    guard copyErr == .success, let focusedRef else { return false }
    let focused = focusedRef as! AXUIElement
    let setErr = AXUIElementSetAttributeValue(
      focused,
      kAXSelectedTextAttribute as CFString,
      text as CFTypeRef
    )
    return setErr == .success
  }

  @discardableResult
  private static func postCommandKey(_ keyCode: CGKeyCode) -> Bool {
    let source = CGEventSource(stateID: .hidSystemState)

    guard
      let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
      let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
    else {
      return false
    }

    keyDown.flags = .maskCommand
    keyUp.flags = .maskCommand
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
    return true
  }

  private static func snapshot(_ pasteboard: NSPasteboard) -> [[String: Data]] {
    guard let items = pasteboard.pasteboardItems else { return [] }
    return items.map { item in
      var map: [String: Data] = [:]
      for type in item.types {
        if let data = item.data(forType: type) {
          map[type.rawValue] = data
        }
      }
      return map
    }
  }

  private static func restore(_ saved: [[String: Data]], onto pasteboard: NSPasteboard) {
    pasteboard.clearContents()
    guard !saved.isEmpty else { return }
    let items: [NSPasteboardItem] = saved.compactMap { map in
      let item = NSPasteboardItem()
      var wrote = false
      for (rawType, data) in map {
        item.setData(data, forType: NSPasteboard.PasteboardType(rawType))
        wrote = true
      }
      return wrote ? item : nil
    }
    if !items.isEmpty {
      pasteboard.writeObjects(items)
    }
  }
}
