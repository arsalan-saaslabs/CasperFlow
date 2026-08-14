import AppKit
import SwiftUI

struct KeysSectionView: View {
  @ObservedObject var settings: AppSettingsStore
  @State private var pyaiDraft: String = ""
  @State private var openAIDraft: String = ""
  @State private var showPyai = false
  @State private var showOpenAI = false
  @State private var savedMessage: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 6) {
          Text("API Keys")
            .font(.system(size: 28, weight: .semibold, design: .rounded))
          Text("Stored on this Mac only. Never logged.")
            .foregroundStyle(.secondary)
        }

        keyCard(
          title: "PyAI",
          subtitle: "Required for Hear speech-to-text",
          placeholder: "PYAI_API_KEY",
          text: $pyaiDraft,
          revealed: $showPyai
        )

        keyCard(
          title: "OpenAI",
          subtitle: "Optional for tone rewrite; required for Ask ChatGPT (Option+Command)",
          placeholder: "OPENAI_API_KEY",
          text: $openAIDraft,
          revealed: $showOpenAI
        )

        HStack(spacing: 12) {
          Button("Save keys") { save() }
            .buttonStyle(.borderedProminent)
            .tint(WFTheme.accent)

          if let savedMessage {
            Text(savedMessage)
              .font(.caption)
              .foregroundStyle(WFTheme.accent)
          }
        }

        Text("OpenAI rewrites dictation tone (except Do nothing) and writes Ask ChatGPT replies. Local tone still works with PyAI alone.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(28)
      .frame(maxWidth: 640, alignment: .leading)
    }
    .onAppear {
      pyaiDraft = settings.pyaiApiKey
      openAIDraft = settings.openAIApiKey
    }
  }

  private func keyCard(
    title: String,
    subtitle: String,
    placeholder: String,
    text: Binding<String>,
    revealed: Binding<Bool>
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.headline)
      Text(subtitle)
        .font(.caption)
        .foregroundStyle(.secondary)

      HStack(spacing: 8) {
        Group {
          if revealed.wrappedValue {
            TextField(placeholder, text: text)
          } else {
            SecureField(placeholder, text: text)
          }
        }
        .textFieldStyle(.plain)
        .font(.system(.body, design: .monospaced))
        .padding(10)
        .frame(minHeight: 36)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
        )

        Button(revealed.wrappedValue ? "Hide" : "Show") {
          revealed.wrappedValue.toggle()
        }
        .buttonStyle(.bordered)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(WFTheme.panel.opacity(0.95))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(WFTheme.accent.opacity(0.2), lineWidth: 1)
    )
  }

  private func save() {
    settings.pyaiApiKey = pyaiDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.openAIApiKey = openAIDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    savedMessage = "Keys saved."
  }
}


struct AppTonesSectionView: View {
  @ObservedObject var settings: AppSettingsStore

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 6) {
          Text("App tones")
            .font(.system(size: 28, weight: .semibold, design: .rounded))
          Text("Rephrase dictation to match each app. Do nothing pastes as spoken.")
            .foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 10) {
          Toggle("Enable tone rephrasing", isOn: $settings.tonePolishEnabled)
            .font(.headline)
          Text(toneHelpText)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

        VStack(alignment: .leading, spacing: 12) {
          Text("Tone per application")
            .font(.headline)
          ForEach(AppToneProfile.catalog) { profile in
            HStack {
              Text(profile.displayName)
                .frame(width: 140, alignment: .leading)
              Picker("", selection: binding(for: profile)) {
                ForEach(WritingTone.allCases) { tone in
                  Text(tone.displayName).tag(tone)
                }
              }
              .pickerStyle(.menu)
              .frame(maxWidth: 180)
              Text(settings.tone(for: profile).detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
              Spacer(minLength: 0)
            }
          }
          Button("Reset to defaults", role: .destructive) {
            settings.resetToneOverrides()
          }
          .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      }
      .padding(28)
      .frame(maxWidth: 720, alignment: .leading)
    }
  }

  private var toneHelpText: String {
    if !settings.tonePolishEnabled {
      return "Off — only lexicon cleanup (no casual/professional rewrite)."
    }
    if settings.openAIApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return "On — local tone rewrite per app. Do nothing skips rewrite. Add an OpenAI key for full LLM rephrasing."
    }
    return "On — local tone + OpenAI rephrase per app. Do nothing pastes as spoken even with an OpenAI key."
  }

  private var cardBackground: some View {
    RoundedRectangle(cornerRadius: 14, style: .continuous)
      .fill(WFTheme.panel.opacity(0.95))
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(WFTheme.accent.opacity(0.2), lineWidth: 1)
      )
  }

  private func binding(for profile: AppToneProfile) -> Binding<WritingTone> {
    Binding(
      get: { settings.tone(for: profile) },
      set: { settings.setTone($0, for: profile) }
    )
  }
}

