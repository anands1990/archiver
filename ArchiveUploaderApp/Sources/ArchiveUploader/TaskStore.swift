import Foundation
import SwiftUI

enum UploadStatus: String, CaseIterable {
    case idle = "Idle"
    case resolving = "Resolving"
    case extractingMetadata = "Metadata"
    case reviewing = "Reviewing"
    case downloading = "Downloading"
    case uploading = "Uploading"
    case completed = "Completed"
    case failed = "Failed"
}

struct UploadTask: Identifiable {
    let id = UUID()
    let url: String
    var status: UploadStatus
    var message: String
    var progress: Double?
    var title: String?
    var driveLink: String?
    var timestamp: Date
}

@MainActor
@Observable
final class TaskStore {
    var tasks: [UploadTask] = []
    var isProcessing = false
    var currentURL = ""
    var currentStatus: UploadStatus = .idle
    var currentMessage = "Ready to upload"
    var currentProgress: Double?
    var showError = false
    var errorMessage = ""

    // Metadata review state
    var showMetadataReview = false
    var pendingMetadata: ExtractedMetadata?
    var pendingTaskID: UUID?

    func addTask(url: String) {
        let task = UploadTask(
            url: url,
            status: .idle,
            message: "Queued",
            timestamp: Date()
        )
        tasks.insert(task, at: 0)
        isProcessing = true
        currentStatus = .idle
        currentMessage = "Queued"
        currentProgress = nil
    }

    func updateTask(id: UUID, status: UploadStatus, message: String, progress: Double? = nil, title: String? = nil, driveLink: String? = nil) {
        if let index = tasks.firstIndex(where: { $0.id == id }) {
            tasks[index].status = status
            tasks[index].message = message
            tasks[index].progress = progress
            if let title { tasks[index].title = title }
            if let driveLink { tasks[index].driveLink = driveLink }
        }
        currentStatus = status
        currentMessage = message
        currentProgress = progress
    }

    func showError(_ msg: String) {
        errorMessage = msg
        showError = true
        currentStatus = .failed
        currentMessage = msg
    }

    func prepareMetadataReview(taskID: UUID, metadata: ExtractedMetadata) {
        pendingTaskID = taskID
        pendingMetadata = metadata
        showMetadataReview = true
    }

    func completeMetadataReview() {
        showMetadataReview = false
        pendingMetadata = nil
        pendingTaskID = nil
    }
}
