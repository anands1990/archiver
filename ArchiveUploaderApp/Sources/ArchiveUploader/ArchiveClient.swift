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
    case noTextLayer

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid archive.org URL"
        case .noIdentifier: return "Could not parse archive.org identifier from URL"
        case .noPDFFound: return "No PDF found for this item"
        case .alreadyExists(let name): return "Already exists: \(name)"
        case .downloadFailed(let msg): return "Download failed: \(msg)"
        case .noTextLayer: return "No OCR text layer on archive.org for this item"
        }
    }
}

final class ArchiveClient {
    private let base = "https://archive.org"
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        // Large scanned PDFs from archive.org can be slow; allow long downloads.
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 0
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

        // Reuse an already-downloaded PDF instead of failing; delete stale partials.
        if FileManager.default.fileExists(atPath: localPath.path) {
            try? FileManager.default.removeItem(at: incompletePath)
            return localPath
        }

        // Remove any stale incomplete download
        try? FileManager.default.removeItem(at: incompletePath)

        // The download task writes straight to `incompletePath` and only reports
        // success once the whole body is on disk.
        _ = try await downloadToDisk(url, destination: incompletePath, progress: progress)
        await progress?(1.0)

        // Promote to the final name only now: a cancelled or failed download
        // leaves an `.incomplete` file, never a truncated PDF.
        if FileManager.default.fileExists(atPath: localPath.path) {
            try? FileManager.default.removeItem(at: incompletePath)
            return localPath
        }
        do {
            try FileManager.default.moveItem(at: incompletePath, to: localPath)
        } catch {
            try? FileManager.default.removeItem(at: incompletePath)
            throw ArchiveError.downloadFailed(error.localizedDescription)
        }
        return localPath
    }

    /// Streams `url` to a file, reporting fractional progress on the main actor.
    ///
    /// `URLSession.bytes(from:)` yields one `UInt8` at a time, which costs a
    /// concurrency continuation *per byte* — minutes of pure overhead on
    /// multi-gigabyte scanned books. A download task moves data in large chunks,
    /// keeps the file off the main memory, and is cancellable.
    private func downloadToDisk(
        _ url: URL,
        destination: URL,
        progress: (@MainActor (Double) async -> Void)?
    ) async throws -> URL {
        var progressContinuation: AsyncStream<Double>.Continuation!
        let progressStream = AsyncStream<Double> { progressContinuation = $0 }

        let config = URLSessionConfiguration.default
        // Large scanned PDFs from archive.org can be slow; allow long downloads.
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 0

        // Forward ticks to the (main actor) caller while the task runs.
        let pump = Task { @MainActor in
            for await fraction in progressStream {
                await progress?(fraction)
            }
        }
        defer { pump.cancel() }

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadProgressDelegate(
                destination: destination,
                progress: progressContinuation,
                completion: { result in continuation.resume(with: result) }
            )
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            // The session retains its delegate; holding it here keeps the task
            // alive until it finishes.
            delegate.session = session
            session.downloadTask(with: URLRequest(url: url)).resume()
        }
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

    /// Fetches the OCR text layer archive.org already produced for the item
    /// (`<id>_djvu.txt`). Throws `noTextLayer` only when the derivative is
    /// genuinely absent or empty — a transport failure is reported as itself so
    /// the pipeline does not silently kick off a multi-hour local OCR run.
    func fetchItemText(identifier: String) async throws -> String {
        let encoded = identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? identifier
        let url = URL(string: "\(base)/download/\(encoded)/\(encoded)_djvu.txt")!
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                throw ArchiveError.noTextLayer
            }
            // archive.org answers 404 for items with no derivatives, so a missing
            // text layer is a real "not there" rather than a failure.
            guard http.statusCode == 200 else {
                if http.statusCode == 404 || http.statusCode == 403 {
                    throw ArchiveError.noTextLayer
                }
                throw ArchiveError.downloadFailed("Text layer request failed (HTTP \(http.statusCode))")
            }
            guard let text = String(data: data, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ArchiveError.noTextLayer
            }
            return text
        } catch let error as ArchiveError {
            throw error
        } catch {
            throw error
        }
    }

    /// Pulls title/author/year/description from the archive.org `/metadata/<id>`
    /// JSON API. Replaces the previous LM Studio scraping approach — archive.org
    /// already exposes structured metadata, so no local LLM is needed.
    func fetchItemMetadata(identifier: String) async throws -> ExtractedMetadata {
        let url = URL(string: "\(base)/metadata/\(identifier)")!
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ArchiveError.downloadFailed("Metadata request failed")
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let meta = root["metadata"] as? [String: Any] else {
            throw ArchiveError.downloadFailed("No metadata found for item")
        }

        let date = stringValue(meta["date"])
        let year = cleanYear(date.isEmpty ? stringValue(meta["year"]) : date)

        return ExtractedMetadata(
            title: stringValue(meta["title"]),
            author: stringValue(meta["creator"]),
            year: year,
            description: stringValue(meta["description"]),
            identifier: identifier
        )
    }

    /// archive.org fields can be strings, arrays, or numbers depending on the
    /// item — coerce any of them into a single display string.
    private func stringValue(_ any: Any?) -> String {
        if let s = any as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = any as? NSNumber { return n.stringValue }
        if let a = any as? [Any] {
            return a.compactMap { stringValue($0) }.filter { !$0.isEmpty }.joined(separator: ", ")
        }
        return ""
    }

    /// Normalises archive.org date strings ("1900-01-01", "1900?", "[1900]")
    /// down to a 4-digit year when possible.
    private func cleanYear(_ raw: String) -> String {
        guard let digits = raw.range(of: #"\d{4}"#, options: .regularExpression) else {
            return raw
        }
        return String(raw[digits])
    }

    /// Shared filename builder so the review preview and the actual upload use
    /// exactly the same name. Sanitised to Drive-safe characters.
    static func suggestFilename(from metadata: ExtractedMetadata, identifier: String) -> String {
        let parts = [metadata.author, metadata.title, metadata.year].filter { !$0.isEmpty }
        let name = parts.isEmpty ? identifier : parts.joined(separator: " – ")
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,_-")
        let safe = name.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
        let trimmed = String(safe.prefix(200))
        return trimmed + ".pdf"
    }
}

