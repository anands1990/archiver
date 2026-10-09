import Foundation

/// Manages the IndicTrans2 Python sidecar as a child process: launches it,
/// polls `/health` until the model is ready, and tears it down on stop/quit.
@MainActor
@Observable
final class SidecarProcess {
    /// Process-wide instance so app termination can stop the child even when no
    /// window is holding a reference.
    static let shared = SidecarProcess()

    enum Status: Equatable {
        case stopped
        case starting
        case running
        case failed
    }

    private(set) var status: Status = .stopped
    private(set) var lastError: String = ""

    private var process: Process?
    private var monitor: Task<Void, Never>?
    private var client = TranslatorClient()

    var isRunning: Bool { status == .running }

    /// Launches the sidecar and polls until healthy (or the process dies).
    /// Returns once launched; readiness is reported via `status`.
    func start() {
        guard process == nil else { return }
        guard FileManager.default.fileExists(atPath: AppConfig.translatorScriptPath) else {
            status = .failed
            lastError = "Script not found: \(AppConfig.translatorScriptPath)"
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: AppConfig.translatorPython)
        proc.arguments = [
            AppConfig.translatorScriptPath,
            "--port", String(AppConfig.translatorPort),
            "--model", AppConfig.translatorModel,
        ]

        // Capture stderr so a failed launch has a useful message.
        let errPipe = Pipe()
        proc.standardError = errPipe
        proc.standardOutput = FileHandle(forWritingAtPath: "/dev/null")

        do {
            try proc.run()
        } catch {
            status = .failed
            lastError = "Could not launch \(AppConfig.translatorPython): \(error.localizedDescription)"
            return
        }

        process = proc
        status = .starting
        lastError = ""
        // Rebuild the client so a port change in Settings takes effect on Start.
        client = TranslatorClient(port: AppConfig.translatorPort)
        beginMonitoring(process: proc, errPipe: errPipe)
    }

    private func beginMonitoring(process: Process, errPipe: Pipe) {
        monitor?.cancel()
        monitor = Task { @MainActor [weak self] in
            guard let self else { return }
            let client = self.client
            // Health polling: model load (and first-run download) can take a while.
            let deadline = 600 // seconds
            var waited = 0
            while !Task.isCancelled, process.isRunning, waited < deadline {
                if await client.health() {
                    self.status = .running
                    self.lastError = ""
                    return
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                waited += 2
            }
            if !process.isRunning {
                self.status = .failed
                self.lastError = Self.readTail(errPipe) ?? "Translator process exited"
            } else if waited >= deadline {
                self.status = .failed
                self.lastError = "Translator did not become ready (still downloading or loading the model?)"
            }
        }
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        status = .stopped
        lastError = ""
    }

    private static func readTail(_ pipe: Pipe) -> String? {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        return s.isEmpty ? nil : String(s.suffix(500))
    }
}