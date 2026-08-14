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
    WindowGroup("Casper", id: "main") {
      RootView(session: session)
    }
    .defaultSize(width: 860, height: 600)

    MenuBarExtra {
      MenuBarPanel(session: session)
    } label: {
      MenuBarLabel(session: session)
    }
    .menuBarExtraStyle(.window)
  }

  /// Keep this launch. Quit stale CasperFlow copies that still own the old shortcuts.
  private static func quitIfAnotherInstanceIsRunning() {
    let id = Bundle.main.bundleIdentifier ?? "com.casperflow.app"
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
      .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    for other in others {
      other.forceTerminate()
    }
  }
}
