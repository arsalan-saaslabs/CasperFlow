import AVFoundation
import Foundation

/// Shared audio / session constants for the Hear PTT pipeline.
enum AudioConstants {
  static let targetSampleRate: Double = 16_000
  static let channelCount: AVAudioChannelCount = 1
  static let bytesPerSample = 2 // PCM16
  /// ~250 ms of 16 kHz mono — flushed on PTT so the first word is not clipped.
  static let preRollDurationSeconds: Double = 0.25
  static var preRollSampleCount: Int {
    Int(targetSampleRate * preRollDurationSeconds)
  }
  /// Soft clip threshold in linear amplitude.
  static let clipAmplitudeThreshold: Float = 0.98
}
