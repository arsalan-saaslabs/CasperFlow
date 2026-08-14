import AppKit
import SwiftUI

struct NotesSectionView: View {
  @ObservedObject var session: DictationSession
  @ObservedObject var settings = AppSettingsStore.shared
  @ObservedObject var notes = NoteStore.shared
  @State private var selectedId: UUID?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header
      controls
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
      Text("Start from the menu bar or \(settings.notesHotkey.displayName) — you do not need this window during a meeting. System audio transcribes YouTube and calls (Screen Recording required).")
        .foregroundStyle(.secondary)
    }
  }

  private var controls: some View {
    VStack(alignment: .leading, spacing: 10) {
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

      HStack {
        if session.isNoteTaking {
          Button("Stop") { session.stopNoteTaking() }
            .buttonStyle(.borderedProminent)
            .tint(.red)
          ListeningPulse(isActive: session.phase == .listening, tint: .green)
          Text(session.statusMessage)
            .font(.caption)
            .foregroundStyle(.secondary)
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
            } label: {
              VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                  .font(.subheadline.weight(.semibold))
                  .lineLimit(1)
                Text(note.body.isEmpty ? "Empty" : note.body)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(2)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(10)
              .background(
                (selectedId ?? notes.activeNoteId) == note.id
                  ? WFTheme.accent.opacity(0.14)
                  : Color.secondary.opacity(0.08)
              )
              .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
    .frame(width: 240)
  }

  private var noteDetail: some View {
    let note = notes.notes.first { $0.id == (selectedId ?? notes.activeNoteId) }
    return VStack(alignment: .leading, spacing: 10) {
      if let note {
        Text(note.title)
          .font(.headline)
        Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
          .font(.caption)
          .foregroundStyle(.secondary)
        ScrollView {
          Text(note.body.isEmpty ? "Listening…" : note.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        HStack {
          Button("Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(note.body, forType: .string)
          }
          .disabled(note.body.isEmpty)
          Button("Delete", role: .destructive) {
            notes.delete(id: note.id)
            if selectedId == note.id { selectedId = nil }
          }
          Spacer()
        }
      } else {
        Text("Select a note or start capturing.")
          .foregroundStyle(.tertiary)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .padding(16)
    .background(cardBackground)
  }

  private var cardBackground: some View {
    RoundedRectangle(cornerRadius: 14, style: .continuous)
      .fill(WFTheme.panel.opacity(0.95))
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(WFTheme.accent.opacity(0.2), lineWidth: 1)
      )
  }
}
