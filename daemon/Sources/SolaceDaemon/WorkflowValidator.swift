import Foundation

actor WorkflowValidator {
    private let mcpManager: MCPManager

    init(mcpManager: MCPManager) {
        self.mcpManager = mcpManager
    }

    func validate(workflow: WorkflowDefinition) async -> WorkflowValidationResult {
        let availableTools = await mcpManager.getTools()
        let toolMap: [String: MCPToolInfo] = Dictionary(
            availableTools.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var stepResults: [StepValidationResult] = []
        let allStepIds = Set(workflow.steps.map(\.id))

        for step in workflow.steps {
            var issues: [StepValidationIssue] = []

            // 1. Check tool exists
            guard let tool = toolMap[step.toolName] else {
                let suggestion = findSimilarToolName(step.toolName, in: availableTools)
                issues.append(StepValidationIssue(
                    field: "toolName",
                    severity: .error,
                    message: "Tool '\(step.toolName)' not found in any connected MCP server",
                    suggestion: suggestion
                ))
                stepResults.append(StepValidationResult(
                    stepId: step.id, stepName: step.name, valid: false, issues: issues
                ))
                continue
            }

            // 2. Check required inputs are present
            let requiredParams = extractRequiredParams(from: tool.inputSchema)
            let providedKeys = Set(step.inputTemplate.keys)
            for requiredParam in requiredParams {
                if !providedKeys.contains(requiredParam) {
                    issues.append(StepValidationIssue(
                        field: requiredParam,
                        severity: .error,
                        message: "Required parameter '\(requiredParam)' is missing",
                        suggestion: describeParam(requiredParam, in: tool.inputSchema)
                    ))
                }
            }

            // 3. Check for empty values in provided inputs
            for (key, value) in step.inputTemplate {
                let resolved = value.resolve(with: [:])
                if resolved.isEmpty && !containsTemplateRef(value) {
                    issues.append(StepValidationIssue(
                        field: key,
                        severity: .warning,
                        message: "Parameter '\(key)' has an empty value",
                        suggestion: nil
                    ))
                }
            }

            // 4. Check parameter names match schema
            let allSchemaParams = extractAllParams(from: tool.inputSchema)
            if !allSchemaParams.isEmpty {
                for key in providedKeys {
                    if !allSchemaParams.contains(key) {
                        issues.append(StepValidationIssue(
                            field: key,
                            severity: .warning,
                            message: "Parameter '\(key)' is not in the tool's schema",
                            suggestion: "Valid parameters: \(allSchemaParams.sorted().joined(separator: ", "))"
                        ))
                    }
                }
            }

            // 5. Check dependsOn references
            for dep in step.dependsOn ?? [] {
                if !allStepIds.contains(dep) {
                    issues.append(StepValidationIssue(
                        field: "dependsOn",
                        severity: .error,
                        message: "Depends on non-existent step '\(dep)'",
                        suggestion: nil
                    ))
                }
            }

            stepResults.append(StepValidationResult(
                stepId: step.id,
                stepName: step.name,
                valid: !issues.contains(where: { $0.severity == .error }),
                issues: issues
            ))
        }

        let allValid = stepResults.allSatisfy(\.valid)
        return WorkflowValidationResult(
            workflowId: workflow.id,
            valid: allValid,
            stepResults: stepResults
        )
    }

    // MARK: - Helpers

    private func containsTemplateRef(_ value: StringOrVariable) -> Bool {
        switch value {
        case .variable: return true
        case .template: return true
        case .literal(let s): return s.contains("{{")
        }
    }

    private func extractRequiredParams(from schema: JSONValue) -> [String] {
        guard case .object(let obj) = schema,
              case .array(let reqArr) = obj["required"] else {
            return []
        }
        return reqArr.compactMap {
            if case .string(let s) = $0 { return s }
            return nil
        }
    }

    private func extractAllParams(from schema: JSONValue) -> Set<String> {
        guard case .object(let obj) = schema,
              case .object(let props) = obj["properties"] else {
            return []
        }
        return Set(props.keys)
    }

    private func findSimilarToolName(_ name: String, in tools: [MCPToolInfo]) -> String? {
        let nameLower = name.lowercased()
        var bestMatch: String?
        var bestScore = 0

        for tool in tools {
            let toolLower = tool.name.lowercased()
            let score = commonSubstringLength(nameLower, toolLower)
            if score > bestScore && score >= 3 {
                bestScore = score
                bestMatch = tool.name
            }
        }
        return bestMatch.map { "Did you mean '\($0)'?" }
    }

    private func commonSubstringLength(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        var maxLen = 0
        for i in 0..<aChars.count {
            for j in 0..<bChars.count {
                var len = 0
                while i + len < aChars.count && j + len < bChars.count && aChars[i + len] == bChars[j + len] {
                    len += 1
                }
                maxLen = max(maxLen, len)
            }
        }
        return maxLen
    }

    private func describeParam(_ name: String, in schema: JSONValue) -> String? {
        guard case .object(let obj) = schema,
              case .object(let props) = obj["properties"],
              case .object(let propObj) = props[name],
              case .string(let desc) = propObj["description"] else {
            return nil
        }
        return desc
    }
}
