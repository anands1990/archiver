import Foundation
import PDFKit
import AppKit

enum OCRError: Error, LocalizedError {
    case tesseractMissing
    case openFailed(String)
    case pageFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .tesseractMissing:
            return "Local OCR needs tesseract. Install it: brew install tesseract tesseract-lang"
        case .openFailed(let msg):
            return "Could not open PDF for OCR: \(msg)"
        case .pageFailed(let page, let msg):
            return "OCR failed on page \(page): \(msg)"
        }
    }
}

/// Local OCR fallback used when an archive.org item has no text layer.
/// Rasterises each PDF page with PDFKit, then runs the `tesseract` CLI with
/// Devanagari/Sanskrit traineddata. Slow for full books — progress is reported
/// per page.
final class OCRClient {
    private let tesseractPath: String?

    init() {
        // GUI apps get a minimal PATH; look in the usual Homebrew locations.
        let candidates = ["/opt/homebrew/bin/tesseract", "/usr/local/bin/tesseract", "/usr/bin/tesseract"]
        tesseractPath = candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    var isAvailable: Bool { tesseractPath != nil }

    func ocrPDF(
        _ url: URL,
        lang: String,
        onProgress: @escaping @MainActor (Double) async -> Void
    ) async throws -> String {
        guard let tesseractPath else { throw OCRError.tesseractMissing }
        guard let pdf = PDFDocument(url: url), pdf.pageCount > 0 else {
            throw OCRError.openFailed(url.lastPathComponent)
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("archiver-ocr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var pages: [String] = []
        let total = pdf.pageCount
        for i in 0..<total {
            try Task.checkCancellation()
            guard let page = pdf.page(at: i) else { continue }

            let image = page.thumbnail(of: CGSize(width: 2000, height: 2600), for: .mediaBox)
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                throw OCRError.pageFailed(i + 1, "rasterisation failed")
            }

            let pngPath = tempDir.appendingPathComponent("page-\(i).png")
            try png.write(to: pngPath)

            let text = try await runTesseract(at: tesseractPath, image: pngPath, lang: lang)
            pages.append(text)

            let fraction = Double(i + 1) / Double(total)
            await onProgress(fraction)
        }

        // Join pages with a form feed so downstream segmentation sees page breaks.
        return pages.joined(separator: "\u{0C}")
    }

    /// Runs tesseract without parking a cooperative thread for the whole job:
    /// stdout is drained by a readability handler and the text is handed back
    /// through a continuation once the process exits.
    private func runTesseract(at path: String, image: URL, lang: String) async throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = [image.path, "stdout", "-l", lang, "--psm", "6"]

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        let output = OutputBox()
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            output.append(handle.availableData)
        }
        // stderr is drained only to keep the pipe from filling up.
        errPipe.fileHandleForReading.readabilityHandler = { _ in }

        return try await withCheckedThrowingContinuation { continuation in
            proc.terminationHandler = { process in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                // Anything buffered but not yet delivered.
                output.append(outPipe.fileHandleForReading.availableData)

                if process.terminationStatus == 0 {
                    continuation.resume(returning: output.string)
                } else {
                    continuation.resume(throwing: OCRError.pageFailed(0, "tesseract exited with status \(process.terminationStatus)"))
                }
            }

            do {
                try proc.run()
            } catch {
                continuation.resume(throwing: OCRError.pageFailed(0, error.localizedDescription))
            }
        }
    }
}

/// Thread-safe accumulator: the readability handler fires on Foundation's pipe
/// queue while the continuation resumes from the process's termination queue.
private final class OutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.withLock { data.append(chunk) }
    }

    var string: String {
        lock.withLock { String(data: data, encoding: .utf8) ?? "" }
    }
}