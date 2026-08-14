import AppKit
import SwiftUI

struct MenuBarLabel: View {
  @ObservedObject var session: DictationSession

  var body: some View {
    Image(nsImage: CasperBrandAssets.menuBarStatusImage())
      .renderingMode(.original)
      .resizable()
      .interpolation(.high)
      .aspectRatio(contentMode: .fit)
      .frame(width: 18, height: 18)
      .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
      .help(helpText)
      .accessibilityLabel("Casper")
  }

  private var helpText: String {
    if !session.isEngineEnabled { return "Casper is disabled" }
    return session.statusMessage
  }
}

struct MenuBarPanel: View {
  @ObservedObject var session: DictationSession
  @ObservedObject private var settings = AppSettingsStore.shared
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header

      Button(session.isHoldingDictate ? "Stop dictation" : "Start dictation") {
        session.toggleOverlayDictate()
      }
      .buttonStyle(.borderedProminent)
      .tint(WFTheme.accent)
      .controlSize(.large)
      .frame(maxWidth: .infinity)

      Divider()

      if session.phase == .error {
        Button("Restart last action") { session.restartAfterError() }
        Button("Dismiss error") { session.dismissError() }
        Divider()
      }

      Button(session.isEngineEnabled ? "Disable Casper" : "Enable Casper") {
        session.setEngineEnabled(!session.isEngineEnabled)
      }

      Button(session.isNoteTaking ? "Stop note taker" : "Start note taker") {
        session.toggleNoteTaking()
      }

      Picker("Note audio", selection: $settings.noteAudioSource) {
        ForEach(NoteAudioSource.allCases) { source in
          Text(source.title).tag(source)
        }
      }
      .disabled(session.isNoteTaking)

      Picker("Tone · \(session.activeProfileName)", selection: toneBinding) {
        ForEach(WritingTone.allCases) { tone in
          Text(tone.displayName).tag(tone)
        }
      }

      Button(session.isHoldingAsk ? "Stop Ask ChatGPT" : "Ask ChatGPT") {
        session.toggleOverlayAsk()
      }
      Button("Rephrase selection") { session.rephraseFrontmostSelection() }
      Button("Command overlay") { session.toggleCommandOverlay() }
      Button("Show history") { session.toggleHistoryOverlay() }

      Divider()

      Button("Send error logs…") { AppLog.sendToSupport() }
      Button("Open Casper") { openMainWindow() }
      Button("Quit Casper") { NSApp.terminate(nil) }
        .foregroundStyle(.secondary)
    }
    .padding(14)
    .frame(width: 268)
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 10) {
      CasperAppIconView()
        .frame(width: 36, height: 36)
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(statusWord)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
          Image(systemName: statusSymbol)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(statusTint)
        }
        Text(hotkeyHint)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
      Spacer(minLength: 0)
    }
  }

  private var statusWord: String {
    if !session.isEngineEnabled { return "Off" }
    switch session.phase {
    case .listening:
      return session.isNoteTaking ? "Notes" : "Listening"
    case .connecting: return "Listening"
    case .finalizing: return "Pasting"
    case .composing: return "Working"
    case .error: return "Error"
    default: return "Ready"
    }
  }

  private var statusSymbol: String {
    if !session.isEngineEnabled { return "pause.circle.fill" }
    switch session.phase {
    case .error: return "exclamationmark.circle.fill"
    case .listening, .connecting: return "waveform.circle.fill"
    default: return "checkmark.circle.fill"
    }
  }

  private var statusTint: Color {
    if !session.isEngineEnabled { return .secondary }
    switch session.phase {
    case .error: return .orange
    case .listening, .connecting: return WFTheme.accent
    default: return .green
    }
  }

  private var hotkeyHint: String {
    if session.phase == .error {
      return session.statusMessage
    }
    return "Hold \(settings.dictateHotkey.displayName) to dictate"
  }

  private var toneBinding: Binding<WritingTone> {
    Binding(
      get: { session.activeTone },
      set: { session.setToneForCurrentApp($0) }
    )
  }

  private func openMainWindow() {
    NSApp.activate(ignoringOtherApps: true)
    openWindow(id: "main")
    DispatchQueue.main.async {
      for window in NSApp.windows where window.title.contains("Casper") {
        window.makeKeyAndOrderFront(nil)
      }
    }
  }
}
