import AppKit
import Foundation

/// On-device spell suggestions via macOS spell checker. Instant; no network.
enum LocalSpellCorrector {
  /// Corrects likely misspellings word-by-word. Skips URLs, code-like tokens, acronyms.
  static func correct(_ text: String, language: String = "en") -> String {
    guard !text.isEmpty else { return text }

    let checker = NSSpellChecker.shared
    var output = text
    var cursor = 0
    var guardCounter = 0

    while guardCounter < 64 {
      guardCounter += 1
      let ns = output as NSString
      if cursor >= ns.length { break }

      let misspelled = checker.checkSpelling(
        of: output,
        startingAt: cursor,
        language: language,
        wrap: false,
        inSpellDocumentWithTag: 0,
        wordCount: nil
      )
      if misspelled.location == NSNotFound { break }

      let word = ns.substring(with: misspelled)
      let nextCursor = misspelled.location + misspelled.length

      if shouldSkipSpellFix(word) {
        cursor = nextCursor
        continue
      }

      guard
        let guesses = checker.guesses(
          forWordRange: misspelled,
          in: output,
          language: language,
          inSpellDocumentWithTag: 0
        ),
        let best = guesses.first,
        best.caseInsensitiveCompare(word) != .orderedSame
      else {
        cursor = nextCursor
        continue
      }

      let replacement = matchCapitalization(of: word, onto: best)
      if let range = Range(misspelled, in: output) {
        output.replaceSubrange(range, with: replacement)
        cursor = misspelled.location + replacement.count
      } else {
        cursor = nextCursor
      }
    }

    return output
  }

  private static func shouldSkipSpellFix(_ word: String) -> Bool {
    if word.count <= 2 { return true }
    if word.contains(".") || word.contains("/") || word.contains("_") { return true }
    if word.contains("-") { return true }
    let letters = word.filter(\.isLetter)
    if !letters.isEmpty, letters.allSatisfy(\.isUppercase) { return true }
    let hasLower = word.contains(where: \.isLowercase)
    let hasUpper = word.dropFirst().contains(where: \.isUppercase)
    if hasLower && hasUpper { return true }
    return false
  }

  private static func matchCapitalization(of original: String, onto suggestion: String) -> String {
    if original == original.uppercased(), original.count > 1 {
      return suggestion.uppercased()
    }
    if let first = original.first, first.isUppercase {
      return suggestion.prefix(1).uppercased() + suggestion.dropFirst()
    }
    return suggestion
  }
}
