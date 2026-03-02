import Foundation

struct MCPServerInfo: Identifiable {
    let name: String
    let type: String  // "stdio" or "http"
    var enabled: Bool
    let toolCount: Int

    var id: String { name }
}
