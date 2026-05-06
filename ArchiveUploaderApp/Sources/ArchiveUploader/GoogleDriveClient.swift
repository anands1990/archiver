import Foundation
import Security
import AppKit

struct GoogleCredentials: Codable {
    struct Installed: Codable {
        let client_id: String
        let client_secret: String
        let auth_uri: String
        let token_uri: String
        let redirect_uris: [String]
    }
    let installed: Installed
}

struct GoogleToken: Codable {
    var access_token: String
    var refresh_token: String?
    var token_type: String
    var expires_in: Int
    var expiry: Date?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        access_token = try container.decode(String.self, forKey: .access_token)
        refresh_token = try container.decodeIfPresent(String.self, forKey: .refresh_token)
        token_type = try container.decode(String.self, forKey: .token_type)
        expires_in = try container.decode(Int.self, forKey: .expires_in)
        expiry = try container.decodeIfPresent(Date.self, forKey: .expiry)
        if expiry == nil {
            expiry = Date().addingTimeInterval(TimeInterval(expires_in - 60))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(access_token, forKey: .access_token)
        try container.encodeIfPresent(refresh_token, forKey: .refresh_token)
        try container.encode(token_type, forKey: .token_type)
        try container.encode(expires_in, forKey: .expires_in)
        try container.encodeIfPresent(expiry, forKey: .expiry)
    }

    enum CodingKeys: String, CodingKey {
        case access_token, refresh_token, token_type, expires_in, expiry
    }
}

enum GoogleDriveError: Error, LocalizedError {
    case credentialsNotFound
    case invalidCredentials
    case authFailed(String)
    case uploadFailed(String)
    case noRefreshToken

    var errorDescription: String? {
        switch self {
        case .credentialsNotFound: return "Google credentials not found. Add them in Settings."
        case .invalidCredentials: return "Invalid credentials.json format"
        case .authFailed(let msg): return "Authentication failed: \(msg)"
        case .uploadFailed(let msg): return "Upload failed: \(msg)"
        case .noRefreshToken: return "No refresh token available. Re-authenticate in Settings."
        }
    }
}

final class GoogleDriveClient {
    private let session = URLSession.shared

    // MARK: - Credentials

    func loadCredentials() throws -> GoogleCredentials {
        let data = try Data(contentsOf: AppConfig.credentialsPath)
        return try JSONDecoder().decode(GoogleCredentials.self, from: data)
    }

    var hasCredentials: Bool {
        (try? loadCredentials()) != nil
    }

    var isAuthenticated: Bool {
        (try? loadToken()) != nil
    }

    // MARK: - Token Storage (Keychain)

