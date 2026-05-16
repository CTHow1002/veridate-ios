import SwiftUI

struct SplashView: View {
    @Binding var isFinished: Bool
    @Environment(\.locale) private var locale

    private var splashImageName: String {
        switch locale.identifier {
        case "zh-Hans":
            return "LaunchSplashCN"
        default:
            return "LaunchSplashEN"
        }
    }

    var body: some View {
        Image(splashImageName)
            .resizable()
            .scaledToFill()
            .ignoresSafeArea()
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        isFinished = true
                    }
                }
            }
    }
}
