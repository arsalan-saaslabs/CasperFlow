import Foundation

/// Instant, offline jargon fixes applied on Hear output.
/// Runs in-process (microseconds) — no network, no LLM, no added paste latency.
struct LexiconCorrector: Sendable {
  struct Rule: Sendable {
    let pattern: NSRegularExpression
    let replacement: String
  }

  private let rules: [Rule]

  /// Default CRM / engineering vocabulary seen in CasperFlow tests.
  static let `default` = LexiconCorrector(rules: Self.defaultRules)

  init(rules: [Rule]) {
    self.rules = rules
  }

  /// User terms win over built-in rules. Heard phrases are matched as literals, not regex.
  func applyingUserTerms(_ terms: [VocabularyTerm]) -> LexiconCorrector {
    guard !terms.isEmpty else { return self }
    return LexiconCorrector(rules: Self.rules(fromUserTerms: terms) + rules)
  }

  static func rules(fromUserTerms terms: [VocabularyTerm]) -> [Rule] {
    terms.compactMap { term in
      let escaped = NSRegularExpression.escapedPattern(for: term.heard)
      let pattern = "(?i)\\b\(escaped)\\b"
      guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
      return Rule(pattern: regex, replacement: NSRegularExpression.escapedTemplate(for: term.replacement))
    }
  }

  func correct(_ text: String) -> String {
    guard !text.isEmpty else { return text }

    var output = text
    let options: NSRegularExpression.MatchingOptions = []
    for rule in rules {
      let range = NSRange(output.startIndex..<output.endIndex, in: output)
      output = rule.pattern.stringByReplacingMatches(
        in: output,
        options: options,
        range: range,
        withTemplate: rule.replacement
      )
    }
    return collapseSpaces(output)
  }

  /// Streaming-friendly: correct completed tokens immediately; try last-token aliases early.
  func correctStreaming(_ text: String) -> String {
    let whole = correct(text)
    // If full-string rules already fired, prefer that.
    if whole != text { return whole }

    let parts = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
    guard !parts.isEmpty else { return text }

    var rebuilt: [String] = []
    rebuilt.reserveCapacity(parts.count)

    for (index, part) in parts.enumerated() {
      let isLast = index == parts.count - 1
      if part.isEmpty {
        rebuilt.append(part)
        continue
      }

      let correctedToken = correct(part)
      if correctedToken != part {
        rebuilt.append(correctedToken)
        continue
      }

      if isLast, let early = earlyAlias(for: part) {
        rebuilt.append(early)
      } else {
        rebuilt.append(part)
      }
    }

    return collapseSpaces(rebuilt.joined(separator: " "))
  }

  /// Map partial last-word prefixes of known mishears → final jargon (live HUD only).
  private func earlyAlias(for token: String) -> String? {
    let lower = token.lowercased()
    // Avoid tiny prefixes that collide with normal words.
    guard lower.count >= 5 else { return nil }

    let aliases: [(prefix: String, replacement: String)] = [
      ("cardin", "DNM"),   // cardinal…
      ("deniu", "DNM"),    // denium…
      ("denim", "DNM"),
    ]
    for alias in aliases where lower.hasPrefix(alias.prefix) {
      return alias.replacement
    }
    return nil
  }

  // MARK: - Rules

  private static var defaultRules: [Rule] {
    // Order matters: more specific phrases first.
    let specs: [(String, String)] = [
      // DNM (Do Not Message) — common Hear mishears
      (#"(?i)\bdenium\b"#, "DNM"),
      (#"(?i)\bdenim\b"#, "DNM"),
      (#"(?i)\bdnm\b"#, "DNM"),
      (#"(?i)\bdee[\s-]?n[\s-]?m\b"#, "DNM"),
      (#"(?i)\bd[\s.-]?n[\s.-]?m\b"#, "DNM"),
      (#"(?i)\bcardinal status\b"#, "DNM status"),
      (#"(?i)\bcardinal tag\b"#, "DNM tag"),
      (#"(?i)\bcardinal\b"#, "DNM"),
      (#"(?i)\bdo not message\b"#, "DNM"),
      (#"(?i)\bdo not mail\b"#, "DNM"),

      // CRM / contact jargon
      (#"(?i)\bsee are em\b"#, "CRM"),
      (#"(?i)\bsee our em\b"#, "CRM"),
      (#"(?i)\bcrm\b"#, "CRM"),
      (#"(?i)\bsales force\b"#, "Salesforce"),
      (#"(?i)\bhub spot\b"#, "HubSpot"),

      // Sync / send confusions in this domain
      (#"(?i)\bnot sent correctly\b"#, "not synced correctly"),
      (#"(?i)\bwasn't sent correctly\b"#, "wasn't synced correctly"),
      (#"(?i)\bwas not sent correctly\b"#, "was not synced correctly"),
      (#"(?i)\bnot sink correctly\b"#, "not synced correctly"),
      (#"(?i)\bnot synced correctly\b"#, "not synced correctly"),

      // API / env (from earlier live tests)
      (#"(?i)\bpay[\s-]?case\b"#, "API key"),
      (#"(?i)\ba\.?\s*p\.?\s*i\.?\s*key\b"#, "API key"),
      (#"(?i)\bin be file\b"#, ".env file"),
      (#"(?i)\benv file\b"#, ".env file"),
      (#"(?i)\bdot env\b"#, ".env"),

      // STT product jargon
      (#"(?i)\bpartial update\b"#, "partials update"),
      (#"(?i)\bfinal logs in\b"#, "finals lock in"),
      (#"(?i)\blot of proxy\b"#, "local proxy"),
      (#"(?i)\bwhisper flow\b"#, "CasperFlow"),
      (#"(?i)\bpy[\s-]?a\.?i\.?\b"#, "PyAI"),
      (#"(?i)\bpai hear\b"#, "PyAI Hear"),
      (#"(?i)\bpie ai\b"#, "PyAI"),
    ]

    return specs.compactMap { pattern, replacement in
      guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
      return Rule(pattern: regex, replacement: replacement)
    }
  }

  private func collapseSpaces(_ text: String) -> String {
    text
      .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
