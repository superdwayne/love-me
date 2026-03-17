import SwiftUI

enum StepTemplateCategory: String, CaseIterable, Identifiable {
    case create = "Create"
    case manage = "Manage"
    case connect = "Connect"
    case extend = "Extend"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .create: return "sparkles"
        case .manage: return "folder"
        case .connect: return "paperplane"
        case .extend: return "puzzlepiece.extension"
        }
    }

    var color: Color {
        switch self {
        case .create: return .coral
        case .manage: return .amberGlow
        case .connect: return .sageGreen
        case .extend: return .electricBlue
        }
    }
}

struct StepTemplate: Identifiable {
    let id: String
    let name: String
    let description: String
    let category: StepTemplateCategory
    let icon: String
    let iconColor: Color
    let toolName: String
    let serverName: String
    let defaultInputs: [String: String]

    init(
        id: String = UUID().uuidString,
        name: String,
        description: String,
        category: StepTemplateCategory,
        icon: String,
        iconColor: Color,
        toolName: String,
        serverName: String = "",
        defaultInputs: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.icon = icon
        self.iconColor = iconColor
        self.toolName = toolName
        self.serverName = serverName
        self.defaultInputs = defaultInputs
    }
}

enum StepTemplates {
    static let builtIn: [StepTemplate] = [
        StepTemplate(
            name: "Write with AI",
            description: "Draft, rewrite, or summarize any text",
            category: .create,
            icon: "sparkles",
            iconColor: .coral,
            toolName: "generate_text",
            defaultInputs: ["prompt": ""]
        ),
        StepTemplate(
            name: "Open a File",
            description: "Pull content from a document or file",
            category: .manage,
            icon: "doc.text",
            iconColor: .amberGlow,
            toolName: "read_file",
            defaultInputs: ["path": ""]
        ),
        StepTemplate(
            name: "Save to File",
            description: "Store results in a document",
            category: .manage,
            icon: "doc.text.fill",
            iconColor: .amberGlow,
            toolName: "write_file",
            defaultInputs: ["path": "", "content": ""]
        ),
        StepTemplate(
            name: "Run a Task",
            description: "Execute an action on your computer",
            category: .manage,
            icon: "terminal",
            iconColor: .electricBlue,
            toolName: "run_command",
            defaultInputs: ["command": ""]
        ),
        StepTemplate(
            name: "Send an Email",
            description: "Compose and deliver a message",
            category: .connect,
            icon: "paperplane.fill",
            iconColor: .sageGreen,
            toolName: "send_email",
            defaultInputs: ["to": "", "subject": "", "body": ""]
        ),
        StepTemplate(
            name: "Fetch from Web",
            description: "Pull data from any website or service",
            category: .connect,
            icon: "globe",
            iconColor: .electricBlue,
            toolName: "http_request",
            defaultInputs: ["url": "", "method": "GET"]
        ),
    ]

    static func humanizeName(_ rawName: String) -> String {
        rawName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    static func fromMCPTools(_ tools: [MCPToolItem]) -> [StepTemplate] {
        tools.map { tool in
            let (icon, color) = WorkflowStepCard.toolIcon(for: tool.name)
            let category: StepTemplateCategory
            let lower = tool.name.lowercased() + " " + tool.description.lowercased()
            if lower.contains("ai") || lower.contains("generate") || lower.contains("llm") || lower.contains("summarize") || lower.contains("translate") {
                category = .create
            } else if lower.contains("email") || lower.contains("send") || lower.contains("mail") || lower.contains("notify") || lower.contains("message") || lower.contains("webhook") || lower.contains("http") || lower.contains("fetch") || lower.contains("api") {
                category = .connect
            } else if lower.contains("file") || lower.contains("read") || lower.contains("write") || lower.contains("bash") || lower.contains("shell") || lower.contains("directory") || lower.contains("folder") {
                category = .manage
            } else {
                category = .extend
            }

            return StepTemplate(
                name: humanizeName(tool.name),
                description: tool.description,
                category: category,
                icon: icon,
                iconColor: color,
                toolName: tool.name,
                serverName: tool.serverName
            )
        }
    }

    static func merged(mcpTools: [MCPToolItem]) -> [StepTemplate] {
        let mcpTemplates = fromMCPTools(mcpTools)
        let mcpNames = Set(mcpTemplates.map { $0.toolName.lowercased() })
        let filteredBuiltIn = builtIn.filter { !mcpNames.contains($0.toolName.lowercased()) }
        return filteredBuiltIn + mcpTemplates
    }
}