    private func saveToken(_ token: GoogleToken) throws {
        let data = try JSONEncoder().encode(token)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "archive_uploader_google_token",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            // Fallback: save to file
            try data.write(to: AppConfig.tokenPath)
        }
    }

    private func loadToken() throws -> GoogleToken {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "archive_uploader_google_token",
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return try JSONDecoder().decode(GoogleToken.self, from: data)
        }
        // Fallback: read from file
        let data = try Data(contentsOf: AppConfig.tokenPath)
        return try JSONDecoder().decode(GoogleToken.self, from: data)
    }

    func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "archive_uploader_google_token",
        ]
        SecItemDelete(query as CFDictionary)
        try? FileManager.default.removeItem(at: AppConfig.tokenPath)
    }

    // MARK: - OAuth Flow

    func authenticate() async throws {
        let creds = try loadCredentials()

        // PKCE
        let codeVerifier = randomString(length: 128)
        let codeChallenge = base64URLEncode(SHA256(data: codeVerifier))
        let state = randomString(length: 32)

        // Start temporary callback server on a free port
        let server = TempHTTPServer(port: 0) { requestURL in
            // handled via continuation below
        }
        try server.start()
        let actualPort = server.actualPort
        guard actualPort > 0 else {
            throw GoogleDriveError.authFailed("Could not start callback server")
        }
        let redirectURI = "http://localhost:\(actualPort)"

        var components = URLComponents(string: creds.installed.auth_uri)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: creds.installed.client_id),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/drive"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]

        let code: String = try await withCheckedThrowingContinuation { continuation in
            server.onRequest = { requestURL in
                server.stop()
                if let c = URLComponents(url: requestURL, resolvingAgainstBaseURL: false),
                   let items = c.queryItems,
                   let codeItem = items.first(where: { $0.name == "code" })?.value {
                    continuation.resume(returning: codeItem)
                } else {
                    continuation.resume(throwing: GoogleDriveError.authFailed("No authorization code received"))
                }
            }
            NSWorkspace.shared.open(components.url!)
        }

        // Exchange code for token
        var tokenRequest = URLRequest(url: URL(string: creds.installed.token_uri)!)
        tokenRequest.httpMethod = "POST"
        tokenRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "code=\(code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? code)",
            "client_id=\(creds.installed.client_id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? creds.installed.client_id)",
            "client_secret=\(creds.installed.client_secret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? creds.installed.client_secret)",
            "redirect_uri=\(redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectURI)",
            "grant_type=authorization_code",
            "code_verifier=\(codeVerifier)",
        ].joined(separator: "&")
        tokenRequest.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: tokenRequest)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GoogleDriveError.authFailed(String(data: data, encoding: .utf8) ?? "Token exchange failed")
        }
        var token = try JSONDecoder().decode(GoogleToken.self, from: data)
        token.expiry = Date().addingTimeInterval(TimeInterval(token.expires_in - 60))
        try saveToken(token)
    }

    private func ensureValidToken() async throws -> String {
        var token = try loadToken()
        if let expiry = token.expiry, expiry <= Date() {
            token = try await refreshToken(token)
        }
        return token.access_token
    }

    private func refreshToken(_ token: GoogleToken) async throws -> GoogleToken {
        guard let refresh = token.refresh_token else {
            throw GoogleDriveError.noRefreshToken
        }
        let creds = try loadCredentials()

        var request = URLRequest(url: URL(string: creds.installed.token_uri)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "refresh_token=\(refresh)",
            "client_id=\(creds.installed.client_id)",
            "client_secret=\(creds.installed.client_secret)",
            "grant_type=refresh_token",
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GoogleDriveError.authFailed("Token refresh failed")
        }
        var newToken = try JSONDecoder().decode(GoogleToken.self, from: data)
        newToken.refresh_token = refresh
        newToken.expiry = Date().addingTimeInterval(TimeInterval(newToken.expires_in - 60))
        try saveToken(newToken)
        return newToken
    }

    // MARK: - Upload

    func uploadFile(_ fileURL: URL, filename: String? = nil, description: String = "") async throws -> String {
        let accessToken = try await ensureValidToken()
        let name = filename ?? fileURL.lastPathComponent

        let metadata: [String: Any] = [
            "name": name,
            "description": description,
        ].merging(AppConfig.driveFolderID.isEmpty ? [:] : ["parents": [AppConfig.driveFolderID]]) { _, new in new }

        let metadataData = try JSONSerialization.data(withJSONObject: metadata)

        let boundary = "----ArchiveUploaderBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let tempDir = FileManager.default.temporaryDirectory
        let bodyURL = tempDir.appendingPathComponent("gdrive_upload_\(UUID().uuidString).tmp")

        let headerData = "--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!
        let midData = "\r\n--\(boundary)\r\nContent-Type: application/pdf\r\n\r\n".data(using: .utf8)!
        let footerData = "\r\n--\(boundary)--\r\n".data(using: .utf8)!

        try Data().write(to: bodyURL)
        let handle = try FileHandle(forWritingTo: bodyURL)
        handle.write(headerData)
        handle.write(metadataData)
        handle.write(midData)

        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer {
            fileHandle.closeFile()
            try? FileManager.default.removeItem(at: bodyURL)
        }
        let chunkSize = 256 * 1024
        while let chunk = try? fileHandle.read(upToCount: chunkSize), !chunk.isEmpty {
            handle.write(chunk)
        }
        handle.write(footerData)
        handle.closeFile()

        var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.upload(for: request, fromFile: bodyURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw GoogleDriveError.uploadFailed("HTTP \(code): \(bodyStr)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["webViewLink"] as? String ?? "https://drive.google.com"
    }

    // MARK: - Helpers

    private func randomString(length: Int) -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    private func SHA256(data: String) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.data(using: .utf8)!.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.utf8.count), &hash)
        }
        return Data(hash)
    }

    private func base64URLEncode(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

import CommonCrypto

// MARK: - Temporary HTTP Server

private final class TempHTTPServer {
    let requestedPort: UInt16
    private var socketFD: Int32 = -1
    private var source: DispatchSourceRead?
    var onRequest: ((URL) -> Void)?

    init(port: UInt16, onRequest: @escaping (URL) -> Void) {
        self.requestedPort = port
        self.onRequest = onRequest
    }

    var actualPort: UInt16 {
        guard socketFD >= 0 else { return 0 }
        var addr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socketFD, $0, &addrLen)
            }
        }
        guard result == 0 else { return 0 }
        return UInt16(addr.sin_port.bigEndian)
    }

    func start() throws {
        socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw GoogleDriveError.authFailed("Socket creation failed") }

        var opt: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout.size(ofValue: opt)))

        var addr = sockaddr_in(
            sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
            sin_family: UInt8(AF_INET),
            sin_port: requestedPort.bigEndian,
            sin_addr: in_addr(s_addr: INADDR_ANY),
            sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
        )

        guard withUnsafePointer(to: &addr, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }) else {
            close(socketFD)
            throw GoogleDriveError.authFailed("Bind failed")
        }

        guard listen(socketFD, 1) == 0 else {
            close(socketFD)
            throw GoogleDriveError.authFailed("Listen failed")
        }

        source = DispatchSource.makeReadSource(fileDescriptor: socketFD, queue: .global())
        source?.setEventHandler { [weak self] in
            self?.handleConnection()
        }
        source?.resume()
    }

    private func handleConnection() {
        var clientAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let clientFD = withUnsafeMutablePointer(to: &clientAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                accept(socketFD, $0, &addrLen)
            }
        }
        guard clientFD >= 0 else { return }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let readLen = read(clientFD, &buffer, 4096)
        guard readLen > 0 else {
            close(clientFD)
            return
        }

        let request = String(bytes: buffer[0..<readLen], encoding: .utf8) ?? ""
        if let line = request.split(separator: "\r\n").first,
           let path = line.split(separator: " ").dropFirst().first {
            let urlString = "http://localhost:\(actualPort)\(path)"
            if let url = URL(string: String(urlString)) {
                DispatchQueue.main.async { [weak self] in
                    self?.onRequest?(url)
                }
            }
        }

        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n<html><body><h2>Authorization successful!</h2><p>You can close this window and return to Archiver.</p></body></html>"
        _ = response.data(using: .utf8)?.withUnsafeBytes {
            write(clientFD, $0.baseAddress, $0.count)
        }
        close(clientFD)
    }

    func stop() {
        source?.cancel()
        if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }
    }
}
