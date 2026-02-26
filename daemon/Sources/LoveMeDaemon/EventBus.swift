import Foundation

/// An event emitted by an MCP server or polling source that can trigger workflows.
struct WorkflowEvent: Sendable {
    let source: String      // MCP server name
    let eventType: String   // e.g., "file_changed", "new_email"
    let data: [String: String]
    let timestamp: Date

    init(source: String, eventType: String, data: [String: String] = [:], timestamp: Date = Date()) {
        self.source = source
        self.eventType = eventType
        self.data = data
        self.timestamp = timestamp
    }
}

/// Manages event subscriptions and dispatches events to registered handlers.
actor EventBus {
    typealias EventHandler = @Sendable (WorkflowEvent) async -> Void

    /// eventKey -> list of (id, handler) pairs
    private var subscriptions: [String: [(id: String, handler: EventHandler)]] = [:]

    // MARK: - Public API

    /// Subscribe to events matching a specific source and event type.
    func subscribe(source: String, eventType: String, id: String, handler: @escaping EventHandler) {
        let key = eventKey(source: source, eventType: eventType)
        subscriptions[key, default: []].append((id: id, handler: handler))
        Logger.info("EventBus: subscribed \(id) to \(key)")
    }

    /// Remove a subscription by its ID.
    func unsubscribe(id: String) {
        for key in subscriptions.keys {
            subscriptions[key]?.removeAll { $0.id == id }
            if subscriptions[key]?.isEmpty == true {
                subscriptions.removeValue(forKey: key)
            }
        }
        Logger.info("EventBus: unsubscribed \(id)")
    }

    /// Publish an event, invoking all matching handlers.
    func publish(_ event: WorkflowEvent) async {
        let key = eventKey(source: event.source, eventType: event.eventType)
        Logger.info("EventBus: publishing \(key) with \(event.data.count) data entries")

        guard let handlers = subscriptions[key] else { return }

        for (handlerId, handler) in handlers {
            Logger.info("EventBus: dispatching \(key) to handler \(handlerId)")
            await handler(event)
        }
    }

    // MARK: - Private

    private func eventKey(source: String, eventType: String) -> String {
        "\(source):\(eventType)"
    }
}
