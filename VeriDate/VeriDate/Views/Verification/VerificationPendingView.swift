import SwiftUI

struct VerificationPendingView: View {
    @EnvironmentObject var session: SessionViewModel
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    pendingHeroCard
                    reviewStepsCard
                    nextStepsCard
                    refreshButton

                    if let error = session.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .accessibilityLabel(error)
                    }
                }
                .padding(18)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(AppLanguageManager.localized("verificationPending.navigationTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLanguageManager.localized("common_sign_out")) {
                        Task { await session.signOut() }
                    }
                    .foregroundStyle(.red)
                    .accessibilityLabel(AppLanguageManager.localized("common_sign_out"))
                }
            }
        }
    }

    private var pendingHeroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.pink.opacity(0.12))
                        .frame(width: 58, height: 58)

                    Image(systemName: "checkmark.shield.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.pink)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(AppLanguageManager.localized("verificationPending.hero.title"))
                        .font(.title2.weight(.bold))

                    Text(AppLanguageManager.localized("verificationPending.hero.subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                ProgressView()
                    .tint(.pink)
                    .accessibilityHidden(true)

                Text(AppLanguageManager.localized("verificationPending.hero.reviewTime"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(12)
            .background(Color.pink.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .combine)
        }
        .verificationPendingCard()
        .accessibilityElement(children: .contain)
    }

    private var reviewStepsCard: some View {
        VerificationPendingCard(title: AppLanguageManager.localized("verificationPending.reviewChecklist.title"), systemImage: "list.bullet.clipboard.fill") {
            VStack(spacing: 12) {
                VerificationPendingStepRow(title: AppLanguageManager.localized("verificationPending.step.video.title"), subtitle: AppLanguageManager.localized("verificationPending.step.video.subtitle"), isComplete: true)
                VerificationPendingStepRow(title: AppLanguageManager.localized("verificationPending.step.document.title"), subtitle: AppLanguageManager.localized("verificationPending.step.document.subtitle"), isComplete: true)
                VerificationPendingStepRow(title: AppLanguageManager.localized("verificationPending.step.admin.title"), subtitle: AppLanguageManager.localized("verificationPending.step.admin.subtitle"), isComplete: false)
            }
        }
    }

    private var nextStepsCard: some View {
        VerificationPendingCard(title: AppLanguageManager.localized("verificationPending.whileYouWait.title"), systemImage: "sparkles") {
            VStack(alignment: .leading, spacing: 10) {
                PendingTipRow(text: AppLanguageManager.localized("verificationPending.tip.keepInstalled"))
                PendingTipRow(text: AppLanguageManager.localized("verificationPending.tip.changes"))
                PendingTipRow(text: AppLanguageManager.localized("verificationPending.tip.approved"))
            }
        }
    }

    private var refreshButton: some View {
        Button {
            Task {
                HapticManager.light()
                isRefreshing = true
                await session.loadProfile()
                isRefreshing = false
            }
        } label: {
            HStack(spacing: 10) {
                if isRefreshing {
                    ProgressView()
                        .tint(.white)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .accessibilityHidden(true)
                }

                Text(isRefreshing ? AppLanguageManager.localized("verificationPending.refresh.checking") : AppLanguageManager.localized("verificationPending.refresh.title"))
            }
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.pink, in: Capsule())
            .shadow(color: Color.pink.opacity(0.22), radius: 14, y: 7)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRefreshing ? AppLanguageManager.localized("verificationPending.refresh.checking") : AppLanguageManager.localized("verificationPending.refresh.title"))
        .disabled(isRefreshing)
        .opacity(isRefreshing ? 0.72 : 1)
    }
}

private struct VerificationPendingCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .accessibilityElement(children: .combine)

            content
        }
        .verificationPendingCard()
    }
}

private struct VerificationPendingStepRow: View {
    let title: String
    let subtitle: String
    let isComplete: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "clock.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(isComplete ? Color.green : Color.orange)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityValue(isComplete ? AppLanguageManager.localized("verificationPending.step.status.complete") : AppLanguageManager.localized("verificationPending.step.status.pending"))
    }
}

private struct PendingTipRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(.pink)
                .frame(width: 18, height: 18)
                .background(Color.pink.opacity(0.1), in: Circle())
                .padding(.top, 1)
                .accessibilityHidden(true)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    func verificationPendingCard() -> some View {
        self
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color(.systemBackground), Color(.secondarySystemGroupedBackground).opacity(0.36)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(0.045), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.06), radius: 16, y: 8)
    }
}
