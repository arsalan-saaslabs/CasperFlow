import SwiftUI

struct DictationSectionView: View {
  @ObservedObject var session: DictationSession
  @ObservedObject var settings: AppSettingsStore

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        header
        statusRow
        controls
        levelMeter
        transcript
        Text("Hold \(settings.dictateHotkey.displayName) to dictate into the focused app (microphone). Use Note taker to transcribe a video via system audio.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(28)
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Dictation")
          .font(.system(size: 28, weight: .semibold, design: .rounded))
        Text("Speak naturally — text pastes at the caret")
          .foregroundStyle(.secondary)
      }
      Spacer()
      if isArmed {
        ListeningPulse(isActive: true, tint: session.phase == .listening ? .green : .orange)
      }
    }
  }

  private var statusRow: some View {
    HStack(spacing: 12) {
      statusChip(
        title: session.activeAppName,
        subtitle: settings.tonePolishEnabled
          ? "\(session.activeProfileName) · \(session.activeTone.displayName)"
          : "Tone polish off",
        tint: WFTheme.accent
      )
      statusChip(
        title: session.globalHotkeyActive ? "Global ON" : "Global OFF",
        subtitle: settings.dictateHotkey.displayName,
        tint: session.globalHotkeyActive ? .green : .orange
      )
      statusChip(
        title: "Ask ChatGPT",
        subtitle: settings.askHotkey.displayName,
        tint: WFTheme.accent
      )
      statusChip(
        title: "Rephrase",
        subtitle: settings.rephraseHotkey.displayName,
        tint: WFTheme.accent
      )
      Spacer()
      Button("Refresh app") { session.refreshFrontmostApp() }
        .buttonStyle(.bordered)
    }
  }

  private func statusChip(title: String, subtitle: String, tint: Color) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
      Text(subtitle)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(tint.opacity(0.12))
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
  }

  private var controls: some View {
    HStack(spacing: 12) {
      HoldButton(
        title: isArmed ? "Release to finish" : "Hold to talk",
        isActive: isArmed,
        onPress: { session.beginHold() },
        onRelease: { session.endHold() }
      )
      Button("Clear") { session.clearTranscript() }
        .buttonStyle(.bordered)
      Spacer()
      Text(session.statusMessage)
        .font(.caption)
        .foregroundStyle(session.phase == .error ? .red : .secondary)
        .lineLimit(2)
        .multilineTextAlignment(.trailing)
    }
  }

  private var isArmed: Bool {
    session.phase == .listening
      || session.phase == .connecting
      || session.phase == .finalizing
      || session.phase == .composing
  }

  private var levelMeter: some View {
    VStack(alignment: .leading, spacing: 8) {
      LiveWaveform(level: session.level, isActive: isArmed)
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(Color.secondary.opacity(0.15))
          Capsule()
            .fill(session.didClipRecently ? Color.red : WFTheme.accent)
            .frame(width: max(0, geo.size.width * CGFloat(session.level)))
            .animation(.easeOut(duration: 0.12), value: session.level)
        }
      }
      .frame(height: 8)
      if session.didClipRecently {
        Text("Clipping — back off the mic a little")
          .font(.caption2)
          .foregroundStyle(.red)
          .transition(.opacity)
      }
    }
    .animation(.easeInOut(duration: 0.2), value: isArmed)
  }

  private var transcript: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        if !session.fullTranscript.isEmpty {
          Text(session.fullTranscript)
            .font(.title3)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        if !session.pendingPartial.isEmpty {
          Text(session.pendingPartial)
            .font(.title3)
            .italic()
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentTransition(.opacity)
            .animation(.easeOut(duration: 0.15), value: session.pendingPartial)
        }
        if session.fullTranscript.isEmpty && session.pendingPartial.isEmpty {
          Text("Transcript appears here while you dictate…")
            .foregroundStyle(.tertiary)
        }
      }
      .padding(16)
    }
    .frame(minHeight: 180)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(WFTheme.panel.opacity(0.9))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(WFTheme.accent.opacity(0.18), lineWidth: 1)
    )
  }
}

struct HoldButton: View {
  let title: String
  let isActive: Bool
  let onPress: () -> Void
  let onRelease: () -> Void

  @State private var pressed = false

  var body: some View {
    Text(title)
      .font(.headline)
      .padding(.horizontal, 18)
      .padding(.vertical, 12)
      .background(isActive || pressed ? Color.red.opacity(0.85) : WFTheme.accent)
      .foregroundStyle(.white)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .scaleEffect(isActive || pressed ? 1.04 : 1)
      .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isActive || pressed)
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { _ in
            guard !pressed else { return }
            pressed = true
            onPress()
          }
          .onEnded { _ in
            pressed = false
            onRelease()
          }
      )
  }
}
