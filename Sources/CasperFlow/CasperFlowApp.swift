import AppKit
import SwiftUI

@main
struct CasperFlowApp: App {
  @StateObject private var session: DictationSession

  init() {
    Self.quitIfAnotherInstanceIsRunning()
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

  /// Two running copies each keep their own in-memory shortcut, so old ⌘E and new ⌘O both fire.
  private static func quitIfAnotherInstanceIsRunning() {
    let id = Bundle.main.bundleIdentifier ?? "com.casperflow.app"
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
      .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    guard let other = others.first else { return }
    other.activate()
    exit(0)
  }
}
