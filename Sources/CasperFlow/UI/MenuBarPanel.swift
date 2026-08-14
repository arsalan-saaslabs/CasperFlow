import AppKit
import SwiftUI

struct MenuBarLabel: View {
  @ObservedObject var session: DictationSession

  var body: some View {
    Image(systemName: symbolName)
      .symbolRenderingMode(.hierarchical)
      .help(helpText)
  }

  private var symbolName: String {
    if !session.isEngineEnabled { return "waveform.slash" }
    switch session.phase {
    case .listening: return "mic.fill"
    case .connecting, .finalizing: return "waveform"
    case .composing: return "sparkles"
    case .error: return "exclamationmark.triangle.fill"
    default: return "waveform"
    }
  }

  private var helpText: String {
    if !session.isEngineEnabled { return "CasperFlow is disabled" }
    return session.statusMessage
  }
}

struct MenuBarPanel: View {
  @ObservedObject var session: DictationSession
  @ObservedObject private var settings = AppSettingsStore.shared
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(statusTitle)
        .font(.headline)
      Text(session.statusMessage)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }
    .padding(.vertical, 4)

    Divider()

    if session.phase == .error {
      Button("Restart last action") {
        session.restartAfterError()
      }
      Button("Dismiss error") {
        session.dismissError()
      }
      Divider()
    }

    Button(session.isEngineEnabled ? "Disable CasperFlow" : "Enable CasperFlow") {
      session.setEngineEnabled(!session.isEngineEnabled)
    }

    Divider()

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

    Button(session.isHoldingDictate ? "Stop dictate" : "Dictate") {
      session.toggleOverlayDictate()
    }

    Button(session.isHoldingAsk ? "Stop Ask ChatGPT" : "Ask ChatGPT") {
      session.toggleOverlayAsk()
    }

    Button("Rephrase selection") {
      session.rephraseFrontmostSelection()
    }

    Button("Command overlay") {
      session.toggleCommandOverlay()
    }

    Button("Show history") {
      session.toggleHistoryOverlay()
    }

    Button("Send error logs…") {
      AppLog.sendToSupport()
    }

    Button("Open CasperFlow") {
      openMainWindow()
    }

    Divider()

    Button("Quit CasperFlow") {
      NSApp.terminate(nil)
    }
  }

  private var toneBinding: Binding<WritingTone> {
    Binding(
      get: { session.activeTone },
      set: { session.setToneForCurrentApp($0) }
    )
  }

  private var statusTitle: String {
    if !session.isEngineEnabled { return "CasperFlow · Off" }
    switch session.phase {
    case .listening:
      return session.isNoteTaking ? "CasperFlow · Note taker" : "CasperFlow · Listening"
    case .connecting: return "CasperFlow · Connecting"
    case .finalizing: return "CasperFlow · Pasting"
    case .composing: return "CasperFlow · ChatGPT"
    case .error: return "CasperFlow · Error"
    default: return "CasperFlow · Ready"
    }
  }

  private func openMainWindow() {
    NSApp.activate(ignoringOtherApps: true)
    openWindow(id: "main")
    DispatchQueue.main.async {
      for window in NSApp.windows where window.title.contains("CasperFlow") {
        window.makeKeyAndOrderFront(nil)
      }
    }
  }
}
