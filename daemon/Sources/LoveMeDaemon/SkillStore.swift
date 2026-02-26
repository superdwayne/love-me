import Foundation

/// A skill definition parsed from a SKILL.md file
struct SkillDefinition: Sendable {
    let id: String
    let name: String
    let description: String
    let serverName: String?
    let body: String
}

/// Loads and manages Agent Skills from ~/.love-me/skills/*/SKILL.md
actor SkillStore {
    private let skillsDirectory: String
    private var skills: [String: SkillDefinition] = [:]

    init(skillsDirectory: String) {
        self.skillsDirectory = skillsDirectory
    }

    /// Load all skills from the skills directory
    func loadAll() {
        skills.removeAll()
        let fm = FileManager.default

        guard fm.fileExists(atPath: skillsDirectory) else {
            Logger.info("Skills directory not found at \(skillsDirectory)")
            return
        }

        guard let entries = try? fm.contentsOfDirectory(atPath: skillsDirectory) else {
            Logger.error("Failed to read skills directory")
            return
        }

        for entry in entries {
            let skillDir = "\(skillsDirectory)/\(entry)"
            let skillFile = "\(skillDir)/SKILL.md"

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: skillDir, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            guard fm.fileExists(atPath: skillFile) else {
                continue
            }

            guard let content = try? String(contentsOfFile: skillFile, encoding: .utf8) else {
                Logger.error("Failed to read skill file: \(skillFile)")
                continue
            }

            if let skill = parseSkill(id: entry, content: content) {
                skills[skill.id] = skill
                Logger.info("Loaded skill: \(skill.name) (server: \(skill.serverName ?? "none"))")
            }
        }

        Logger.info("Loaded \(skills.count) skill(s)")
    }

    /// Get a lightweight metadata summary for the system prompt (~100 tokens/skill)
    func getMetadataSummary() -> String? {
        guard !skills.isEmpty else { return nil }

        var lines = ["## Available Skills"]
        for skill in skills.values.sorted(by: { $0.name < $1.name }) {
            lines.append("- **\(skill.name)**: \(skill.description)")
        }
        return lines.joined(separator: "\n")
    }

    /// Get the full body content of a specific skill
    func getSkillContent(name: String) -> String? {
        skills[name]?.body
    }

    /// Get all skills that map to a specific MCP server name
    func skillsForServer(name: String) -> [SkillDefinition] {
        skills.values.filter { $0.serverName == name }
    }

    /// Get full skill content for all skills whose mapped server is active
    func getActiveSkillContent(activeServers: Set<String>) -> String? {
        let activeSkills = skills.values.filter { skill in
            guard let server = skill.serverName else { return false }
            return activeServers.contains(server)
        }.sorted(by: { $0.name < $1.name })

        guard !activeSkills.isEmpty else { return nil }

        var sections: [String] = []
        for skill in activeSkills {
            sections.append("## Skill: \(skill.name)\n\n\(skill.body)")
        }
        return sections.joined(separator: "\n\n---\n\n")
    }

    /// Total number of loaded skills
    var count: Int { skills.count }

    // MARK: - Parsing

    /// Parse a SKILL.md file with YAML frontmatter
    private func parseSkill(id: String, content: String) -> SkillDefinition? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        var name: String?
        var description: String?
        var serverName: String?
        var body: String

        // Check for YAML frontmatter (--- delimited)
        if trimmed.hasPrefix("---") {
            let parts = trimmed.split(separator: "---", maxSplits: 2, omittingEmptySubsequences: false)
            // parts[0] is empty (before first ---), parts[1] is frontmatter, parts[2] is body
            if parts.count >= 3 {
                let frontmatter = String(parts[1])
                body = String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines)

                // Simple YAML parsing for flat key-value pairs
                for line in frontmatter.split(separator: "\n") {
                    let pair = line.split(separator: ":", maxSplits: 1)
                    guard pair.count == 2 else { continue }
                    let key = pair[0].trimmingCharacters(in: .whitespaces)
                    let value = pair[1].trimmingCharacters(in: .whitespaces)

                    switch key {
                    case "name": name = value
                    case "description": description = value
                    case "server": serverName = value
                    default: break
                    }
                }
            } else {
                body = trimmed
            }
        } else {
            body = trimmed
        }

        // Require at least a name
        guard let skillName = name else {
            Logger.error("Skill '\(id)' missing required 'name' in frontmatter")
            return nil
        }

        return SkillDefinition(
            id: id,
            name: skillName,
            description: description ?? skillName,
            serverName: serverName,
            body: body
        )
    }
}
