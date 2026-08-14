import AppKit
import SwiftUI

/// Compact command palette over any app (tones, notes, history, dictate/ask).
@MainActor
final class CommandOverlayController {
  static let shared = CommandOverlayController()

  private var panel: NSPanel?
  private(set) var isVisible = false
  private var localEscapeMonitor: Any?
  private var globalEscapeMonitor: Any?
  private var lastOrigin: NSPoint?
  private var session: DictationSession?

  func attach(session: DictationSession) {
    self.session = session
  }

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
      context.duration = 0.16
      panel.animator().alphaValue = 0
    } completionHandler: {
      panel.orderOut(nil)
      panel.alphaValue = 1
    }
  }

  private func show() {
    HistoryOverlayController.shared.hide()
    guard let session else { return }
    session.refreshFrontmostApp()

    if panel == nil {
      let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 360, height: 430),
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
      rootView: CommandOverlayView(
        session: session,
        settings: AppSettingsStore.shared,
        onClose: { [weak self] in self?.hide() }
      )
    )
    host.frame = NSRect(x: 0, y: 0, width: 360, height: 430)
    host.autoresizingMask = [.width, .height]
    panel.contentView = host
    panel.setContentSize(NSSize(width: 360, height: 430))
    position(panel)
    panel.alphaValue = 0
    panel.orderFrontRegardless()
    isVisible = true
    installEscapeMonitors()
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.2
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
    let x = visible.midX - panel.frame.width / 2
    let y = visible.minY + 72
    panel.setFrameOrigin(NSPoint(x: x, y: y))
  }
}

struct CommandOverlayView: View {
  @ObservedObject var session: DictationSession
  @ObservedObject var settings: AppSettingsStore
  var onClose: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      Text(session.statusMessage)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)

      toneSection
      actionGrid
      noteRow
    }
    .padding(14)
    .frame(width: 360, height: 430, alignment: .topLeading)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(WFTheme.accent.opacity(0.28), lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
  }

  private var header: some View {
    HStack {
      OverlayWindowDragArea()
        .frame(width: 16, height: 24)
        .overlay {
          Image(systemName: "line.3.horizontal")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      VStack(alignment: .leading, spacing: 1) {
        Text("Casper")
          .font(.headline)
        Text("\(session.activeAppName) · Esc to close")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer()
      Button("Close", action: onClose)
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
  }

  private var toneSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Tone for \(session.activeProfileName)")
        .font(.caption.weight(.semibold))
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 6) {
        ForEach(WritingTone.allCases) { tone in
          Button {
            session.setToneForCurrentApp(tone)
          } label: {
            Text(tone.displayName)
              .font(.caption.weight(.semibold))
              .frame(maxWidth: .infinity)
              .padding(.vertical, 7)
              .background(
                session.activeTone == tone ? WFTheme.accent : Color.secondary.opacity(0.14)
              )
              .foregroundStyle(session.activeTone == tone ? Color.white : Color.primary)
              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private var actionGrid: some View {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
      overlayButton(
        title: session.isHoldingDictate ? "Stop dictate" : "Dictate",
        subtitle: settings.dictateHotkey.displayName,
        systemImage: "mic.fill"
      ) {
        session.toggleOverlayDictate()
      }
      overlayButton(
        title: session.isHoldingAsk ? "Stop Ask" : "Ask ChatGPT",
        subtitle: settings.askHotkey.displayName,
        systemImage: "sparkles"
      ) {
        session.toggleOverlayAsk()
      }
      overlayButton(
        title: "Rephrase",
        subtitle: settings.rephraseHotkey.displayName,
        systemImage: "text.quote"
      ) {
        session.rephraseFrontmostSelection()
      }
      overlayButton(
        title: "History",
        subtitle: settings.historyHotkey.displayName,
        systemImage: "clock.arrow.circlepath"
      ) {
        onClose()
        session.toggleHistoryOverlay()
      }
    }
  }

  private var noteRow: some View {
    VStack(alignment: .leading, spacing: 8) {
      overlayButton(
        title: session.isNoteTaking ? "Stop note taker" : "Start note taker",
        subtitle: settings.notesHotkey.displayName,
        systemImage: "note.text"
      ) {
        session.toggleNoteTaking()
      }
      Picker("Note audio", selection: $settings.noteAudioSource) {
        ForEach(NoteAudioSource.allCases) { source in
          Text(source.title).tag(source)
        }
      }
      .pickerStyle(.segmented)
      .disabled(session.isNoteTaking)
      .controlSize(.small)
    }
  }

  private func overlayButton(
    title: String,
    subtitle: String,
    systemImage: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 4) {
        Label(title, systemImage: systemImage)
          .font(.subheadline.weight(.semibold))
          .labelStyle(.titleAndIcon)
        Text(subtitle)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(10)
      .background(Color.secondary.opacity(0.12))
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}
