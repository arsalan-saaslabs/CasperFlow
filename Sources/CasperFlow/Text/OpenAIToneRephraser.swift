import Foundation

/// Optional OpenAI chat rewrite for true tone rephrasing on commit.
enum OpenAIToneRephraser {
  private static let maxInputCharacters = 2_000
  private static let timeoutSeconds: TimeInterval = 12

  static func rephrase(
    _ text: String,
    tone: WritingTone,
    appName: String,
    apiKey: String
  ) async -> String? {
    guard tone.appliesRewrite else { return nil }

    let system = """
    You rewrite dictated text for the app "\(appName)" using a \(tone.displayName.lowercased()) tone.
    Rules:
    - Return ONLY the rewritten text.
    - No quotes, labels, or explanation.
    - Keep meaning; fix grammar lightly.
    - \(tonePrompt(tone))
    """

    return await OpenAIChatClient.complete(
      system: system,
      user: text,
      apiKey: apiKey,
      temperature: 0.2,
      timeout: timeoutSeconds,
      maxTokens: nil,
      maxInputCharacters: maxInputCharacters
    )
  }

  private static func tonePrompt(_ tone: WritingTone) -> String {
    switch tone {
    case .doNothing:
      return "Return the input unchanged."
    case .casual:
      return "Sound friendly and conversational; contractions OK; avoid stiff formality."
    case .professional:
      return "Sound polished and professional; expand slang; suitable for email."
    case .developer:
      return "Keep technical terms exact (API, PR, DNM, etc.); concise; no fluff."
    case .general:
      return "Clear, neutral, well-punctuated prose."
    }
  }
}
