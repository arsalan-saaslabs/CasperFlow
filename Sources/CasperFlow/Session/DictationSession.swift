import AVFoundation
import AppKit
import Combine
import Foundation

/// Push-to-talk dictation session:
/// pre-roll → Hear stream → HUD partials → release commits → lock on `speech_final`.
@MainActor
final class DictationSession: ObservableObject {
  enum Phase: String {
    case idle
    case connecting
    case listening
    case finalizing
    case composing
    case error
  }

  enum CaptureKind: String {
    case dictate
    case ask
  }

  @Published var phase: Phase = .idle
  @Published var pendingPartial: String = ""
  @Published var committedLines: [String] = []
  @Published var statusMessage: String = "Hold Ctrl+Option to dictate, or Option+Command to ask ChatGPT"
  @Published var level: Float = 0
  @Published var didClipRecently: Bool = false
  @Published var lastError: String?
  @Published var activeTone: WritingTone = .general
  @Published var activeAppName: String = "—"
  @Published var activeProfileName: String = "Other apps"
  /// True only when Ctrl+Option works while another app is focused.
  @Published var globalHotkeyActive = false
  /// Settings recorder is capturing a new rephrase shortcut.
  @Published var isRecordingRephraseHotkey = false

  private var capture: AudioCaptureEngine?
  private var hear: HearClient?
  private let preRoll = PreRollBuffer(capacitySamples: AudioConstants.preRollSampleCount)
  private var isHolding = false
  private var didFlushPreRoll = false
  private var committedUtteranceIDs = Set<String>()
  /// Whether we already pasted at least one chunk during the current hold.
  private var didPasteInThisHold = false
  /// PCM actually sent this hold (for optional WAV export).
  private(set) var sentPCM: [Int16] = []
  private let polish = TextPolish.default
  private let settings: AppSettingsStore
  private var appSwitchCancellable: AnyCancellable?
  private var hotkeyCancellable: AnyCancellable?
  private var isRephrasingSelection = false
  private var captureKind: CaptureKind = .dictate
  /// Spoken instruction captured during an Ask ChatGPT hold (not prior dictation).
  private var askPromptLines: [String] = []

  private let apiKeyLock = NSLock()
  private var apiKey: String
  private let enableVoiceProcessing: Bool
  private let hotKey = GlobalHoldHotKey()
  private let rephraseHotKey: GlobalRephraseHotKey

