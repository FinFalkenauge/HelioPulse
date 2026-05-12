import SwiftUI

enum Theme {
    static let bgDeep = Color(red: 9 / 255, green: 11 / 255, blue: 16 / 255)
    static let bgRaised = Color(red: 17 / 255, green: 24 / 255, blue: 39 / 255)
    static let cardGlass = Color(red: 22 / 255, green: 32 / 255, blue: 52 / 255).opacity(0.72)

    static let solarAmber = Color(red: 1.00, green: 0.70, blue: 0.28)
    static let flowCyan = Color(red: 0.36, green: 0.85, blue: 1.00)
    static let stateGreen = Color(red: 0.22, green: 0.85, blue: 0.54)
    static let warnCoral = Color(red: 1.00, green: 0.42, blue: 0.42)

    static let textPrimary = Color(red: 0.96, green: 0.97, blue: 1.00)
    static let textSecondary = Color(red: 0.67, green: 0.71, blue: 0.83)
}

struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.cardGlass)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 10)
            )
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCard())
    }
}
