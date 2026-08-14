import AppKit
import SwiftUI

/// Becomes first responder while recording so key events reach CasperFlow.
struct ShortcutCatcherView: NSViewRepresentable {
  var isActive: Bool
  var onEvent: (NSEvent) -> Void

  func makeNSView(context: Context) -> CatcherView {
    let view = CatcherView()
    view.onEvent = onEvent
    return view
  }

  func updateNSView(_ view: CatcherView, context: Context) {
    view.onEvent = onEvent
    view.isCatching = isActive
    if isActive {
      DispatchQueue.main.async {
        view.window?.makeFirstResponder(view)
      }
    }
  }

  final class CatcherView: NSView {
    var onEvent: ((NSEvent) -> Void)?
    var isCatching = false

    override var acceptsFirstResponder: Bool { isCatching }

    override func flagsChanged(with event: NSEvent) {
      if isCatching { onEvent?(event) }
    }

    override func keyDown(with event: NSEvent) {
      if isCatching {
        onEvent?(event)
      } else {
        super.keyDown(with: event)
      }
    }

    override func keyUp(with event: NSEvent) {
      if isCatching { onEvent?(event) }
    }
  }
}
