import Foundation

struct UploadResult {
    let driveLink: String
    let title: String
}

struct UploadPipeline {
    private let archive = ArchiveClient()
    private let lmStudio = LMStudioClient()
    private let drive = GoogleDriveClient()

    func preview(url: String) async throws -> ExtractedMetadata {
        guard let identifier = archive.resolveIdentifier(from: url) else {
            throw ArchiveError.noIdentifier
        }
        let pageText = await archive.getPageText(identifier: identifier)
        guard !pageText.isEmpty else {
            throw ArchiveError.downloadFailed("Failed to fetch archive page")
        }
        var metadata = try await lmStudio.extractMetadata(from: pageText)
        metadata = ExtractedMetadata(
            title: metadata.title,
            author: metadata.author,
            year: metadata.year,
            description: metadata.description,
            identifier: identifier
        )
        return metadata
    }

    func run(
        url: String,
        metadata: ExtractedMetadata? = nil,
        onProgress: @escaping @MainActor (UploadStatus, String, Double?) -> Void
    ) async throws -> UploadResult {
        guard let identifier = archive.resolveIdentifier(from: url) else {
            throw ArchiveError.noIdentifier
        }

        let finalMetadata: ExtractedMetadata
        if let metadata {
            finalMetadata = metadata
            await onProgress(.extractingMetadata, "Using edited metadata...", nil)
        } else {
            await onProgress(.resolving, "Resolving \(identifier)...", nil)
            let pageText = await archive.getPageText(identifier: identifier)
            guard !pageText.isEmpty else {
                throw ArchiveError.downloadFailed("Failed to fetch page")
            }
            await onProgress(.extractingMetadata, "Extracting metadata...", nil)
            var extracted = try await lmStudio.extractMetadata(from: pageText)
            extracted = ExtractedMetadata(
                title: extracted.title,
                author: extracted.author,
                year: extracted.year,
                description: extracted.description,
                identifier: identifier
            )
            finalMetadata = extracted
        }

        let filename = lmStudio.suggestFilename(from: finalMetadata, identifier: identifier)
        await onProgress(.downloading, "Downloading PDF...", 0)

        var localPath = try await archive.downloadBook(identifier: identifier) { progress in
            await onProgress(.downloading, "Downloading PDF...", progress)
        }

        let newPath = AppConfig.downloadDir.appendingPathComponent(filename)
        if localPath != newPath {
            do {
                try FileManager.default.moveItem(at: localPath, to: newPath)
                localPath = newPath
            } catch {
                // Keep original name if rename fails
            }
        }

        await onProgress(.uploading, "Uploading to Google Drive...", nil)
        let link = try await drive.uploadFile(
            localPath,
            filename: filename,
            description: finalMetadata.description
        )

        return UploadResult(
            driveLink: link,
            title: finalMetadata.title.isEmpty ? identifier : finalMetadata.title
        )
    }
}
