import Foundation

// MARK: - Trigger Store Errors

enum EmailTriggerStoreError: Error, LocalizedError {
    case ruleNotFound(String)
    case duplicateRule(String)

    var errorDescription: String? {
        switch self {
        case .ruleNotFound(let id):
            return "Email trigger rule not found: \(id)"
        case .duplicateRule(let id):
            return "Email trigger rule already exists: \(id)"
        }
    }
}

/// Persistence layer for `EmailTriggerRule` definitions.
///
/// Rules are stored as a JSON array at the specified file path (e.g. `~/.love-me/email-triggers.json`).
/// All operations are thread-safe via the actor model.
actor EmailTriggerStore {

    // MARK: - State

    private var rules: [EmailTriggerRule] = []
    private let filePath: String

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

    /// - Parameter basePath: Base directory path (e.g. `~/.love-me`). The triggers file
    ///   will be stored at `<basePath>/email-triggers.json`.
    init(basePath: String) {
        self.filePath = "\(basePath)/email-triggers.json"

        // Load rules inline in init (synchronous file read is safe here --
        // we only touch stored properties before the actor becomes accessible).
        if let data = try? Data(contentsOf: URL(fileURLWithPath: self.filePath)),
           let loaded = try? self.decoder.decode([EmailTriggerRule].self, from: data) {
            self.rules = loaded
        }
    }

    // MARK: - Public API (CRUD)

    /// Return all trigger rules.
    func listAll() -> [EmailTriggerRule] {
        rules
    }

    /// Get a single rule by ID.
    ///
    /// - Throws: `EmailTriggerStoreError.ruleNotFound` if no rule matches the ID.
    func get(id: String) throws -> EmailTriggerRule {
        guard let rule = rules.first(where: { $0.id == id }) else {
            throw EmailTriggerStoreError.ruleNotFound(id)
        }
        return rule
    }

    /// Create a new trigger rule. The rule's `id` must be unique.
    ///
    /// - Throws: `EmailTriggerStoreError.duplicateRule` if a rule with the same ID already exists.
    func create(_ rule: EmailTriggerRule) throws {
        guard !rules.contains(where: { $0.id == rule.id }) else {
            throw EmailTriggerStoreError.duplicateRule(rule.id)
        }
        rules.append(rule)
        try persistToDisk()
        Logger.info("EmailTriggerStore: created rule \(rule.id) -> workflow \(rule.workflowId)")
    }

    /// Update an existing trigger rule. Matches by `id`.
    ///
    /// - Throws: `EmailTriggerStoreError.ruleNotFound` if no rule matches the ID.
    func update(_ rule: EmailTriggerRule) throws {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else {
            throw EmailTriggerStoreError.ruleNotFound(rule.id)
        }
        rules[index] = rule
        try persistToDisk()
        Logger.info("EmailTriggerStore: updated rule \(rule.id)")
    }

    /// Delete a trigger rule by ID.
    ///
    /// - Throws: `EmailTriggerStoreError.ruleNotFound` if no rule matches the ID.
    func delete(id: String) throws {
        guard let index = rules.firstIndex(where: { $0.id == id }) else {
            throw EmailTriggerStoreError.ruleNotFound(id)
        }
        rules.remove(at: index)
        try persistToDisk()
        Logger.info("EmailTriggerStore: deleted rule \(id)")
    }

    /// Return the number of stored rules.
    var count: Int {
        rules.count
    }

    /// Return only enabled rules.
    func enabledRules() -> [EmailTriggerRule] {
        rules.filter { $0.enabled }
    }

    // MARK: - Persistence

    /// Write the current rules array to disk atomically.
    private func persistToDisk() throws {
        let data = try encoder.encode(rules)
        try data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
    }
}
