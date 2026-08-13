import AppKit
import SwiftUI

/// Spacebar push-to-talk without stealing text-field focus incorrectly.
struct SpaceHoldMonitor: NSViewRepresentable {
  let onPress: () -> Void
  let onRelease: () -> Void

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    context.coordinator.attach()
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(onPress: onPress, onRelease: onRelease)
  }

  final class Coordinator {
    private var localMonitor: Any?
    private let onPress: () -> Void
    private let onRelease: () -> Void
    private var spaceDown = false

    init(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
      self.onPress = onPress
      self.onRelease = onRelease
    }

    func attach() {
      localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
        guard let self else { return event }
        guard event.keyCode == 49 else { return event }
        if let target = event.window?.firstResponder as? NSView,
           target is NSTextView || target is NSTextField {
          return event
        }
        if event.type == .keyDown, !event.isARepeat, !self.spaceDown {
          self.spaceDown = true
          self.onPress()
          return nil
        }
        if event.type == .keyUp, self.spaceDown {
          self.spaceDown = false
          self.onRelease()
          return nil
        }
        return nil
      }
    }

    deinit {
      if let localMonitor {
        NSEvent.removeMonitor(localMonitor)
      }
    }
  }
}
