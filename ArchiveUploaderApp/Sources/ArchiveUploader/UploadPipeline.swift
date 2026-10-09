import Foundation
import os

private let pipelineLog = Logger(subsystem: "com.anand.archiver", category: "UploadPipeline")

struct UploadResult {
    let driveLink: String
    let title: String
}

struct UploadPipeline {
    private let archive = ArchiveClient()
    private let drive = GoogleDriveClient()
    private let translator = TranslatorClient()
    private let ocr = OCRClient()

    func preview(url: String) async throws -> ExtractedMetadata {
        guard let identifier = archive.resolveIdentifier(from: url) else {
            throw ArchiveError.noIdentifier
        }
        return try await archive.fetchItemMetadata(identifier: identifier)
    }

    func run(
        url: String,
        metadata: ExtractedMetadata? = nil,
        translate: Bool = false,
        onProgress: @escaping @MainActor (UploadStatus, String, Double?) -> Void
    ) async throws -> UploadResult {
        guard let identifier = archive.resolveIdentifier(from: url) else {
            pipelineLog.error("Could not parse identifier from URL: \(url, privacy: .public)")
            throw ArchiveError.noIdentifier
        }
        pipelineLog.info("Starting pipeline for \(identifier, privacy: .public) (translate=\(translate))")

        let finalMetadata: ExtractedMetadata
        if let metadata {
            finalMetadata = metadata
            await onProgress(.extractingMetadata, "Using edited metadata...", nil)
        } else {
            await onProgress(.resolving, "Resolving \(identifier)...", nil)
            await onProgress(.extractingMetadata, "Fetching metadata...", nil)
            finalMetadata = try await archive.fetchItemMetadata(identifier: identifier)
        }
        pipelineLog.info("Metadata: \(finalMetadata.title, privacy: .public)")

        let filename = ArchiveClient.suggestFilename(from: finalMetadata, identifier: identifier)

        // Dedupe before the (possibly multi-gigabyte) download: if Drive already
        // holds this filename there is nothing to fetch.
        if try await drive.hasExistingFile(named: filename) {
            pipelineLog.info("\(filename, privacy: .public) already in Drive; skipping")
            throw ArchiveError.alreadyExists(filename)
        }

        await onProgress(.downloading, "Downloading PDF...", 0)

        var localPath = try await archive.downloadBook(identifier: identifier) { progress in
            await onProgress(.downloading, "Downloading PDF...", progress)
        }
        pipelineLog.info("PDF ready at \(localPath.path, privacy: .public)")

        let newPath = AppConfig.downloadDir.appendingPathComponent(filename)
        if localPath != newPath {
            do {
                try FileManager.default.moveItem(at: localPath, to: newPath)
                localPath = newPath
                pipelineLog.info("Renamed PDF to \(localPath.path, privacy: .public)")
            } catch {
                pipelineLog.warning("Could not rename PDF: \(error.localizedDescription, privacy: .public)")
            }
        }

        if translate {
            pipelineLog.info("Translation requested for \(identifier, privacy: .public)")
            try await translateBook(
                localPath: localPath,
                filename: filename,
                metadata: finalMetadata,
                identifier: identifier,
                onProgress: onProgress
            )
        }

        await onProgress(.uploading, "Uploading to Google Drive...", nil)
        let link = try await drive.uploadFile(
            localPath,
            filename: filename,
            description: finalMetadata.description
        )
        pipelineLog.info("Uploaded to \(link, privacy: .public)")

        return UploadResult(
            driveLink: link,
            title: finalMetadata.title.isEmpty ? identifier : finalMetadata.title
        )
    }

    // MARK: - Translation