/// Streams a `URLSessionDownloadTask` straight to a file on disk, reporting
/// fractional progress through an `AsyncStream` and the finished file (or the
/// failure) through a continuation.
private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    /// Progress is reported at most this often, so a multi-GB book does not
    /// fire thousands of main-actor hops — which measured at ~100% of a core
    /// when the bar animated on every update.
    private let reportInterval: Int64 = 512 * 1024
    private var lastReported: Int64 = 0

    private let destination: URL
    private let progressContinuation: AsyncStream<Double>.Continuation
    private let completion: @Sendable (Result<URL, Error>) -> Void

    /// Held only until the download resolves. The session retains its delegate,
    /// so the session is kept from here instead of a local.
    var session: URLSession?

    init(
        destination: URL,
        progress: AsyncStream<Double>.Continuation,
        completion: @escaping @Sendable (Result<URL, Error>) -> Void
    ) {
        self.destination = destination
        self.progressContinuation = progress
        self.completion = completion
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        lock.lock()
        let shouldReport = totalBytesWritten - lastReported >= reportInterval
            || totalBytesWritten >= totalBytesExpectedToWrite
        if shouldReport { lastReported = totalBytesWritten }
        lock.unlock()
        guard shouldReport else { return }
        progressContinuation.yield(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // archive.org answers a missing item with a status code plus a small
        // body, so the status has to be checked here rather than trusting that
        // the download "succeeded".
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            try? FileManager.default.removeItem(at: location)
            finish(with: .failure(ArchiveError.downloadFailed("HTTP \(http.statusCode)")))
            return
        }

        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            finish(with: .success(destination))
        } catch {
            finish(with: .failure(ArchiveError.downloadFailed(error.localizedDescription)))
        }
    }

    /// Transport failures (offline, reset, timeout) never reach
    /// `didFinishDownloadingTo`.
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(with: .failure(error))
        }
    }

    private func finish(with result: Result<URL, Error>) {
        lock.lock()
        let alreadyFinished = finished
        finished = true
        lock.unlock()
        guard !alreadyFinished else { return }

        progressContinuation.finish()
        session?.finishTasksAndInvalidate()
        session = nil
        completion(result)
    }
}
