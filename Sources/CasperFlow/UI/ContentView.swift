import SwiftUI

/// Kept for previews; the app entry point is `CasperFlowApp`.
struct ContentView: View {
  @ObservedObject var session: DictationSession

  var body: some View {
    RootView(session: session)
  }
}
