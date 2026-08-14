import AVFoundation
import AppKit
import Combine
import CoreGraphics
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
    case notes
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
  /// Settings recorder is capturing a new shortcut.
  @Published var recordingAction: HotkeyAction?
  @Published var hotkeyRecordError: String?
  /// Menu-bar enable/disable: pauses global hotkeys when false.
  @Published var isEngineEnabled = true
  /// Note Taker records into CasperFlow instead of pasting.
  @Published var isNoteTaking = false
  var isHoldingDictate: Bool { isHolding && captureKind == .dictate }
  var isHoldingAsk: Bool { isHolding && captureKind == .ask }

  private var noteAudioSource: NoteAudioSource { settings.noteAudioSource }

  private var capture: AudioCaptureEngine?
  private var systemCapture: SystemAudioCapture?
  private var hear: HearClient?
  /// Idle dictate/ask socket so the next hold skips most of the handshake.
  private var warmHear: HearClient?
  /// True after Hear WebSocket opens. Audio is pre-rolled until then.
  private var hearSocketReady = false
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
  /// OpenAI rewrite + paste jobs still running after the user released the key.
  private var inFlightPasteCount = 0
  private var captureKind: CaptureKind = .dictate
  /// Spoken instruction captured during an Ask ChatGPT hold (not prior dictation).
  private var askPromptLines: [String] = []
  private var lastFailedKind: CaptureKind = .dictate
  private var lastHudLevelSync = Date.distantPast

  private let apiKeyLock = NSLock()
  private var apiKey: String
  private let enableVoiceProcessing: Bool
  private let hotKey = GlobalHoldHotKey()
  private let rephraseHotKey: GlobalRephraseHotKey
  private let historyHotKey: GlobalRephraseHotKey
  private let notesHotKey: GlobalRephraseHotKey
  private let paletteHotKey: GlobalRephraseHotKey
  private let shortcutRecorder = ShortcutRecorder()
  private var historyHotkeyCancellable: AnyCancellable?
  private var notesHotkeyCancellable: AnyCancellable?
  private var paletteHotkeyCancellable: AnyCancellable?
  /// When true, dictate/ask was started from the overlay or menu — ignore hotkey release.
  private var overlayCaptureActive = false
  private var lastNoteMic: [Int16] = []
  private var lastNoteSys: [Int16] = []

  init(
    apiKey: String,
    settings: AppSettingsStore,
    enableVoiceProcessing: Bool = true
  ) {
    self.apiKey = apiKey
    self.settings = settings
    self.enableVoiceProcessing = enableVoiceProcessing
    self.rephraseHotKey = GlobalRephraseHotKey(combo: settings.rephraseHotkey)
    self.historyHotKey = GlobalRephraseHotKey(combo: settings.historyHotkey)
    self.notesHotKey = GlobalRephraseHotKey(combo: settings.notesHotkey)
    self.paletteHotKey = GlobalRephraseHotKey(combo: settings.paletteHotkey)
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
    historyHotkeyCancellable = settings.$historyHotkey
      .receive(on: RunLoop.main)
      .sink { [weak self] combo in
        self?.historyHotKey.updateCombo(combo)
      }
    notesHotkeyCancellable = settings.$notesHotkey
      .receive(on: RunLoop.main)
      .sink { [weak self] combo in
        self?.notesHotKey.updateCombo(combo)
      }
    paletteHotkeyCancellable = settings.$paletteHotkey
      .receive(on: RunLoop.main)
      .sink { [weak self] combo in
        self?.paletteHotKey.updateCombo(combo)
      }
  }

  private func installHotKey() {
    hotKey.rephraseCombo = { [weak self] in
      self?.settings.rephraseHotkey ?? .defaultRephrase
    }
    hotKey.dictateCombo = { [weak self] in
      self?.settings.dictateHotkey ?? .pushToTalk
    }
    hotKey.askCombo = { [weak self] in
      self?.settings.askHotkey ?? .askChat
    }
    hotKey.isToggleMode = { [weak self] in
      self?.settings.pushToTalkStyle == .toggle
    }
    hotKey.onPress = { [weak self] in
      guard let self, self.recordingAction == nil else { return }
      self.overlayCaptureActive = false
      self.beginHold(kind: .dictate)
    }
    hotKey.onRelease = { [weak self] in
      guard let self, !self.overlayCaptureActive else { return }
      self.endHold()
    }
    hotKey.onAskPress = { [weak self] in
      guard let self, self.recordingAction == nil else { return }
      self.overlayCaptureActive = false
      self.beginHold(kind: .ask)
    }
    hotKey.onAskRelease = { [weak self] in
      guard let self, !self.overlayCaptureActive else { return }
      self.endHold()
    }
    hotKey.onStatusChange = { [weak self] active in
      self?.globalHotkeyActive = active
      if active {
        let dictate = self?.settings.dictateHotkey.displayName ?? "⌃ + ⌥"
        let ask = self?.settings.askHotkey.displayName ?? "⌥ + ⌘"
        self?.statusMessage = "Global hotkeys armed — hold \(dictate) to dictate, \(ask) to ask ChatGPT"
      } else {
        self?.statusMessage = "Enable ~/Applications/Casper.app in Accessibility for global hotkeys + paste"
      }
    }
    rephraseHotKey.onFire = { [weak self] in
      guard let self, self.recordingAction == nil else { return }
      guard self.canOpenUtilityOverlay else { return }
      self.rephraseFrontmostSelection()
    }
    historyHotKey.onFire = { [weak self] in
      guard let self, self.recordingAction == nil else { return }
      guard self.canOpenUtilityOverlay else { return }
      self.toggleHistoryOverlay()
    }
    notesHotKey.onFire = { [weak self] in
      guard let self, self.recordingAction == nil else { return }
      guard self.canOpenUtilityOverlay else { return }
      self.toggleNoteTaking()
    }
    paletteHotKey.onFire = { [weak self] in
      guard let self, self.recordingAction == nil else { return }
      guard self.canOpenUtilityOverlay else { return }
      self.toggleCommandOverlay()
    }
    shortcutRecorder.onCapture = { [weak self] combo in
      self?.finishRecording(combo: combo)
    }
    shortcutRecorder.onCancel = { [weak self] in
      self?.setRecordingHotkey(nil)
      self?.statusMessage = "Shortcut change cancelled"
    }
    HistoryOverlayController.shared.onPaste = { [weak self] item in
      self?.pasteHistoryItem(item)
    }
    isEngineEnabled = settings.engineEnabled
    if isEngineEnabled {
      hotKey.start()
      rephraseHotKey.start()
      historyHotKey.start()
      notesHotKey.start()
      paletteHotKey.start()
    } else {
      statusMessage = "CasperFlow is disabled — enable it from the menu bar"
    }
    FloatingHUDController.shared.attach(session: self)
    CommandOverlayController.shared.attach(session: self)
    warmPreconnect()
  }

  /// Pause or resume global hotkeys from the menu bar.
  func setEngineEnabled(_ enabled: Bool) {
    settings.engineEnabled = enabled
    isEngineEnabled = enabled
    if enabled {
      hotKey.start()
      rephraseHotKey.start()
      historyHotKey.start()
      notesHotKey.start()
      paletteHotKey.start()
      refreshHotKeyAccess()
      statusMessage = "CasperFlow enabled — hotkeys armed"
      warmPreconnect()
    } else {
      if isHolding {
        endHold()
      }
      discardWarmHear()
      HistoryOverlayController.shared.hide()
      CommandOverlayController.shared.hide()
      hotKey.stop()
      rephraseHotKey.stop()
      historyHotKey.stop()
      notesHotKey.stop()
      paletteHotKey.stop()
      globalHotkeyActive = false
      statusMessage = "CasperFlow disabled — hotkeys paused"
      phase = .idle
      syncFloatingHUD()
    }
  }

  /// Re-check Accessibility and reinstall the global monitor (after enabling in Settings).
  func refreshHotKeyAccess() {
    if recordingAction != nil { return }
    _ = GlobalHoldHotKey.requestTrust(prompt: true)
    hotKey.reinstall()
    rephraseHotKey.reinstall()
    historyHotKey.reinstall()
    notesHotKey.reinstall()
    paletteHotKey.reinstall()
    globalHotkeyActive = hotKey.canInterceptOtherApps
  }

  func toggleHistoryOverlay() {
    guard isEngineEnabled else { return }
    guard recordingAction == nil else { return }
    guard canOpenUtilityOverlay else { return }
    CommandOverlayController.shared.hide()
    HistoryOverlayController.shared.toggle()
  }

  func toggleCommandOverlay() {
    guard isEngineEnabled else { return }
    guard recordingAction == nil else { return }
    guard canOpenUtilityOverlay else { return }
    CommandOverlayController.shared.toggle()
  }

  /// History / command palette must not open on the same key-up as dictate.
  private var canOpenUtilityOverlay: Bool {
    !isHolding
      && phase != .connecting
      && phase != .listening
      && phase != .finalizing
      && phase != .composing
  }

  func setToneForCurrentApp(_ tone: WritingTone) {
    refreshFrontmostApp()
    let info = FrontmostAppDetector.current(settings: settings)
    settings.setTone(tone, for: info.profile)
    refreshFrontmostApp()
    statusMessage = "Tone for \(info.profile.displayName): \(tone.displayName)"
  }

  func toggleOverlayDictate() {
    if isHoldingDictate {
      overlayCaptureActive = false
      endHold()
      return
    }
    overlayCaptureActive = true
    beginHold(kind: .dictate)
  }

  func toggleOverlayAsk() {
    if isHoldingAsk {
      overlayCaptureActive = false
      endHold()
      return
    }
    overlayCaptureActive = true
    beginHold(kind: .ask)
  }

  func dismissError() {
    guard phase == .error else { return }
    lastError = nil
    phase = .idle
    statusMessage = "Ready. Start again from the shortcut, overlay, or Restart."
    syncFloatingHUD()
  }

  func restartAfterError() {
    let kind = lastFailedKind
    lastError = nil
    phase = .idle
    isHolding = false
    isNoteTaking = false
    overlayCaptureActive = false
    capture?.stop()
    capture = nil
    systemCapture?.stop()
    systemCapture = nil
    tearDownHear()
    switch kind {
    case .notes:
      startNoteTaking()
    case .dictate:
      overlayCaptureActive = true
      beginHold(kind: .dictate)
    case .ask:
      overlayCaptureActive = true
      beginHold(kind: .ask)
    }
  }

  func pasteHistoryItem(_ item: HistoryItem) {
    let pasted = FrontmostTextInserter.paste(item.text)
    statusMessage = pasted
      ? "Pasted history into \(activeAppName)"
      : "Click a text field, then paste from history"
    if pasted {
      FloatingHUDController.shared.flashPasted(into: activeAppName)
    }
  }

  func setRecordingHotkey(_ action: HotkeyAction?) {
    recordingAction = action
    hotkeyRecordError = nil
    hotKey.isPaused = action != nil

    if let action {
      if isHolding { endHold() }
      rephraseHotKey.stop()
      historyHotKey.stop()
      notesHotKey.stop()
      paletteHotKey.stop()
      shortcutRecorder.start()
      statusMessage = "Press a shortcut for \(action.title), then release"
    } else {
      shortcutRecorder.stop()
      if isEngineEnabled {
        rephraseHotKey.start()
        historyHotKey.start()
        notesHotKey.start()
        paletteHotKey.start()
      }
    }
  }

  func ingestRecordingEvent(_ event: NSEvent) {
    guard recordingAction != nil else { return }
    shortcutRecorder.ingest(event)
  }

  private func finishRecording(combo: HotkeyCombo) {
    guard let action = recordingAction else { return }
    if let error = settings.assign(combo, to: action) {
      hotkeyRecordError = error
      shortcutRecorder.stop()
      shortcutRecorder.start()
      return
    }
    hotkeyRecordError = nil
    setRecordingHotkey(nil)
    statusMessage = "\(action.title) shortcut set to \(combo.displayName)"
  }

  func setRecordingRephraseHotkey(_ recording: Bool) {
    setRecordingHotkey(recording ? .rephrase : nil)
  }

  /// Rephrase selected text in the focused app (ignores per-app "Do nothing").
  func rephraseFrontmostSelection() {
    guard isEngineEnabled else {
      statusMessage = "CasperFlow is disabled — enable it from the menu bar"
      return
    }
    guard !isHolding, !isRephrasingSelection, phase != .composing else { return }
    refreshFrontmostApp()

    let openAIKey = settings.openAIApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !openAIKey.isEmpty else {
      statusMessage = "Add an OpenAI key in API Keys to rephrase a selection"
      return
    }
    guard GlobalHoldHotKey.isProcessTrusted else {
      statusMessage = "Enable Casper.app in Accessibility to rephrase in other apps"
      return
    }

    isRephrasingSelection = true
    let requestedTone = activeTone.appliesRewrite ? activeTone : .general
    let appName = activeAppName
    phase = .composing
    statusMessage = "Rephrasing selection (\(requestedTone.displayName))…"
    pendingPartial = ""
    syncFloatingHUD()

    Task { @MainActor in
      defer { self.isRephrasingSelection = false }
      guard let selected = await FrontmostTextInserter.copySelection() else {
        self.phase = .idle
        self.statusMessage = "Select text in \(appName), then press \(self.settings.rephraseHotkey.displayName)"
        self.syncFloatingHUD()
        return
      }
      guard let rewritten = await OpenAIToneRephraser.rephrase(
        selected,
        tone: requestedTone,
        appName: appName,
        apiKey: openAIKey
      ) else {
        self.phase = .idle
        self.statusMessage = "OpenAI unavailable — selection left unchanged"
        self.syncFloatingHUD()
        return
      }
      let pasted = FrontmostTextInserter.paste(rewritten)
      if pasted {
        HistoryStore.shared.add(text: rewritten, kind: .rephrase, appName: appName)
        self.statusMessage = "Rephrased in \(appName)"
        self.phase = .idle
        FloatingHUDController.shared.flashPasted(into: appName)
      } else {
        self.phase = .idle
        self.statusMessage = "Rephrase ready — focus another app to paste"
        self.syncFloatingHUD()
      }
    }
  }

  private func syncFloatingHUD() {
    let toneLabel: String
    if captureKind == .ask {
      toneLabel = "Ask ChatGPT · \(activeAppName)"
    } else if captureKind == .notes {
      toneLabel = "Note taker · \(noteAudioSource.title)"
    } else {
      toneLabel = settings.tonePolishEnabled
        ? "\(activeProfileName) · \(activeTone.displayName)"
        : "\(activeProfileName) · tone off"
    }
    FloatingHUDController.shared.sync(
      phase: phase,
      activity: hudActivityTitle(),
      pending: hudSpeechText(),
      committed: phase == .error ? (lastError ?? statusMessage) : "",
      mode: toneLabel,
      level: level
    )
  }

  /// Short HUD title for the current job (not Connecting/Connected).
  private func hudActivityTitle() -> String {
    if phase == .error {
      return "Error"
    }
    switch phase {
    case .connecting:
      return "Starting"
    case .listening:
      if !hearSocketReady {
        return "Starting"
      }
      switch captureKind {
      case .ask: return "Ask ChatGPT"
      case .notes: return "Note taker"
      case .dictate: return "Listening"
      }
    case .finalizing:
      switch captureKind {
      case .ask: return "Finishing request"
      case .notes: return "Saving note"
      case .dictate: return "Committing"
      }
    case .composing:
      let text = statusMessage.lowercased()
      if text.contains("chatgpt") { return "ChatGPT writing" }
      if text.contains("rephras") { return "Rephrasing" }
      if text.contains("insert") { return "Inserting" }
      return "Working"
    case .idle, .error:
      return "Casper"
    }
  }

  private func hudSpeechText() -> String {
    if phase == .error || phase == .composing {
      return ""
    }
    return pendingPartial
  }

  private func finishDictateHold() {
    if inFlightPasteCount > 0 {
      phase = .composing
      if !statusMessage.lowercased().contains("rephras") {
        statusMessage = "Inserting text — please wait…"
      }
      syncFloatingHUD()
      return
    }
    phase = .idle
    if didPasteInThisHold {
      statusMessage = "Pasted into \(activeAppName). Hold again to continue."
      syncFloatingHUD()
      return
    }
    let spoken = fullTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    if spoken.isEmpty {
      statusMessage = "No speech captured — hold and speak, then release."
      FloatingHUDController.shared.flashNotice(
        title: "No speech captured",
        subtitle: "Hold the shortcut and speak, then release."
      )
    } else {
      statusMessage = "Done. Hold again to continue."
      syncFloatingHUD()
    }
  }

  private func completePasteJob() {
    inFlightPasteCount = max(0, inFlightPasteCount - 1)
    guard inFlightPasteCount == 0, !isHolding, captureKind == .dictate, phase != .error else {
      return
    }
    phase = .idle
    if !didPasteInThisHold {
      statusMessage = "Done. Hold again to continue."
      syncFloatingHUD()
    }
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
      toneEnabled: toneEnabled && captureKind == .dictate,
      userTerms: VocabularyStore.shared.terms,
      stripFillers: captureKind == .notes
    )
  }

  func updateApiKey(_ key: String) {
    apiKeyLock.lock()
    apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
    apiKeyLock.unlock()
    discardWarmHear()
    warmPreconnect()
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
    guard recordingAction == nil else { return }
    guard isEngineEnabled else {
      statusMessage = "CasperFlow is disabled — enable it from the menu bar"
      return
    }
    guard !isHolding, phase != .composing else { return }
    if kind != .notes, isNoteTaking { return }
    let key = currentApiKey
    guard !key.isEmpty else {
      AppLog.error("PYAI API key missing")
      phase = .error
      lastError = "PYAI_API_KEY is missing."
      statusMessage = lastError ?? ""
      syncFloatingHUD()
      return
    }
    if kind == .ask {
      let openAIKey = settings.openAIApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !openAIKey.isEmpty else {
        phase = .error
        lastError = "Add an OpenAI key in API Keys to ask ChatGPT."
        statusMessage = lastError ?? ""
        syncFloatingHUD()
        return
      }
    }

    captureKind = kind
    CommandOverlayController.shared.hide()
    HistoryOverlayController.shared.hide()
    isNoteTaking = kind == .notes
    if kind == .notes {
      NoteStore.shared.beginSession(source: noteAudioSource)
    }
    askPromptLines = []
    isHolding = true
    didFlushPreRoll = false
    didPasteInThisHold = false
    sentPCM = []
    pendingPartial = ""
    lastError = nil
    refreshFrontmostApp()
    hearSocketReady = false
    phase = .listening
    statusMessage = listeningStatus(for: kind)
    AppLog.info("beginHold kind=\(kind.rawValue) source=\(noteAudioSource.rawValue)")
    syncFloatingHUD()

    Task {
      if kind == .notes, noteAudioSource.usesSystemAudio, !noteAudioSource.usesMicrophone {
        // Screen Recording is requested when the system-audio stream starts.
      } else {
        let granted = await requestMicPermission()
        guard granted else {
          self.fail("Microphone permission denied.")
          return
        }
      }
      do {
        try await self.startPipeline(apiKey: key)
      } catch {
        self.fail(self.friendlyAudioError(error))
      }
    }
  }

  func toggleNoteTaking() {
    guard isEngineEnabled else {
      statusMessage = "CasperFlow is disabled — enable it from the menu bar"
      return
    }
    if isNoteTaking {
      stopNoteTaking()
    } else {
      startNoteTaking()
    }
  }

  func startNoteTaking() {
    guard !isNoteTaking else { return }
    beginHold(kind: .notes)
  }

  func stopNoteTaking() {
    guard isNoteTaking else { return }
    endHold()
  }

  func endHold() {
    guard isHolding else { return }
    isHolding = false
    overlayCaptureActive = false
    let kind = captureKind
    phase = .finalizing
    statusMessage = kind == .ask
      ? "Finishing your request…"
      : kind == .notes ? "Saving note…" : "Committing…"
    syncFloatingHUD()

    // Stop sending new audio; keep socket open briefly for speech_final.
    capture?.stop()
    capture = nil
    systemCapture?.stop()
    systemCapture = nil

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
      } else if kind == .notes {
        NoteStore.shared.endSession()
        self.isNoteTaking = false
        self.phase = .idle
        self.statusMessage = "Note saved. Start again to continue."
        self.syncFloatingHUD()
      } else {
        self.finishDictateHold()
      }
    }
  }

  private func listeningStatus(for kind: CaptureKind) -> String {
    switch kind {
    case .ask:
      return "Ask ChatGPT — speak your request, then release"
    case .notes:
      return "Note taker listening — \(noteAudioSource.title)"
    case .dictate:
      return "Listening · \(activeTone.displayName) — release to commit"
    }
  }

  private func friendlyAudioError(_ error: Error) -> String {
    AppLog.error("Note taker / audio start failed", error: error)
    if let captureError = error as? SystemAudioCaptureError {
      return captureError.localizedDescription
    }
    let ns = error as NSError
    if ns.domain.lowercased().contains("screencapture")
      || ns.localizedDescription.localizedCaseInsensitiveContains("screen")
      || !CGPreflightScreenCaptureAccess() {
      return "\(SystemAudioCaptureError.screenRecordingDenied.localizedDescription) (\(ns.domain) \(ns.code))"
    }
    return "Note taker failed: \(ns.localizedDescription) [\(ns.domain) \(ns.code)]"
  }

  private func startPipeline(apiKey: String) async throws {
    let client: HearClient
    if let warm = claimWarmHear() {
      client = warm
    } else {
      client = HearClient(
        apiKey: apiKey,
        config: captureKind == .notes ? .notes : HearConfig()
      )
      client.connect()
    }
    hear = client
    bindHearCallbacks(client)
    if client.isConnected {
      onHearConnected()
    }

    lastNoteMic = []
    lastNoteSys = []

    if captureKind == .notes, noteAudioSource.usesSystemAudio {
      let sys = SystemAudioCapture()
      systemCapture = sys
      sys.onPCM16 = { [weak self] samples in
        Task { @MainActor in
          self?.ingestNoteSystem(samples)
        }
      }
      sys.onMetrics = { [weak self] metrics in
        Task { @MainActor in
          self?.applyAudioMetrics(metrics)
        }
      }
      sys.onFatalError = { [weak self] error in
        Task { @MainActor in
          self?.fail(self?.friendlyAudioError(error) ?? error.localizedDescription)
        }
      }
      try await sys.start()
    }

    if captureKind != .notes || noteAudioSource.usesMicrophone {
      let useVoiceProcessing = captureKind == .notes
        ? noteAudioSource == .both
        : enableVoiceProcessing
      let engine = AudioCaptureEngine(enableVoiceProcessing: useVoiceProcessing)
      capture = engine
      engine.onPCM16 = { [weak self] samples in
        Task { @MainActor in
          guard let self else { return }
          if self.captureKind == .notes {
            self.ingestNoteMic(samples)
          } else {
            self.handlePCM(samples)
          }
        }
      }
      engine.onMetrics = { [weak self] metrics in
        Task { @MainActor in
          self?.applyAudioMetrics(metrics)
        }
      }
      try engine.start()
    }
  }

  private func bindHearCallbacks(_ client: HearClient) {
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
        guard let self else { return }
        guard self.isHolding, self.phase == .listening || self.phase == .connecting else { return }
        AppLog.error("Hear disconnected while holding")
        self.fail("Hear disconnected. Check your network and try again.")
      }
    }
  }

  /// Open a dictate/ask socket while idle so the next hold is already handshake-complete.
  private func warmPreconnect() {
    guard isEngineEnabled, hear == nil, warmHear == nil else { return }
    let key = currentApiKey
    guard !key.isEmpty else { return }
    let client = HearClient(apiKey: key, config: HearConfig())
    client.onDisconnected = { [weak self] in
      Task { @MainActor in
        guard let self, self.warmHear === client else { return }
        self.warmHear = nil
      }
    }
    warmHear = client
    client.connect()
  }

  private func claimWarmHear() -> HearClient? {
    guard captureKind != .notes else { return nil }
    guard let client = warmHear, client.isUsable else {
      discardWarmHear()
      return nil
    }
    warmHear = nil
    return client
  }

  private func discardWarmHear() {
    warmHear?.disconnect()
    warmHear = nil
  }

  private func ingestNoteMic(_ samples: [Int16]) {
    lastNoteMic = samples
    emitNotePCM()
  }

  private func ingestNoteSystem(_ samples: [Int16]) {
    lastNoteSys = samples
    emitNotePCM()
  }

  private func emitNotePCM() {
    switch noteAudioSource {
    case .microphone:
      handlePCM(lastNoteMic)
    case .system:
      handlePCM(lastNoteSys)
    case .both:
      handlePCM(PCMNormalizer.mix(lastNoteMic, lastNoteSys))
    }
  }

  private func applyAudioMetrics(_ metrics: AudioCaptureEngine.Metrics) {
    level = metrics.rmsLevel
    if phase == .listening || phase == .connecting {
      let now = Date()
      if now.timeIntervalSince(lastHudLevelSync) > 0.08 {
        lastHudLevelSync = now
        syncFloatingHUD()
      }
    }
    if metrics.didClip {
      didClipRecently = true
      Task {
        try? await Task.sleep(nanoseconds: 400_000_000)
        await MainActor.run { self.didClipRecently = false }
      }
    }
  }

  private func onHearConnected() {
    guard isHolding else { return }
    guard !hearSocketReady else { return }
    hearSocketReady = true
    phase = .listening
    statusMessage = listeningStatus(for: captureKind)
    syncFloatingHUD()

    let primed = preRoll.flush()
    if !primed.isEmpty {
      didFlushPreRoll = true
      sendPCM(primed)
    }
  }

  private func handlePCM(_ samples: [Int16]) {
    guard isHolding else { return }
    let prepared = PCMNormalizer.boost(samples)

    if !hearSocketReady || hear == nil {
      preRoll.append(prepared)
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
      sendPCM(prepared)
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
      if Self.isBenignSocketError(message) {
        AppLog.info("Ignored Hear socket error: \(message)")
        if phase == .listening || phase == .connecting {
          fail("Hear connection dropped. Tap Restart — you do not need to quit the app.")
        }
        return
      }
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
    if captureKind == .notes {
      NoteStore.shared.append(trimmed)
      statusMessage = "Note taker listening — \(noteAudioSource.title)"
      return
    }

    let tone = activeTone
    let appName = activeAppName
    let openAIKey = settings.openAIApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let useOpenAI =
      settings.tonePolishEnabled
      && tone.appliesRewrite
      && !openAIKey.isEmpty

    inFlightPasteCount += 1
    if useOpenAI, !isHolding {
      phase = .composing
      statusMessage = "Rephrasing (\(tone.displayName)) — please wait…"
      syncFloatingHUD()
    }

    Task { @MainActor in
      defer { self.completePasteJob() }
      var output = trimmed
      if useOpenAI {
        self.statusMessage = "Rephrasing (\(tone.displayName)) — please wait…"
        if !self.isHolding {
          self.phase = .composing
          self.syncFloatingHUD()
        }
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
      self.pasteIntoFocusedApp(output, kind: .dictate)
    }
  }

  /// Send this hold’s spoken request to ChatGPT and paste the formatted reply.
  private func composeAskAndPaste() async {
    let prompt = askPromptLines.joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prompt.isEmpty else {
      phase = .idle
      statusMessage = "No speech captured — hold Option+Command and speak a request"
      FloatingHUDController.shared.flashNotice(
        title: "No speech captured",
        subtitle: "Hold the Ask shortcut and speak a request."
      )
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
    pasteIntoFocusedApp(answer, kind: .ask)
    phase = .idle
    if didPasteInThisHold {
      statusMessage = "Pasted ChatGPT reply into \(appName)"
    }
  }

  /// Paste into the app that currently has the text caret (not CasperFlow).
  private func pasteIntoFocusedApp(_ text: String, kind: HistoryTaskKind) {
    refreshFrontmostApp()
    var chunk = text
    if didPasteInThisHold {
      chunk = " " + text
    }
    let pasted = FrontmostTextInserter.paste(chunk)
    if pasted {
      didPasteInThisHold = true
      statusMessage = "Pasted into \(activeAppName)"
      FloatingHUDController.shared.flashPasted(into: activeAppName)
      HistoryStore.shared.add(text: text, kind: kind, appName: activeAppName)
    } else {
      let message: String
      if !GlobalHoldHotKey.isProcessTrusted {
        message = "Paste failed — enable ~/Applications/Casper.app in Accessibility"
      } else {
        message = "Paste failed — click the other app’s text field, then dictate again"
      }
      statusMessage = message
      lastError = message
      FloatingHUDController.shared.flashNotice(
        title: message,
        subtitle: activeAppName,
        isError: true
      )
    }
  }

  private static func isBenignSocketError(_ message: String) -> Bool {
    let lower = message.lowercased()
    return lower.contains("socket is not connected")
      || lower.contains("socketnotconnected")
      || lower.contains("not connected")
      || lower.contains("enotconn")
      || (lower.contains("socket") && lower.contains("connect"))
  }

  private func fail(_ message: String) {
    AppLog.error(message)
    lastError = message
    statusMessage = message
    phase = .error
    lastFailedKind = captureKind
    isHolding = false
    inFlightPasteCount = 0
    overlayCaptureActive = false
    if captureKind == .notes {
      NoteStore.shared.cancelIfEmpty()
      isNoteTaking = false
    }
    capture?.stop()
    capture = nil
    systemCapture?.stop()
    systemCapture = nil
    tearDownHear()
    level = 0
    syncFloatingHUD()
  }

  private func tearDownHear() {
    hear?.disconnect()
    hear = nil
    hearSocketReady = false
    preRoll.reset()
    warmPreconnect()
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
