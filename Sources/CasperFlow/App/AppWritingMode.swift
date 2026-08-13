import AppKit
import Combine
import Foundation

struct FrontmostAppInfo: Sendable {
  var bundleIdentifier: String?
  var localizedName: String?
  var profile: AppToneProfile
  var tone: WritingTone
}

/// Tracks the last focused app that is not CasperFlow itself.
/// Needed because opening CasperFlow would otherwise always report "CasperFlow".
@MainActor
final class FrontmostAppTracker: ObservableObject {
  static let shared = FrontmostAppTracker()

  static let casperFlowBundleId = "com.casperflow.app"

  @Published private(set) var targetBundleId: String?
  @Published private(set) var targetLocalizedName: String?

  private var observer: NSObjectProtocol?

  private init() {
    capture(from: NSWorkspace.shared.frontmostApplication, allowSelf: false)
    observer = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] note in
      guard let self else { return }
      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
      Task { @MainActor in
        self.capture(from: app, allowSelf: false)
      }
    }
  }

  deinit {
    if let observer {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }
  }

  /// Prefer the live frontmost app when it is not CasperFlow; otherwise last target.
  func resolveTarget() -> (bundleId: String?, name: String?) {
    let front = NSWorkspace.shared.frontmostApplication
    if let front, !Self.isCasperFlow(front) {
      capture(from: front, allowSelf: false)
      return (front.bundleIdentifier, front.localizedName)
    }
    return (targetBundleId, targetLocalizedName)
  }

  func info(settings: AppSettingsStore) -> FrontmostAppInfo {
    let target = resolveTarget()
    let profile = AppToneProfile.matching(
      bundleIdentifier: target.bundleId,
      localizedName: target.name
    )
    return FrontmostAppInfo(
      bundleIdentifier: target.bundleId,
      localizedName: target.name,
      profile: profile,
      tone: settings.tone(for: profile)
    )
  }

  private func capture(from app: NSRunningApplication?, allowSelf: Bool) {
    guard let app else { return }
    if !allowSelf, Self.isCasperFlow(app) { return }
    targetBundleId = app.bundleIdentifier
    targetLocalizedName = app.localizedName
  }

  private static func isCasperFlow(_ app: NSRunningApplication) -> Bool {
    if app.bundleIdentifier == casperFlowBundleId { return true }
    if (app.localizedName ?? "").localizedCaseInsensitiveContains("CasperFlow") {
      return true
    }
    return false
  }
}

enum FrontmostAppDetector {
  @MainActor
  static func current(settings: AppSettingsStore) -> FrontmostAppInfo {
    FrontmostAppTracker.shared.info(settings: settings)
  }
}
