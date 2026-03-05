import SwiftUI

enum StepTemplateCategory: String, CaseIterable, Identifiable {
    case aiContent = "AI & Content"
    case filesData = "Files & Data"
    case communication = "Communication"
    case custom = "Custom"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .aiContent: return "brain.head.profile"
        case .filesData: return "doc.text"
        case .communication: return "paperplane"
        case .custom: return "gearshape"
        }
    }

    var color: Color {
        switch self {
        case .aiContent: return .coral
        case .filesData: return .warning
        case .communication: return .success
        case .custom: return .info
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
            name: "Generate Text",
            description: "Use AI to generate or transform text content",
            category: .aiContent,
            icon: "brain.head.profile",
            iconColor: .coral,
            toolName: "generate_text",
            defaultInputs: ["prompt": ""]
        ),
        StepTemplate(
            name: "Read File",
            description: "Read contents from a file path",
            category: .filesData,
            icon: "doc.text",
            iconColor: .warning,
            toolName: "read_file",
            defaultInputs: ["path": ""]
        ),
        StepTemplate(
            name: "Write File",
            description: "Write content to a file path",
            category: .filesData,
            icon: "doc.text.fill",
            iconColor: .warning,
            toolName: "write_file",
            defaultInputs: ["path": "", "content": ""]
        ),
        StepTemplate(
            name: "Run Command",
            description: "Execute a shell command",
            category: .filesData,
            icon: "terminal",
            iconColor: .info,
            toolName: "run_command",
            defaultInputs: ["command": ""]
        ),
        StepTemplate(
            name: "Send Email",
            description: "Send an email message",
            category: .communication,
            icon: "paperplane",
            iconColor: .success,
            toolName: "send_email",
            defaultInputs: ["to": "", "subject": "", "body": ""]
        ),
        StepTemplate(
            name: "HTTP Request",
            description: "Make an HTTP request to an API endpoint",
            category: .filesData,
            icon: "network",
            iconColor: .info,
            toolName: "http_request",
            defaultInputs: ["url": "", "method": "GET"]
        ),
    ]

    static func fromMCPTools(_ tools: [MCPToolItem]) -> [StepTemplate] {
        tools.map { tool in
            let (icon, color) = WorkflowStepCard.toolIcon(for: tool.name)
            let category: StepTemplateCategory
            let lower = tool.name.lowercased()
            if lower.contains("ai") || lower.contains("generate") || lower.contains("llm") {
                category = .aiContent
            } else if lower.contains("email") || lower.contains("send") || lower.contains("mail") {
                category = .communication
            } else if lower.contains("file") || lower.contains("read") || lower.contains("write") || lower.contains("bash") || lower.contains("shell") {
                category = .filesData
            } else {
                category = .custom
            }

            return StepTemplate(
                name: tool.name,
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
