import AppKit
import SwiftUI

/// Floating HUD above all apps while dictating (does not steal key focus).
@MainActor
final class FloatingHUDController {
  static let shared = FloatingHUDController()

  private static let compactSize = NSSize(width: 440, height: 148)
  private static let errorSize = NSSize(width: 440, height: 196)

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
    case .connecting, .listening, .finalizing, .composing, .error:
      show(
        pending: pending,
        committed: committed,
        mode: mode,
        phase: phase,
        level: level,
        pastedInto: nil
      )
    case .idle:
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
      level: 0,
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
    level: Float,
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

    guard let panel, let session else { return }
    if panel.isVisible {
      lastOrigin = panel.frame.origin
    }

    let size = phase == .error ? Self.errorSize : Self.compactSize
    let root = FloatingHUDView(
      phase: phase,
      mode: mode,
      committed: committed,
      pending: pending,
      level: level,
      pastedInto: pastedInto,
      onRetry: { session.restartAfterError() },
      onDismiss: { session.dismissError() }
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
      panel.alphaValue = 0
      panel.orderFrontRegardless()
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.22
        panel.animator().alphaValue = 1
      }
    }
  }

  private func hide() {
    guard let panel, panel.isVisible else { return }
    lastOrigin = panel.frame.origin
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.18
      panel.animator().alphaValue = 0
    } completionHandler: {
      panel.orderOut(nil)
      panel.alphaValue = 1
    }
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
  let level: Float
  let pastedInto: String?
  var onRetry: () -> Void = {}
  var onDismiss: () -> Void = {}

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
            .symbolEffect(.bounce, value: pastedInto)
        } else {
          ListeningPulse(isActive: phase == .listening, tint: pulseColor)
        }
        Text(phaseLabel)
          .font(.caption.weight(.semibold))
        Spacer()
        Text(mode)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      if pastedInto == nil, phase != .error {
        LiveWaveform(level: level, isActive: phase == .listening || phase == .connecting)
      }

      if !committed.isEmpty {
        Text(committed)
          .font(.callout)
          .foregroundStyle(.primary)
          .lineLimit(phase == .composing ? 8 : 3)
          .contentTransition(.opacity)
      }
      if !pending.isEmpty {
        Text(pending)
          .font(.callout)
          .italic()
          .foregroundStyle(.secondary)
          .lineLimit(phase == .composing ? 8 : 3)
      }
      if committed.isEmpty && pending.isEmpty && pastedInto == nil {
        Text(emptyLabel)
          .foregroundStyle(.secondary)
      }

      if phase == .error {
        HStack {
          Button("Restart") { onRetry() }
            .buttonStyle(.borderedProminent)
            .tint(WFTheme.accent)
            .controlSize(.small)
          Button("Dismiss") { onDismiss() }
            .buttonStyle(.bordered)
            .controlSize(.small)
          Spacer()
        }
      }
    }
    .padding(16)
    .frame(width: 440, alignment: .leading)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(borderColor.opacity(0.45), lineWidth: 1)
    )
    .shadow(color: borderColor.opacity(0.18), radius: 16, y: 6)
  }

  private var pulseColor: Color {
    switch phase {
    case .listening: return .green
    case .composing: return .purple
    case .error: return .red
    default: return .orange
    }
  }

  private var borderColor: Color {
    pastedInto != nil ? .green : pulseColor
  }

  private var emptyLabel: String {
    switch phase {
    case .composing: return "ChatGPT is writing…"
    case .error: return pending.isEmpty ? "Something went wrong" : pending
    case .connecting: return "Connecting…"
    default: return "Listening…"
    }
  }

  private var phaseLabel: String {
    if pastedInto != nil { return "Pasted" }
    switch phase {
    case .connecting: return "Connecting"
    case .listening: return "Dictating"
    case .finalizing: return "Finishing"
    case .composing: return "ChatGPT"
    case .error: return "Error"
    default: return "CasperFlow"
    }
  }
}

struct ListeningPulse: View {
  let isActive: Bool
  var tint: Color = .green

  var body: some View {
    TimelineView(.animation(minimumInterval: 0.05, paused: !isActive)) { timeline in
      let t = timeline.date.timeIntervalSinceReferenceDate
      let pulse = isActive ? (0.55 + 0.45 * sin(t * 6)) : 0.4
      ZStack {
        Circle()
          .stroke(tint.opacity(0.25), lineWidth: 2)
          .frame(width: 22, height: 22)
          .scaleEffect(isActive ? 0.9 + 0.35 * pulse : 1)
        Circle()
          .fill(tint)
          .frame(width: 8, height: 8)
          .scaleEffect(0.85 + 0.2 * pulse)
      }
      .frame(width: 24, height: 24)
    }
  }
}

struct LiveWaveform: View {
  let level: Float
  let isActive: Bool

  var body: some View {
    TimelineView(.animation(minimumInterval: 0.04, paused: !isActive)) { timeline in
      let t = timeline.date.timeIntervalSinceReferenceDate
      HStack(spacing: 3) {
        ForEach(0..<9, id: \.self) { index in
          let wobble = isActive ? (0.35 + 0.65 * abs(sin(t * 7 + Double(index) * 0.55))) : 0.22
          let height = 6 + CGFloat(level) * 22 * wobble + (isActive ? 4 : 0)
          Capsule()
            .fill(WFTheme.accent.opacity(isActive ? 0.95 : 0.35))
            .frame(width: 3.5, height: min(28, max(5, height)))
        }
      }
      .frame(height: 28, alignment: .center)
    }
  }
}