    private func translateBook(
        localPath: URL,
        filename: String,
        metadata: ExtractedMetadata,
        identifier: String,
        onProgress: @escaping @MainActor (UploadStatus, String, Double?) -> Void
    ) async throws {
        // 1. Acquire source text: prefer archive.org's OCR layer, fall back to
        //    local OCR when it's absent.
        let rawText: String
        do {
            await onProgress(.extractingText, "Fetching text layer...", nil)
            pipelineLog.info("Fetching archive.org text layer for \(identifier, privacy: .public)")
            rawText = try await archive.fetchItemText(identifier: identifier)
            pipelineLog.info("Text layer: \(rawText.count, privacy: .public) chars")
        } catch ArchiveError.noTextLayer {
            pipelineLog.warning("No archive.org text layer; falling back to OCR")
            guard ocr.isAvailable else { throw OCRError.tesseractMissing }
            await onProgress(.extractingText, "No text layer — running local OCR...", 0)
            rawText = try await ocr.ocrPDF(localPath, lang: AppConfig.ocrLang) { progress in
                await onProgress(.extractingText, "Running local OCR...", progress)
            }
            pipelineLog.info("OCR result: \(rawText.count, privacy: .public) chars")
        }

        // 2. Segment into pages of paragraphs.
        let pages = BilingualDocument.segment(rawText)
        let nonEmptyPages = pages.enumerated().filter { !$0.element.isEmpty }
        pipelineLog.info("Segmented into \(pages.count, privacy: .public) pages, \(nonEmptyPages.count, privacy: .public) non-empty")
        guard !nonEmptyPages.isEmpty else {
            throw ArchiveError.downloadFailed("No text found to translate")
        }

        // 3. Translate page by page so we can report "Page N of M" progress.
        await onProgress(.translating, "Translating \(nonEmptyPages.count) pages...", 0)
        pipelineLog.info("Starting translation of \(nonEmptyPages.count, privacy: .public) pages")
        var translatedPages: [[(source: String, translation: String)]] = Array(repeating: [], count: pages.count)
        var untranslatedSegments = 0

        let batchSize = 16
        for (step, (pageIndex, pageParagraphs)) in nonEmptyPages.enumerated() {
            let completed = step + 1
            let total = nonEmptyPages.count
            let pageNumber = pageIndex + 1
            await onProgress(
                .translating,
                "Translating page \(completed) of \(total)...",
                Double(completed - 1) / Double(total)
            )

            // Translate paragraphs on this page in small batches.
            var pageTranslations: [String] = []
            for start in stride(from: 0, to: pageParagraphs.count, by: batchSize) {
                let end = min(start + batchSize, pageParagraphs.count)
                let batch = Array(pageParagraphs[start..<end])
                let result = try await translator.translate(
                    segments: batch,
                    srcLang: AppConfig.translatorSrcLang
                )
                pageTranslations.append(contentsOf: result)
            }

            // The model sometimes returns the Sanskrit instead of translating it
            // (short or idiomatic lines in particular). Those are swapped for a
            // romanisation so the document never shows a dead English line.
            let resolved = zip(pageParagraphs, pageTranslations).map { source, translation in
                (source: source, translation: BilingualDocument.resolveTranslation(source: source, translated: translation))
            }
            untranslatedSegments += resolved.filter { $0.translation.hasPrefix("_(untranslated)_") }.count
            translatedPages[pageIndex] = resolved

            await onProgress(
                .translating,
                "Translated page \(pageNumber) of \(total)",
                Double(step + 1) / Double(total)
            )
        }

        // 4. Render the bilingual Markdown and write it next to the PDF.
        pipelineLog.info("Translation complete; rendering bilingual Markdown")
        if untranslatedSegments > 0 {
            pipelineLog.info("\(untranslatedSegments, privacy: .public) segment(s) came back untranslated and were romanised instead")
        }
        let markdown = BilingualDocument.render(
            title: metadata.title,
            identifier: identifier,
            sourceLang: AppConfig.translatorSrcLang,
            pages: translatedPages
        )
        let mdFilename = (filename as NSString).deletingPathExtension + ".md"
        let mdPath = AppConfig.downloadDir.appendingPathComponent(mdFilename)
        try markdown.write(to: mdPath, atomically: true, encoding: .utf8)
        pipelineLog.info("Wrote bilingual doc to \(mdPath.path, privacy: .public)")

        // 5. Upload the bilingual doc alongside the original PDF.
        if try await drive.hasExistingFile(named: mdFilename) {
            pipelineLog.info("Bilingual document already in Drive; skipping upload")
        } else {
            await onProgress(.uploading, "Uploading bilingual document...", nil)
            _ = try await drive.uploadFile(
                mdPath,
                filename: mdFilename,
                description: "Bilingual translation of \(metadata.title.isEmpty ? identifier : metadata.title)"
            )
            pipelineLog.info("Uploaded bilingual document")
        }
    }
}