  init(
    apiKey: String,
    settings: AppSettingsStore,
    enableVoiceProcessing: Bool = false
  ) {
    self.apiKey = apiKey
    self.settings = settings
    self.enableVoiceProcessing = enableVoiceProcessing
    self.rephraseHotKey = GlobalRephraseHotKey(combo: settings.rephraseHotkey)
    refreshFrontmostApp()
    installHotKey()
    appSwitchCancellable = FrontmostAppTracker.shared.$targetBundleId
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.refreshFrontmostApp()
      }
    hotkeyCancellable = settings.$rephraseHotkey
      .receive(on: RunLoop.main)
      .sink { [weak self] combo in
        self?.rephraseHotKey.updateCombo(combo)
      }
  }

  private func installHotKey() {
    hotKey.rephraseCombo = { [weak self] in
      self?.settings.rephraseHotkey ?? .defaultRephrase
    }
    hotKey.onPress = { [weak self] in self?.beginHold(kind: .dictate) }
    hotKey.onRelease = { [weak self] in self?.endHold() }
    hotKey.onAskPress = { [weak self] in
      guard let self, !self.isRecordingRephraseHotkey else { return }
      self.beginHold(kind: .ask)
    }
    hotKey.onAskRelease = { [weak self] in self?.endHold() }
    hotKey.onStatusChange = { [weak self] active in
      self?.globalHotkeyActive = active
      if active {
        self?.statusMessage = "Global hotkeys armed — Ctrl+Option dictate, Option+Command ask ChatGPT"
      } else {
        self?.statusMessage = "Enable ~/Applications/CasperFlow.app in Accessibility for global hotkeys + paste"
      }
    }
    rephraseHotKey.onFire = { [weak self] in
      self?.rephraseFrontmostSelection()
    }
    rephraseHotKey.onRecorded = { [weak self] combo in
      guard let self else { return }
      self.settings.rephraseHotkey = combo
      self.setRecordingRephraseHotkey(false)
    }
    hotKey.start()
    rephraseHotKey.start()
    FloatingHUDController.shared.attach(session: self)
  }

  /// Re-check Accessibility and reinstall the global monitor (after enabling in Settings).
  func refreshHotKeyAccess() {
    _ = GlobalHoldHotKey.requestTrust(prompt: true)
    hotKey.reinstall()
    rephraseHotKey.reinstall()
    globalHotkeyActive = hotKey.canInterceptOtherApps
  }

  func setRecordingRephraseHotkey(_ recording: Bool) {
    isRecordingRephraseHotkey = recording
    rephraseHotKey.isRecording = recording
  }

  /// Rephrase selected text in the focused app (ignores per-app "Do nothing").
  func rephraseFrontmostSelection() {
    guard !isHolding, !isRephrasingSelection, phase != .composing else { return }
    refreshFrontmostApp()

    let openAIKey = settings.openAIApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !openAIKey.isEmpty else {
      statusMessage = "Add an OpenAI key in API Keys to rephrase a selection"
      return
    }
    guard GlobalHoldHotKey.isProcessTrusted else {
      statusMessage = "Enable CasperFlow.app in Accessibility to rephrase in other apps"
      return
    }

    isRephrasingSelection = true
    let requestedTone = activeTone.appliesRewrite ? activeTone : .general
    let appName = activeAppName
    statusMessage = "Rephrasing selection (\(requestedTone.displayName))…"

    Task { @MainActor in
      defer { self.isRephrasingSelection = false }
      guard let selected = await FrontmostTextInserter.copySelection() else {
        self.statusMessage = "Select text in \(appName), then press \(self.settings.rephraseHotkey.displayName)"
        return
      }
      guard let rewritten = await OpenAIToneRephraser.rephrase(
        selected,
        tone: requestedTone,
        appName: appName,
        apiKey: openAIKey
      ) else {
        self.statusMessage = "OpenAI unavailable — selection left unchanged"
        return
      }
      let pasted = FrontmostTextInserter.paste(rewritten)
      self.statusMessage = pasted
        ? "Rephrased in \(appName)"
        : "Rephrase ready — focus another app to paste"
    }
  }

  private func syncFloatingHUD() {
    let toneLabel: String
    let committed: String
    if captureKind == .ask {
      toneLabel = "Ask ChatGPT · \(activeAppName)"
      committed = askPromptLines.joined(separator: " ")
    } else {
      toneLabel = settings.tonePolishEnabled
        ? "\(activeProfileName) · \(activeTone.displayName)"
        : "\(activeProfileName) · tone off"
      committed = fullTranscript
    }
    FloatingHUDController.shared.sync(
      phase: phase,
      pending: pendingPartial,
      committed: committed,
      mode: toneLabel
    )
  }

  func refreshFrontmostApp() {
    let info = FrontmostAppDetector.current(settings: settings)
    activeTone = info.tone
    activeProfileName = info.profile.displayName
    activeAppName = info.localizedName ?? info.bundleIdentifier ?? "Unknown"
  }

  private var toneEnabled: Bool { settings.tonePolishEnabled }

  private func polishText(_ text: String, stage: TextPolish.Stage) -> String {
    polish.apply(
      text,
      stage: stage,
      tone: activeTone,
      toneEnabled: toneEnabled && captureKind == .dictate
    )
  }

  func updateApiKey(_ key: String) {
    apiKeyLock.lock()
    apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
    apiKeyLock.unlock()
  }

  private var currentApiKey: String {
    apiKeyLock.lock()
    defer { apiKeyLock.unlock() }
    return apiKey
  }

  var fullTranscript: String {
    committedLines.joined(separator: " ")
  }

  func clearTranscript() {
    committedLines = []
    pendingPartial = ""
  }

  func beginHold(kind: CaptureKind = .dictate) {
    guard !isHolding, phase != .composing else { return }
    let key = currentApiKey
    guard !key.isEmpty else {
      phase = .error
      lastError = "PYAI_API_KEY is missing."
      statusMessage = lastError ?? ""
      return
    }
    if kind == .ask {
      let openAIKey = settings.openAIApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !openAIKey.isEmpty else {
        phase = .error
        lastError = "Add an OpenAI key in API Keys to ask ChatGPT."
        statusMessage = lastError ?? ""
        return
      }
    }

    captureKind = kind
    askPromptLines = []
    isHolding = true
    didFlushPreRoll = false
    didPasteInThisHold = false
    sentPCM = []
    pendingPartial = ""
    lastError = nil
    refreshFrontmostApp()
    phase = .connecting
    statusMessage = kind == .ask
      ? "Connecting… ChatGPT will write into \(activeAppName)"
      : "Connecting… will paste into \(activeAppName)"
    syncFloatingHUD()

    Task {
      let granted = await requestMicPermission()
      guard granted else {
        self.fail("Microphone permission denied.")
        return
      }
      do {
        try self.startPipeline(apiKey: key)
      } catch {
        self.fail(error.localizedDescription)
      }
    }
  }

  func endHold() {
    guard isHolding else { return }
    isHolding = false
    let kind = captureKind
    phase = .finalizing
    statusMessage = kind == .ask ? "Finishing your request…" : "Committing…"
    syncFloatingHUD()

    // Stop sending new mic audio; keep socket open briefly for speech_final.
    capture?.stop()
    capture = nil

    hear?.commit()

    Task {
      try? await Task.sleep(nanoseconds: 700_000_000)
      self.tearDownHear()
      if !self.pendingPartial.isEmpty {
        self.commitLine(self.pendingPartial, utteranceId: nil)
        self.pendingPartial = ""
      }
      self.level = 0
      if kind == .ask {
        await self.composeAskAndPaste()
      } else {
        self.phase = .idle
        self.statusMessage = self.didPasteInThisHold
          ? "Pasted into \(self.activeAppName). Hold again to continue."
          : "Done. Hold again to continue."
        self.syncFloatingHUD()
      }
    }
  }

  private func startPipeline(apiKey: String) throws {
    let client = HearClient(apiKey: apiKey)
    hear = client

    client.onConnected = { [weak self] in
      Task { @MainActor in
        self?.onHearConnected()
      }
    }
    client.onEvent = { [weak self] event in
      Task { @MainActor in
        self?.handleHearEvent(event)
      }
    }
    client.onDisconnected = { [weak self] in
      Task { @MainActor in
        guard let self, self.isHolding else { return }
        self.fail("Hear disconnected.")
      }
    }

    let engine = AudioCaptureEngine(enableVoiceProcessing: enableVoiceProcessing)
    capture = engine

    // Warm pre-roll while connecting so first word is not clipped.
    engine.onPCM16 = { [weak self] samples in
      Task { @MainActor in
        self?.handlePCM(samples)
      }
    }
    engine.onMetrics = { [weak self] metrics in
      Task { @MainActor in
        self?.level = metrics.rmsLevel
        if metrics.didClip {
          self?.didClipRecently = true
          Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            await MainActor.run { self?.didClipRecently = false }
          }
        }
      }
    }

    try engine.start()
    client.connect()
  }

  private func onHearConnected() {
    guard isHolding else { return }
    phase = .listening
    statusMessage = captureKind == .ask
      ? "Ask ChatGPT — speak your request, then release"
      : "Listening @ 16 kHz · \(activeTone.displayName) — release to commit"
    syncFloatingHUD()

    // Flush pre-roll collected during connect/warm-up.
    let primed = preRoll.flush()
    if !primed.isEmpty {
      didFlushPreRoll = true
      sendPCM(primed)
    }
  }

  private func handlePCM(_ samples: [Int16]) {
    guard isHolding else { return }

    if phase == .connecting || hear == nil {
      preRoll.append(samples)
      return
    }

    if phase == .listening {
      if !didFlushPreRoll {
        let primed = preRoll.flush()
        didFlushPreRoll = true
        if !primed.isEmpty {
          sendPCM(primed)
        }
      }
      sendPCM(samples)
    }
  }

  private func sendPCM(_ samples: [Int16]) {
    sentPCM.append(contentsOf: samples)
    hear?.sendPCM16(samples)
  }

  private func handleHearEvent(_ event: HearEvent) {
    switch event {
    case .partial(let text), .partialStable(let text):
      if !text.isEmpty {
        pendingPartial = polishText(text, stage: .live)
        syncFloatingHUD()
      }
    case .speechFinal(let text, let utteranceId):
      commitLine(text, utteranceId: utteranceId)
      pendingPartial = ""
      syncFloatingHUD()
    case .final(let text, let utteranceId):
      let corrected = polishText(text, stage: .committed)
      if let utteranceId, committedUtteranceIDs.contains(utteranceId) {
        if let idx = committedLines.indices.last, !corrected.isEmpty {
          committedLines[idx] = corrected
        }
        syncFloatingHUD()
        return
      }
      commitLine(text, utteranceId: utteranceId)
      pendingPartial = ""
      syncFloatingHUD()
    case .error(let message):
      fail(message)
    case .other:
      break
    }
  }

  private func commitLine(_ text: String, utteranceId: String?) {
    let trimmed = polishText(text, stage: .committed)
    guard !trimmed.isEmpty else { return }
    if let utteranceId {
      if committedUtteranceIDs.contains(utteranceId) {
        if let idx = committedLines.indices.last {
          committedLines[idx] = trimmed
        }
        if captureKind == .ask, let idx = askPromptLines.indices.last {
          askPromptLines[idx] = trimmed
        }
        // Do not re-paste late `final` corrections (would duplicate text).
        return
      }
      committedUtteranceIDs.insert(utteranceId)
    }
    committedLines.append(trimmed)
    if captureKind == .ask {
      askPromptLines.append(trimmed)
    }
    syncFloatingHUD()

    if captureKind == .ask {
      return
    }

    let tone = activeTone
    let appName = activeAppName
    let openAIKey = settings.openAIApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let useOpenAI =
      settings.tonePolishEnabled
      && tone.appliesRewrite
      && !openAIKey.isEmpty

    Task { @MainActor in
      var output = trimmed
      if useOpenAI {
        self.statusMessage = "Rephrasing (\(tone.displayName))…"
        if let rewritten = await OpenAIToneRephraser.rephrase(
          trimmed,
          tone: tone,
          appName: appName,
          apiKey: openAIKey
        ) {
          output = rewritten
          if let idx = self.committedLines.indices.last {
            self.committedLines[idx] = rewritten
          }
          self.syncFloatingHUD()
        } else {
          self.statusMessage = "OpenAI unavailable — using local \(tone.displayName) tone"
        }
      }
      self.pasteIntoFocusedApp(output)
    }
  }

  /// Send this hold’s spoken request to ChatGPT and paste the formatted reply.
  private func composeAskAndPaste() async {
    let prompt = askPromptLines.joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prompt.isEmpty else {
      phase = .idle
      statusMessage = "No speech captured — hold Option+Command and speak a request"
      syncFloatingHUD()
      return
    }

    let openAIKey = settings.openAIApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !openAIKey.isEmpty else {
      phase = .error
      statusMessage = "Add an OpenAI key in API Keys to ask ChatGPT"
      syncFloatingHUD()
      return
    }

    let appName = activeAppName
    phase = .composing
    statusMessage = "ChatGPT is writing…"
    pendingPartial = ""
    syncFloatingHUD()

    guard let answer = await OpenAICommandWriter.compose(
      prompt: prompt,
      appName: appName,
      apiKey: openAIKey
    ) else {
      phase = .error
      statusMessage = "ChatGPT unavailable — check your OpenAI key and try again"
      syncFloatingHUD()
      return
    }

    committedLines.append(answer)
    didPasteInThisHold = false
    pasteIntoFocusedApp(answer)
    phase = .idle
    if didPasteInThisHold {
      statusMessage = "Pasted ChatGPT reply into \(appName)"
    }
    syncFloatingHUD()
  }

  /// Paste into the app that currently has the text caret (not CasperFlow).
  private func pasteIntoFocusedApp(_ text: String) {
    refreshFrontmostApp()
    var chunk = text
    if didPasteInThisHold {
      chunk = " " + text
    }
    let pasted = FrontmostTextInserter.paste(chunk)
    if pasted {
      didPasteInThisHold = true
      statusMessage = "Pasted into \(activeAppName)"
    } else if !GlobalHoldHotKey.isProcessTrusted {
      statusMessage = "Paste failed — enable ~/Applications/CasperFlow.app in Accessibility"
    } else {
      statusMessage = "Paste failed — click the other app’s text field, then dictate again"
    }
  }

  private func fail(_ message: String) {
    lastError = message
    statusMessage = message
    phase = .error
    isHolding = false
    capture?.stop()
    capture = nil
    tearDownHear()
    level = 0
    syncFloatingHUD()
  }

  private func tearDownHear() {
    hear?.disconnect()
    hear = nil
    preRoll.reset()
  }

  private func requestMicPermission() async -> Bool {
    await withCheckedContinuation { continuation in
      switch AVCaptureDevice.authorizationStatus(for: .audio) {
      case .authorized:
        continuation.resume(returning: true)
      case .notDetermined:
        AVCaptureDevice.requestAccess(for: .audio) { granted in
          continuation.resume(returning: granted)
        }
      default:
        continuation.resume(returning: false)
      }
    }
  }
}
