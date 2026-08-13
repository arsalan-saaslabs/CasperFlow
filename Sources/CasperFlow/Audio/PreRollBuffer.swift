import Foundation

/// Fixed-capacity ring buffer of Int16 PCM samples (pre-roll).
final class PreRollBuffer: @unchecked Sendable {
  private let capacity: Int
  private var storage: [Int16]
  private var writeIndex = 0
  private var count = 0
  private let lock = NSLock()

  init(capacitySamples: Int) {
    self.capacity = max(capacitySamples, 1)
    self.storage = Array(repeating: 0, count: self.capacity)
  }

  /// Appends PCM16 samples, overwriting oldest data when full.
  func append(_ samples: [Int16]) {
    guard !samples.isEmpty else { return }
    lock.lock()
    defer { lock.unlock() }

    for sample in samples {
      storage[writeIndex] = sample
      writeIndex = (writeIndex + 1) % capacity
      if count < capacity {
        count += 1
      }
    }
  }

  /// Returns chronologically ordered samples and clears the buffer.
  func flush() -> [Int16] {
    lock.lock()
    defer { lock.unlock() }

    guard count > 0 else { return [] }

    var result = [Int16](repeating: 0, count: count)
    let start = (writeIndex - count + capacity) % capacity
    for i in 0..<count {
      result[i] = storage[(start + i) % capacity]
    }
    writeIndex = 0
    count = 0
    return result
  }

  func reset() {
    lock.lock()
    defer { lock.unlock() }
    writeIndex = 0
    count = 0
  }
}
