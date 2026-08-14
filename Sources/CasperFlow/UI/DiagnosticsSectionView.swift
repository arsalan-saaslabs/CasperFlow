import SwiftUI

struct DiagnosticsSectionView: View {
  @ObservedObject var session: DictationSession
  @State private var copied = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Diagnostics")
          .font(.system(size: 28, weight: .semibold, design: .rounded))
        Text("Errors are saved on this Mac. Keys and tokens are stripped before send or copy.")
          .foregroundStyle(.secondary)
      }

      if let last = session.lastError, !last.isEmpty {
        Text(last)
          .font(.callout)
          .foregroundStyle(.red)
          .textSelection(.enabled)
      }

      HStack {
        Button("Send logs…") { AppLog.sendToSupport() }
          .buttonStyle(.borderedProminent)
          .tint(WFTheme.accent)
        Button("Copy logs") {
          AppLog.copyToPasteboard()
          copied = true
        }
        Button("Reveal log file") { AppLog.revealInFinder() }
        if copied {
          Text("Copied")
            .font(.caption)
            .foregroundStyle(WFTheme.accent)
        }
      }

      ScrollView {
        Text(AppLog.readSanitized())
          .font(.system(.caption2, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(12)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(WFTheme.panel.opacity(0.95))
      )
    }
    .padding(28)
  }
}
