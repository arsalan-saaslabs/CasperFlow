import SwiftUI

struct HistorySectionView: View {
  @ObservedObject var store = HistoryStore.shared
  @ObservedObject var settings: AppSettingsStore
  @State private var filter: HistoryFilter = .all

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        Text("History")
          .font(.system(size: 28, weight: .semibold, design: .rounded))
        Text("Press \(settings.historyHotkey.displayName) anywhere to open the overlay. Drag a card into Slack, Mail, or Cursor.")
          .foregroundStyle(.secondary)
      }

      HStack {
        Picker("Filter", selection: $filter) {
          Text("All").tag(HistoryFilter.all)
          Text("Saved").tag(HistoryFilter.saved)
          ForEach(HistoryTaskKind.allCases) { kind in
            Text(kind.title).tag(HistoryFilter.kind(kind))
          }
        }
        .pickerStyle(.segmented)
        Spacer()
        Button("Clear unsaved", role: .destructive) {
          store.clearUnsaved()
        }
        .disabled(store.items.filter { !$0.isSaved }.isEmpty)
      }

      ScrollView {
        LazyVStack(spacing: 10) {
          let visible = store.items(filter: filter)
          if visible.isEmpty {
            Text("Nothing here yet.")
              .foregroundStyle(.tertiary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.top, 24)
          }
          ForEach(visible) { item in
            HistoryCardView(item: item, store: store) {
              _ = FrontmostTextInserter.paste(item.text)
            }
            .transition(.asymmetric(
              insertion: .scale.combined(with: .opacity),
              removal: .opacity
            ))
          }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.84), value: store.items)
      }
    }
    .padding(28)
  }
}
