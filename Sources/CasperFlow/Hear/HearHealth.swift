import Foundation

/// Lightweight reachability check so we fail before opening the Hear stream.
enum HearHealth {
  private static let healthURL = URL(string: "https://api.pyai.com/v1/health")!
  private static let originURL = URL(string: "https://api.pyai.com/")!
  private static let timeout: TimeInterval = 2.5

  /// `true` if PyAI’s API host responds and is not returning a server error.
  static func isAvailable(apiKey: String) async -> Bool {
    if await probe(healthURL, apiKey: apiKey) { return true }
    return await probe(originURL, apiKey: apiKey)
  }

  private static func probe(_ url: URL, apiKey: String) async -> Bool {
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = timeout
    request.cachePolicy = .reloadIgnoringLocalCacheData
    let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty {
      request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
    }
    do {
      let (_, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse else { return false }
      // 404 = no health route but the host is up. 401/403 = API is up, key may be wrong.
      if (500...599).contains(http.statusCode) {
        AppLog.error("PyAI Hear health check failed: HTTP \(http.statusCode)")
        return false
      }
      return true
    } catch {
      AppLog.error("PyAI Hear health check failed: \(error.localizedDescription)")
      return false
    }
  }
}
