import SwiftUI

/// Settings: add, edit, and delete personal names and jargon.
struct VocabularySectionView: View {
  @ObservedObject var store = VocabularyStore.shared
  @State private var heardDraft = ""
  @State private var replacementDraft = ""
  @State private var editingId: UUID?
  @State private var errorMessage: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Vocabulary")
          .font(.system(size: 28, weight: .semibold, design: .rounded))
        Text("Teach CasperFlow how Hear should spell names and jargon. Applied live in the HUD and when text is pasted.")
          .foregroundStyle(.secondary)
      }

      editorCard

      if let errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
      }

      ScrollView {
        LazyVStack(spacing: 10) {
          if store.terms.isEmpty {
            Text("No personal terms yet. Example: heard “denim”, paste “DNM”.")
              .foregroundStyle(.tertiary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.top, 12)
          }
          ForEach(store.terms) { term in
            termRow(term)
          }
        }
      }
    }
    .padding(28)
    .frame(maxWidth: 720, alignment: .leading)
  }

  private var editorCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(editingId == nil ? "Add a term" : "Edit term")
        .font(.headline)
      HStack(alignment: .top, spacing: 12) {
        labeledField("Hear writes", text: $heardDraft, placeholder: "denim")
        Image(systemName: "arrow.right")
          .foregroundStyle(.secondary)
          .padding(.top, 28)
        labeledField("You want", text: $replacementDraft, placeholder: "DNM")
      }
      HStack {
        Button(editingId == nil ? "Add" : "Save") {
          save()
        }
        .buttonStyle(.borderedProminent)
        .tint(WFTheme.accent)
        .disabled(!canSubmit)

        if editingId != nil {
          Button("Cancel") { resetEditor() }
        }
        Spacer()
        Text("\(store.terms.count) / \(VocabularyStore.maxTermCount)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(cardBackground)
  }

  private func labeledField(_ title: String, text: Binding<String>, placeholder: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      TextField(placeholder, text: text)
        .textFieldStyle(.roundedBorder)
        .onChange(of: text.wrappedValue) { _, _ in
          errorMessage = nil
        }
    }
  }

  private func termRow(_ term: VocabularyTerm) -> some View {
    HStack(spacing: 12) {
      Text(term.heard)
        .font(.body)
      Image(systemName: "arrow.right")
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(term.replacement)
        .font(.body.weight(.semibold))
      Spacer()
      Button("Edit") {
        editingId = term.id
        heardDraft = term.heard
        replacementDraft = term.replacement
        errorMessage = nil
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      Button(role: .destructive) {
        if editingId == term.id {
          resetEditor()
        }
        store.delete(id: term.id)
      } label: {
        Image(systemName: "trash")
      }
      .buttonStyle(.plain)
    }
    .padding(12)
    .background(cardBackground)
  }

  private var canSubmit: Bool {
    !heardDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !replacementDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var cardBackground: some View {
    RoundedRectangle(cornerRadius: 14, style: .continuous)
      .fill(WFTheme.panel.opacity(0.95))
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(WFTheme.accent.opacity(0.2), lineWidth: 1)
      )
  }

  private func save() {
    let error: String?
    if let editingId {
      error = store.update(id: editingId, heard: heardDraft, replacement: replacementDraft)
    } else {
      error = store.add(heard: heardDraft, replacement: replacementDraft)
    }
    if let error {
      errorMessage = error
      return
    }
    resetEditor()
  }

  private func resetEditor() {
    editingId = nil
    heardDraft = ""
    replacementDraft = ""
    errorMessage = nil
  }
}
