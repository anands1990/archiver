import Foundation

enum AppConfig {
    static var lmStudioURL: String {
        get { UserDefaults.standard.string(forKey: "lm_studio_url") ?? "http://localhost:1234/v1" }
        set { UserDefaults.standard.set(newValue, forKey: "lm_studio_url") }
    }

    static var lmStudioModel: String {
        get { UserDefaults.standard.string(forKey: "lm_studio_model") ?? "local-model" }
        set { UserDefaults.standard.set(newValue, forKey: "lm_studio_model") }
    }

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
}
