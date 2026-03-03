import Foundation

struct LinkPreviewData: Identifiable, Sendable {
    let id: String
    let url: URL
    var title: String?
    var description: String?
    var imageURL: URL?
    var siteName: String?
    var isFailed: Bool = false

    init(url: URL, title: String? = nil, description: String? = nil, imageURL: URL? = nil, siteName: String? = nil, isFailed: Bool = false) {
        self.id = url.absoluteString
        self.url = url
        self.title = title
        self.description = description
        self.imageURL = imageURL
        self.siteName = siteName
        self.isFailed = isFailed
    }
}
