import Foundation

/// Instant, offline tone rewrite (visible difference without OpenAI).
enum LocalToneRewriter {
  static func apply(_ text: String, tone: WritingTone) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }

    switch tone {
    case .casual:
      return applyCasual(trimmed)
    case .professional:
      return applyProfessional(trimmed)
    case .developer:
      return applyDeveloper(trimmed)
    case .general:
      return applyGeneral(trimmed)
    }
  }

  private static func applyCasual(_ text: String) -> String {
    var output = replace(text, map: [
      (#"(?i)\bI am\b"#, "I'm"),
      (#"(?i)\bdo not\b"#, "don't"),
      (#"(?i)\bcannot\b"#, "can't"),
      (#"(?i)\bwould like to\b"#, "want to"),
      (#"(?i)\bplease be advised that\b"#, ""),
      (#"(?i)\bkindly\b"#, ""),
    ])
    output = collapseSpaces(output)
    if output.count < 80, output.hasSuffix(".") {
      output = String(output.dropLast())
    }
    return output
  }

  private static func applyProfessional(_ text: String) -> String {
    var output = replace(text, map: [
      (#"(?i)\bhey\b"#, "Hello"),
      (#"(?i)\bhi there\b"#, "Hello"),
      (#"(?i)\byeah\b"#, "yes"),
      (#"(?i)\byep\b"#, "yes"),
      (#"(?i)\bnope\b"#, "no"),
      (#"(?i)\bgonna\b"#, "going to"),
      (#"(?i)\bwanna\b"#, "want to"),
      (#"(?i)\bgotta\b"#, "need to"),
      (#"(?i)\bkinda\b"#, "somewhat"),
      (#"(?i)\bthx\b"#, "thank you"),
      (#"(?i)\bthanks\b"#, "thank you"),
      (#"(?i)\basap\b"#, "as soon as possible"),
      (#"(?i)\bidk\b"#, "I do not know"),
      (#"(?i)\bdon't\b"#, "do not"),
      (#"(?i)\bcan't\b"#, "cannot"),
      (#"(?i)\bwon't\b"#, "will not"),
    ])
    output = collapseSpaces(output)
    if let first = output.first {
      output = String(first).uppercased() + output.dropFirst()
    }
    if let last = output.last, !".!?".contains(last) {
      output += "."
    }
    return output
  }

  private static func applyDeveloper(_ text: String) -> String {
    collapseSpaces(
      replace(text, map: [
        (#"(?i)\bplease\b"#, ""),
        (#"(?i)\bkindly\b"#, ""),
      ])
    )
  }

  private static func applyGeneral(_ text: String) -> String {
    var output = collapseSpaces(text)
    if let first = output.first {
      output = String(first).uppercased() + output.dropFirst()
    }
    return output
  }

  private static func replace(_ text: String, map: [(String, String)]) -> String {
    var output = text
    for (pattern, replacement) in map {
      output = output.replacingOccurrences(
        of: pattern,
        with: replacement,
        options: .regularExpression
      )
    }
    return output
  }

  private static func collapseSpaces(_ text: String) -> String {
    text
      .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
