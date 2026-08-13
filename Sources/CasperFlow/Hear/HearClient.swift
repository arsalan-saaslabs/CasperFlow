import Foundation

/// Wire frames from PyAI Hear (`protocol=pyai-hear-v1`).
enum HearEvent: Sendable {
  case partial(text: String)
  case partialStable(text: String)
  case speechFinal(text: String, utteranceId: String?)
  case final(text: String, utteranceId: String?)
  case error(message: String)
  case other(type: String)
}

struct HearConfig: Sendable {
  var sampleRate: Int = Int(AudioConstants.targetSampleRate)
  var language: String = "en"
  var endpointingMs: Int = 800
  var numerals: Bool = true

  func streamURL() -> URL {
    var components = URLComponents(string: "wss://api.pyai.com/v1/audio/transcriptions/stream")!
    components.queryItems = [
      URLQueryItem(name: "protocol", value: "pyai-hear-v1"),
      URLQueryItem(name: "model", value: "pyai-hear"),
      URLQueryItem(name: "sample_rate", value: String(sampleRate)),
      URLQueryItem(name: "encoding", value: "pcm16"),
      URLQueryItem(name: "language", value: language),
      URLQueryItem(name: "numerals", value: numerals ? "true" : "false"),
      URLQueryItem(name: "interim_results", value: "true"),
      URLQueryItem(name: "endpointing_ms", value: String(endpointingMs)),
    ]
    return components.url!
  }
}

/// Low-latency Hear WebSocket client (PCM16 in, JSON events out).
final class HearClient: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
  var onEvent: ((HearEvent) -> Void)?
  var onConnected: (() -> Void)?
  var onDisconnected: (() -> Void)?

  private var session: URLSession!
  private var task: URLSessionWebSocketTask?
  private let apiKey: String
  private let config: HearConfig
  private let stateLock = NSLock()
  private var isOpen = false

  init(apiKey: String, config: HearConfig = HearConfig()) {
    self.apiKey = apiKey
    self.config = config
    super.init()
    let conf = URLSessionConfiguration.default
    conf.waitsForConnectivity = false
    self.session = URLSession(configuration: conf, delegate: self, delegateQueue: nil)
  }

  func connect() {
    var request = URLRequest(url: config.streamURL())
    request.timeoutInterval = 30
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    let socket = session.webSocketTask(with: request)
    task = socket
    socket.resume()
    receiveLoop()
  }

  func disconnect() {
    stateLock.lock()
    isOpen = false
    stateLock.unlock()
    task?.cancel(with: .goingAway, reason: nil)
    task = nil
    DispatchQueue.main.async { self.onDisconnected?() }
  }

  func sendPCM16(_ samples: [Int16]) {
    stateLock.lock()
    let open = isOpen
    let socket = task
    stateLock.unlock()

    guard open, let socket, !samples.isEmpty else { return }

    let byteCount = samples.count * MemoryLayout<Int16>.stride
    let pcmData = samples.withUnsafeBufferPointer { ptr in
      Data(bytes: ptr.baseAddress!, count: byteCount)
    }
    socket.send(.data(pcmData)) { [weak self] error in
      if let error {
        DispatchQueue.main.async {
          self?.onEvent?(.error(message: error.localizedDescription))
        }
      }
    }
  }

  func commit() {
    stateLock.lock()
    let open = isOpen
    let socket = task
    stateLock.unlock()
    guard open, let socket else { return }
    socket.send(.string(#"{"type":"commit"}"#)) { _ in }
  }

  private func receiveLoop() {
    task?.receive { [weak self] result in
      guard let self else { return }
      switch result {
      case .failure(let error):
        DispatchQueue.main.async {
          self.onEvent?(.error(message: error.localizedDescription))
          self.onDisconnected?()
        }
        self.stateLock.lock()
        self.isOpen = false
        self.stateLock.unlock()
      case .success(let message):
        self.handle(message)
        if self.task != nil {
          self.receiveLoop()
        }
      }
    }
  }

  private func handle(_ message: URLSessionWebSocketTask.Message) {
    let text: String
    switch message {
    case .string(let s):
      text = s
    case .data(let d):
      text = String(data: d, encoding: .utf8) ?? ""
    @unknown default:
      return
    }

    guard
      let data = text.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let type = json["type"] as? String
    else { return }

    let body = (json["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let utteranceId = json["utterance_id"].map { "\($0)" }

    let event: HearEvent
    switch type {
    case "partial":
      event = .partial(text: body)
    case "partial_stable":
      event = .partialStable(text: body)
    case "speech_final":
      event = .speechFinal(text: body, utteranceId: utteranceId)
    case "final":
      event = .final(text: body, utteranceId: utteranceId)
    case "error":
      let msg = (json["message"] as? String) ?? (json["code"] as? String) ?? "Hear error"
      event = .error(message: msg)
    default:
      event = .other(type: type)
    }

    DispatchQueue.main.async { self.onEvent?(event) }
  }

  func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didOpenWithProtocol protocol: String?
  ) {
    stateLock.lock()
    isOpen = true
    stateLock.unlock()
    DispatchQueue.main.async { self.onConnected?() }
  }

  func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
    reason: Data?
  ) {
    stateLock.lock()
    isOpen = false
    stateLock.unlock()
    DispatchQueue.main.async { self.onDisconnected?() }
  }
}
