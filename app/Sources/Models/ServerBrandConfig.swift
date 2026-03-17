import SwiftUI

struct ServerBrand {
    let icon: String
    let color: Color
    let displayName: String
    let isCLI: Bool

    init(icon: String, color: Color, displayName: String, isCLI: Bool = false) {
        self.icon = icon
        self.color = color
        self.displayName = displayName
        self.isCLI = isCLI
    }
}

enum ServerBrandConfig {
    static func brand(for serverName: String) -> ServerBrand {
        let lower = serverName.lowercased()
        if let known = knownBrands[lower] { return known }
        // Partial match fallback
        for (key, brand) in knownBrands {
            if lower.contains(key) { return brand }
        }
        return ServerBrand(icon: "gearshape.fill", color: .coral, displayName: serverName.capitalized)
    }

    private static let knownBrands: [String: ServerBrand] = [
        "blender": ServerBrand(icon: "cube.transparent", color: Color(hex: "E87D0D"), displayName: "Blender", isCLI: true),
        "figma": ServerBrand(icon: "paintbrush.pointed", color: Color(hex: "A259FF"), displayName: "Figma", isCLI: true),
        "unity": ServerBrand(icon: "gamecontroller", color: Color(hex: "6B6B6B"), displayName: "Unity"),
        "unreal": ServerBrand(icon: "film", color: Color(hex: "0D47A1"), displayName: "Unreal"),
        "xcode": ServerBrand(icon: "hammer", color: Color(hex: "147EFB"), displayName: "Xcode"),
        "touchdesigner": ServerBrand(icon: "waveform.path", color: Color(hex: "FF6B35"), displayName: "TouchDesigner", isCLI: true),
        "leonardo": ServerBrand(icon: "photo.artframe", color: Color(hex: "8B5CF6"), displayName: "Leonardo"),
        "lumadream": ServerBrand(icon: "sparkles", color: Color(hex: "6366F1"), displayName: "Luma Dream"),
        "filesystem": ServerBrand(icon: "folder", color: .warning, displayName: "File System"),
        "lens_studio": ServerBrand(icon: "camera.filters", color: Color(hex: "FFFC00"), displayName: "Lens Studio", isCLI: true),
        "lens-studio": ServerBrand(icon: "camera.filters", color: Color(hex: "FFFC00"), displayName: "Lens Studio", isCLI: true),
        "spline": ServerBrand(icon: "cube", color: Color(hex: "6C5CE7"), displayName: "Spline"),
        "github": ServerBrand(icon: "chevron.left.forwardslash.chevron.right", color: Color(hex: "6E5494"), displayName: "GitHub"),
        "slack": ServerBrand(icon: "number", color: Color(hex: "4A154B"), displayName: "Slack"),
        "notion": ServerBrand(icon: "doc.richtext", color: Color(hex: "000000"), displayName: "Notion"),
        "browser": ServerBrand(icon: "globe", color: .info, displayName: "Browser"),
        "puppeteer": ServerBrand(icon: "globe", color: Color(hex: "40B5A4"), displayName: "Puppeteer"),
        "fetch": ServerBrand(icon: "arrow.down.circle", color: .success, displayName: "Fetch"),
    ]
}

// MARK: - Color hex init

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
