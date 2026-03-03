import Foundation
import Observation

@Observable
@MainActor
final class LinkPreviewService {
    private var cache: [String: LinkPreviewData] = [:]
    private var inFlight: Set<String> = []

    func preview(for url: URL) -> LinkPreviewData? {
        cache[url.absoluteString]
    }

    func fetch(url: URL) {
        let key = url.absoluteString
        guard cache[key] == nil, !inFlight.contains(key) else { return }
        inFlight.insert(key)

        Task {
            let data = await fetchPreview(url: url)
            cache[key] = data
            inFlight.remove(key)
        }
    }

    private func fetchPreview(url: URL) async -> LinkPreviewData {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0 (compatible; SolaceBot/1.0)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else {
                return LinkPreviewData(url: url, isFailed: true)
            }

            return parseHTML(html, url: url)
        } catch {
            return LinkPreviewData(url: url, isFailed: true)
        }
    }

    private func parseHTML(_ html: String, url: URL) -> LinkPreviewData {
        let ogTitle = extractMetaContent(html, property: "og:title")
        let ogDescription = extractMetaContent(html, property: "og:description")
        let ogImage = extractMetaContent(html, property: "og:image")
        let ogSiteName = extractMetaContent(html, property: "og:site_name")

        // Fallbacks
        let title = ogTitle ?? extractTitle(html)
        let description = ogDescription ?? extractMetaContent(html, name: "description")

        var imageURL: URL?
        if let ogImage {
            if ogImage.hasPrefix("http") {
                imageURL = URL(string: ogImage)
            } else if let base = URL(string: "/", relativeTo: url)?.absoluteURL {
                imageURL = URL(string: ogImage, relativeTo: base)
            }
        }

        let siteName = ogSiteName ?? url.host?.replacingOccurrences(of: "www.", with: "")

        return LinkPreviewData(
            url: url,
            title: title,
            description: description,
            imageURL: imageURL,
            siteName: siteName,
            isFailed: title == nil && description == nil
        )
    }

    private func extractMetaContent(_ html: String, property: String) -> String? {
        // Match <meta property="og:title" content="...">
        let pattern = #"<meta[^>]+property\s*=\s*["']\#(property)["'][^>]+content\s*=\s*["']([^"']*)["']"#
        if let match = html.range(of: pattern, options: .regularExpression) {
            let matched = String(html[match])
            if let contentRange = matched.range(of: #"content\s*=\s*["']([^"']*)["']"#, options: .regularExpression) {
                let contentPart = String(matched[contentRange])
                let value = contentPart.replacingOccurrences(of: #"content\s*=\s*["']"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"["']$"#, with: "", options: .regularExpression)
                return value.isEmpty ? nil : value
            }
        }
        // Try reverse attribute order: content before property
        let reversePattern = #"<meta[^>]+content\s*=\s*["']([^"']*)["'][^>]+property\s*=\s*["']\#(property)["']"#
        if let match = html.range(of: reversePattern, options: .regularExpression) {
            let matched = String(html[match])
            if let contentRange = matched.range(of: #"content\s*=\s*["']([^"']*)["']"#, options: .regularExpression) {
                let contentPart = String(matched[contentRange])
                let value = contentPart.replacingOccurrences(of: #"content\s*=\s*["']"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"["']$"#, with: "", options: .regularExpression)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    private func extractMetaContent(_ html: String, name: String) -> String? {
        let pattern = #"<meta[^>]+name\s*=\s*["']\#(name)["'][^>]+content\s*=\s*["']([^"']*)["']"#
        if let match = html.range(of: pattern, options: .regularExpression) {
            let matched = String(html[match])
            if let contentRange = matched.range(of: #"content\s*=\s*["']([^"']*)["']"#, options: .regularExpression) {
                let contentPart = String(matched[contentRange])
                let value = contentPart.replacingOccurrences(of: #"content\s*=\s*["']"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"["']$"#, with: "", options: .regularExpression)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    private func extractTitle(_ html: String) -> String? {
        let pattern = #"<title[^>]*>([^<]*)</title>"#
        if let match = html.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
            let matched = String(html[match])
            let title = matched.replacingOccurrences(of: #"<title[^>]*>"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "</title>", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : title
        }
        return nil
    }

    static func extractURLs(from text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, range: range)
        return Array(matches.compactMap { $0.url }.prefix(3))
    }
}
