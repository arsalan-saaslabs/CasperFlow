import Foundation

/// Shared OpenAI Chat Completions caller. API key is never logged.
enum OpenAIChatClient {
  private static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
  static let model = "gpt-4o-mini"

  static func complete(
    system: String,
    user: String,
    apiKey: String,
    temperature: Double,
    timeout: TimeInterval,
    maxTokens: Int?,
    maxInputCharacters: Int
  ) async -> String? {
    let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let input = user.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedKey.isEmpty, !input.isEmpty else { return nil }
    guard input.count <= maxInputCharacters else { return nil }

    var body: [String: Any] = [
      "model": model,
      "temperature": temperature,
      "messages": [
        ["role": "system", "content": system],
        ["role": "user", "content": input],
      ],
    ]
    if let maxTokens {
      body["max_tokens"] = maxTokens
    }

    guard let json = try? JSONSerialization.data(withJSONObject: body) else { return nil }

    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = timeout
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
      return sanitize(content)
    } catch {
      return nil
    }
  }

  /// Strip wrapping quotes/fences; keep inner punctuation and newlines.
  private static func sanitize(_ raw: String) -> String? {
    var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if cleaned.hasPrefix("```") {
      cleaned = cleaned.replacingOccurrences(
        of: #"^```[a-zA-Z]*\n?"#,
        with: "",
        options: .regularExpression
      )
      if let fence = cleaned.range(of: "```", options: .backwards) {
        cleaned = String(cleaned[..<fence.lowerBound])
      }
      cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    return cleaned.isEmpty ? nil : cleaned
  }
}
