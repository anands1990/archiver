import Foundation

enum AppConfig {
    static var driveFolderID: String {
        get { UserDefaults.standard.string(forKey: "drive_folder_id") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "drive_folder_id") }
    }

    static var downloadDir: URL {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/archive-books")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var configDir: URL {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/archive-uploader")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var credentialsPath: URL { configDir.appendingPathComponent("credentials.json") }
    static var tokenPath: URL { configDir.appendingPathComponent("token.json") }

    // MARK: - Translator (IndicTrans2 sidecar)

    static var translatorEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "translator_enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "translator_enabled") }
    }

    static var translatorPython: String {
        get {
            if let saved = UserDefaults.standard.string(forKey: "translator_python"),
               !saved.isEmpty,
               FileManager.default.isExecutableFile(atPath: saved) {
                return saved
            }
            return defaultPythonPath
        }
        set {
            UserDefaults.standard.set(absolutePythonPath(newValue), forKey: "translator_python")
        }
    }

    static var translatorScriptPath: String {
        get { UserDefaults.standard.string(forKey: "translator_script_path") ?? defaultScriptPath }
        set { UserDefaults.standard.set(newValue, forKey: "translator_script_path") }
    }

    static var translatorModel: String {
        get { UserDefaults.standard.string(forKey: "translator_model") ?? "ai4bharat/indictrans2-indic-en-dist-200M" }
        set { UserDefaults.standard.set(newValue, forKey: "translator_model") }
    }

    static var translatorPort: Int {
        get { (UserDefaults.standard.object(forKey: "translator_port") as? Int) ?? 8765 }
        set { UserDefaults.standard.set(newValue, forKey: "translator_port") }
    }

    static var translatorSrcLang: String {
        get { UserDefaults.standard.string(forKey: "translator_src_lang") ?? "san_Deva" }
        set { UserDefaults.standard.set(newValue, forKey: "translator_src_lang") }
    }

    /// The two model sizes offered in Settings. Both are the same IndicTrans2
    /// family, so `rawValue` is the model name passed to the sidecar.
    enum TranslatorModelChoice: String, CaseIterable, Identifiable {
        case standard   // ~900 MB, the default
        case large      // ~4 GB
        case custom

        var id: String { rawValue }

        static let standardName = "ai4bharat/indictrans2-indic-en-dist-200M"
        static let largeName = "ai4bharat/indictrans2-indic-en-1B"

        /// The model this choice loads, or `nil` when the user supplies their own.
        var model: String? {
            switch self {
            case .standard: return Self.standardName
            case .large: return Self.largeName
            case .custom: return nil
            }
        }

        /// Matches a stored model name back to a picker entry.
        init(modelName: String) {
            if modelName == Self.largeName {
                self = .large
            } else if modelName == Self.standardName {
                self = .standard
            } else {
                self = .custom
            }
        }

        var label: String {
            switch self {
            case .standard: return "200M"
            case .large: return "1B"
            case .custom: return "Custom"
            }
        }
    }

    static var ocrLang: String {
        get { UserDefaults.standard.string(forKey: "ocr_lang") ?? "san+deva" }
        set { UserDefaults.standard.set(newValue, forKey: "ocr_lang") }
    }

    /// Default location of the bundled Python sidecar. Resolves to a
    /// `translator/server.py` next to the app, falling back to the repo path.
    private static var defaultScriptPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let repoCandidate = home
            .appendingPathComponent("Developer/archive-uploader/translator/server.py")
        if FileManager.default.fileExists(atPath: repoCandidate.path) {
            return repoCandidate.path
        }
        return configDir.appendingPathComponent("translator/server.py").path
    }

    /// Prefers a `.venv/bin/python*` sitting next to the sidecar script (so the
    /// user's venv with the heavy ML deps is used automatically); falls back to
    /// common system Python locations, then the bare `python3` command as a last
    /// resort (which will need to be edited to an absolute path to actually run).
    private static var defaultPythonPath: String {
        let scriptPath = translatorScriptPath
        if FileManager.default.fileExists(atPath: scriptPath) {
            let scriptDir = (scriptPath as NSString).deletingLastPathComponent
            let venvCandidates = ["python", "python3", "python3.11"].map {
                (scriptDir as NSString).appendingPathComponent(".venv/bin/\($0)")
            }
            if let venvPython = venvCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
                return venvPython
            }
        }

        // Common interpreters on macOS.
        let systemCandidates = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
        if let systemPython = systemCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return systemPython
        }

        return "python3"
    }

    /// Normalizes a user-provided Python value into an absolute executable path.
    /// Empty values reset to the default; bare command names are resolved against
    /// common install locations and the app’s PATH; absolute paths are validated
    /// as-is. Falls back to the input if it cannot be resolved.
    private static func absolutePythonPath(_ value: String) -> String {
        guard !value.isEmpty else { return defaultPythonPath }
        if FileManager.default.isExecutableFile(atPath: value) { return value }
        guard !value.contains("/") else { return value }

        let candidates = ["/opt/homebrew/bin/\(value)", "/usr/local/bin/\(value)", "/usr/bin/\(value)"]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }

        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        for dir in pathEnv.split(separator: ":") {
            let candidate = (String(dir) as NSString).appendingPathComponent(value)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return value
    }
}
