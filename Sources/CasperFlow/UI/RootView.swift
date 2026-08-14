import SwiftUI

struct RootView: View {
  @ObservedObject private var settings = AppSettingsStore.shared
  @ObservedObject var session: DictationSession
  @State private var section: AppSection = .dictation

  var body: some View {
    NavigationSplitView {
      sidebar
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
    } detail: {
      detail
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background)
    }
    .tint(WFTheme.accent)
    .preferredColorScheme(colorScheme)
    .onAppear {
      session.refreshFrontmostApp()
      session.refreshHotKeyAccess()
      session.updateApiKey(settings.pyaiApiKey)
    }
    .onChange(of: settings.pyaiApiKey) { _, newValue in
      session.updateApiKey(newValue)
    }
    .background(
      SpaceHoldMonitor(
        onPress: { session.beginHold() },
        onRelease: { session.endHold() }
      )
    )
  }

  private var colorScheme: ColorScheme? {
    switch settings.appearance {
    case .system: return nil
    case .light: return .light
    case .dark: return .dark
    }
  }

  private var background: some View {
    LinearGradient(
      colors: [
        WFTheme.cream.opacity(0.35),
        WFTheme.accent.opacity(0.08),
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
    .ignoresSafeArea()
  }

  private var sidebar: some View {
    List(selection: $section) {
      Section {
        ForEach(AppSection.allCases) { item in
          Label(item.title, systemImage: item.systemImage)
            .tag(item)
        }
      }
    }
    .listStyle(.sidebar)
    .safeAreaInset(edge: .top) {
      CasperLockup(compact: true)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder
  private var detail: some View {
    switch section {
    case .dictation:
      DictationSectionView(session: session, settings: settings)
    case .notes:
      NotesSectionView(session: session)
    case .keys:
      KeysSectionView(settings: settings)
    case .shortcuts:
      ShortcutsSectionView(settings: settings, session: session)
    case .history:
      HistorySectionView(settings: settings)
    case .vocabulary:
      VocabularySectionView()
    case .appTones:
      AppTonesSectionView(settings: settings)
    case .appearance:
      AppearanceSectionView(settings: settings)
    case .permissions:
      PermissionsSectionView(session: session)
    case .diagnostics:
      DiagnosticsSectionView(session: session)
    }
  }
}
