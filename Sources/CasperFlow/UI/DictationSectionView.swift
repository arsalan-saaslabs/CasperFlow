import SwiftUI

struct DictationSectionView: View {
  @ObservedObject var session: DictationSession
  @ObservedObject var settings: AppSettingsStore

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        header
        if session.phase == .error {
          errorBanner
        }
        controls
        levelMeter
        transcript
        Text("Hold \(settings.dictateHotkey.displayName) to dictate into the app that has the text caret. Use Note taker for videos and system audio.")
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
        Text(session.phase == .listening ? "Listening" : session.statusMessage)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }
    }
  }

  private var errorBanner: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("PyAI / Hear is unavailable")
        .font(.headline)
      Text(session.lastError ?? session.statusMessage)
        .font(.callout)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
      HStack {
        Button("Restart") { session.restartAfterError() }
          .buttonStyle(.borderedProminent)
          .tint(WFTheme.accent)
        Button("Dismiss") { session.dismissError() }
          .buttonStyle(.bordered)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.red.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(Color.red.opacity(0.35), lineWidth: 1)
    )
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
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(Color.secondary.opacity(0.15))
          Capsule()
            .fill(session.didClipRecently ? Color.red : WFTheme.accent)
            .frame(width: max(0, geo.size.width * CGFloat(session.level)))
        }
      }
      .frame(height: 6)
      if session.didClipRecently {
        Text("Clipping — back off the mic a little")
          .font(.caption2)
          .foregroundStyle(.red)
      }
    }
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
