import Foundation

/// Raises quiet PCM so Hear gets a healthier signal without wrapping into distortion.
enum PCMNormalizer {
  private static let quietPeak: Float = 0.08
  private static let targetPeak: Float = 0.42
  private static let loudPeak: Float = 0.97

  static func boost(_ samples: [Int16]) -> [Int16] {
    guard !samples.isEmpty else { return samples }
    var peak: Int16 = 1
    for sample in samples {
      let magnitude = sample == Int16.min ? Int16.max : abs(sample)
      if magnitude > peak { peak = magnitude }
    }
    let peakFloat = Float(peak) / Float(Int16.max)
    let gain: Float
    if peakFloat < quietPeak {
      gain = min(targetPeak / max(peakFloat, 0.001), 8)
    } else if peakFloat > loudPeak {
      gain = loudPeak / peakFloat
    } else {
      return samples
    }
    return samples.map { sample in
      let scaled = Float(sample) * gain
      let clamped = max(Float(Int16.min), min(Float(Int16.max), scaled))
      return Int16(clamped)
    }
  }

  static func mix(_ mic: [Int16], _ system: [Int16]) -> [Int16] {
    let count = max(mic.count, system.count)
    guard count > 0 else { return [] }
    var mixed = [Int16](repeating: 0, count: count)
    for index in 0..<count {
      let a = index < mic.count ? Int32(mic[index]) : 0
      let b = index < system.count ? Int32(system[index]) : 0
      let sum = a + b
      mixed[index] = Int16(clamping: sum)
    }
    return mixed
  }
}
