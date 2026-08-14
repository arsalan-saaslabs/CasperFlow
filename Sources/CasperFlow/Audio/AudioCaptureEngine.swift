import AVFoundation
import Foundation

/// Mic → mono → 16 kHz PCM16 with optional Apple voice processing (default off).
final class AudioCaptureEngine: NSObject {
  struct Metrics: Sendable {
    var rmsLevel: Float = 0
    var didClip: Bool = false
  }

  var onPCM16: (([Int16]) -> Void)?
  var onMetrics: ((Metrics) -> Void)?

  private let engine = AVAudioEngine()
  private var converter: AVAudioConverter?
  private var isRunning = false
  private let enableVoiceProcessing: Bool

  init(enableVoiceProcessing: Bool = false) {
    self.enableVoiceProcessing = enableVoiceProcessing
    super.init()
  }

  func start() throws {
    guard !isRunning else { return }

    let input = engine.inputNode
    let inputFormat = input.outputFormat(forBus: 0)

    if enableVoiceProcessing {
      do {
        try input.setVoiceProcessingEnabled(true)
      } catch {
        // Continue without VP — dictation accuracy often better without it.
        print("[audio] voice processing unavailable: \(error.localizedDescription)")
      }
    } else if input.isVoiceProcessingEnabled {
      try? input.setVoiceProcessingEnabled(false)
    }

    guard
      let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: AudioConstants.targetSampleRate,
        channels: AudioConstants.channelCount,
        interleaved: true
      )
    else {
      throw AudioCaptureError.invalidTargetFormat
    }

    converter = AVAudioConverter(from: inputFormat, to: targetFormat)
    converter?.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Mastering
    guard converter != nil else {
      throw AudioCaptureError.converterFailed
    }

    let bufferSize: AVAudioFrameCount = 1024
    input.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
      self?.handleInputBuffer(buffer, targetFormat: targetFormat)
    }

    engine.prepare()
    try engine.start()
    isRunning = true
  }

  func stop() {
    guard isRunning else { return }
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    converter = nil
    isRunning = false
  }

  private func handleInputBuffer(_ buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) {
    guard let converter else { return }

    let ratio = targetFormat.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
    guard
      let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity)
    else { return }

    var error: NSError?
    let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
      outStatus.pointee = .haveData
      return buffer
    }

    let status = converter.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)
    if status == .error {
      return
    }

    guard outBuffer.frameLength > 0,
          let channels = outBuffer.int16ChannelData
    else { return }

    let frameCount = Int(outBuffer.frameLength)
    let ptr = channels[0]
    var samples = [Int16](repeating: 0, count: frameCount)
    var sumSquares: Float = 0
    var clipped = false

    for i in 0..<frameCount {
      var sample = ptr[i]
      let amplitude = abs(Float(sample) / Float(Int16.max))
      if amplitude >= AudioConstants.clipAmplitudeThreshold {
        clipped = true
        // Soft limit — avoid hard wrap distortion into Hear.
        let sign: Int16 = sample >= 0 ? 1 : -1
        sample = sign * Int16(Float(Int16.max) * 0.97)
      }
      samples[i] = sample
      let f = Float(sample) / Float(Int16.max)
      sumSquares += f * f
    }

    let rms = sqrt(sumSquares / Float(max(frameCount, 1)))
    onMetrics?(Metrics(rmsLevel: min(1, rms * 3), didClip: clipped))
    onPCM16?(samples)
  }
}

enum AudioCaptureError: LocalizedError {
  case invalidTargetFormat
  case converterFailed

  var errorDescription: String? {
    switch self {
    case .invalidTargetFormat: return "Could not create 16 kHz PCM16 format."
    case .converterFailed: return "Could not create audio converter."
    }
  }
}
