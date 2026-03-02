import Foundation
import Observation

struct DiscoveredDaemon: Identifiable, Sendable {
    let id: String
    let name: String
    let host: String
    let port: UInt16

    var displayAddress: String { "\(host):\(port)" }
}

@Observable
@MainActor
final class BonjourBrowser {
    var discoveredDaemons: [DiscoveredDaemon] = []
    var isSearching = false
    var permissionDenied = false
    var debugStatus: String = "Starting..."

    private var delegate: BonjourDelegate?
    private var netServiceBrowser: NetServiceBrowser?
    private var pendingServices: [NetService] = []

    init() {
        startBrowsing()
    }

    func startBrowsing() {
        stopBrowsing()
        isSearching = true
        permissionDenied = false
        debugStatus = "Browsing..."

        let del = BonjourDelegate(owner: self)
        let browser = NetServiceBrowser()
        browser.delegate = del
        browser.searchForServices(ofType: "_solace._tcp.", inDomain: "local.")
        self.delegate = del
        self.netServiceBrowser = browser
    }

    func stopBrowsing() {
        netServiceBrowser?.stop()
        netServiceBrowser = nil
        delegate = nil
        pendingServices.removeAll()
        isSearching = false
    }

    fileprivate func handleWillSearch() {
        debugStatus = "Searching..."
        isSearching = true
    }

    fileprivate func handleDidNotSearch(_ errorDict: [String: NSNumber]) {
        debugStatus = "Search failed: \(errorDict)"
        isSearching = false
    }

    fileprivate func handleDidFind(name: String, type: String, domain: String) {
        debugStatus = "Found: \(name) — resolving..."
        let service = NetService(domain: domain, type: type, name: name)
        pendingServices.append(service)
        service.delegate = delegate
        service.resolve(withTimeout: 5.0)
    }

    fileprivate func handleDidRemove(name: String) {
        discoveredDaemons.removeAll { $0.name == name }
        pendingServices.removeAll { $0.name == name }
    }

    fileprivate func handleStopSearch() {
        isSearching = false
        debugStatus = "Search stopped"
    }

    fileprivate func handleDidResolve(name: String, hostName: String, port: Int) {
        pendingServices.removeAll { $0.name == name }

        guard port > 0 else {
            debugStatus = "Resolved \(name) but port=0"
            return
        }

        let daemon = DiscoveredDaemon(
            id: "\(name).\(hostName):\(port)",
            name: name,
            host: hostName,
            port: UInt16(port)
        )

        if !discoveredDaemons.contains(where: { $0.name == name }) {
            discoveredDaemons.append(daemon)
        }
        debugStatus = "Resolved: \(hostName):\(port)"
    }

    fileprivate func handleDidNotResolve(name: String, error: [String: NSNumber]) {
        pendingServices.removeAll { $0.name == name }
        debugStatus = "Resolve failed for \(name): \(error)"
    }
}

// MARK: - Non-isolated delegate that bridges to @MainActor BonjourBrowser

private final class BonjourDelegate: NSObject, NetServiceBrowserDelegate, NetServiceDelegate, @unchecked Sendable {
    private weak var owner: BonjourBrowser?

    init(owner: BonjourBrowser) {
        self.owner = owner
    }

    // MARK: NetServiceBrowserDelegate

    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        Task { @MainActor [owner] in owner?.handleWillSearch() }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        Task { @MainActor [owner] in owner?.handleDidNotSearch(errorDict) }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        let name = service.name
        let type = service.type
        let domain = service.domain
        Task { @MainActor [owner] in owner?.handleDidFind(name: name, type: type, domain: domain) }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        let name = service.name
        Task { @MainActor [owner] in owner?.handleDidRemove(name: name) }
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        Task { @MainActor [owner] in owner?.handleStopSearch() }
    }

    // MARK: NetServiceDelegate

    func netServiceDidResolveAddress(_ service: NetService) {
        let name = service.name
        let port = service.port
        let hostName = service.hostName ?? ""
        Task { @MainActor [owner] in owner?.handleDidResolve(name: name, hostName: hostName, port: port) }
    }

    func netService(_ service: NetService, didNotResolve errorDict: [String: NSNumber]) {
        let name = service.name
        Task { @MainActor [owner] in owner?.handleDidNotResolve(name: name, error: errorDict) }
    }
}
