import AppKit
import SwiftUI

struct NotesSectionView: View {
  @ObservedObject var session: DictationSession
  @ObservedObject var settings = AppSettingsStore.shared
  @ObservedObject var notes = NoteStore.shared
  @State private var selectedId: UUID?
  @State private var isSummarizing = false
  @State private var insightError: String?

  private var selectedNote: NoteEntry? {
    notes.notes.first { $0.id == (selectedId ?? notes.activeNoteId) }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header
      if session.phase == .error {
        errorBanner
      }
      sessionCard
      HStack(alignment: .top, spacing: 16) {
        noteList
        noteDetail
      }
    }
    .padding(28)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Note taker")
        .font(.system(size: 28, weight: .semibold, design: .rounded))
      Text(
        "Capture meetings or videos with \(settings.notesHotkey.displayName). Summarize with OpenAI when you are done."
      )
      .foregroundStyle(.secondary)
    }
  }

  private var errorBanner: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(session.lastError ?? session.statusMessage)
        .font(.callout)
        .foregroundStyle(.secondary)
      HStack {
        Button("Restart") { session.restartAfterError() }
          .buttonStyle(.borderedProminent)
          .tint(WFTheme.accent)
        Button("Dismiss") { session.dismissError() }
          .buttonStyle(.bordered)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.red.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private var sessionCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Picker("Audio source", selection: $settings.noteAudioSource) {
        ForEach(NoteAudioSource.allCases) { source in
          Text(source.title).tag(source)
        }
      }
      .pickerStyle(.segmented)
      .disabled(session.isNoteTaking)

      Text(settings.noteAudioSource.detail)
        .font(.caption)
        .foregroundStyle(.secondary)

      HStack(alignment: .center, spacing: 12) {
        if session.isNoteTaking {
          Button("Stop") { session.stopNoteTaking() }
            .buttonStyle(.borderedProminent)
            .tint(.red)
          Text("Recording")
            .font(.subheadline.weight(.semibold))
          elapsedLabel
          Text(session.statusMessage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        } else {
          Button("Start note taker") { session.startNoteTaking() }
            .buttonStyle(.borderedProminent)
            .tint(WFTheme.accent)
            .disabled(!session.isEngineEnabled)
        }
        Spacer()
      }
    }
    .padding(16)
    .background(cardBackground)
  }

  private var elapsedLabel: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let start = notes.activeNote?.createdAt ?? context.date
      Text(Self.formatElapsed(from: start, to: context.date))
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }
  }

  private var noteList: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Saved notes")
        .font(.headline)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 8) {
          if notes.notes.isEmpty {
            Text("No notes yet.")
              .foregroundStyle(.tertiary)
          }
          ForEach(notes.notes) { note in
            Button {
              selectedId = note.id
              insightError = nil
            } label: {
              noteRow(note)
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
    .frame(width: 260)
  }

  private func noteRow(_ note: NoteEntry) -> some View {
    let isSelected = (selectedId ?? notes.activeNoteId) == note.id
    return VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(note.title)
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)
        Spacer()
        if note.hasInsights {
          Image(systemName: "sparkles")
            .font(.caption2)
            .foregroundStyle(WFTheme.accent)
        }
      }
      Text(note.sourceTitle)
        .font(.caption2)
        .foregroundStyle(.secondary)
      Text(note.body.isEmpty ? "Empty" : note.body)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
    .background(
      isSelected ? WFTheme.accent.opacity(0.14) : Color.secondary.opacity(0.08)
    )
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
  }

  private var noteDetail: some View {
    Group {
      if let note = selectedNote {
        detailContent(note)
      } else {
        Text("Select a note or start capturing.")
          .foregroundStyle(.tertiary)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          .padding(16)
          .background(cardBackground)
      }
    }
  }

  private func detailContent(_ note: NoteEntry) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 4) {
          Text(note.title)
            .font(.headline)
          Text(
            "\(note.sourceTitle) · \(note.createdAt.formatted(date: .abbreviated, time: .shortened))"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        Spacer()
        detailActions(note)
      }

      if let insightError {
        Text(insightError)
          .font(.caption)
          .foregroundStyle(.red)
      }

      if note.hasInsights {
        insightsCard(note)
      }

      ScrollView {
        Text(note.body.isEmpty ? "Listening…" : note.body)
          .frame(maxWidth: .infinity, alignment: .leading)
          .textSelection(.enabled)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(cardBackground)
  }

  @ViewBuilder
  private func detailActions(_ note: NoteEntry) -> some View {
    HStack(spacing: 8) {
      Button {
        Task { await summarize(note) }
      } label: {
        if isSummarizing {
          ProgressView()
            .controlSize(.small)
        } else {
          Text(note.hasInsights ? "Refresh insights" : "Summarize")
        }
      }
      .disabled(note.body.isEmpty || isSummarizing || session.isNoteTaking)
      .help(summarizeHelp(for: note))

      Button("Copy") { copy(note.body) }
        .disabled(note.body.isEmpty)
      Button("Delete", role: .destructive) {
        notes.delete(id: note.id)
        if selectedId == note.id { selectedId = nil }
      }
    }
  }

  private func insightsCard(_ note: NoteEntry) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Insights")
          .font(.subheadline.weight(.semibold))
        Spacer()
        Button("Copy insights") {
          copy(Self.insightsText(note))
        }
      }
      if !note.summary.isEmpty {
        Text(note.summary)
          .font(.callout)
          .textSelection(.enabled)
      }
      if !note.actionItems.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("Action items")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          ForEach(Array(note.actionItems.enumerated()), id: \.offset) { _, item in
            HStack(alignment: .top, spacing: 6) {
              Text("•")
              Text(item)
                .textSelection(.enabled)
            }
            .font(.callout)
          }
        }
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
  }

  private var cardBackground: some View {
    RoundedRectangle(cornerRadius: 14, style: .continuous)
      .fill(WFTheme.panel.opacity(0.95))
  }

  private func summarizeHelp(for note: NoteEntry) -> String {
    if settings.openAIApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return "Add an OpenAI key in API Keys."
    }
    if session.isNoteTaking {
      return "Stop recording before summarizing."
    }
    if note.body.isEmpty {
      return "Capture some transcript first."
    }
    return "Write a summary and action items with OpenAI."
  }

  private func summarize(_ note: NoteEntry) async {
    insightError = nil
    let key = settings.openAIApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else {
      insightError = "Add an OpenAI key in API Keys to summarize."
      return
    }
    isSummarizing = true
    defer { isSummarizing = false }
    let result = await OpenAINoteInsights.generate(transcript: note.body, apiKey: key)
    if let result {
      notes.setInsights(id: note.id, summary: result.summary, actionItems: result.actionItems)
    } else {
      insightError = "Could not summarize. Check your OpenAI key and try again."
    }
  }

  private func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  private static func insightsText(_ note: NoteEntry) -> String {
    var parts: [String] = []
    if !note.summary.isEmpty {
      parts.append("Summary\n\(note.summary)")
    }
    if !note.actionItems.isEmpty {
      let bullets = note.actionItems.map { "• \($0)" }.joined(separator: "\n")
      parts.append("Action items\n\(bullets)")
    }
    return parts.joined(separator: "\n\n")
  }

  private static func formatElapsed(from start: Date, to now: Date) -> String {
    let seconds = max(0, Int(now.timeIntervalSince(start)))
    let minutes = seconds / 60
    let remainder = seconds % 60
    return String(format: "%d:%02d", minutes, remainder)
  }
}
