import AppKit
import SwiftUI

/// Floating history palette over any app. Toggle with the History shortcut.
@MainActor
final class HistoryOverlayController {
  static let shared = HistoryOverlayController()

  private var panel: NSPanel?
  private(set) var isVisible = false
  var onPaste: ((HistoryItem) -> Void)?
  private var localEscapeMonitor: Any?
  private var globalEscapeMonitor: Any?
  private var lastOrigin: NSPoint?

  func toggle() {
    if isVisible {
      hide()
    } else {
      show()
    }
  }

  func hide() {
    guard let panel, isVisible else { return }
    isVisible = false
    lastOrigin = panel.frame.origin
    removeEscapeMonitors()
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.18
      panel.animator().alphaValue = 0
    } completionHandler: {
      panel.orderOut(nil)
      panel.alphaValue = 1
    }
  }

  private func show() {
    if panel == nil {
      let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
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
      panel.becomesKeyOnlyIfNeeded = false
      panel.worksWhenModal = true
      panel.isMovable = true
      panel.isMovableByWindowBackground = true
      self.panel = panel
    }

    guard let panel else { return }
    let host = NSHostingView(
      rootView: HistoryOverlayView(
        store: HistoryStore.shared,
        onPaste: { [weak self] item in
          self?.onPaste?(item)
          self?.hide()
        },
        onClose: { [weak self] in self?.hide() }
      )
    )
    host.frame = NSRect(x: 0, y: 0, width: 420, height: 520)
    host.autoresizingMask = [.width, .height]
    panel.contentView = host
    panel.setContentSize(NSSize(width: 420, height: 520))
    position(panel)
    panel.alphaValue = 0
    panel.orderFrontRegardless()
    isVisible = true
    installEscapeMonitors()
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.24
      panel.animator().alphaValue = 1
    }
  }

  private func installEscapeMonitors() {
    removeEscapeMonitors()
    let hideIfEscape: (NSEvent) -> Bool = { [weak self] event in
      guard event.keyCode == 53 else { return false }
      self?.hide()
      return true
    }
    localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      hideIfEscape(event) ? nil : event
    }
    globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
      _ = hideIfEscape(event)
    }
  }

  private func removeEscapeMonitors() {
    if let localEscapeMonitor {
      NSEvent.removeMonitor(localEscapeMonitor)
      self.localEscapeMonitor = nil
    }
    if let globalEscapeMonitor {
      NSEvent.removeMonitor(globalEscapeMonitor)
      self.globalEscapeMonitor = nil
    }
  }

  private func position(_ panel: NSPanel) {
    if let lastOrigin {
      panel.setFrameOrigin(lastOrigin)
      return
    }
    guard let screen = NSScreen.main else { return }
    let visible = screen.visibleFrame
    let x = visible.maxX - panel.frame.width - 24
    let y = visible.midY - panel.frame.height / 2
    panel.setFrameOrigin(NSPoint(x: x, y: y))
  }
}

struct HistoryOverlayView: View {
  @ObservedObject var store: HistoryStore
  var onPaste: (HistoryItem) -> Void
  var onClose: () -> Void
  @State private var filter: HistoryFilter = .all
  @State private var appeared = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      filterRow
      list
    }
    .padding(16)
    .frame(width: 420, height: 520)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(WFTheme.accent.opacity(0.28), lineWidth: 1)
    )
    .shadow(color: WFTheme.accent.opacity(0.16), radius: 22, y: 10)
    .scaleEffect(appeared ? 1 : 0.94)
    .opacity(appeared ? 1 : 0)
    .onAppear {
      withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
        appeared = true
      }
    }
  }

  private var header: some View {
    HStack {
      OverlayWindowDragArea()
        .frame(width: 18, height: 28)
        .overlay {
          Image(systemName: "line.3.horizontal")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .help("Drag to move")
      VStack(alignment: .leading, spacing: 2) {
        Text("History")
          .font(.headline)
        Text("Drag the handle to move · Esc to close")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button("Close", action: onClose)
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
  }

  private var filterRow: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        filterChip("All", selected: filter == .all) { filter = .all }
        filterChip("Saved", selected: filter == .saved) { filter = .saved }
        ForEach(HistoryTaskKind.allCases) { kind in
          filterChip(kind.title, selected: filter == .kind(kind)) {
            filter = .kind(kind)
          }
        }
      }
    }
  }

  private func filterChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(selected ? WFTheme.accent : Color.secondary.opacity(0.12))
        .foregroundStyle(selected ? Color.white : Color.primary)
        .clipShape(Capsule())
    }
    .buttonStyle(.plain)
  }

  private var list: some View {
    let visible = store.items(filter: filter)
    return ScrollView {
      LazyVStack(spacing: 10) {
        if visible.isEmpty {
          Text("No history yet — dictate, ask, or rephrase to fill this list.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 24)
        }
        ForEach(Array(visible.enumerated()), id: \.element.id) { index, item in
          HistoryCardView(item: item, store: store) {
            onPaste(item)
          }
          .offset(y: appeared ? 0 : 12)
          .opacity(appeared ? 1 : 0)
          .animation(
            .spring(response: 0.4, dampingFraction: 0.82).delay(Double(index) * 0.03),
            value: appeared
          )
        }
      }
    }
  }
}

struct HistoryCardView: View {
  let item: HistoryItem
  @ObservedObject var store: HistoryStore
  var onPaste: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: item.kind.systemImage)
          .foregroundStyle(WFTheme.accent)
        Text(item.kind.title)
          .font(.caption.weight(.semibold))
        Text("·")
          .foregroundStyle(.tertiary)
        Text(item.appName)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Spacer()
        Text(item.createdAt.formatted(date: .omitted, time: .shortened))
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }

      Text(item.text)
        .font(.callout)
        .lineLimit(4)
        .textSelection(.enabled)

      HStack {
        Text("Drag me")
          .font(.caption2)
          .foregroundStyle(.secondary)
        Spacer()
        Button {
          store.toggleSaved(item.id)
        } label: {
          Image(systemName: item.isSaved ? "bookmark.fill" : "bookmark")
        }
        .buttonStyle(.plain)
        .help(item.isSaved ? "Remove from saved" : "Save")
        Button("Paste", action: onPaste)
          .buttonStyle(.bordered)
          .controlSize(.small)
        Button(role: .destructive) {
          store.delete(item.id)
        } label: {
          Image(systemName: "trash")
        }
        .buttonStyle(.plain)
      }
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(WFTheme.panel.opacity(0.92))
    )
    .draggable(item.text) {
      HistoryDragPreview(text: item.text)
    }
  }
}

private struct HistoryDragPreview: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.callout)
      .lineLimit(5)
      .multilineTextAlignment(.leading)
      .padding(12)
      .frame(width: 280, alignment: .leading)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(WFTheme.accent.opacity(0.35), lineWidth: 1)
      )
      .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
  }
}

/// Lets the user drag a borderless panel by grabbing this area.
struct OverlayWindowDragArea: NSViewRepresentable {
  func makeNSView(context: Context) -> OverlayDragNSView {
    OverlayDragNSView()
  }

  func updateNSView(_ nsView: OverlayDragNSView, context: Context) {}
}

final class OverlayDragNSView: NSView {
  override var mouseDownCanMoveWindow: Bool { true }
}
