import SwiftUI

struct RootView: View {
    @EnvironmentObject var session: SessionViewModel
    @State private var acknowledgedWarningKey: String?

    var body: some View {
        Group {
            if session.isCheckingSession {
                ProgressView("Checking session...")
            } else if session.isAuthenticated {
                if let profile = session.currentProfile {
                    if profile.isCurrentlyBanned {
                        BannedAccountView(profile: profile)
                    } else if shouldShowWarning(for: profile) {
                        WarningAccountView(profile: profile) {
                            acknowledgedWarningKey = warningKey(for: profile)
                        }
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

    private func shouldShowWarning(for profile: Profile) -> Bool {
        profile.hasActiveWarning && acknowledgedWarningKey != warningKey(for: profile)
    }

    private func warningKey(for profile: Profile) -> String {
        "\(profile.warnedAt ?? "")-\(profile.warningMessage ?? "")"
    }
}

private struct BannedAccountView: View {
    @EnvironmentObject var session: SessionViewModel
    let profile: Profile

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.red)

                Text("Account Restricted")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(profile.banMessage ?? "This account can no longer access VeriDate.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let banUntil = profile.banUntilDate {
                    Text("Restricted until \(banUntil.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .fontWeight(.semibold)
                }

                if let details = profile.banDetails, !details.isEmpty {
                    Text(details)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button("Sign Out") {
                    Task { await session.signOut() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}

private struct WarningAccountView: View {
    let profile: Profile
    let onContinue: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)

                Text("Account Warning")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(profile.warningMessage ?? "Please review VeriDate safety rules before continuing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let details = profile.warningDetails, !details.isEmpty {
                    Text(details)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button("I Understand") {
                    onContinue()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}
