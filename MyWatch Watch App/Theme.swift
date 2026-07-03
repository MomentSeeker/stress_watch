import SwiftUI

/// Central place for the app's visual language: colors, gradients and a few
/// reusable styling helpers. Each module (stress / water / meds / meals) gets
/// its own accent gradient so the app feels cohesive but each tab has identity.
enum Theme {
    // Backgrounds
    static let bg = Color.black
    static let card = Color.white.opacity(0.08)
    static let cardStroke = Color.white.opacity(0.10)

    // Module accent gradients
    static let stressGradient = LinearGradient(
        colors: [Color(red: 0.39, green: 0.85, blue: 0.78),
                 Color(red: 0.55, green: 0.45, blue: 0.96)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let waterGradient = LinearGradient(
        colors: [Color(red: 0.30, green: 0.78, blue: 0.98),
                 Color(red: 0.20, green: 0.45, blue: 0.95)],
        startPoint: .top, endPoint: .bottom)

    static let medGradient = LinearGradient(
        colors: [Color(red: 1.00, green: 0.58, blue: 0.40),
                 Color(red: 0.96, green: 0.36, blue: 0.55)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let mealGradient = LinearGradient(
        colors: [Color(red: 0.55, green: 0.86, blue: 0.45),
                 Color(red: 0.20, green: 0.70, blue: 0.55)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Maps a 0–100 stress score to a color (green → amber → red).
    static func stressColor(_ score: Int) -> Color {
        switch score {
        case ..<34:  return Color(red: 0.36, green: 0.86, blue: 0.55) // calm
        case 34..<67: return Color(red: 0.99, green: 0.78, blue: 0.30) // balanced
        default:      return Color(red: 0.98, green: 0.42, blue: 0.42) // stressed
        }
    }
}

extension View {
    /// Rounded translucent card used throughout the app.
    func cardBackground(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(Theme.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Theme.cardStroke, lineWidth: 0.5)
            )
    }
}

extension LinearGradient {
    /// SwiftUI controls such as `tint()` expect a `Color`, so use a stable
    /// accent representative for gradients.
    var asColor: Color { Color(red: 0.25, green: 0.6, blue: 0.96) }
}
