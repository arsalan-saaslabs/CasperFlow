import Foundation

/// Instant text polish for Hear output (lexicon + spell + tone punctuation).
/// All local — no network / LLM, so no paste latency.
struct TextPolish: Sendable {
  enum Stage: Sendable {
    case live
    case committed
  }

  private let lexicon: LexiconCorrector

  static let `default` = TextPolish(lexicon: .default)

  init(lexicon: LexiconCorrector = .default) {
    self.lexicon = lexicon
  }

  func apply(
    _ text: String,
    stage: Stage,
    tone: WritingTone = .general,
    toneEnabled: Bool = true,
    userTerms: [VocabularyTerm] = [],
    stripFillers: Bool = false
  ) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }

    let activeLexicon = lexicon.applyingUserTerms(userTerms)
    var output: String
    let rewrite = toneEnabled && tone.appliesRewrite
    switch stage {
    case .live:
      output = activeLexicon.correctStreaming(trimmed)
      if stripFillers {
        output = FillerStripper.strip(output)
      }
      if rewrite {
        output = Punctuator.format(output, stage: .live, tone: tone)
        output = LocalToneRewriter.apply(output, tone: tone)
      }
    case .committed:
      output = activeLexicon.correct(trimmed)
      if stripFillers {
        output = FillerStripper.strip(output)
      }
      if rewrite || stripFillers {
        if tone != .developer {
          output = LocalSpellCorrector.correct(output)
          output = activeLexicon.correct(output)
        }
        output = Punctuator.format(output, stage: .committed, tone: stripFillers ? .general : tone)
        if rewrite {
          output = LocalToneRewriter.apply(output, tone: tone)
        }
      }
    }
    return output
  }
}

enum Punctuator {
  static func format(
    _ text: String,
    stage: TextPolish.Stage,
    tone: WritingTone
  ) -> String {
    var output = collapseSpaces(text)
    guard !output.isEmpty else { return output }

    output = insertClauseCommas(output)

    switch stage {
    case .live:
      return capitalizeFirst(output)
    case .committed:
      output = capitalizeSentences(output)
      switch tone {
      case .doNothing, .casual:
        return output
      case .professional, .general:
        return ensureTerminalPunctuation(output)
      case .developer:
        if output.split(separator: " ").count >= 8 {
          return ensureTerminalPunctuation(output)
        }
        return output
      }
    }
  }

  private static func insertClauseCommas(_ text: String) -> String {
    var output = text
    let patterns: [(String, String)] = [
      (#"(?i)(?<![,\s])\s+which is why\b"#, ", which is why"),
      (#"(?i)(?<![,\s])\s+even though\b"#, ", even though"),
      (#"(?i)(?<![,\s])\s+so that\b"#, ", so that"),
    ]
    for (pattern, replacement) in patterns {
      output = output.replacingOccurrences(
        of: pattern,
        with: replacement,
        options: .regularExpression
      )
    }
    return output
  }

  private static func capitalizeFirst(_ text: String) -> String {
    guard let first = text.first else { return text }
    return String(first).uppercased() + text.dropFirst()
  }

  private static func capitalizeSentences(_ text: String) -> String {
    var chars = Array(text)
    var capitalizeNext = true
    for i in chars.indices {
      let ch = chars[i]
      if capitalizeNext, ch.isLetter {
        chars[i] = Character(String(ch).uppercased())
        capitalizeNext = false
      }
      if ch == "." || ch == "!" || ch == "?" {
        capitalizeNext = true
      }
    }
    return String(chars)
  }

  private static func ensureTerminalPunctuation(_ text: String) -> String {
    guard let last = text.last else { return text }
    if last == "." || last == "!" || last == "?" || last == "," {
      return text
    }
    return text + "."
  }

  private static func collapseSpaces(_ text: String) -> String {
    text
      .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
