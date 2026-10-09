import Foundation

enum TranslatorError: Error, LocalizedError {
    case notRunning
    case requestFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notRunning: return "Translator is not running. Start it in Settings."
        case .requestFailed(let msg): return "Translator request failed: \(msg)"
        case .invalidResponse: return "Invalid response from translator"
        }
    }
}

/// HTTP client for the local IndicTrans2 Python sidecar.
final class TranslatorClient {
    private let session: URLSession
    private let baseURL: URL

    init(port: Int = AppConfig.translatorPort) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 1800 // long books
        self.session = URLSession(configuration: config)
        self.baseURL = URL(string: "http://127.0.0.1:\(port)")!
    }

    /// True when the sidecar responds on `/health` with a ready model.
    func health() async -> Bool {
        do {
            let (data, response) = try await session.data(from: baseURL.appendingPathComponent("health"))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return false
            }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return (obj["status"] as? String) == "ok"
            }
            return false
        } catch {
            return false
        }
    }

    /// Translates a batch of source segments. The sidecar handles model work
    /// and internal batching; this returns one translation per input segment.
    func translate(segments: [String], srcLang: String) async throws -> [String] {
        guard !segments.isEmpty else { return [] }

        var request = URLRequest(url: baseURL.appendingPathComponent("translate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 1800

        let body: [String: Any] = ["segments": segments, "src_lang": srcLang]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranslatorError.invalidResponse
        }
        guard http.statusCode == 200 else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            if http.statusCode == 503 {
                throw TranslatorError.notRunning
            }
            throw TranslatorError.requestFailed("HTTP \(http.statusCode): \(bodyStr)")
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let translations = obj["translations"] as? [String] else {
            throw TranslatorError.invalidResponse
        }
        return translations
    }
}