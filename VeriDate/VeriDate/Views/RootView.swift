import SwiftUI

struct RootView: View {
    @EnvironmentObject var session: SessionViewModel

    var body: some View {
        Group {
            if session.isAuthenticated {
                if let profile = session.currentProfile {
                    switch profile.verificationStatus {
                    case .verified:
                        MainTabView()
                    case .pending:
                        VerificationPendingView()
                    case .rejected, .unsubmitted:
                        ProfileSetupView()
                    }
                } else {
                    ProgressView("Loading profile...")
                }
            } else {
                AuthView()
            }
        }
    }
}
