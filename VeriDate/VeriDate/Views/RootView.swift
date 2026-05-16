import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject var session: SessionViewModel
    @State private var acknowledgedWarningKey: String?
    @State private var isRevisitingProfileSetup = false

    var body: some View {
        Group {
            if session.isCheckingSession {
                ProgressView("root_checking_session")
            } else if session.isAuthenticated {
                if let profile = session.currentProfile {
                    if profile.isDeactivated {
                        AccountDeletionPendingView(profile: profile)
                    } else if profile.isCurrentlyBanned {
                        BannedAccountView(profile: profile)
                    } else if shouldShowWarning(for: profile) {
                        WarningAccountView(profile: profile) {
                            acknowledgedWarningKey = warningKey(for: profile)
                        }
                    } else if isRevisitingProfileSetup {
                        ProfileSetupView(startsAtLastStep: true) {
                            isRevisitingProfileSetup = false
                        }
                    } else {
                        switch profile.verificationStatus {
                        case .verified:
                            MainTabView()
                        case .pending:
                            VerificationPendingView()
                        case .unsubmitted:
                            if profile.hasCompletedBasicProfile {
                                VerificationUploadView {
                                    isRevisitingProfileSetup = true
                                }
                            } else {
                                ProfileSetupView()
                            }
                        case .rejected:
                            VerificationUploadView {
                                isRevisitingProfileSetup = true
                            }
                        }
                    }
                } else if session.isLoadingProfile {
                    ProgressView("root_loading_profile")
                } else {
                    NavigationStack {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 44))
                                .foregroundStyle(.orange)

                            Text("root_profile_load_failed_title")
                                .font(.title3)
                                .fontWeight(.semibold)

                            Text(session.errorMessage ?? AppLanguageManager.localized("root_profile_load_failed_message"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Button("common_try_again") {
                                Task {
                                    await session.createEmptyProfileIfNeeded()
                                    await session.loadProfile()
                                }
                            }
                            .buttonStyle(.borderedProminent)

                            Button("common_sign_out") {
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
        "\(profile.warnedAt ?? "")-\(profile.warningUntil ?? "")-\(profile.warningMessage ?? "")"
    }
}

private struct AccountDeletionPendingView: View {
    @EnvironmentObject var session: SessionViewModel
    let profile: Profile
    @State private var isCanceling = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.red)

                Text("account_deletion_scheduled_title")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("account_deletion_scheduled_message")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let scheduledDate {
                    Text(String.localizedStringWithFormat(
                        AppLanguageManager.localized("account_deletion_scheduled_for_format"),
                        scheduledDate.formatted(date: .abbreviated, time: .shortened)
                    ))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                }

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await cancelDeletion() }
                } label: {
                    if isCanceling {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("account_deletion_cancel_button")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCanceling)

                Button("common_sign_out") {
                    Task { await session.signOut() }
                }
                .foregroundStyle(.red)
            }
            .padding(24)
        }
    }

    private var scheduledDate: Date? {
        guard let value = profile.accountDeletionScheduledAt else { return nil }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractionalFormatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func cancelDeletion() async {
        isCanceling = true
        defer { isCanceling = false }

        if await session.cancelAccountDeletion() {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            message = session.errorMessage ?? AppLanguageManager.localized("account_deletion_cancel_failed_message")
        }
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

                Text("account_restricted_title")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(profile.banMessage ?? AppLanguageManager.localized("account_restricted_message"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let banUntil = profile.banUntilDate {
                    Text(String.localizedStringWithFormat(
                        AppLanguageManager.localized("account_restricted_until_format"),
                        banUntil.formatted(date: .abbreviated, time: .shortened)
                    ))
                        .font(.footnote)
                        .fontWeight(.semibold)
                }

                if let details = profile.banDetails, !details.isEmpty {
                    Text(details)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button("common_sign_out") {
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

                Text(AppLanguageManager.localized("account_warning_title"))
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(profile.warningMessage ?? AppLanguageManager.localized("account_warning_message"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let details = profile.warningDetails,
                   !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   details != profile.warningMessage {
                    Text(details)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let warningUntil = profile.warningUntilDate {
                    Text(String.localizedStringWithFormat(
                        AppLanguageManager.localized("account_warning_until_format"),
                        warningUntil.formatted(date: .abbreviated, time: .shortened)
                    ))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Button("common_i_understand") {
                    onContinue()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}
