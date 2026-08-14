import SwiftUI

struct ShortcutsSectionView: View {
  @ObservedObject var settings: AppSettingsStore
  @ObservedObject var session: DictationSession

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Shortcuts")
            .font(.system(size: 28, weight: .semibold, design: .rounded))
          Text("Press any key or modifier chord, then release. One key is enough. Esc cancels recording.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 8) {
          Text("Dictate & Ask ChatGPT")
            .font(.headline)
          Picker("Talk style", selection: $settings.pushToTalkStyle) {
            ForEach(PushToTalkStyle.allCases) { style in
              Text(style.title).tag(style)
            }
          }
          .pickerStyle(.segmented)
          Text(settings.pushToTalkStyle.detail)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(WFTheme.panel.opacity(0.95))
            .overlay(
              RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(WFTheme.accent.opacity(0.2), lineWidth: 1)
            )
        )

        ForEach(HotkeyAction.allCases) { action in
          shortcutCard(action)
        }

        if let error = session.hotkeyRecordError {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
        }
      }
      .padding(28)
      .frame(maxWidth: 720, alignment: .leading)
    }
    .onDisappear {
      session.setRecordingHotkey(nil)
    }
    .background(
      ShortcutCatcherView(isActive: session.recordingAction != nil) { event in
        session.ingestRecordingEvent(event)
      }
    )
  }

  private func shortcutCard(_ action: HotkeyAction) -> some View {
    let combo = settings.combo(for: action)
    let isRecording = session.recordingAction == action

    return VStack(alignment: .leading, spacing: 10) {
      Text(action.title)
        .font(.headline)
      Text(action.detail)
        .font(.caption)
        .foregroundStyle(.secondary)

      HStack(spacing: 12) {
        Text(combo.displayName)
          .font(.system(.body, design: .rounded).monospaced())
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(WFTheme.accentSoft)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

        if isRecording {
          Text("Press the new shortcut now, then release. Esc cancels.")
            .font(.caption)
            .foregroundStyle(WFTheme.accent)
          Button("Cancel") {
            session.setRecordingHotkey(nil)
          }
          .buttonStyle(.bordered)
        } else {
          Button("Change shortcut") {
            session.hotkeyRecordError = nil
            session.setRecordingHotkey(action)
          }
          .buttonStyle(.bordered)
          Button("Reset") {
            settings.resetHotkey(action)
            session.hotkeyRecordError = nil
          }
          .buttonStyle(.bordered)
        }
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(WFTheme.panel.opacity(0.95))
        .overlay(
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(WFTheme.accent.opacity(isRecording ? 0.55 : 0.2), lineWidth: 1)
        )
    )
  }
}
