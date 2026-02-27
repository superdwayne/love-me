import Foundation

// MARK: - Polling Errors

enum EmailPollingError: Error, LocalizedError {
    case notConfigured
    case alreadyRunning
    case clientNotAvailable

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Email polling cannot start: email is not configured"
        case .alreadyRunning:
            return "Email polling is already running"
        case .clientNotAvailable:
            return "Gmail client is not available"
        }
    }
}

/// Polls Gmail for new messages on a configurable interval, publishes events to `EventBus`,
/// and invokes an `onEmailReceived` callback for each new message.
///
/// State (last-seen message ID/timestamp) is persisted to the specified state file path
/// so polling resumes correctly after daemon restarts. API errors are handled with
/// exponential backoff (1s -> 2s -> 4s -> 8s max).
actor EmailPollingService {

    // MARK: - Dependencies

    private let gmailClient: GmailClient
    private let eventBus: EventBus
    private let configStore: EmailConfigStore

    // MARK: - Configuration

    private let stateFilePath: String

    // MARK: - State

    private var pollingState: EmailPollingState
    private var pollingTask: Task<Void, Never>?
    private var isRunning: Bool = false

    /// Current backoff delay in seconds; reset to 0 after a successful poll.
    private var currentBackoffSeconds: TimeInterval = 0

    /// Maximum backoff ceiling (8 seconds).
    private static let maxBackoffSeconds: TimeInterval = 8

    // MARK: - Callbacks

    /// Signature for the email-received handler.
    typealias EmailHandler = @Sendable (EmailMessage) async -> Void

    /// Called for each new `EmailMessage` fetched during a poll cycle.
    /// Set via `setOnEmailReceived(_:)` before calling `start()`.
    private var onEmailReceived: EmailHandler?

    // MARK: - JSON Coding

    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }()

    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    // MARK: - Init

    /// - Parameters:
    ///   - gmailClient: The Gmail API client for fetching messages.
    ///   - eventBus: The event bus for publishing `WorkflowEvent`s.
    ///   - configStore: The email configuration store (provides polling interval).
    ///   - statePath: Full file path for persisting `EmailPollingState` (e.g. `~/.love-me/email-state.json`).
    init(gmailClient: GmailClient, eventBus: EventBus, configStore: EmailConfigStore, statePath: String) {
        self.gmailClient = gmailClient
        self.eventBus = eventBus
        self.configStore = configStore
        self.stateFilePath = statePath
        self.pollingState = EmailPollingState()
    }

    // MARK: - Public API

    /// Set the callback invoked for each new email. This is how `EmailConversationBridge` receives emails.
    ///
    /// The handler is called once per new email, from within the polling actor's context.
    func setOnEmailReceived(_ handler: @escaping EmailHandler) {
        self.onEmailReceived = handler
    }

    /// Start the polling loop. Loads persisted state and begins periodic fetches.
    /// Logs a warning and returns if email is not configured or polling is already active.
    func start() async {
        guard !isRunning else {
            Logger.info("EmailPollingService: already running, ignoring start()")
            return
        }

        guard let config = await configStore.load() else {
            Logger.error("EmailPollingService: cannot start — email not configured")
            return
        }

        // Load persisted state (ignore errors — start fresh if missing/corrupt)
        loadState()

        isRunning = true
        currentBackoffSeconds = 0
        let intervalSeconds = config.pollingIntervalSeconds

        Logger.info("EmailPollingService: starting with \(intervalSeconds)s interval")

        pollingTask = Task { [weak self] in
            guard let self = self else { return }

            while !Task.isCancelled {
                await self.pollOnce()

                // Determine sleep duration (normal interval + any backoff)
                let backoff = await self.currentBackoffSeconds
                let sleepDuration = TimeInterval(intervalSeconds) + backoff
                try? await Task.sleep(nanoseconds: UInt64(sleepDuration * 1_000_000_000))
            }
        }
    }

    /// Stop the polling loop and persist current state.
    func stop() {
        guard isRunning else { return }

        pollingTask?.cancel()
        pollingTask = nil
        isRunning = false
        currentBackoffSeconds = 0
        persistState()

        Logger.info("EmailPollingService: stopped")
    }

    /// Whether the service is currently polling.
    var running: Bool {
        isRunning
    }

    /// Return a snapshot of the current polling state (for status reporting).
    func getState() -> EmailPollingState {
        pollingState
    }

    /// Trigger an immediate poll and return the number of new emails processed.
    /// This is used by the "poll now" WebSocket command for on-demand checks.
    func pollNow() async -> Int {
        let beforeCount = pollingState.totalProcessed
        await pollOnce()
        return pollingState.totalProcessed - beforeCount
    }

    // MARK: - Polling Logic

    /// Execute a single poll cycle: fetch new messages, process them, persist state.
    private func pollOnce() async {
        do {
            let query = buildQuery()
            let (summaries, _) = try await gmailClient.listMessages(query: query, maxResults: 20, pageToken: nil)

            if summaries.isEmpty {
                Logger.info("EmailPollingService: poll complete, no new emails")
                resetBackoff()
                return
            }

            Logger.info("EmailPollingService: poll found \(summaries.count) new message(s)")

            // Process each message (newest messages come first from Gmail; process oldest first)
            for summary in summaries.reversed() {
                // Skip if we already processed this message
                if let lastId = pollingState.lastSeenMessageId, summary.id == lastId {
                    continue
                }

                do {
                    let message = try await gmailClient.getMessage(id: summary.id)
                    await processNewEmail(message)
                } catch {
                    Logger.error("EmailPollingService: failed to fetch message \(summary.id): \(error)")
                    // Continue processing other messages
                }
            }

            // Update last-seen marker to the newest message
            if let newest = summaries.first {
                pollingState.lastSeenMessageId = newest.id
                pollingState.lastSeenTimestamp = Date()
            }

            persistState()
            resetBackoff()

        } catch {
            Logger.error("EmailPollingService: poll failed: \(error)")
            applyBackoff()
        }
    }

    /// Build the Gmail search query. Uses `after:` timestamp if we have a last-seen date,
    /// otherwise fetches recent messages.
    private func buildQuery() -> String {
        if let lastTimestamp = pollingState.lastSeenTimestamp {
            // Gmail "after:" uses epoch seconds
            let epoch = Int(lastTimestamp.timeIntervalSince1970)
            return "after:\(epoch)"
        }
        // First poll: only fetch emails from the last hour to avoid flooding
        let oneHourAgo = Int(Date().timeIntervalSince1970) - 3600
        return "after:\(oneHourAgo)"
    }

    /// Process a single new email: publish event to EventBus and invoke callback.
    private func processNewEmail(_ message: EmailMessage) async {
        pollingState.totalProcessed += 1

        // Publish workflow event to EventBus
        let event = WorkflowEvent(
            source: "email",
            eventType: "email_received",
            data: [
                "messageId": message.id,
                "threadId": message.threadId,
                "from": message.from,
                "subject": message.subject,
            ]
        )
        await eventBus.publish(event)

        // Invoke the direct callback (used by EmailConversationBridge)
        if let callback = onEmailReceived {
            await callback(message)
        }

        Logger.info("EmailPollingService: processed email '\(message.subject)' from \(message.from)")
    }

    // MARK: - Backoff

    /// Apply exponential backoff: 1s -> 2s -> 4s -> 8s (max).
    private func applyBackoff() {
        if currentBackoffSeconds == 0 {
            currentBackoffSeconds = 1
        } else {
            currentBackoffSeconds = min(currentBackoffSeconds * 2, Self.maxBackoffSeconds)
        }
        Logger.info("EmailPollingService: backing off for \(currentBackoffSeconds)s")
    }

    /// Reset backoff after a successful poll.
    private func resetBackoff() {
        currentBackoffSeconds = 0
    }

    // MARK: - State Persistence

    /// Load polling state from disk. Silently defaults to fresh state if file is missing or corrupt.
    private func loadState() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: stateFilePath)) else {
            pollingState = EmailPollingState()
            return
        }
        do {
            pollingState = try decoder.decode(EmailPollingState.self, from: data)
            Logger.info("EmailPollingService: loaded state — lastSeenId=\(pollingState.lastSeenMessageId ?? "none"), totalProcessed=\(pollingState.totalProcessed)")
        } catch {
            Logger.error("EmailPollingService: failed to decode state file, starting fresh: \(error)")
            pollingState = EmailPollingState()
        }
    }

    /// Persist current polling state to disk.
    private func persistState() {
        do {
            let data = try encoder.encode(pollingState)
            try data.write(to: URL(fileURLWithPath: stateFilePath), options: .atomic)
        } catch {
            Logger.error("EmailPollingService: failed to persist state: \(error)")
        }
    }
}
