import Foundation

/// Reads/writes email configuration to ~/.love-me/email.json with secure file permissions.
actor EmailConfigStore {
    private let filePath: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(basePath: String) {
        self.filePath = "\(basePath)/email.json"

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    /// Load the email configuration, or nil if not configured.
    func load() -> EmailConfig? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else {
            return nil
        }
        return try? decoder.decode(EmailConfig.self, from: data)
    }

    /// Save the email configuration with owner-only read/write permissions (0600).
    func save(_ config: EmailConfig) throws {
        let data = try encoder.encode(config)
        let url = URL(fileURLWithPath: filePath)
        try data.write(to: url, options: .atomic)

        // Set file permissions to 0600 (owner read/write only)
        let fm = FileManager.default
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: filePath)
    }

    /// Update only the access token and expiry (for token refresh).
    func updateTokens(accessToken: String, tokenExpiry: Date) throws {
        guard var config = load() else {
            throw EmailConfigError.notConfigured
        }
        config.accessToken = accessToken
        config.tokenExpiry = tokenExpiry
        try save(config)
    }

    /// Update the polling interval.
    func updatePollingInterval(_ seconds: Int) throws {
        guard var config = load() else {
            throw EmailConfigError.notConfigured
        }
        config.pollingIntervalSeconds = seconds
        try save(config)
    }

    /// Delete the configuration file (disconnect).
    func delete() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: filePath) {
            try fm.removeItem(atPath: filePath)
        }
    }

    /// Check if email is configured.
    var isConfigured: Bool {
        load() != nil
    }
}

enum EmailConfigError: Error, LocalizedError {
    case notConfigured
    case invalidTokenResponse
    case authFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Email is not configured"
        case .invalidTokenResponse:
            return "Invalid token response from OAuth2 provider"
        case .authFailed(let message):
            return "Authentication failed: \(message)"
        }
    }
}