struct AppearanceSectionView: View {
  @ObservedObject var settings: AppSettingsStore

  var body: some View {
    Form {
      Section {
        Picker("Theme", selection: $settings.appearance) {
          ForEach(AppAppearance.allCases) { mode in
            Text(mode.displayName).tag(mode)
          }
        }
        .pickerStyle(.segmented)
      } header: {
        Text("Appearance")
      } footer: {
        Text("Light, dark, or follow macOS System Settings.")
      }

      Section {
        HStack(spacing: 16) {
          previewCard(title: "Light", scheme: .light)
          previewCard(title: "Dark", scheme: .dark)
        }
        .listRowBackground(Color.clear)
      } header: {
        Text("Preview")
      }
    }
    .formStyle(.grouped)
    .padding(8)
  }

  private func previewCard(title: String, scheme: ColorScheme) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.caption.weight(.semibold))
      RoundedRectangle(cornerRadius: 8)
        .fill(WFTheme.accent.opacity(0.35))
        .frame(height: 36)
      Text("CasperFlow")
        .font(.system(.body, design: .rounded).weight(.semibold))
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(scheme == .dark ? Color.black.opacity(0.85) : Color.white)
    .foregroundStyle(scheme == .dark ? Color.white : WFTheme.ink)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
    )
  }
}

struct PermissionsSectionView: View {
  @ObservedObject var session: DictationSession

  var body: some View {
    Form {
      Section {
        HStack {
          Circle()
            .fill(session.globalHotkeyActive ? Color.green : Color.orange)
            .frame(width: 8, height: 8)
          Text(session.globalHotkeyActive ? "Global hotkey + paste ready" : "Accessibility required")
        }
        Text(GlobalHoldHotKey.isProcessTrusted ? "This process is trusted." : "This process is not trusted yet (toggle can look ON after a rebuild).")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(GlobalHoldHotKey.bundleIdentity)
          .font(.system(.caption2, design: .monospaced))
          .foregroundStyle(.secondary)
          .textSelection(.enabled)

        Button("Open Accessibility…") {
          GlobalHoldHotKey.openAccessibilitySettings()
          DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            session.refreshHotKeyAccess()
          }
        }
        Button("Reveal CasperFlow.app") {
          GlobalHoldHotKey.revealAppInFinder()
        }
        Button("I enabled it — recheck") {
          session.refreshHotKeyAccess()
        }
      } header: {
        Text("Accessibility")
      } footer: {
        Text("Enable the CasperFlow in ~/Applications (not Cursor, not the Desktop/dist copy). Use Reveal CasperFlow.app then Accessibility → +. Required for Ctrl+Option dictate, Option+Command Ask ChatGPT, rephrase, and paste.")
      }

      Section {
        Text("Microphone access is requested the first time you dictate.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } header: {
        Text("Microphone")
      }

      Section {
        Text("Note Taker → System audio needs Screen Recording. CasperFlow does not save the screen; it only reads playback audio.")
          .font(.caption)
          .foregroundStyle(.secondary)
        Button("Open Screen Recording…") {
          let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
          ]
          for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
          }
        }
      } header: {
        Text("Screen Recording")
      }
    }
    .formStyle(.grouped)
    .padding(8)
  }
}
