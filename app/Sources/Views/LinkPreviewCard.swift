import SwiftUI

struct LinkPreviewCard: View {
    let preview: LinkPreviewData

    var body: some View {
        Link(destination: preview.url) {
            HStack(spacing: SolaceTheme.sm) {
                // Optional image
                if let imageURL = preview.imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.xs))
                        default:
                            EmptyView()
                        }
                    }
                }

                // Text content
                VStack(alignment: .leading, spacing: 2) {
                    if let siteName = preview.siteName {
                        Text(siteName.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.electricBlue)
                            .tracking(0.5)
                            .lineLimit(1)
                    }

                    if let title = preview.title {
                        Text(title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.textPrimary)
                            .lineLimit(2)
                    }

                    if let description = preview.description {
                        Text(description)
                            .font(.system(size: 11))
                            .foregroundStyle(.textSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(SolaceTheme.sm)
            .background(Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.sm))
        }
    }
}

struct LinkPreviewContainer: View {
    let messageContent: String
    let isStreaming: Bool
    @Environment(LinkPreviewService.self) private var linkPreviewService

    private var urls: [URL] {
        guard !isStreaming else { return [] }
        return LinkPreviewService.extractURLs(from: messageContent)
    }

    var body: some View {
        if !urls.isEmpty {
            VStack(spacing: SolaceTheme.xs) {
                ForEach(urls, id: \.absoluteString) { url in
                    if let preview = linkPreviewService.preview(for: url), !preview.isFailed {
                        LinkPreviewCard(preview: preview)
                    }
                }
            }
            .onAppear {
                for url in urls {
                    linkPreviewService.fetch(url: url)
                }
            }
        }
    }
}
