import SwiftUI

@main
struct CasperFlowApp: App {
  @StateObject private var session: DictationSession

  init() {
    let store = AppSettingsStore.shared
    _session = StateObject(
      wrappedValue: DictationSession(apiKey: store.pyaiApiKey, settings: store)
    )
  }

  var body: some Scene {
    WindowGroup("CasperFlow", id: "main") {
      RootView(session: session)
    }
    .defaultSize(width: 860, height: 600)

    MenuBarExtra {
      MenuBarPanel(session: session)
    } label: {
      MenuBarLabel(session: session)
    }
  }
}
