import Foundation
import Network

// MARK: - Gmail Auth Error

enum GmailAuthError: Error, LocalizedError, Sendable {
    case missingCredentials
    case serverStartFailed(String)
    case callbackTimeout
    case noCodeReceived
    case tokenExchangeFailed(String)
    case invalidTokenResponse

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Missing clientId or clientSecret for Gmail OAuth"
        case .serverStartFailed(let reason):
            return "Failed to start OAuth callback server: \(reason)"
        case .callbackTimeout:
            return "OAuth callback timed out waiting for authorization"
        case .noCodeReceived:
            return "No authorization code received in callback"
        case .tokenExchangeFailed(let reason):
            return "Token exchange failed: \(reason)"
        case .invalidTokenResponse:
            return "Invalid token response from Google OAuth"
        }
    }
}

// MARK: - Thread-safe once guard for continuation resumption

/// A Sendable guard that ensures a continuation is resumed exactly once,
/// safe to call from NWListener's non-isolated state callbacks.
private final class OnceGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    /// Returns `true` the first time it is called; `false` thereafter.
    func tryFire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}

// MARK: - Gmail Auth Service

actor GmailAuthService {
    private let clientId: String
    private let clientSecret: String
    private let configStore: EmailConfigStore
    private let session: URLSession

    private let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    private let authBaseURL = "https://accounts.google.com/o/oauth2/v2/auth"

    private static let scopes = [
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/gmail.send",
        "https://www.googleapis.com/auth/gmail.modify"
    ].joined(separator: " ")

    /// The NWListener used for the local callback server.
    private var listener: NWListener?

    /// Port the listener was started on (needed to build redirect_uri later).
    private var listenerPort: UInt16?

    /// Continuation to deliver the auth code from the callback handler to the waiting task.
    private var authCodeContinuation: CheckedContinuation<String, Error>?

    init(clientId: String, clientSecret: String, configStore: EmailConfigStore) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.configStore = configStore

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: sessionConfig)
    }

    // MARK: - Public API

    /// Start the OAuth2 authorization flow.
    /// Returns the Google authorization URL the user should open in a browser.
    /// Starts a local HTTP server on the given port to receive the redirect callback.
    func startAuthFlow(port: UInt16) async throws -> String {
        guard !clientId.isEmpty, !clientSecret.isEmpty else {
            throw GmailAuthError.missingCredentials
        }

        // Stop any existing server
        stopCallbackServer()

        let redirectURI = "http://localhost:\(port)/oauth/callback"

        // Build the authorization URL
        var components = URLComponents(string: authBaseURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]

        guard let authURL = components.url?.absoluteString else {
            throw GmailAuthError.serverStartFailed("Failed to build auth URL")
        }

        // Start the local callback server
        try await startCallbackServer(port: port)

        Logger.info("Gmail OAuth: auth flow started, callback server on port \(port)")
        return authURL
    }

    /// Wait for the OAuth callback and exchange the code for tokens.
    /// This blocks until the user completes the auth flow or a timeout occurs.
    func waitForCallback(timeoutSeconds: Int = 300) async throws -> EmailConfig {
        // Wait for the auth code from the callback server
        let code = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            self.authCodeContinuation = continuation

            // Set a timeout
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
                // If the continuation is still pending, time out
                if let pending = self.authCodeContinuation {
                    self.authCodeContinuation = nil
                    pending.resume(throwing: GmailAuthError.callbackTimeout)
                }
            }
        }

        Logger.info("Gmail OAuth: received auth code, exchanging for tokens...")
        let config = try await exchangeCodeForTokens(code: code)

        stopCallbackServer()
        return config
    }

    /// Exchange an authorization code for access and refresh tokens.
    func exchangeCodeForTokens(code: String) async throws -> EmailConfig {
        guard !clientId.isEmpty, !clientSecret.isEmpty else {
            throw GmailAuthError.missingCredentials
        }

        // Determine the redirect URI -- must match the one used in the auth URL.
        let port = listenerPort ?? 8095
        let redirectURI = "http://localhost:\(port)/oauth/callback"

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "code": code,
            "client_id": clientId,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code"
        ]
        request.httpBody = formEncode(bodyParams).data(using: .utf8)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailAuthError.invalidTokenResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GmailAuthError.tokenExchangeFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        struct TokenResponse: Codable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int
            let token_type: String
            let scope: String?
        }

        let tokenResponse: TokenResponse
        do {
            tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw GmailAuthError.invalidTokenResponse
        }

        guard let refreshToken = tokenResponse.refresh_token else {
            throw GmailAuthError.tokenExchangeFailed("No refresh_token in response (try revoking and re-authorizing)")
        }

        // Fetch the user's email address using the new access token
        let emailAddress = try await fetchEmailAddress(accessToken: tokenResponse.access_token)

        let tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))

        let config = EmailConfig(
            provider: .gmail,
            clientId: clientId,
            clientSecret: clientSecret,
            refreshToken: refreshToken,
            accessToken: tokenResponse.access_token,
            tokenExpiry: tokenExpiry,
            emailAddress: emailAddress
        )

        // Persist the config
        try await configStore.save(config)

        Logger.info("Gmail OAuth: tokens stored for \(emailAddress)")
        return config
    }

    /// Shut down the local callback server.
    func stopCallbackServer() {
        if let listener {
            listener.cancel()
            self.listener = nil
            self.listenerPort = nil
            Logger.info("Gmail OAuth: callback server stopped")
        }
    }

    // MARK: - Callback Server (NWListener)

    /// Start a minimal TCP listener that handles one HTTP request for the OAuth callback.
    private func startCallbackServer(port: UInt16) async throws {
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let newListener: NWListener
        do {
            newListener = try NWListener(using: parameters, on: nwPort)
        } catch {
            throw GmailAuthError.serverStartFailed(error.localizedDescription)
        }

        self.listener = newListener
        self.listenerPort = port

        // Use a continuation to wait for the listener to be ready.
        // OnceGuard ensures the continuation is resumed exactly once,
        // safe across NWListener's concurrent state callbacks.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let guard_ = OnceGuard()

            newListener.stateUpdateHandler = { [guard_] state in
                switch state {
                case .ready:
                    if guard_.tryFire() {
                        continuation.resume()
                    }
                case .failed(let error):
                    if guard_.tryFire() {
                        continuation.resume(throwing: GmailAuthError.serverStartFailed(error.localizedDescription))
                    }
                case .cancelled:
                    if guard_.tryFire() {
                        continuation.resume(throwing: GmailAuthError.serverStartFailed("Listener cancelled"))
                    }
                default:
                    break
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                Task {
                    await self.handleConnection(connection)
                }
            }

            newListener.start(queue: DispatchQueue(label: "love.me.oauth.callback"))
        }
    }

    /// Handle a single TCP connection: read the HTTP request, extract the code, send a response.
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: DispatchQueue(label: "love.me.oauth.conn"))

        // Read up to 8KB (more than enough for an OAuth callback GET request)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self else {
                connection.cancel()
                return
            }

            if let error {
                Logger.error("Gmail OAuth callback connection error: \(error)")
                connection.cancel()
                return
            }

            guard let data, let requestString = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            // Parse the HTTP request line to extract the code parameter
            let code = Self.extractAuthCode(from: requestString)

            // Build HTTP response
            let responseHTML: String
            let statusLine: String

            if code != nil {
                statusLine = "HTTP/1.1 200 OK"
                responseHTML = """
                <!DOCTYPE html>
                <html>
                <head><title>love.Me - Authentication Successful</title></head>
                <body style="font-family: -apple-system, sans-serif; text-align: center; padding-top: 80px;">
                <h1>Authentication successful!</h1>
                <p>You can close this window and return to love.Me.</p>
                </body>
                </html>
                """
            } else {
                statusLine = "HTTP/1.1 400 Bad Request"
                responseHTML = """
                <!DOCTYPE html>
                <html>
                <head><title>love.Me - Authentication Failed</title></head>
                <body style="font-family: -apple-system, sans-serif; text-align: center; padding-top: 80px;">
                <h1>Authentication failed</h1>
                <p>No authorization code received. Please try again.</p>
                </body>
                </html>
                """
            }

            let httpResponse = "\(statusLine)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(responseHTML.utf8.count)\r\nConnection: close\r\n\r\n\(responseHTML)"

            if let responseData = httpResponse.data(using: .utf8) {
                connection.send(content: responseData, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            } else {
                connection.cancel()
            }

            // Deliver the auth code to the waiting task
            Task {
                if let code {
                    await self.deliverAuthCode(code)
                } else {
                    await self.deliverAuthError(GmailAuthError.noCodeReceived)
                }
            }
        }
    }

    /// Extract the `code` query parameter from an HTTP GET request string.
    private static func extractAuthCode(from request: String) -> String? {
        // The first line looks like: GET /oauth/callback?code=...&scope=... HTTP/1.1
        guard let firstLine = request.split(separator: "\r\n").first ?? request.split(separator: "\n").first else {
            return nil
        }

        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        let path = String(parts[1])
        guard let urlComponents = URLComponents(string: path) else { return nil }

        return urlComponents.queryItems?.first(where: { $0.name == "code" })?.value
    }

    /// Deliver the auth code to the waiting continuation.
    private func deliverAuthCode(_ code: String) {
        if let continuation = authCodeContinuation {
            authCodeContinuation = nil
            continuation.resume(returning: code)
        }
    }

    /// Deliver an error to the waiting continuation.
    private func deliverAuthError(_ error: Error) {
        if let continuation = authCodeContinuation {
            authCodeContinuation = nil
            continuation.resume(throwing: error)
        }
    }

    // MARK: - Helpers

    /// Fetch the authenticated user's email address using the Gmail API profile endpoint.
    private func fetchEmailAddress(accessToken: String) async throws -> String {
        let profileURL = URL(string: "https://www.googleapis.com/gmail/v1/users/me/profile")!

        var request = URLRequest(url: profileURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GmailAuthError.tokenExchangeFailed("Failed to fetch user profile")
        }

        struct ProfileResponse: Codable {
            let emailAddress: String
        }

        let profile = try JSONDecoder().decode(ProfileResponse.self, from: data)
        return profile.emailAddress
    }

    /// URL-encode a dictionary as application/x-www-form-urlencoded.
    private func formEncode(_ params: [String: String]) -> String {
        params.map { key, value in
            let escapedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let escapedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(escapedKey)=\(escapedValue)"
        }.joined(separator: "&")
    }
}
