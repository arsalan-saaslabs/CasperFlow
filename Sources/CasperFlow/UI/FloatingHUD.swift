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

  private static let hudSize = NSSize(width: 440, height: 128)
  private static let bottomMargin: CGFloat = 48

  private var panel: DictationHUDPanel?
  private var model: HUDModel?
  private var pasteHideTask: Task<Void, Never>?
  private var isShowingPasteFlash = false

  func attach(session: DictationSession) {
    _ = session
  }

  func sync(
    phase: DictationSession.Phase,
    pending: String,
    committed: String,
    mode: String,
    level: Float = 0
  ) {
    if isShowingPasteFlash {
      return
    }
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
    isShowingPasteFlash = true
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
      self.isShowingPasteFlash = false
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
    let model = ensurePanel()
    model.phase = phase
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
        } else if model.phase == .composing {
          ProgressView()
            .controlSize(.small)
        }
        Text(phaseLabel)
          .font(.caption.weight(.semibold))
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
          .italic()
          .foregroundStyle(.secondary)
          .lineLimit(3)
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
    case .composing: return "ChatGPT is writing…"
    case .connecting: return "Connecting…"
    case .listening, .finalizing, .idle, .error: return "Listening…"
    }
  }

  private var phaseLabel: String {
    if model.pastedInto != nil { return "Pasted" }
    switch model.phase {
    case .connecting: return "Connecting"
    case .listening: return "Listening"
    case .finalizing: return "Finishing"
    case .composing: return "Working"
    case .idle, .error: return "CasperFlow"
    }
  }
}
