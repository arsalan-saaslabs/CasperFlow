import Foundation

/// Turns a spoken instruction into paste-ready writing (email, message, etc.).
enum OpenAICommandWriter {
  private static let maxInputCharacters = 2_000
  private static let maxOutputTokens = 2_048
  private static let timeoutSeconds: TimeInterval = 45
  private static let temperature = 0.4

  static func compose(
    prompt: String,
    appName: String,
    apiKey: String
  ) async -> String? {
    let system = """
    You are a writing assistant. The user dictated a request by voice.
    Write the content they asked for so it can be pasted into "\(appName)".

    Rules:
    - Return ONLY the finished content. No preamble, labels, or surrounding quotes.
    - Do not wrap the answer in markdown code fences.
    - Use real newline characters. Separate paragraphs with a blank line.
    - Use correct punctuation, capitalization, and spelling.
    - If they ask for an email: greeting, blank line, body paragraphs, blank line, sign-off.
    - If they ask for a message or reply: natural line breaks, not one long line.
    - Match the requested language. Keep names and facts from the request.
    - Do not invent private details (salary numbers, addresses) the user did not say.
    """

    return await OpenAIChatClient.complete(
      system: system,
      user: prompt,
      apiKey: apiKey,
      temperature: temperature,
      timeout: timeoutSeconds,
      maxTokens: maxOutputTokens,
      maxInputCharacters: maxInputCharacters
    )
  }
}
