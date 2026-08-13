import AppKit
import ApplicationServices
import Foundation

/// Inserts text into the frontmost app (caret focus) without activating CasperFlow.
/// Uses clipboard + Cmd+V, then restores the previous clipboard.
enum FrontmostTextInserter {
  private static let casperFlowBundleId = "com.casperflow.app"
  private static let restoreDelayNs: UInt64 = 350_000_000
  private static let keyCodeV: CGKeyCode = 9

  /// - Returns: `true` if a paste was posted to another app.
  @MainActor
  @discardableResult
  static func paste(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }

    let front = NSWorkspace.shared.frontmostApplication
    if let id = front?.bundleIdentifier, id == casperFlowBundleId {
      // Keep text in CasperFlow UI only — do not Cmd+V into ourselves.
      return false
    }

    guard AXIsProcessTrusted() else { return false }

    let pasteboard = NSPasteboard.general
    let saved = snapshot(pasteboard)

    pasteboard.clearContents()
    pasteboard.setString(trimmed, forType: .string)

    // Brief settle so the target app reads the new pasteboard contents.
    usleep(25_000)

    guard postCommandV() else {
      restore(saved, onto: pasteboard)
      return false
    }

    Task { @MainActor in
      try? await Task.sleep(nanoseconds: restoreDelayNs)
      restore(saved, onto: NSPasteboard.general)
    }
    return true
  }

  private static func postCommandV() -> Bool {
    let source = CGEventSource(stateID: .hidSystemState)

    guard
      let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: true),
      let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: false)
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
