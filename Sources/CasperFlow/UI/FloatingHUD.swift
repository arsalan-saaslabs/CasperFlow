import AppKit
import SwiftUI

/// Floating HUD above all apps while dictating (does not steal key focus).
@MainActor
final class FloatingHUDController {
  static let shared = FloatingHUDController()

  private var panel: NSPanel?
  private var session: DictationSession?

  func attach(session: DictationSession) {
    self.session = session
  }

  func sync(phase: DictationSession.Phase, pending: String, committed: String, mode: String) {
    switch phase {
    case .connecting, .listening, .finalizing, .composing:
      show(pending: pending, committed: committed, mode: mode, phase: phase)
    case .idle, .error:
      hide()
    }
  }

  private func show(pending: String, committed: String, mode: String, phase: DictationSession.Phase) {
    if panel == nil {
      let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 420, height: 120),
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
      // Critical: don't steal focus from Slack/Cursor/etc.
      panel.worksWhenModal = true
      self.panel = panel
    }

    guard let panel else { return }

    let root = FloatingHUDView(
      phase: phase,
      mode: mode,
      committed: committed,
      pending: pending
    )
    let host = NSHostingView(rootView: root)
    host.frame = panel.contentView?.bounds ?? panel.frame
    host.autoresizingMask = [.width, .height]
    panel.contentView = host

    position(panel)
    if !panel.isVisible {
      panel.orderFrontRegardless()
    }
  }

  private func hide() {
    panel?.orderOut(nil)
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

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Circle()
          .fill(phase == .listening ? Color.green : Color.orange)
          .frame(width: 8, height: 8)
        Text(phaseLabel)
          .font(.caption.weight(.semibold))
        Spacer()
        Text(mode)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      if !committed.isEmpty {
        Text(committed)
          .font(.callout)
          .foregroundStyle(.primary)
          .lineLimit(phase == .composing ? 8 : 3)
      }
      if !pending.isEmpty {
        Text(pending)
          .font(.callout)
          .italic()
          .foregroundStyle(.secondary)
          .lineLimit(phase == .composing ? 8 : 3)
      }
      if committed.isEmpty && pending.isEmpty {
        Text(phase == .composing ? "ChatGPT is writing…" : "Listening…")
          .foregroundStyle(.secondary)
      }
    }
    .padding(14)
    .frame(width: 420, alignment: .leading)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(Color.white.opacity(0.12), lineWidth: 1)
    )
  }

  private var phaseLabel: String {
    switch phase {
    case .connecting: return "Connecting"
    case .listening: return "Dictating"
    case .finalizing: return "Finishing"
    case .composing: return "ChatGPT"
    default: return "CasperFlow"
    }
  }
}
