import Foundation

/// Persistence layer for pending email approvals.
///
/// Approvals are stored as a JSON dictionary at `~/.solace/email-approvals.json`.
/// Stale pending approvals older than 24 hours are pruned on init.
actor EmailApprovalStore {

    // MARK: - State

    private var approvals: [String: PendingEmailApproval] = [:]
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

    init(basePath: String) {
        self.filePath = "\(basePath)/email-approvals.json"

        // Load from disk
        if let data = try? Data(contentsOf: URL(fileURLWithPath: self.filePath)),
           let loaded = try? self.decoder.decode([String: PendingEmailApproval].self, from: data) {
            self.approvals = loaded
        }

        // Prune stale pending approvals (older than 24 hours)
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        var pruned = 0
        for (id, approval) in approvals {
            if approval.status == .pending && approval.createdAt < cutoff {
                approvals.removeValue(forKey: id)
                pruned += 1
            }
        }
        if pruned > 0 {
            Logger.info("EmailApprovalStore: pruned \(pruned) stale pending approval(s)")
            if let data = try? self.encoder.encode(self.approvals) {
                try? data.write(to: URL(fileURLWithPath: self.filePath), options: .atomic)
            }
        }
    }

    // MARK: - Public API

    func add(_ approval: PendingEmailApproval) throws {
        approvals[approval.id] = approval
        try persistToDisk()
        Logger.info("EmailApprovalStore: added approval \(approval.id) (\(approval.classification.rawValue))")
    }

    func get(id: String) -> PendingEmailApproval? {
        approvals[id]
    }

    func update(id: String, status: ApprovalStatus) throws {
        guard approvals[id] != nil else { return }
        approvals[id]?.status = status
        try persistToDisk()
        Logger.info("EmailApprovalStore: updated approval \(id) -> \(status.rawValue)")
    }

    func remove(id: String) throws {
        approvals.removeValue(forKey: id)
        try persistToDisk()
    }

    func listPending() -> [PendingEmailApproval] {
        approvals.values.filter { $0.status == .pending }.sorted { $0.createdAt > $1.createdAt }
    }

    func listAll() -> [PendingEmailApproval] {
        approvals.values.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Persistence

    private func persistToDisk() throws {
        let data = try encoder.encode(approvals)
        try data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
    }
}
