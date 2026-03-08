import Foundation

// MARK: - JSON-RPC 2.0

struct JSONRPCRequest: Codable, Sendable {
    let jsonrpc: String
    let id: Int
    let method: String
    let params: JSONValue?

    init(id: Int, method: String, params: JSONValue? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

struct JSONRPCResponse: Codable, Sendable {
    let jsonrpc: String
    let id: Int?
    let result: JSONValue?
    let error: JSONRPCError?
}

struct JSONRPCError: Codable, Sendable {
    let code: Int
    let message: String
    let data: JSONValue?
}

// MARK: - Tool I/O Types

enum ToolIOType: String, Codable, Sendable, CaseIterable {
    case text
    case image
    case file
    case json
    case audio
    case video
    case mesh3d
    case code
    case any
}

// MARK: - MCP Tool Info

struct MCPToolInfo: Sendable {
    let name: String
    let description: String
    let inputSchema: JSONValue
    let serverName: String
    let outputType: ToolIOType
    let acceptsInputTypes: [ToolIOType]
}

// MARK: - Tool Type Inference

enum ToolTypeInference {
    static func infer(name: String, description: String, inputSchema: JSONValue) -> (output: ToolIOType, accepts: [ToolIOType]) {
        let lower = name.lowercased()
        let descLower = description.lowercased()

        // Image generation/manipulation
        if lower.contains("generate_image") || lower.contains("create_image") || lower.contains("render")
            || lower.contains("screenshot") || lower.contains("export_png") || lower.contains("export_jpg")
            || descLower.contains("generates an image") || descLower.contains("render") {
            return (.image, [.text, .json, .any])
        }

        // Image input tools
        if lower.contains("describe_image") || lower.contains("analyze_image") || lower.contains("ocr") {
            return (.text, [.image])
        }

        // 3D/mesh tools
        if lower.contains("mesh") || lower.contains("3d") || lower.contains("model_export")
            || lower.contains("sculpt") || lower.contains("geometry") {
            return (.mesh3d, [.text, .json, .mesh3d, .any])
        }

        // Audio tools
        if lower.contains("audio") || lower.contains("speech") || lower.contains("tts")
            || lower.contains("voice") || lower.contains("sound") {
            return (.audio, [.text, .audio, .any])
        }

        // Video tools
        if lower.contains("video") || lower.contains("animate") || lower.contains("movie")
            || lower.contains("sequence") {
            return (.video, [.image, .text, .video, .any])
        }

        // Code tools
        if lower.contains("code") || lower.contains("compile") || lower.contains("script")
            || lower.contains("execute") || lower.contains("run_command") || lower.contains("bash")
            || lower.contains("shell") {
            return (.code, [.text, .code, .any])
        }

        // File tools
        if lower.contains("read_file") || lower.contains("get_file") || lower.contains("download") {
            return (.file, [.text, .any])
        }
        if lower.contains("write_file") || lower.contains("save_file") || lower.contains("upload") {
            return (.file, [.text, .file, .code, .any])
        }
        if lower.contains("file") || lower.contains("directory") || lower.contains("folder")
            || lower.contains("list_dir") || lower.contains("path") {
            return (.file, [.text, .file, .any])
        }

        // JSON/data tools
        if lower.contains("json") || lower.contains("parse") || lower.contains("transform")
            || lower.contains("query") || lower.contains("api") || lower.contains("fetch")
            || lower.contains("http") || lower.contains("request") {
            return (.json, [.text, .json, .any])
        }

        // Text generation/manipulation (broad catch)
        if lower.contains("generate") || lower.contains("text") || lower.contains("write")
            || lower.contains("summarize") || lower.contains("translate") || lower.contains("chat")
            || lower.contains("send") || lower.contains("email") || lower.contains("message") {
            return (.text, [.text, .any])
        }

        // Default: any → any
        return (.any, [.any])
    }
}

// MARK: - MCP Tool Call Result

struct MCPToolCallResult: Sendable {
    let content: String
    let isError: Bool
}

// MARK: - MCP Server Configuration (from mcp.json)

struct MCPConfigFile: Codable, Sendable {
    let mcpServers: [String: MCPServerConfig]
}

struct MCPServerConfig: Codable, Sendable {
    let command: String?
    let args: [String]?
    let env: [String: String]?
    let url: String?
    let headers: [String: String]?
    let enabled: Bool?
    let ollamaEnabled: Bool?

    /// Whether this is a stdio-based server (has command)
    var isStdio: Bool { command != nil }

    /// Resolved enabled state (defaults to true when nil)
    var isEnabled: Bool { enabled ?? true }

    /// Whether this server's tools are sent to Ollama (defaults to true when nil)
    var isOllamaEnabled: Bool { ollamaEnabled ?? true }
}
