import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(TaskStore.self) var store
    @State private var urlInput = ""
    @State private var showingSettings = false
    @State private var showClearConfirmation = false
    @State private var isDropTarget = false
    @State private var queueCount = 0
    @State private var progressShake: CGFloat = 0
    @State private var buttonShake: CGFloat = 0
    private let pipeline = UploadPipeline()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if showingSettings {
                settingsContent
            } else {
                mainContent
            }
            Divider()
            HStack {
                Spacer()
                Button(action: { NSApp.terminate(nil) }) {
                    Text("Quit Archiver")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }
        }
        .alert("Error", isPresented: Bindable(store).showError) {
            Button("OK") { store.showError = false }
        } message: {
            Text(store.errorMessage)
        }
        .sheet(isPresented: Bindable(store).showMetadataReview) {
            if store.pendingMetadata != nil {
                MetadataReviewView(
                    onConfirm: confirmUpload,
                    onCancel: cancelUpload
                )
                .environment(store)
            }
        }
    }

    // MARK: Header

    var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(showingSettings ? "Settings" : "Archiver")
                .font(.system(size: 15, weight: .semibold))

            Spacer()

            Button(action: { showingSettings.toggle() }) {
                Image(systemName: showingSettings ? "xmark" : "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showingSettings ? "Close settings" : "Settings")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: Main Content

    var mainContent: some View {
        VStack(spacing: 0) {
            inputSection
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            Divider()
            ScrollView {
                VStack(spacing: 8) {
                    if store.isProcessing {
                        progressCard
                            .transition(.opacity.combined(with: .scale(0.96)))
                    }
                    historySection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .frame(maxHeight: 300)
        }
    }

    // MARK: Input

    var inputSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: isDropTarget ? "arrow.down.doc" : "link")
                    .foregroundStyle(isDropTarget ? AppTheme.accent : .secondary)
                    .font(.system(size: 12, weight: .medium))
                    .animation(.easeInOut(duration: 0.15), value: isDropTarget)
                TextField("Paste archive.org link...", text: $urlInput)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
                if !urlInput.isEmpty {
                    Button(action: { urlInput = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary.opacity(0.5))
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear input")
                }
                Button(action: pasteFromClipboard) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Paste from clipboard")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isDropTarget ? AppTheme.accent.opacity(0.6) : Color.secondary.opacity(0.12), lineWidth: isDropTarget ? 2 : 1)
                    .animation(.easeInOut(duration: 0.15), value: isDropTarget)
            )
            .onDrop(of: [.url, .plainText], isTargeted: $isDropTarget) { providers, _ in
                Task { @MainActor in
                    await handleProviders(providers)
                }
                return true
            }

            HStack(spacing: 8) {
                Button(action: previewMetadata) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12))
                        Text("Preview")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(urlInput.isEmpty)
                .opacity(urlInput.isEmpty ? 0.5 : 1)

                Button(action: submitDirect) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 12))
                        Text(queueCount > 0 ? "Upload \(queueCount)" : "Upload")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(AppTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(urlInput.isEmpty)
                .opacity(urlInput.isEmpty ? 0.6 : 1)
                .offset(x: buttonShake)
            }
        }
    }

    // MARK: Progress

    var progressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: statusIcon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
                Text(store.currentMessage)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if store.isProcessing {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }
            }
            if let progress = store.currentProgress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.1))
                            .frame(height: 3)
                        Capsule()
                            .fill(AppTheme.accent)
                            .frame(width: geo.size.width * progress, height: 3)
                            .animation(.easeInOut(duration: 0.3), value: progress)
                    }
                }
                .frame(height: 3)
            } else {
                StepDots(activeStep: store.currentStatus)
            }
        }
        .padding(12)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
        )
        .offset(x: progressShake)
    }

    var statusIcon: String {
        switch store.currentStatus {
        case .resolving: return "magnifyingglass"
        case .extractingMetadata: return "sparkles"
        case .downloading: return "arrow.down"
        case .uploading: return "arrow.up"
        default: return "clock"
        }
    }

    // MARK: History

    var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !store.tasks.isEmpty {
                    Button("Clear") {
                        showClearConfirmation = true
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .buttonStyle(.plain)
                    .confirmationDialog("Clear all uploads?", isPresented: $showClearConfirmation, titleVisibility: .visible) {
                        Button("Clear", role: .destructive) {
                            store.tasks.removeAll()
                        }
                        Button("Cancel", role: .cancel) { }
                    }
                }
            }

            if store.tasks.isEmpty {
                emptyState
            } else {
                VStack(spacing: 6) {
                    ForEach(store.tasks) { task in
                        TaskRow(task: task, onRetry: task.status == .failed ? { retryUpload(task: task) } : nil)
                    }
                }
            }
        }
    }

    var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "books.vertical")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary.opacity(0.2))
            Text("Drop archive.org links here")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.4))
            Text("Supports batch uploads")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.secondary.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: Settings Content (Inline)

    @State private var settingsDownloadPath = ""
    @State private var settingsCredentialsStatus = ""
    @State private var settingsDriveFolderID = ""
    @State private var settingsLMStudioURL = ""
    @State private var settingsLMStudioModel = ""
    @State private var settingsIsAuthenticating = false
    @State private var settingsAuthError = ""
    @State private var settingsEditingCredentials = false
    @State private var settingsEditorJSON = ""
    @State private var settingsEditorError = ""

    var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                lmStudioSettingsSection
                Divider()
                credentialsSettingsSection
                Divider()
                driveFolderSettingsSection
                Divider()
                downloadFolderSettingsSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .frame(maxHeight: 380)
        .onAppear {
            loadInlineSettings()
        }
    }

    var lmStudioSettingsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            settingsSectionHeader(icon: "cpu", title: "LM Studio")
            VStack(alignment: .leading, spacing: 5) {
                settingsLabelField(icon: "network", label: "URL", text: $settingsLMStudioURL, placeholder: "http://localhost:1234/v1")
                    .onChange(of: settingsLMStudioURL) { _, newValue in
                        AppConfig.lmStudioURL = newValue.isEmpty ? "http://localhost:1234/v1" : newValue
                    }
                settingsLabelField(icon: "tag", label: "Model", text: $settingsLMStudioModel, placeholder: "local-model")
                    .onChange(of: settingsLMStudioModel) { _, newValue in
                        AppConfig.lmStudioModel = newValue.isEmpty ? "local-model" : newValue
                    }
            }
            Text("Local LLM for metadata extraction")
                .font(.system(size: 9))
                .foregroundStyle(.secondary.opacity(0.5))
        }
    }

    var credentialsSettingsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            settingsSectionHeader(icon: "key", title: "Google Drive")

            HStack(spacing: 6) {
                Image(systemName: settingsCredentialsStatus.isEmpty ? "exclamationmark.triangle" : "checkmark")
                    .font(.system(size: 10))
                    .foregroundStyle(settingsCredentialsStatus.isEmpty ? .secondary : .primary)
                Text(settingsCredentialsStatus.isEmpty ? "Not configured" : settingsCredentialsStatus)
                    .font(.system(size: 10))
                    .foregroundStyle(settingsCredentialsStatus.isEmpty ? .secondary : .primary)
                Spacer()
            }

            if settingsEditingCredentials {
                VStack(alignment: .leading, spacing: 6) {
                    TextEditor(text: $settingsEditorJSON)
                        .font(.system(size: 10, design: .monospaced))
                        .frame(minHeight: 100, maxHeight: 100)
                        .padding(3)
                        .background(AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                        )
                        .onChange(of: settingsEditorJSON) { _, _ in
                            settingsEditorError = ""
                        }

                    if !settingsEditorError.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.red)
                            Text(settingsEditorError)
                                .font(.system(size: 9))
                                .foregroundStyle(.red)
                        }
                    }

                    HStack(spacing: 6) {
                        Button(action: { settingsEditingCredentials = false }) {
                            Text("Cancel")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(Color.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)

                        Button(action: saveInlineCredentials) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9))
                                Text("Save")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(AppTheme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            } else {
                HStack(spacing: 6) {
                    Button(action: { settingsEditingCredentials = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: settingsCredentialsStatus.isEmpty ? "plus" : "pencil")
                                .font(.system(size: 9))
                            Text(settingsCredentialsStatus.isEmpty ? "Add" : "Edit")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)

                    if !settingsCredentialsStatus.isEmpty {
                        Button(action: authenticateInlineDrive) {
                            HStack(spacing: 4) {
                                Image(systemName: "lock.open")
                                    .font(.system(size: 9))
                                Text(settingsIsAuthenticating ? "…" : "Auth")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(settingsIsAuthenticating ? Color.secondary : Color.green)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        .disabled(settingsIsAuthenticating)

                        Button(action: deleteInlineCredentials) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 9))
                                Text("Remove")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.red.opacity(0.25), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !settingsAuthError.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                    Text(settingsAuthError)
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                }
            }
        }
    }

    var driveFolderSettingsSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            settingsSectionHeader(icon: "folder.badge.person.crop", title: "Drive Folder")
            settingsLabelField(icon: "number", label: "ID", text: $settingsDriveFolderID, placeholder: "Optional")
                .onChange(of: settingsDriveFolderID) { _, newValue in
                    AppConfig.driveFolderID = newValue
                }
            Text("Blank = Drive root")
                .font(.system(size: 9))
                .foregroundStyle(.secondary.opacity(0.5))
        }
    }

    var downloadFolderSettingsSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            settingsSectionHeader(icon: "folder", title: "Downloads")
            HStack {
                Text(settingsDownloadPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Open") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: settingsDownloadPath))
                }
                .font(.system(size: 10, weight: .medium))
            }
        }
    }

    func settingsSectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .default))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
    }

    func settingsLabelField(icon: String, label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .font(.system(size: 11))
                .textFieldStyle(.plain)
            if !text.wrappedValue.isEmpty {
                Button(action: { text.wrappedValue = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary.opacity(0.4))
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }

    func loadInlineSettings() {
        settingsCredentialsStatus = FileManager.default.fileExists(atPath: AppConfig.credentialsPath.path) ? "Configured" : ""
        settingsDownloadPath = AppConfig.downloadDir.path
        settingsDriveFolderID = AppConfig.driveFolderID
        settingsLMStudioURL = AppConfig.lmStudioURL
        settingsLMStudioModel = AppConfig.lmStudioModel
    }

    func saveInlineCredentials() {
        let trimmed = settingsEditorJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            settingsEditorError = "Credentials cannot be empty."
            return
        }
        guard let data = trimmed.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            settingsEditorError = "Invalid JSON."
            return
        }
        do {
            try trimmed.write(to: AppConfig.credentialsPath, atomically: true, encoding: .utf8)
            settingsCredentialsStatus = "Configured"
            settingsEditingCredentials = false
            settingsEditorJSON = ""
        } catch {
            settingsEditorError = "Failed to save: \(error.localizedDescription)"
        }
    }

    func authenticateInlineDrive() {
        settingsIsAuthenticating = true
        settingsAuthError = ""
        Task { @MainActor in
            let client = GoogleDriveClient()
            do {
                try await client.authenticate()
                settingsIsAuthenticating = false
            } catch {
                settingsIsAuthenticating = false
                settingsAuthError = error.localizedDescription
            }
        }
    }

    func deleteInlineCredentials() {
        let client = GoogleDriveClient()
        client.deleteToken()
        try? FileManager.default.removeItem(at: AppConfig.credentialsPath)
        settingsCredentialsStatus = ""
    }

    // MARK: Actions

    func triggerProgressShake() {
        let values: [CGFloat] = [0, -6, 6, -4, 4, -2, 2, 0]
        for (i, v) in values.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.04) {
                withAnimation(.easeOut(duration: 0.04)) {
                    progressShake = v
                }
            }
        }
    }

    func triggerButtonShake() {
        let values: [CGFloat] = [0, -6, 6, -4, 4, -2, 2, 0]
        for (i, v) in values.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.04) {
                withAnimation(.easeOut(duration: 0.04)) {
                    buttonShake = v
                }
            }
        }
    }

    func pasteFromClipboard() {
        if let string = NSPasteboard.general.string(forType: .string) {
            urlInput = string
        }
    }

    func handleProviders(_ providers: [NSItemProvider]) async {
        var collected: [String] = []
        for provider in providers {
            do {
                let item: Any? = try await withCheckedThrowingContinuation { continuation in
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: item)
                        }
                    }
                }
                if let url = item as? URL {
                    collected.append(url.absoluteString)
                    continue
                } else if let string = item as? String, URL(string: string) != nil {
                    collected.append(string)
                    continue
                }
            } catch {
                do {
                    let item: Any? = try await withCheckedThrowingContinuation { continuation in
                        provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, error in
                            if let error = error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume(returning: item)
                            }
                        }
                    }
                    if let string = item as? String, URL(string: string) != nil {
                        collected.append(string)
                        continue
                    }
                } catch {
                    // ignore
                }
            }
        }
        guard !collected.isEmpty else { return }
        if urlInput.isEmpty {
            urlInput = collected.joined(separator: "\n")
        } else {
            urlInput += "\n" + collected.joined(separator: "\n")
        }
    }

    func parseURLs(from input: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",\n\r")
        let candidates = input.components(separatedBy: separators).map { $0.trimmingCharacters(in: .whitespaces) }
        return candidates.filter { !$0.isEmpty && $0.contains("archive.org") }
    }

    func previewMetadata() {
        guard !urlInput.isEmpty else { return }
        let urls = parseURLs(from: urlInput)
        guard let first = urls.first else {
            store.showError("No valid archive.org URLs found")
            return
        }
        urlInput = urls.dropFirst().joined(separator: "\n")
        Task { @MainActor in
            do {
                let metadata = try await pipeline.preview(url: first)
                store.addTask(url: first)
                if let task = store.tasks.first {
                    store.tasks[0].status = .reviewing
                    store.tasks[0].message = "Reviewing metadata..."
                    store.currentStatus = .reviewing
                    store.currentMessage = "Reviewing metadata..."
                    store.currentURL = first
                    store.prepareMetadataReview(taskID: task.id, metadata: metadata)
                }
            } catch {
                store.showError(error.localizedDescription)
            }
        }
    }

    func submitDirect() {
        guard !urlInput.isEmpty else { return }
        let urls = parseURLs(from: urlInput)
        guard !urls.isEmpty else {
            triggerButtonShake()
            urlInput = ""
            return
        }
        guard checkAuth() else { return }
        urlInput = ""
        queueCount = urls.count
        store.isProcessing = true

        Task { @MainActor in
            defer { store.isProcessing = false }
            for url in urls {
                let taskID = UUID()
                withAnimation(.spring(duration: 0.3)) {
                    store.addTask(url: url)
                }
                await runPipeline(url: url, taskID: taskID)
                queueCount -= 1
            }
        }
    }

    func runPipeline(url: String, taskID: UUID, metadata: ExtractedMetadata? = nil) async {
        do {
            let result = try await pipeline.run(url: url, metadata: metadata) { status, message, progress in
                store.updateTask(id: taskID, status: status, message: message, progress: progress)
                store.currentStatus = status
                store.currentMessage = message
                store.currentProgress = progress
            }
            withAnimation(.spring(duration: 0.3)) {
                store.updateTask(
                    id: taskID,
                    status: .completed,
                    message: "Uploaded to Drive",
                    title: result.title,
                    driveLink: result.driveLink
                )
            }
        } catch let error as ArchiveError {
            if case .alreadyExists = error {
                withAnimation(.spring(duration: 0.3)) {
                    store.updateTask(id: taskID, status: .failed, message: "Already exists")
                }
                triggerProgressShake()
            } else {
                withAnimation(.spring(duration: 0.3)) {
                    store.updateTask(id: taskID, status: .failed, message: error.localizedDescription)
                }
                store.showError(error.localizedDescription)
            }
        } catch {
            withAnimation(.spring(duration: 0.3)) {
                store.updateTask(id: taskID, status: .failed, message: error.localizedDescription)
            }
            store.showError(error.localizedDescription)
        }
    }

    func retryUpload(task: UploadTask) {
        guard checkAuth() else { return }
        let taskID = UUID()
        let url = task.url
        withAnimation(.spring(duration: 0.3)) {
            store.addTask(url: url)
        }
        Task { @MainActor in
            store.isProcessing = true
            await runPipeline(url: url, taskID: taskID)
            store.isProcessing = false
        }
    }

    func confirmUpload() {
        guard let metadata = store.pendingMetadata, let taskID = store.pendingTaskID else { return }
        guard checkAuth() else { return }
        store.completeMetadataReview()
        Task { @MainActor in
            store.isProcessing = true
            await runPipeline(url: store.currentURL, taskID: taskID, metadata: metadata)
            store.isProcessing = false
        }
    }

    func cancelUpload() {
        store.completeMetadataReview()
    }

    func checkAuth() -> Bool {
        let client = GoogleDriveClient()
        let authed = client.isAuthenticated
        if !authed {
            store.completeMetadataReview()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                showingSettings = true
            }
        }
        return authed
    }
}

