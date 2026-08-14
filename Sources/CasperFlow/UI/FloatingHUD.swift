import AppKit
import SwiftUI

/// Non-activating HUD. Must not become key or global hotkeys stop working in other apps.
private final class DictationHUDPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

/// Floating HUD above all apps while dictating (does not steal key focus).
@MainActor
final class FloatingHUDController {
  static let shared = FloatingHUDController()

  private static let hudSize = NSSize(width: 440, height: 148)
  private static let bottomMargin: CGFloat = 48

  private var panel: DictationHUDPanel?
  private var model: HUDModel?
  private var dismissTask: Task<Void, Never>?
  private var isHoldingNotice = false

  func attach(session: DictationSession) {
    _ = session
  }

  func sync(
    phase: DictationSession.Phase,
    activity: String,
    pending: String,
    committed: String,
    mode: String,
    level: Float = 0
  ) {
    if isHoldingNotice, phase == .idle {
      return
    }
    dismissTask?.cancel()
    switch phase {
    case .connecting, .listening, .finalizing, .composing:
      isHoldingNotice = false
      show(
        activity: activity,
        pending: pending,
        committed: committed,
        mode: mode,
        phase: phase,
        pastedInto: nil
      )
    case .error:
      isHoldingNotice = true
      show(
        activity: activity,
        pending: pending,
        committed: committed,
        mode: mode,
        phase: .error,
        pastedInto: nil
      )
      scheduleDismiss(afterNanoseconds: 4_500_000_000)
    case .idle:
      hide()
    }
  }

  func flashPasted(into appName: String) {
    flashNotice(
      title: "Inserted into \(appName)",
      subtitle: appName,
      phase: .idle,
      isPaste: true
    )
  }

  func flashNotice(title: String, subtitle: String = "", isError: Bool = false) {
    flashNotice(
      title: title,
      subtitle: subtitle,
      phase: isError ? .error : .idle,
      isPaste: false
    )
  }

  private func flashNotice(
    title: String,
    subtitle: String,
    phase: DictationSession.Phase,
    isPaste: Bool
  ) {
    dismissTask?.cancel()
    isHoldingNotice = true
    show(
      activity: isPaste ? "Pasted" : (phase == .error ? "Error" : title),
      pending: "",
      committed: title,
      mode: subtitle,
      phase: phase,
      pastedInto: isPaste ? subtitle : nil
    )
    scheduleDismiss(afterNanoseconds: isErrorDuration(phase))
  }

  private func isErrorDuration(_ phase: DictationSession.Phase) -> UInt64 {
    phase == .error ? 4_500_000_000 : 2_000_000_000
  }

  private func scheduleDismiss(afterNanoseconds nanos: UInt64) {
    dismissTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: nanos)
      guard !Task.isCancelled else { return }
      self.isHoldingNotice = false
      self.hide()
    }
  }

  private func show(
    activity: String,
    pending: String,
    committed: String,
    mode: String,
    phase: DictationSession.Phase,
    pastedInto: String?
  ) {
    let model = ensurePanel()
    model.phase = phase
    model.activity = activity
    model.mode = mode
    model.committed = committed
    model.pending = pending
    model.pastedInto = pastedInto

    guard let panel else { return }
    panel.animationBehavior = .none
    pinToBottomCenter(panel)
    panel.alphaValue = 1
    if !panel.isVisible {
      panel.orderFrontRegardless()
    }
  }

  private func hide() {
    guard let panel, panel.isVisible else { return }
    panel.animationBehavior = .none
    panel.orderOut(nil)
  }

  private func ensurePanel() -> HUDModel {
    if let model {
      return model
    }

    let model = HUDModel()
    let host = NSHostingView(rootView: FloatingHUDView(model: model))
    host.frame = NSRect(origin: .zero, size: Self.hudSize)

    let panel = DictationHUDPanel(
      contentRect: Self.bottomCenterFrame(size: Self.hudSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.animationBehavior = .none
    panel.level = .floating
    panel.isFloatingPanel = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = true
    panel.worksWhenModal = true
    panel.isMovable = false
    panel.isMovableByWindowBackground = false
    panel.contentView = host
    pinToBottomCenter(panel)

    self.model = model
    self.panel = panel
    return model
  }

  private func pinToBottomCenter(_ panel: NSPanel) {
    panel.setFrame(Self.bottomCenterFrame(size: panel.frame.size), display: true, animate: false)
  }

  private static func bottomCenterFrame(size: NSSize) -> NSRect {
    let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
    let x = visible.midX - size.width / 2
    let y = visible.minY + bottomMargin
    return NSRect(origin: NSPoint(x: x, y: y), size: size)
  }
}

@MainActor
final class HUDModel: ObservableObject {
  @Published var phase: DictationSession.Phase = .idle
  @Published var activity = ""
  @Published var mode = ""
  @Published var committed = ""
  @Published var pending = ""
  @Published var pastedInto: String?
}

struct FloatingHUDView: View {
  @ObservedObject var model: HUDModel

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        if model.pastedInto != nil {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
        } else if model.phase == .error {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
        } else if model.phase == .composing
          || model.phase == .finalizing
          || model.phase == .connecting {
          ProgressView()
            .controlSize(.small)
        } else if model.phase == .listening {
          Image(systemName: "waveform")
            .foregroundStyle(WFTheme.accent)
        }
        Text(phaseLabel)
          .font(.caption.weight(.semibold))
          .lineLimit(1)
        Spacer()
        Text(model.mode)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      if !model.committed.isEmpty {
        Text(model.committed)
          .font(.callout)
          .foregroundStyle(.primary)
          .lineLimit(3)
      }
      if !model.pending.isEmpty {
        Text(model.pending)
          .font(.callout)
          .italic(model.phase != .error)
          .foregroundStyle(model.phase == .error ? .primary : .secondary)
          .lineLimit(4)
      }
      if model.committed.isEmpty && model.pending.isEmpty && model.pastedInto == nil {
        Text(emptyLabel)
          .foregroundStyle(.secondary)
      }
    }
    .padding(16)
    .frame(width: 440, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(.ultraThinMaterial)
    }
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .transaction { transaction in
      transaction.animation = nil
    }
  }

  private var emptyLabel: String {
    switch model.phase {
    case .connecting: return "Connecting to PyAI…"
    case .listening: return "Speak…"
    case .finalizing: return "Finishing…"
    case .composing: return model.activity.isEmpty ? "Working…" : "\(model.activity)…"
    case .error: return "Something went wrong"
    case .idle: return "Speak…"
    }
  }

  private var phaseLabel: String {
    if model.pastedInto != nil { return "Pasted" }
    if !model.activity.isEmpty { return model.activity }
    switch model.phase {
    case .connecting: return "Connecting to PyAI"
    case .listening: return "Listening"
    case .finalizing: return "Committing"
    case .composing: return "Working"
    case .error: return "Error"
    case .idle: return "Casper"
    }
  }
}
