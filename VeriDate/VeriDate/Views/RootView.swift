import SwiftUI

struct RootView: View {
    @EnvironmentObject var session: SessionViewModel

    var body: some View {
        Group {
            if session.isCheckingSession {
                ProgressView("Checking session...")
            } else if session.isAuthenticated {
                if let profile = session.currentProfile {
                    if profile.isBanned {
                        BannedAccountView()
                    } else {
                        switch profile.verificationStatus {
                        case .verified:
                            MainTabView()
                        case .pending:
                            VerificationPendingView()
                        case .unsubmitted:
                            if profile.hasCompletedBasicProfile {
                                VerificationUploadView()
                            } else {
                                ProfileSetupView()
                            }
                        case .rejected:
                            VerificationUploadView()
                        }
                    }
                } else if session.isLoadingProfile {
                    ProgressView("Loading profile...")
                } else {
                    NavigationStack {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 44))
                                .foregroundStyle(.orange)

                            Text("Profile did not load")
                                .font(.title3)
                                .fontWeight(.semibold)

                            Text(session.errorMessage ?? "Try again or sign out and sign back in.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Button("Try Again") {
                                Task {
                                    await session.createEmptyProfileIfNeeded()
                                    await session.loadProfile()
                                }
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Sign Out") {
                                Task { await session.signOut() }
                            }
                            .foregroundStyle(.red)
                        }
                        .padding()
                    }
                }
            } else {
                AuthView()
            }
        }
    }
}

private struct BannedAccountView: View {
    @EnvironmentObject var session: SessionViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.red)

                Text("Account Restricted")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("This account can no longer access VeriDate. Contact support if you believe this is a mistake.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Sign Out") {
                    Task { await session.signOut() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}
