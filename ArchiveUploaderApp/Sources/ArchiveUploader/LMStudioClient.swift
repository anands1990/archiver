import Foundation

struct LMStudioRequest: Codable {
    let model: String
    let messages: [LMMessage]
    let temperature: Double
    let max_tokens: Int
}

struct LMMessage: Codable {
    let role: String
    let content: String
}

struct LMStudioResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

enum LMStudioError: Error, LocalizedError {
    case requestFailed(String)
    case invalidResponse
    case noJSONFound

    var errorDescription: String? {
        switch self {
        case .requestFailed(let msg): return "LM Studio request failed: \(msg)"
        case .invalidResponse: return "Invalid response from LM Studio"
        case .noJSONFound: return "No JSON found in LM Studio response"
        }
    }
}

final class LMStudioClient {
    private let session = URLSession.shared

    func extractMetadata(from text: String) async throws -> ExtractedMetadata {
        let prompt = """
Extract book metadata from this archive.org page text.
Return ONLY a JSON object with keys: title, author, year, description.
If a field is unknown, use an empty string.

Text:
\(String(text.prefix(4000)))

JSON:
"""

        let requestBody = LMStudioRequest(
            model: AppConfig.lmStudioModel,
            messages: [LMMessage(role: "user", content: prompt)],
            temperature: 0.2,
            max_tokens: 512
        )

        let url = URL(string: "\(AppConfig.lmStudioURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LMStudioError.requestFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0) – \(body)")
        }

        let result = try JSONDecoder().decode(LMStudioResponse.self, from: data)
        guard let content = result.choices.first?.message.content else {
            throw LMStudioError.invalidResponse
        }

        // Extract JSON from response
        if let jsonStart = content.firstIndex(of: "{"),
           let jsonEnd = content.lastIndex(of: "}") {
            let jsonString = String(content[jsonStart...jsonEnd])
            if let jsonData = jsonString.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: String] {
                return ExtractedMetadata(
                    title: dict["title"] ?? "",
                    author: dict["author"] ?? "",
                    year: dict["year"] ?? "",
                    description: dict["description"] ?? "",
                    identifier: ""
                )
            }
        }

        throw LMStudioError.noJSONFound
    }

    func suggestFilename(from metadata: ExtractedMetadata, identifier: String) -> String {
        let parts = [metadata.author, metadata.title, metadata.year].filter { !$0.isEmpty }
        let name = parts.isEmpty ? identifier : parts.joined(separator: " – ")
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,_-")
        let safe = name.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
        let trimmed = String(safe.prefix(200))
        return trimmed + ".pdf"
    }
}
