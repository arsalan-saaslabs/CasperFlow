import AppKit
import SwiftUI

/// Floating HUD above all apps while dictating (does not steal key focus).
@MainActor
final class FloatingHUDController {
  static let shared = FloatingHUDController()

  private static let compactSize = NSSize(width: 440, height: 128)

  private var panel: NSPanel?
  private var session: DictationSession?
  private var pasteHideTask: Task<Void, Never>?
  private var lastOrigin: NSPoint?
  private var didPlaceOnce = false

  func attach(session: DictationSession) {
    self.session = session
  }

  func sync(
    phase: DictationSession.Phase,
    pending: String,
    committed: String,
    mode: String,
    level: Float = 0
  ) {
    pasteHideTask?.cancel()
    switch phase {
    case .connecting, .listening, .finalizing, .composing:
      show(
        pending: pending,
        committed: committed,
        mode: mode,
        phase: phase,
        pastedInto: nil
      )
    case .idle, .error:
      hide()
    }
  }

  func flashPasted(into appName: String) {
    pasteHideTask?.cancel()
    show(
      pending: "",
      committed: "Inserted into \(appName)",
      mode: appName,
      phase: .idle,
      pastedInto: appName
    )
    pasteHideTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 1_200_000_000)
      guard !Task.isCancelled else { return }
      self.hide()
    }
  }

  private func show(
    pending: String,
    committed: String,
    mode: String,
    phase: DictationSession.Phase,
    pastedInto: String?
  ) {
    if panel == nil {
      let panel = NSPanel(
        contentRect: NSRect(origin: .zero, size: Self.compactSize),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
      )
      panel.level = .floating
      panel.isFloatingPanel = true
      panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      panel.isOpaque = false
      panel.backgroundColor = .clear
      panel.hasShadow = true
      panel.hidesOnDeactivate = false
      panel.becomesKeyOnlyIfNeeded = true
      panel.worksWhenModal = true
      panel.isMovable = true
      panel.isMovableByWindowBackground = true
      self.panel = panel
    }

    guard let panel else { return }
    if panel.isVisible {
      lastOrigin = panel.frame.origin
    }

    let size = Self.compactSize
    let root = FloatingHUDView(
      phase: phase,
      mode: mode,
      committed: committed,
      pending: pending,
      pastedInto: pastedInto
    )
    let host = NSHostingView(rootView: root)
    host.frame = NSRect(origin: .zero, size: size)
    host.autoresizingMask = [.width, .height]
    panel.contentView = host
    panel.setContentSize(size)

    if didPlaceOnce, let lastOrigin {
      panel.setFrameOrigin(lastOrigin)
    } else {
      position(panel)
      didPlaceOnce = true
    }
    if !panel.isVisible {
      panel.alphaValue = 1
      panel.orderFrontRegardless()
    }
  }

  private func hide() {
    guard let panel, panel.isVisible else { return }
    lastOrigin = panel.frame.origin
    panel.orderOut(nil)
  }

  private func position(_ panel: NSPanel) {
    guard let screen = NSScreen.main else { return }
    let visible = screen.visibleFrame
    let size = panel.frame.size
    let x = visible.midX - size.width / 2
    let y = visible.minY + 48
    panel.setFrameOrigin(NSPoint(x: x, y: y))
  }
}

struct FloatingHUDView: View {
  let phase: DictationSession.Phase
  let mode: String
  let committed: String
  let pending: String
  let pastedInto: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        OverlayWindowDragArea()
          .frame(width: 14, height: 22)
          .overlay {
            Image(systemName: "line.3.horizontal")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          .help("Drag to move")
        if pastedInto != nil {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
        }
        Text(phaseLabel)
          .font(.caption.weight(.semibold))
        Spacer()
        Text(mode)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      if !committed.isEmpty {
        Text(committed)
          .font(.callout)
          .foregroundStyle(.primary)
          .lineLimit(3)
      }
      if !pending.isEmpty {
        Text(pending)
          .font(.callout)
          .italic()
          .foregroundStyle(.secondary)
          .lineLimit(3)
      }
      if committed.isEmpty && pending.isEmpty && pastedInto == nil {
        Text(emptyLabel)
          .foregroundStyle(.secondary)
      }
    }
    .padding(16)
    .frame(width: 440, alignment: .leading)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .shadow(color: Color.black.opacity(0.16), radius: 10, y: 4)
  }

  private var emptyLabel: String {
    switch phase {
    case .composing: return "ChatGPT is writing…"
    case .connecting: return "Connecting…"
    default: return "Listening…"
    }
  }

  private var phaseLabel: String {
    if pastedInto != nil { return "Pasted" }
    switch phase {
    case .connecting: return "Connecting"
    case .listening: return "Listening"
    case .finalizing: return "Finishing"
    case .composing: return "ChatGPT"
    default: return "CasperFlow"
    }
  }
}
