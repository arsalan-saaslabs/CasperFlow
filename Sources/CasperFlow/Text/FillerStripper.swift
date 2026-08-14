import Foundation

/// Drops common speech fillers after STT. Conservative so real words stay.
enum FillerStripper {
  static func strip(_ text: String) -> String {
    guard !text.isEmpty else { return text }
    var output = text
    let patterns = [
      #"(?i)\buh+\b"#,
      #"(?i)\bum+\b"#,
      #"(?i)\ber+\b"#,
      #"(?i)\bah+\b"#,
      #"(?i)\bmm+\b"#,
      #"(?i)\byou know\b"#,
      #"(?i)\bi mean\b"#,
    ]
    for pattern in patterns {
      output = output.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
    }
    return output
      .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
