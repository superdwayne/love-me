import UIKit

enum HapticManager: Sendable {
    @MainActor
    static func messageSent() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @MainActor
    static func connectionEstablished() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    @MainActor
    static func connectionLost() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    @MainActor
    static func toolCompleted() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    @MainActor
    static func toolError() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    @MainActor
    static func longPress() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    @MainActor
    static func cascadeComplete() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }
}
