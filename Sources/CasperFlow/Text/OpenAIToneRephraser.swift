import Foundation

/// Optional OpenAI chat rewrite for true tone rephrasing on commit.
enum OpenAIToneRephraser {
  private static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
  private static let model = "gpt-4o-mini"
  private static let maxInputCharacters = 2_000
  private static let timeoutSeconds: TimeInterval = 12

  static func rephrase(
    _ text: String,
    tone: WritingTone,
    appName: String,
    apiKey: String
  ) async -> String? {
    let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedKey.isEmpty, !input.isEmpty else { return nil }
    guard input.count <= maxInputCharacters else { return nil }

    let system = """
    You rewrite dictated text for the app "\(appName)" using a \(tone.displayName.lowercased()) tone.
    Rules:
    - Return ONLY the rewritten text.
    - No quotes, labels, or explanation.
    - Keep meaning; fix grammar lightly.
    - \(tonePrompt(tone))
    """

    let body: [String: Any] = [
      "model": model,
      "temperature": 0.2,
      "messages": [
        ["role": "system", "content": system],
        ["role": "user", "content": input],
      ],
    ]

    guard let json = try? JSONSerialization.data(withJSONObject: body) else { return nil }

    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = timeoutSeconds
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
    request.httpBody = json

    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
        return nil
      }
      guard
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let choices = root["choices"] as? [[String: Any]],
        let message = choices.first?["message"] as? [String: Any],
        let content = message["content"] as? String
      else {
        return nil
      }
      let cleaned = content
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
      return cleaned.isEmpty ? nil : cleaned
    } catch {
      return nil
    }
  }

  private static func tonePrompt(_ tone: WritingTone) -> String {
    switch tone {
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
