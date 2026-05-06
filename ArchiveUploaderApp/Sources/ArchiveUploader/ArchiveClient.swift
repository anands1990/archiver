import Foundation

struct ArchiveMetadata: Codable {
    let files: [ArchiveFile]?
}

struct ArchiveFile: Codable {
    let name: String
    let size: String?
}

enum ArchiveError: Error, LocalizedError {
    case invalidURL
    case noIdentifier
    case noPDFFound
    case alreadyExists(String)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid archive.org URL"
        case .noIdentifier: return "Could not parse archive.org identifier from URL"
        case .noPDFFound: return "No PDF found for this item"
        case .alreadyExists(let name): return "Already exists: \(name)"
        case .downloadFailed(let msg): return "Download failed: \(msg)"
        }
    }
}

final class ArchiveClient {
    private let base = "https://archive.org"
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    func resolveIdentifier(from url: String) -> String? {
        let patterns = [
            "archive\\.org/details/([^/?#]+)",
            "archive\\.org/download/([^/?#]+)",
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(url.startIndex..., in: url)
            if let match = regex.firstMatch(in: url, options: [], range: range),
               let idRange = Range(match.range(at: 1), in: url) {
                return String(url[idRange])
            }
        }
        return nil
    }

    func fetchMetadata(identifier: String) async throws -> ArchiveMetadata {
        let url = URL(string: "\(base)/metadata/\(identifier)")!
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ArchiveError.downloadFailed("Metadata request failed")
        }
        return try JSONDecoder().decode(ArchiveMetadata.self, from: data)
    }

    func findPDFFile(in metadata: ArchiveMetadata) -> String? {
        guard let files = metadata.files else { return nil }
        let candidates = files.filter { $0.name.lowercased().hasSuffix(".pdf") }
        guard !candidates.isEmpty else { return nil }
        // Prefer smaller PDFs (text over scanned image PDF)
        let sorted = candidates.sorted {
            let s1 = Int($0.size ?? "0") ?? 0
            let s2 = Int($1.size ?? "0") ?? 0
            return s1 < s2
        }
        return sorted.first?.name
    }

    func downloadBook(identifier: String, progress: (@MainActor (Double) async -> Void)? = nil) async throws -> URL {
        let metadata = try await fetchMetadata(identifier: identifier)
        guard let pdfName = findPDFFile(in: metadata) else {
            throw ArchiveError.noPDFFound
        }

        let url = URL(string: "\(base)/download/\(identifier)/\(pdfName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pdfName)")!
        let localPath = AppConfig.downloadDir.appendingPathComponent(pdfName)
        let incompletePath = localPath.appendingPathExtension("incomplete")

        if FileManager.default.fileExists(atPath: localPath.path) {
            throw ArchiveError.alreadyExists(pdfName)
        }

        // Remove any stale incomplete download
        try? FileManager.default.removeItem(at: incompletePath)

        let (asyncBytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ArchiveError.downloadFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        let total = http.expectedContentLength
        var downloaded: Int64 = 0
        var lastProgressSent: Int64 = -1
        let progressInterval: Int64 = 100 * 1024 // 100KB

        try Data().write(to: incompletePath)
        let handle = try FileHandle(forWritingTo: incompletePath)
        defer { handle.closeFile() }

        var buffer = Data()
        buffer.reserveCapacity(65536)

        for try await byte in asyncBytes {
            buffer.append(byte)
            if buffer.count >= 65536 {
                handle.write(buffer)
                buffer.removeAll(keepingCapacity: true)
            }
            downloaded += 1
            if total > 0, downloaded - lastProgressSent >= progressInterval {
                lastProgressSent = downloaded
                await progress?(Double(downloaded) / Double(total))
            }
        }

        if !buffer.isEmpty {
            handle.write(buffer)
        }
        handle.closeFile()

        try FileManager.default.moveItem(at: incompletePath, to: localPath)
        return localPath
    }

    func getPageText(identifier: String) async -> String {
        let url = URL(string: "\(base)/details/\(identifier)")!
        do {
            let (data, _) = try await session.data(from: url)
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
