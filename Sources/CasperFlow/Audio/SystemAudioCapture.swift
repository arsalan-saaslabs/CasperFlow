import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

/// Captures macOS system audio (videos, calls, other apps) as 16 kHz mono PCM16.
/// Requires Screen Recording. Video frames are discarded and never written to disk.
final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
  var onPCM16: (([Int16]) -> Void)?
  var onMetrics: ((AudioCaptureEngine.Metrics) -> Void)?
  var onFatalError: ((Error) -> Void)?

  private var stream: SCStream?
  private var converter: AVAudioConverter?
  private var converterFrom: AVAudioFormat?
  private let queue = DispatchQueue(label: "com.casperflow.system-audio")
  private var isRunning = false

  func start() async throws {
    guard !isRunning else { return }

    if !CGPreflightScreenCaptureAccess() {
      let granted = CGRequestScreenCaptureAccess()
      AppLog.info("Screen Recording preflight granted=\(granted)")
      if !granted {
        throw SystemAudioCaptureError.screenRecordingDenied
      }
    }

    let content: SCShareableContent
    do {
      content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    } catch {
      AppLog.error("SCShareableContent failed", error: error)
      throw error
    }

    guard let display = content.displays.first else {
      throw SystemAudioCaptureError.noDisplay
    }

    let filter = SCContentFilter(display: display, excludingWindows: [])
    let config = SCStreamConfiguration()
    config.capturesAudio = true
    config.excludesCurrentProcessAudio = true
    config.width = max(display.width, 64)
    config.height = max(display.height, 64)
    config.showsCursor = false
    config.queueDepth = 5
    config.minimumFrameInterval = CMTime(value: 1, timescale: 15)
    config.sampleRate = 48_000
    config.channelCount = 2

    let stream = SCStream(filter: filter, configuration: config, delegate: self)
    try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
    try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
    try await stream.startCapture()
    self.stream = stream
    isRunning = true
    AppLog.info("System audio capture started display=\(display.displayID) \(display.width)x\(display.height)")
  }

  func stop() {
    guard isRunning || stream != nil else { return }
    isRunning = false
    converter = nil
    converterFrom = nil
    let current = stream
    stream = nil
    if let current {
      try? current.removeStreamOutput(self, type: .audio)
      try? current.removeStreamOutput(self, type: .screen)
      Task {
        try? await current.stopCapture()
      }
    }
  }

  func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
    guard isRunning else { return }
    if type == .screen { return }
    guard type == .audio else { return }
    guard let pcm = Self.pcmBuffer(from: sampleBuffer) else { return }
    convertAndEmit(pcm)
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    isRunning = false
    AppLog.error("SCStream stopped", error: error)
    onFatalError?(error)
  }

  private func convertAndEmit(_ buffer: AVAudioPCMBuffer) {
    guard
      let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: AudioConstants.targetSampleRate,
        channels: AudioConstants.channelCount,
        interleaved: true
      )
    else { return }

    if converter == nil || converterFrom != buffer.format {
      converter = AVAudioConverter(from: buffer.format, to: targetFormat)
      converter?.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Mastering
      converterFrom = buffer.format
    }
    guard let converter else { return }

    let ratio = targetFormat.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
    guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

    var consumed = false
    var error: NSError?
    let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
      if consumed {
        outStatus.pointee = .noDataNow
        return nil
      }
      consumed = true
      outStatus.pointee = .haveData
      return buffer
    }
    let status = converter.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)
    if status == .error {
      if let error {
        AppLog.error("system audio convert failed", error: error)
      }
      return
    }
    guard outBuffer.frameLength > 0, let channels = outBuffer.int16ChannelData else { return }

    let frameCount = Int(outBuffer.frameLength)
    let ptr = channels[0]
    var samples = [Int16](repeating: 0, count: frameCount)
    var sumSquares: Float = 0
    for i in 0..<frameCount {
      let sample = ptr[i]
      samples[i] = sample
      let f = Float(sample) / Float(Int16.max)
      sumSquares += f * f
    }
    let rms = sqrt(sumSquares / Float(max(frameCount, 1)))
    onMetrics?(AudioCaptureEngine.Metrics(rmsLevel: min(1, rms * 3), didClip: false))
    onPCM16?(samples)
  }

  private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
    guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
    guard var asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee else {
      return nil
    }
    guard let format = AVAudioFormat(streamDescription: &asbd) else { return nil }
    let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
    guard frames > 0, let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
    pcm.frameLength = frames

    let channelCount = max(Int(format.channelCount), 1)
    let listSize = AudioBufferList.sizeInBytes(maximumBuffers: channelCount)
    let allocated = AudioBufferList.allocate(maximumBuffers: channelCount)
    defer { allocated.unsafeMutablePointer.deallocate() }

    var blockBuffer: CMBlockBuffer?
    let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sampleBuffer,
      bufferListSizeNeededOut: nil,
      bufferListOut: allocated.unsafeMutablePointer,
      bufferListSize: listSize,
      blockBufferAllocator: nil,
      blockBufferMemoryAllocator: nil,
      flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
      blockBufferOut: &blockBuffer
    )
    guard status == noErr else { return nil }

    let source = UnsafeMutableAudioBufferListPointer(allocated.unsafeMutablePointer)
    let destination = UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList)
    for (src, dst) in zip(source, destination) {
      guard let srcData = src.mData, let dstData = dst.mData else { continue }
      memcpy(dstData, srcData, Int(min(src.mDataByteSize, dst.mDataByteSize)))
    }
    return pcm
  }
}

enum SystemAudioCaptureError: LocalizedError {
  case noDisplay
  case screenRecordingDenied

  var errorDescription: String? {
    switch self {
    case .noDisplay:
      return "No display available for system audio capture."
    case .screenRecordingDenied:
      return "Screen Recording is off. Enable CasperFlow in System Settings → Privacy & Security → Screen Recording, then start Note taker again."
    }
  }
}
