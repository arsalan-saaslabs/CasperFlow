import Foundation

/// OpenAI summary + action items for a finished note transcript.
enum OpenAINoteInsights {
  private static let maxInputCharacters = 24_000
  private static let maxOutputTokens = 1_200
  private static let timeoutSeconds: TimeInterval = 45

  struct Result: Sendable {
    let summary: String
    let actionItems: [String]
  }

  static func generate(transcript: String, apiKey: String) async -> Result? {
    let system = """
    You summarize meeting or lecture notes from a transcript.
    Return JSON only with keys:
    - "summary": 2–5 sentences covering the main points.
    - "action_items": array of short imperative tasks (empty array if none).
    Do not invent facts that are not in the transcript.
    """

    guard let raw = await OpenAIChatClient.complete(
      system: system,
      user: transcript,
      apiKey: apiKey,
      temperature: 0.2,
      timeout: timeoutSeconds,
      maxTokens: maxOutputTokens,
      maxInputCharacters: maxInputCharacters,
      jsonObject: true
    ) else {
      return nil
    }

    return parse(raw)
  }

  private static func parse(_ raw: String) -> Result? {
    guard let data = raw.data(using: .utf8),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }

    let summary = (root["summary"] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let items = (root["action_items"] as? [Any] ?? []).compactMap { value -> String? in
      guard let text = value as? String else { return nil }
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : String(trimmed.prefix(240))
    }

    guard !summary.isEmpty || !items.isEmpty else { return nil }
    return Result(summary: summary, actionItems: Array(items.prefix(20)))
  }
}
