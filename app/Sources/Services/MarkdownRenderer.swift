import SwiftUI

enum MarkdownRenderer {
    /// Renders a simplified markdown string into an AttributedString
    static func render(_ text: String) -> AttributedString {
        // Try the built-in Markdown initializer first for basic formatting
        // Then apply our custom styling on top
        var result = AttributedString()

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var inCodeBlock = false
        var codeBlockContent = ""
        var isFirstLine = true

        for line in lines {
            let lineStr = String(line)

            // Code block toggle
            if lineStr.hasPrefix("```") {
                if inCodeBlock {
                    // End code block
                    if !codeBlockContent.isEmpty {
                        var codeAttr = AttributedString(codeBlockContent)
                        codeAttr.font = .codeFont
                        codeAttr.foregroundColor = .textPrimary
                        codeAttr.backgroundColor = .codeBg
                        result.append(codeAttr)
                        result.append(AttributedString("\n"))
                    }
                    codeBlockContent = ""
                    inCodeBlock = false
                } else {
                    // Start code block
                    inCodeBlock = true
                    if !isFirstLine {
                        result.append(AttributedString("\n"))
                    }
                }
                continue
            }

            if inCodeBlock {
                if !codeBlockContent.isEmpty {
                    codeBlockContent += "\n"
                }
                codeBlockContent += lineStr
                continue
            }

            if !isFirstLine {
                result.append(AttributedString("\n"))
            }
            isFirstLine = false

            // Headings
            if lineStr.hasPrefix("### ") {
                var heading = AttributedString(String(lineStr.dropFirst(4)))
                heading.font = .system(size: 16, weight: .semibold)
                heading.foregroundColor = .textPrimary
                result.append(heading)
                continue
            }
            if lineStr.hasPrefix("## ") {
                var heading = AttributedString(String(lineStr.dropFirst(3)))
                heading.font = .system(size: 18, weight: .semibold)
                heading.foregroundColor = .textPrimary
                result.append(heading)
                continue
            }
            if lineStr.hasPrefix("# ") {
                var heading = AttributedString(String(lineStr.dropFirst(2)))
                heading.font = .system(size: 20, weight: .bold)
                heading.foregroundColor = .textPrimary
                result.append(heading)
                continue
            }

            // Lists
            var processedLine = lineStr
            if lineStr.hasPrefix("- ") || lineStr.hasPrefix("* ") {
                processedLine = "  \u{2022} " + String(lineStr.dropFirst(2))
            } else if let match = lineStr.range(of: #"^(\d+)\.\s"#, options: .regularExpression) {
                let number = lineStr[match].dropLast(2)
                let rest = String(lineStr[match.upperBound...])
                processedLine = "  \(number). " + rest
            }

            // Inline formatting
            let inlineRendered = renderInlineFormatting(processedLine)
            result.append(inlineRendered)
        }

        // Handle unclosed code block
        if inCodeBlock && !codeBlockContent.isEmpty {
            var codeAttr = AttributedString(codeBlockContent)
            codeAttr.font = .codeFont
            codeAttr.foregroundColor = .textPrimary
            codeAttr.backgroundColor = .codeBg
            result.append(codeAttr)
        }

        return result
    }

    /// Renders markdown with search term highlighting
    static func render(_ text: String, highlighting searchQuery: String, isActiveMatch: Bool = false) -> AttributedString {
        var result = render(text)

        guard !searchQuery.isEmpty else { return result }

        let plainText = String(result.characters).lowercased()
        let query = searchQuery.lowercased()

        var searchStart = plainText.startIndex
        while let range = plainText.range(of: query, range: searchStart..<plainText.endIndex) {
            // Convert String range to AttributedString range
            let startOffset = plainText.distance(from: plainText.startIndex, to: range.lowerBound)
            let length = plainText.distance(from: range.lowerBound, to: range.upperBound)

            let attrStart = result.index(result.startIndex, offsetByCharacters: startOffset)
            let attrEnd = result.index(attrStart, offsetByCharacters: length)
            let attrRange = attrStart..<attrEnd

            result[attrRange].backgroundColor = isActiveMatch
                ? Color.warning.opacity(0.6)
                : Color.warning.opacity(0.3)

            searchStart = range.upperBound
        }

        return result
    }

    /// Renders inline markdown (bold, italic, inline code, links)
    private static func renderInlineFormatting(_ text: String) -> AttributedString {
        var result = AttributedString()
        var remaining = text[text.startIndex...]

        while !remaining.isEmpty {
            // Inline code
            if remaining.hasPrefix("`") {
                let afterTick = remaining.index(after: remaining.startIndex)
                if let endTick = remaining[afterTick...].firstIndex(of: "`") {
                    let code = String(remaining[afterTick..<endTick])
                    var codeAttr = AttributedString(code)
                    codeAttr.font = .system(size: 14, design: .monospaced)
                    codeAttr.backgroundColor = .codeBg
                    codeAttr.foregroundColor = .textPrimary
                    result.append(codeAttr)
                    remaining = remaining[remaining.index(after: endTick)...]
                    continue
                }
            }

            // Bold (**text**)
            if remaining.hasPrefix("**") {
                let afterStars = remaining.index(remaining.startIndex, offsetBy: 2)
                if let endRange = remaining[afterStars...].range(of: "**") {
                    let boldText = String(remaining[afterStars..<endRange.lowerBound])
                    var boldAttr = AttributedString(boldText)
                    boldAttr.font = .system(size: 16, weight: .bold)
                    result.append(boldAttr)
                    remaining = remaining[endRange.upperBound...]
                    continue
                }
            }

            // Italic (*text*)
            if remaining.hasPrefix("*") && !remaining.hasPrefix("**") {
                let afterStar = remaining.index(after: remaining.startIndex)
                if let endStar = remaining[afterStar...].firstIndex(of: "*") {
                    let italicText = String(remaining[afterStar..<endStar])
                    var italicAttr = AttributedString(italicText)
                    italicAttr.font = .system(size: 16).italic()
                    result.append(italicAttr)
                    remaining = remaining[remaining.index(after: endStar)...]
                    continue
                }
            }

            // Link [text](url)
            if remaining.hasPrefix("[") {
                let afterBracket = remaining.index(after: remaining.startIndex)
                if let closeBracket = remaining[afterBracket...].firstIndex(of: "]") {
                    let nextIdx = remaining.index(after: closeBracket)
                    if nextIdx < remaining.endIndex && remaining[nextIdx] == "(" {
                        let afterParen = remaining.index(after: nextIdx)
                        if let closeParen = remaining[afterParen...].firstIndex(of: ")") {
                            let linkText = String(remaining[afterBracket..<closeBracket])
                            let urlString = String(remaining[afterParen..<closeParen])
                            var linkAttr = AttributedString(linkText)
                            linkAttr.foregroundColor = .info
                            linkAttr.underlineStyle = .single
                            if let url = URL(string: urlString) {
                                linkAttr.link = url
                            }
                            result.append(linkAttr)
                            remaining = remaining[remaining.index(after: closeParen)...]
                            continue
                        }
                    }
                }
            }

            // Regular character
            var charAttr = AttributedString(String(remaining[remaining.startIndex]))
            charAttr.font = .chatMessage
            result.append(charAttr)
            remaining = remaining[remaining.index(after: remaining.startIndex)...]
        }

        return result
    }
}
