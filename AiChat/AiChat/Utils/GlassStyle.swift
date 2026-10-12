import SwiftUI

/// Glass style configuration used by the app's iOS 18+ SwiftUI surfaces.
struct GlassStyleConfig {
    var cornerRadius: CGFloat
    var shadowRadius: CGFloat
    var shadowY: CGFloat
    var shadowOpacity: Double
    var borderGradientStart: Double
    var borderGradientEnd: Double
    
    /// Standard glass style for input composer (larger)
    static let composer = GlassStyleConfig(
        cornerRadius: 28,
        shadowRadius: 8,
        shadowY: 2,
        shadowOpacity: 0.08,
        borderGradientStart: 0.2,
        borderGradientEnd: 0.05
    )
    
    /// Compact glass style for navbar buttons (smaller)
    static let navbar = GlassStyleConfig(
        cornerRadius: 16,
        shadowRadius: 8,
        shadowY: 2,
        shadowOpacity: 0.08,
        borderGradientStart: 0.2,
        borderGradientEnd: 0.05
    )
}

extension View {
    /// Applies the shared glass style with ultra-thin material, shadow, and gradient border.
    func glassStyle(_ config: GlassStyleConfig = .navbar) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: config.cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(
                        color: .black.opacity(config.shadowOpacity),
                        radius: config.shadowRadius,
                        y: config.shadowY
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: config.cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.primary.opacity(config.borderGradientStart),
                                Color.primary.opacity(config.borderGradientEnd)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
    }
}