// MARK: Step Dots

struct StepDots: View {
    let activeStep: UploadStatus
    let steps: [UploadStatus] = [.resolving, .extractingMetadata, .downloading, .uploading]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                Capsule()
                    .fill(stepColor(for: step))
                    .frame(width: step == activeStep ? 20 : 6, height: 3)
                    .animation(.easeInOut(duration: 0.25), value: activeStep)
            }
        }
    }

    func stepColor(for step: UploadStatus) -> Color {
        if step == activeStep { return AppTheme.accent }
        if steps.firstIndex(of: step) ?? 0 < steps.firstIndex(of: activeStep) ?? 0 {
            return .secondary.opacity(0.3)
        }
        return .secondary.opacity(0.1)
    }
}

// MARK: Task Row

struct TaskRow: View {
    let task: UploadTask
    let onRetry: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(statusColor)
                .frame(width: 22, height: 22)
                .background(statusColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 1) {
                Text(task.title ?? task.url.truncated(to: 32))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(task.message)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let link = task.driveLink, !link.isEmpty, let url = URL(string: link) {
                Button(action: {
                    NSWorkspace.shared.open(url)
                }) {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open in Google Drive")
            }

            if let retry = onRetry {
                Button(action: retry) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retry upload")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(AppTheme.subtleBorder, lineWidth: 1)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    var statusIcon: String {
        switch task.status {
        case .completed: return "checkmark"
        case .failed: return "xmark"
        case .downloading: return "arrow.down"
        case .uploading: return "arrow.up"
        case .idle: return "clock"
        default: return "ellipsis"
        }
    }

    var statusColor: Color {
        switch task.status {
        case .completed: return .secondary
        case .failed: return .red
        case .downloading, .uploading: return AppTheme.accent
        default: return .secondary
        }
    }
}

// MARK: Helpers

extension String {
    func truncated(to length: Int) -> String {
        if count > length {
            return String(prefix(length)) + "…"
        }
        return self
    }
}
