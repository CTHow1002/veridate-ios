import SwiftUI

enum AppSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum AppRadius {
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 22
    static let xl: CGFloat = 28
}

enum AppShadow {
    static let cardColor = Color.black.opacity(0.08)
    static let cardRadius: CGFloat = 14
    static let cardY: CGFloat = 6
}

struct AppCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AppSpacing.lg)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .shadow(
                color: AppShadow.cardColor,
                radius: AppShadow.cardRadius,
                x: 0,
                y: AppShadow.cardY
            )
    }
}

extension View {
    func appCard() -> some View {
        modifier(AppCardModifier())
    }
}
