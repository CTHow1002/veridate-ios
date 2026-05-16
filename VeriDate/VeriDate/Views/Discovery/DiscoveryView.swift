import SwiftUI
import PostgREST
import Supabase
import UIKit

struct DiscoveryView: View {
    @EnvironmentObject var session: SessionViewModel
    @StateObject private var vm = DiscoveryViewModel()
    @StateObject private var safetyVM = SafetyViewModel()
    @State private var isShowingFilters = false
    @State private var reportProfile: Profile?
    @State private var blockProfile: Profile?
    @State private var noticeMessage: String?
    @State private var selectedDiscoveryProfile: Profile?
    @State private var discoverySwipeProgress: CGFloat = 0
    @State private var isShowingInterestedSheet = false
    @State private var isShowingInterestedPaywall = false
    @State private var undoReturningProfileId: UUID?
    @State private var undoReturnEdge: Edge = .trailing
    @State private var detailSwipeAction: DiscoveryDetailSwipeAction?
    @State private var suppressDecisionHapticForProfileId: UUID?
    @State private var detailSwipeGhost: DiscoveryDetailSwipeGhost?

    var body: some View {
        NavigationStack {
            Group {
                if session.currentProfile?.verificationStatus != .verified {
                    ContentUnavailableView(
                        AppLanguageManager.localized("discovery_verification_required_title"),
                        systemImage: "checkmark.seal",
                        description: Text(AppLanguageManager.localized("discovery_verification_required_message"))
                    )
                } else if vm.isLoading {
                    DiscoveryLoadingStateView()
                } else if let error = vm.errorMessage, vm.profiles.isEmpty {
                    DiscoveryErrorStateView(message: error) {
                        Task {
                            await load()
                        }
                    }
                } else if let profile = vm.profiles.first {
                    GeometryReader { proxy in
                        let metrics = DiscoveryLayoutMetrics(size: proxy.size)

                        ZStack(alignment: .top) {
                            VStack(spacing: metrics.verticalSpacing) {
                                interestedInYouSection
                                    .padding(.horizontal)

                                discoveryStack(metrics: metrics)

                                discoveryUtilityBar(for: profile)
                                    .padding(.horizontal)
                                    .padding(.bottom, metrics.bottomPadding)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .padding(.top, metrics.topPadding)

                            if let detailSwipeGhost {
                                DiscoveryDetailSwipeGhostCard(
                                    ghost: detailSwipeGhost,
                                    currentProfile: session.currentProfile,
                                    cardHeight: metrics.cardHeight,
                                    topOffset: metrics.topPadding + interestedSectionEstimatedHeight + metrics.verticalSpacing,
                                    horizontalPadding: metrics.stackHorizontalPadding,
                                    onComplete: {
                                        if self.detailSwipeGhost?.id == detailSwipeGhost.id {
                                            self.detailSwipeGhost = nil
                                        }
                                    }
                                )
                            }
                        }
                    }
                } else {
                    GeometryReader { proxy in
                        let metrics = DiscoveryLayoutMetrics(size: proxy.size)

                        VStack(spacing: metrics.verticalSpacing) {
                            interestedInYouSection
                                .padding(.horizontal)

                            DiscoveryEmptyStateView {
                                isShowingFilters = true
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, metrics.topPadding)
                    }
                }
            }
            .navigationTitle(AppLanguageManager.localized("discovery_navigation_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button {
                    isShowingFilters = true
                } label: {
                    Label(AppLanguageManager.localized("discovery_filters_button"), systemImage: "slider.horizontal.3")
                }
            }
            .sheet(isPresented: $isShowingFilters) {
                if let userId = session.currentUserId {
                    FiltersView(
                        vm: vm,
                        userId: userId,
                        currentProfile: session.currentProfile
                    ) {
                        isShowingFilters = false
                    }
                }
            }
            .navigationDestination(item: $selectedDiscoveryProfile) { profile in
                DiscoveryProfileDetailView(
                    profile: profile,
                    currentProfile: session.currentProfile,
                    compatibilitySummary: vm.compatibilitySummary(for: profile),
                    onBlocked: {
                        vm.removeProfile(id: profile.id)
                    },
                    onLike: {
                        triggerDetailSwipe(for: profile, isLike: true)
                    },
                    onPass: {
                        triggerDetailSwipe(for: profile, isLike: false)
                    }
                )
                .environmentObject(session)
            }
            .sheet(item: $reportProfile) { profile in
                if let userId = session.currentUserId {
                    SafetyReportSheet(
                        reporterUserId: userId,
                        reportedUserId: profile.id,
                        matchId: nil,
                        reportedName: profile.publicName ?? AppLanguageManager.localized("common_user")
                    )
                }
            }
            .sheet(isPresented: $isShowingInterestedSheet) {
                InterestedInYouSheet(
                    profiles: vm.interestedInYouProfiles,
                    isPremiumUser: vm.isPremiumUser,
                    onSelect: { profile in
                        isShowingInterestedSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                            selectedDiscoveryProfile = profile
                        }
                    },
                    onLockedTap: {
                        isShowingInterestedSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                            isShowingInterestedPaywall = true
                        }
                    }
                )
            }
            .sheet(isPresented: $isShowingInterestedPaywall) {
                InterestedInYouPaywallSheet()
                    .presentationDetents([.height(260)])
                    .presentationDragIndicator(.visible)
            }
            .alert(AppLanguageManager.localized("safety_block_user_title"), isPresented: blockAlertBinding) {
                Button(AppLanguageManager.localized("common_cancel"), role: .cancel) {
                    blockProfile = nil
                }
                Button(AppLanguageManager.localized("safety_block_button"), role: .destructive) {
                    Task {
                        await blockSelectedProfile()
                    }
                }
            } message: {
                Text(AppLanguageManager.localized("safety_block_user_message"))
            }
            .alert(AppLanguageManager.localized("safety_alert_title"), isPresented: noticeBinding) {
                Button(AppLanguageManager.localized("common_ok")) {
                    noticeMessage = nil
                    safetyVM.errorMessage = nil
                    safetyVM.successMessage = nil
                }
            } message: {
                Text(noticeMessage ?? "")
            }
            .task(id: session.currentUserId) {
                await load()
            }
        }
    }

    private var interestedInYouSection: some View {
        InterestedInYouSection(
            profiles: Array(vm.interestedInYouProfiles.prefix(5)),
            totalCount: vm.interestedInYouCount,
            isPremiumUser: vm.isPremiumUser,
            profileCreatedAt: session.currentProfile?.createdAt,
            isLoading: vm.isLoadingInterestedInYou,
            onSeeAll: {
                isShowingInterestedSheet = true
            },
            onSelect: { profile in
                selectedDiscoveryProfile = profile
            },
            onLockedTap: {
                isShowingInterestedPaywall = true
            }
        )
    }

    @ViewBuilder
    private func discoveryStack(metrics: DiscoveryLayoutMetrics) -> some View {
        ZStack {
            ForEach(Array(vm.profiles.prefix(3).enumerated()).reversed(), id: \.element.id) { index, profile in
                SwipeableDiscoveryCard(
                    profile: profile,
                    currentProfile: session.currentProfile,
                    compatibilitySummary: vm.compatibilitySummary(for: profile),
                    sharedHighlights: vm.sharedInterestHighlights(for: profile),
                    isInteractive: index == 0,
                    isDisabled: index != 0 || vm.actingProfileIds.contains(profile.id) || profile.id == undoReturningProfileId,
                    cardHeight: metrics.cardHeight,
                    undoReturnEdge: profile.id == undoReturningProfileId ? undoReturnEdge : nil,
                    detailSwipeAction: nil,
                    stackProgress: index == 0 ? $discoverySwipeProgress : .constant(0),
                    onOpen: {
                        selectedDiscoveryProfile = profile
                    },
                    onLike: {
                        like(profile)
                    },
                    onPass: {
                        pass(profile)
                    }
                )
                .scaleEffect(stackScale(for: index))
                .offset(y: stackYOffset(for: index))
                .opacity(stackOpacity(for: index))
                .allowsHitTesting(index == 0)
                .zIndex(Double(3 - index))
            }
        }
        .padding(.horizontal, metrics.stackHorizontalPadding)
        .frame(height: metrics.cardHeight + metrics.stackExtraHeight)
        .animation(.interactiveSpring(response: 0.30, dampingFraction: 0.90), value: discoverySwipeProgress)
        .animation(.spring(response: 0.36, dampingFraction: 0.90), value: vm.profiles.first?.id)
    }

    private func stackScale(for index: Int) -> CGFloat {
        guard index > 0 else { return 1 }
        let base = 1 - CGFloat(index) * 0.045
        let lift = min(discoverySwipeProgress, 1) * 0.045
        return min(base + lift, index == 1 ? 1 : 0.955)
    }

    private func stackYOffset(for index: Int) -> CGFloat {
        guard index > 0 else { return 0 }
        let base = CGFloat(index) * 14
        let lift = min(discoverySwipeProgress, 1) * 14
        return max(base - lift, index == 1 ? 0 : 14)
    }

    private func stackOpacity(for index: Int) -> Double {
        guard index > 0 else { return 1 }
        let base = 1 - Double(index) * 0.18
        let lift = Double(min(discoverySwipeProgress, 1)) * 0.16
        return min(base + lift, index == 1 ? 1 : 0.88)
    }

    private func discoveryUtilityBar(for profile: Profile) -> some View {
        HStack(spacing: 10) {
            Button {
                undoLastSwipe()
            } label: {
                DiscoveryControlButton(
                    systemImage: "arrow.uturn.backward",
                    title: AppLanguageManager.localized("discovery_undo_button"),
                    isEnabled: vm.canShowUndo,
                    isLoading: vm.isUndoing
                )
            }
            .buttonStyle(.plain)
            .disabled(!vm.canShowUndo)
            .accessibilityLabel(AppLanguageManager.localized("discovery_undo_accessibility_label"))
            .opacity(vm.lastSwipedProfile == nil && !vm.isUndoing ? 0.46 : 1)

            Spacer()

            Menu {
                Button(role: .destructive) {
                    reportProfile = profile
                } label: {
                    Label(AppLanguageManager.localized("safety_report_button"), systemImage: "exclamationmark.bubble")
                }

                Button(role: .destructive) {
                    blockProfile = profile
                } label: {
                    Label(AppLanguageManager.localized("safety_block_button"), systemImage: "hand.raised")
                }
            } label: {
                DiscoveryControlButton(
                    systemImage: "ellipsis",
                    title: AppLanguageManager.localized("discovery_more_button"),
                    isEnabled: true,
                    isLoading: false
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLanguageManager.localized("discovery_more_button"))
        }
        .padding(.top, 1)
    }

    private func load() async {
        guard let userId = session.currentUserId else { return }
        await vm.loadFilters(userId: userId)
        await vm.loadInterestedInYou(userId: userId)
        await vm.loadProfiles(userId: userId, currentProfile: session.currentProfile)
    }

    private var blockAlertBinding: Binding<Bool> {
        Binding(
            get: { blockProfile != nil },
            set: { isPresented in
                if !isPresented {
                    blockProfile = nil
                }
            }
        )
    }

    private var noticeBinding: Binding<Bool> {
        Binding(
            get: { noticeMessage != nil },
            set: { isPresented in
                if !isPresented {
                    noticeMessage = nil
                }
            }
        )
    }

    private func blockSelectedProfile() async {
        guard let userId = session.currentUserId, let profile = blockProfile else { return }
        let didBlock = await safetyVM.blockUser(
            blockerUserId: userId,
            blockedUserId: profile.id,
            matchId: nil
        )

        if didBlock {
            vm.removeProfile(id: profile.id)
            noticeMessage = safetyVM.successMessage
        } else {
            noticeMessage = safetyVM.errorMessage
        }

        blockProfile = nil
    }

    private var interestedSectionEstimatedHeight: CGFloat {
        78
    }

    private func triggerDetailSwipe(for profile: Profile, isLike: Bool) {
        detailSwipeAction = nil
        suppressDecisionHapticForProfileId = profile.id

        let summary = vm.compatibilitySummary(for: profile)
        let cachedPhotoImage = DiscoveryCardPhotoView.cachedImage(for: profile.profilePhotoURL)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            detailSwipeGhost = DiscoveryDetailSwipeGhost(
                profile: profile,
                compatibilitySummary: summary,
                cachedPhotoImage: cachedPhotoImage,
                isLike: isLike
            )

            if isLike {
                like(profile)
            } else {
                pass(profile)
            }
        }
    }

    private func like(_ profile: Profile) {
        guard !vm.actingProfileIds.contains(profile.id) else { return }
        if suppressDecisionHapticForProfileId == profile.id {
            suppressDecisionHapticForProfileId = nil
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        Task {
            guard let userId = session.currentUserId else { return }
            await vm.like(userId: userId, targetUserId: profile.id)
        }
    }

    private func pass(_ profile: Profile) {
        guard !vm.actingProfileIds.contains(profile.id) else { return }
        if suppressDecisionHapticForProfileId == profile.id {
            suppressDecisionHapticForProfileId = nil
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        Task {
            guard let userId = session.currentUserId else { return }
            await vm.pass(userId: userId, targetUserId: profile.id)
        }
    }

    private func undoLastSwipe() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            guard let userId = session.currentUserId else { return }
            let returningProfile = vm.lastSwipedProfile
            let profileId = vm.lastSwipedProfile?.id
            undoReturnEdge = vm.lastSwipeAction == .pass ? .leading : .trailing

            await prewarmProfilePhoto(for: returningProfile)
            undoReturningProfileId = profileId

            let didUndo = await vm.undoLastSwipe(userId: userId)
            if !didUndo {
                undoReturningProfileId = nil
                noticeMessage = vm.errorMessage ?? AppLanguageManager.localized("discovery_no_swipe_to_undo_message")
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) {
                    if undoReturningProfileId == profileId {
                        undoReturningProfileId = nil
                    }
                }
            }
        }
    }

    private func prewarmProfilePhoto(for profile: Profile?) async {
        guard let photoPath = profile?.profilePhotoURL, !photoPath.isEmpty else { return }
        _ = try? await ProfilePhotoService.shared.signedURL(for: photoPath)
    }

}

private struct DiscoveryDetailSwipeAction: Equatable {
    let id = UUID()
    let profileId: UUID
    let isLike: Bool
}

private struct DiscoveryDetailSwipeGhost: Identifiable {
    let id = UUID()
    let profile: Profile
    let compatibilitySummary: CompatibilitySummary?
    let cachedPhotoImage: UIImage?
    let isLike: Bool
}

private struct DiscoveryDetailSwipeGhostCard: View {
    let ghost: DiscoveryDetailSwipeGhost
    let currentProfile: Profile?
    let cardHeight: CGFloat
    let topOffset: CGFloat
    let horizontalPadding: CGFloat
    let onComplete: () -> Void

    @State private var offset: CGSize = .zero
    @State private var hasStarted = false

    var body: some View {
        DiscoveryProfileCard(
            profile: ghost.profile,
            currentProfile: currentProfile,
            compatibilitySummary: ghost.compatibilitySummary,
            sharedHighlights: [],
            cardHeight: cardHeight,
            preloadedPhotoImage: ghost.cachedPhotoImage
        )
        .compositingGroup()
        .overlay(alignment: ghost.isLike ? .topLeading : .topTrailing) {
            Label(ghost.isLike ? AppLanguageManager.localized("discovery_like_badge") : AppLanguageManager.localized("discovery_pass_badge"), systemImage: ghost.isLike ? "heart.fill" : "xmark")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background {
                    Capsule()
                        .fill((ghost.isLike ? Color.green : Color.red).gradient)
                        .shadow(color: (ghost.isLike ? Color.green : Color.red).opacity(0.38), radius: 18, y: 8)
                }
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.55), lineWidth: 1)
                }
                .rotationEffect(.degrees(ghost.isLike ? -10 : 10))
                .padding(.horizontal, 22)
                .padding(.top, 28)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, horizontalPadding)
        .offset(x: offset.width, y: topOffset + offset.height)
        .rotationEffect(.degrees(Double(offset.width / 36)))
        .opacity(1)
        .scaleEffect(1)
        .allowsHitTesting(false)
        .zIndex(999)
        .transition(.identity)
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        guard !hasStarted else { return }
        hasStarted = true

        let animationDuration: TimeInterval = 3.0
        let exitWidth: CGFloat = 860
        let exitHeight: CGFloat = ghost.isLike ? -26 : 26

        withAnimation(.timingCurve(0.16, 0.84, 0.24, 1.0, duration: animationDuration)) {
            offset = CGSize(width: ghost.isLike ? exitWidth : -exitWidth, height: exitHeight)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
            onComplete()
        }
    }
}

private struct DiscoveryLoadingStateView: View {
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.pink.opacity(0.10))
                    .frame(width: 72, height: 72)

                ProgressView()
                    .controlSize(.regular)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 6) {
                Text(AppLanguageManager.localized("discovery_loading_title"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(AppLanguageManager.localized("discovery_loading_message"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .accessibilityElement(children: .combine)
    }
}

private struct DiscoveryErrorStateView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 72, height: 72)
                .background(Color.orange.opacity(0.10), in: Circle())
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(AppLanguageManager.localized("discovery_error_title"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Button(action: onRetry) {
                Label(AppLanguageManager.localized("common_try_again"), systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Color.pink, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .accessibilityElement(children: .combine)
    }
}

private struct DiscoveryEmptyStateView: View {
    let onOpenFilters: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.pink.opacity(0.10))
                    .frame(width: 76, height: 76)

                Image(systemName: "person.2.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.pink)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 7) {
                Text(AppLanguageManager.localized("discovery_empty_title"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(AppLanguageManager.localized("discovery_empty_message"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 26)
            }

            Button(action: onOpenFilters) {
                Label(AppLanguageManager.localized("discovery_adjust_filters_button"), systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.pink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Color.pink.opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
        .padding(.horizontal, 18)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 16, y: 8)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }
}

private struct DiscoveryControlButton: View {
    let systemImage: String
    let title: String
    let isEnabled: Bool
    let isLoading: Bool

    var body: some View {
        ZStack {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .bold))
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
        .frame(width: 40, height: 40)
        .background(.thinMaterial, in: Circle())
        .background(
            Circle()
                .fill(Color(.systemBackground).opacity(0.62))
        )
        .overlay {
            Circle()
                .stroke(.white.opacity(isEnabled ? 0.42 : 0.20), lineWidth: 1)
        }
        .shadow(color: .black.opacity(isEnabled ? 0.10 : 0.04), radius: 10, y: 4)
        .contentShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

private struct DiscoveryLayoutMetrics {
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let verticalSpacing: CGFloat
    let stackHorizontalPadding: CGFloat
    let stackExtraHeight: CGFloat
    let cardHeight: CGFloat

    init(size: CGSize) {
        let isCompactHeight = size.height < 640
        let isRegularHeight = size.height >= 760

        topPadding = isCompactHeight ? 2 : 4
        bottomPadding = isCompactHeight ? 2 : 4
        verticalSpacing = isCompactHeight ? 4 : 7
        stackHorizontalPadding = isCompactHeight ? 12 : 16
        stackExtraHeight = isCompactHeight ? 6 : 10

        let reservedHeight: CGFloat = isCompactHeight ? 146 : 172
        let minimumHeight: CGFloat = isCompactHeight ? 320 : 370
        let maximumHeight: CGFloat = isRegularHeight ? 600 : 560
        cardHeight = min(max(size.height - reservedHeight, minimumHeight), maximumHeight)
    }
}

private struct InterestedInYouSection: View {
    let profiles: [Profile]
    let totalCount: Int
    let isPremiumUser: Bool
    let profileCreatedAt: String?
    let isLoading: Bool
    let onSeeAll: () -> Void
    let onSelect: (Profile) -> Void
    let onLockedTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label(AppLanguageManager.localized("interested_in_you_title"), systemImage: "heart.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    onSeeAll()
                } label: {
                    Text(String.localizedStringWithFormat(AppLanguageManager.localized("interested_in_you_see_all_format"), totalCount))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.pink)
                }
                .disabled(totalCount == 0)
                .accessibilityLabel(String.localizedStringWithFormat(AppLanguageManager.localized("interested_in_you_see_all_accessibility_label_format"), totalCount))
            }

            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                        .accessibilityHidden(true)
                    Text(AppLanguageManager.localized("interested_in_you_checking_likes"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            } else if profiles.isEmpty {
                InterestedInYouEmptyStateView(state: emptyState)
                .frame(maxWidth: .infinity, minHeight: emptyState.minimumHeight)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(profiles) { profile in
                            InterestedInYouMiniCard(
                                profile: profile,
                                isPremiumUser: isPremiumUser,
                                onSelect: {
                                    isPremiumUser ? onSelect(profile) : onLockedTap()
                                }
                            )
                        }
                    }
                    .padding(.vertical, 1)
                }
                .frame(height: 52)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }

    private var emptyState: InterestedInYouEmptyState {
        guard !isPremiumUser,
              let createdAtDate = parseDate(profileCreatedAt) else {
            return .fresh
        }

        let hoursWithoutLikes = Date().timeIntervalSince(createdAtDate) / 3600
        if hoursWithoutLikes >= 72 {
            return .threeDaysOld
        }

        if hoursWithoutLikes >= 24 {
            return .dayOld
        }

        return .fresh
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractionalFormatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private enum InterestedInYouEmptyState {
    case fresh
    case dayOld
    case threeDaysOld

    var minimumHeight: CGFloat {
        switch self {
        case .fresh, .threeDaysOld:
            return 58
        case .dayOld:
            return 66
        }
    }
}

private struct InterestedInYouEmptyStateView: View {
    let state: InterestedInYouEmptyState

    var body: some View {
        switch state {
        case .fresh:
            VStack(spacing: 4) {
                Text(AppLanguageManager.localized("interested_empty_fresh_title"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(AppLanguageManager.localized("interested_empty_fresh_message"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(.horizontal, 8)

        case .dayOld:
            VStack(spacing: 6) {
                HStack(spacing: -8) {
                    ForEach(0..<4, id: \.self) { index in
                        SoftAnonymousLikeOrb(index: index)
                    }
                }

                Text(AppLanguageManager.localized("interested_empty_day_old_title"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(.horizontal, 8)

        case .threeDaysOld:
            VStack(spacing: 4) {
                Text(AppLanguageManager.localized("interested_empty_three_days_title"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(AppLanguageManager.localized("interested_empty_three_days_message"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 8)
        }
    }
}

private struct SoftAnonymousLikeOrb: View {
    let index: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: colors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .stroke(.white.opacity(0.62), lineWidth: 1)

            Image(systemName: symbolName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.70))
        }
        .frame(width: 34, height: 34)
        .shadow(color: colors.first?.opacity(0.18) ?? .clear, radius: 8, y: 4)
        .opacity(0.72)
        .accessibilityHidden(true)
    }

    private var colors: [Color] {
        switch index % 4 {
        case 0:
            return [.pink.opacity(0.42), .purple.opacity(0.20)]
        case 1:
            return [.orange.opacity(0.30), .pink.opacity(0.20)]
        case 2:
            return [.blue.opacity(0.24), .mint.opacity(0.18)]
        default:
            return [.purple.opacity(0.28), .indigo.opacity(0.18)]
        }
    }

    private var symbolName: String {
        index.isMultiple(of: 2) ? "heart.fill" : "sparkles"
    }
}

private struct InterestedInYouMiniCard: View {
    let profile: Profile
    let isPremiumUser: Bool
    let onSelect: () -> Void
    private let avatarSize: CGFloat = 48

    var body: some View {
        Button {
            onSelect()
        } label: {
            VStack(spacing: 0) {
                ZStack {
                    InterestedProfileImage(photoPath: profile.profilePhotoURL)
                        .frame(width: avatarSize, height: avatarSize)
                        .blur(radius: isPremiumUser ? 0 : 4.5)
                        .overlay {
                            if !isPremiumUser {
                                Color(.systemBackground).opacity(0.34)
                                    .clipShape(Circle())
                            }
                        }
                        .clipShape(Circle())

                    if !isPremiumUser {
                        LockedLikeCard()
                    }

                    VStack {
                        HStack {
                            Spacer()
                            Label(AppLanguageManager.localized("interested_mutual_like_label"), systemImage: "heart.fill")
                                .font(.caption2.weight(.bold))
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(.pink, in: Circle())
                        }
                        Spacer()
                    }
                    .frame(width: avatarSize, height: avatarSize)
                    .offset(x: 3, y: -3)
                }
                .frame(width: avatarSize, height: avatarSize)

                if isPremiumUser {
                    VStack(spacing: 1) {
                        Text(displayName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(profile.city ?? AppLanguageManager.localized("common_nearby"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(width: 60)
                }
            }
            .frame(width: 52)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if isPremiumUser {
            return String.localizedStringWithFormat(AppLanguageManager.localized("interested_profile_accessibility_label_format"), displayName)
        }

        return AppLanguageManager.localized("interested_locked_profile_accessibility_label")
    }

    private var displayName: String {
        let name = profile.publicName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? AppLanguageManager.localized("common_someone")

        guard let age = profile.displayAge else {
            return name
        }

        return String.localizedStringWithFormat(AppLanguageManager.localized("profile_name_age_format"), name, age)
    }
}

private struct LockedLikeCard: View {
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.primary.opacity(0.82))
            .frame(width: 26, height: 26)
            .background(.ultraThinMaterial, in: Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.40), lineWidth: 1)
            }
            .accessibilityLabel(AppLanguageManager.localized("interested_locked_profile_accessibility_label"))
    }
}

private struct InterestedProfileImage: View {
    let photoPath: String?
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .task(id: photoPath) {
            await loadImage()
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [.pink.opacity(0.18), .purple.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "person.fill")
                .foregroundStyle(.pink.opacity(0.7))
                .accessibilityHidden(true)
        }
    }

    private func loadImage() async {
        image = nil
        guard let photoPath, !photoPath.isEmpty else { return }

        if let cachedImage = ProfilePhotoService.shared.cachedImage(for: photoPath) {
            image = cachedImage
            return
        }

        image = try? await ProfilePhotoService.shared.image(for: photoPath)
    }
}

private struct InterestedInYouSheet: View {
    let profiles: [Profile]
    let isPremiumUser: Bool
    let onSelect: (Profile) -> Void
    let onLockedTap: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 78), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if profiles.isEmpty {
                    ContentUnavailableView(
                        AppLanguageManager.localized("interested_sheet_empty_title"),
                        systemImage: "heart",
                        description: Text(AppLanguageManager.localized("interested_sheet_empty_message"))
                    )
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(profiles) { profile in
                            InterestedInYouMiniCard(
                                profile: profile,
                                isPremiumUser: isPremiumUser,
                                onSelect: {
                                    isPremiumUser ? onSelect(profile) : onLockedTap()
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(AppLanguageManager.localized("interested_in_you_title"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct InterestedInYouPaywallSheet: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.pink)
                .accessibilityHidden(true)

            Text(AppLanguageManager.localized("interested_paywall_title"))
                .font(.title3.weight(.bold))

            Text(AppLanguageManager.localized("interested_paywall_message"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}


private struct SwipeableDiscoveryCard: View {
    let profile: Profile
    let currentProfile: Profile?
    let compatibilitySummary: CompatibilitySummary?
    let sharedHighlights: [String]
    let isInteractive: Bool
    let isDisabled: Bool
    let cardHeight: CGFloat
    let undoReturnEdge: Edge?
    let detailSwipeAction: DiscoveryDetailSwipeAction?
    @Binding var stackProgress: CGFloat
    let onOpen: () -> Void
    let onLike: () -> Void
    let onPass: () -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var isAnimatingAway = false
    @State private var hasPlayedUndoReturn = true
    @State private var isDetailTriggeredSwipe = false
    @State private var detailSwipeBadgeIsLike: Bool?

    private let actionThreshold: CGFloat = 110

    init(
        profile: Profile,
        currentProfile: Profile?,
        compatibilitySummary: CompatibilitySummary?,
        sharedHighlights: [String],
        isInteractive: Bool,
        isDisabled: Bool,
        cardHeight: CGFloat,
        undoReturnEdge: Edge?,
        detailSwipeAction: DiscoveryDetailSwipeAction?,
        stackProgress: Binding<CGFloat>,
        onOpen: @escaping () -> Void,
        onLike: @escaping () -> Void,
        onPass: @escaping () -> Void
    ) {
        self.profile = profile
        self.currentProfile = currentProfile
        self.compatibilitySummary = compatibilitySummary
        self.sharedHighlights = sharedHighlights
        self.isInteractive = isInteractive
        self.isDisabled = isDisabled
        self.cardHeight = cardHeight
        self.undoReturnEdge = undoReturnEdge
        self.detailSwipeAction = detailSwipeAction
        self._stackProgress = stackProgress
        self.onOpen = onOpen
        self.onLike = onLike
        self.onPass = onPass
        self._hasPlayedUndoReturn = State(initialValue: undoReturnEdge == nil)
    }

    var body: some View {
        DiscoveryProfileCard(
            profile: profile,
            currentProfile: currentProfile,
            compatibilitySummary: compatibilitySummary,
            sharedHighlights: sharedHighlights,
            cardHeight: cardHeight
        )
            .overlay(alignment: badgeIsLike ? .topLeading : .topTrailing) {
                swipeBadge
                    .padding(.horizontal, 22)
                    .padding(.top, 28)
                    .opacity(actionBadgeProgress)
                    .scaleEffect(0.86 + actionBadgeProgress * 0.14)
            }
            .offset(x: totalOffset.width, y: totalOffset.height)
            .rotationEffect(.degrees(rotationDegrees))
            .scaleEffect(isAnimatingAway ? 0.96 : 1)
            .animation(.easeInOut(duration: 0.14), value: isAnimatingAway)
            .animation(.interpolatingSpring(stiffness: 135, damping: 19), value: hasPlayedUndoReturn)
            .highPriorityGesture(
                DragGesture(minimumDistance: 16, coordinateSpace: .local)
                    .onChanged { value in
                        guard isInteractive, !isDisabled else { return }
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        dragOffset = value.translation
                        stackProgress = currentSwipeProgress(for: value.translation.width)
                    }
                    .onEnded { value in
                        guard isInteractive, !isDisabled else {
                            resetCard()
                            return
                        }

                        let horizontal = value.translation.width
                        guard abs(horizontal) >= actionThreshold else {
                            resetCard()
                            return
                        }

                        completeSwipe(isLike: horizontal > 0)
                    }
            )
            .onChange(of: profile.id) { _, _ in
                dragOffset = .zero
                isAnimatingAway = false
                stackProgress = 0
                hasPlayedUndoReturn = undoReturnEdge == nil
                isDetailTriggeredSwipe = false
                detailSwipeBadgeIsLike = nil
                playUndoReturnIfNeeded()
            }
            .onChange(of: detailSwipeAction?.id) { _, _ in
                guard let detailSwipeAction,
                      detailSwipeAction.profileId == profile.id,
                      isInteractive,
                      !isDisabled else { return }

                isDetailTriggeredSwipe = true
                detailSwipeBadgeIsLike = detailSwipeAction.isLike
                completeSwipe(isLike: detailSwipeAction.isLike)
            }
            .onAppear {
                playUndoReturnIfNeeded()
            }
            .onTapGesture {
                guard isInteractive, !isDisabled, dragOffset == .zero else { return }
                onOpen()
            }
    }

    private var swipeBadge: some View {
        let isLike = badgeIsLike
        let color = isLike ? Color.green : Color.red

        return Label(isLike ? AppLanguageManager.localized("discovery_like_badge") : AppLanguageManager.localized("discovery_pass_badge"), systemImage: isLike ? "heart.fill" : "xmark")
            .font(.system(size: 24, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background {
                Capsule()
                    .fill(color.gradient)
                    .shadow(color: color.opacity(0.38), radius: 18, y: 8)
            }
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.55), lineWidth: 1)
            }
            .rotationEffect(.degrees(isLike ? -10 : 10))
            .accessibilityHidden(true)
    }

    private var actionBadgeProgress: CGFloat {
        if isDetailTriggeredSwipe {
            return 1
        }

        return currentSwipeProgress(for: dragOffset.width)
    }

    private var badgeIsLike: Bool {
        detailSwipeBadgeIsLike ?? (dragOffset.width >= 0)
    }

    private var undoReturnOffset: CGSize {
        guard let undoReturnEdge, !hasPlayedUndoReturn else { return .zero }
        return CGSize(width: undoReturnEdge == .leading ? -520 : 520, height: 24)
    }

    private var totalOffset: CGSize {
        CGSize(
            width: undoReturnOffset.width + dragOffset.width,
            height: undoReturnOffset.height + dragOffset.height * 0.18
        )
    }

    private var rotationDegrees: Double {
        if let undoReturnEdge, !hasPlayedUndoReturn {
            return undoReturnEdge == .leading ? -8 : 8
        }

        return Double(dragOffset.width / 24)
    }

    private func currentSwipeProgress(for width: CGFloat) -> CGFloat {
        min(abs(width) / actionThreshold, 1)
    }

    private func completeSwipe(isLike: Bool) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isAnimatingAway = true

        if isDetailTriggeredSwipe {
            withAnimation(.easeOut(duration: 0.40)) {
                stackProgress = 1
            }
        } else {
            stackProgress = 1
        }

        let animationDuration: TimeInterval = isDetailTriggeredSwipe ? 3.0 : 0.24
        let exitWidth: CGFloat = isDetailTriggeredSwipe ? 860 : 520
        let exitHeight: CGFloat = isDetailTriggeredSwipe ? (isLike ? -26 : 26) : dragOffset.height * 0.35

        let animation: Animation = isDetailTriggeredSwipe
            ? .timingCurve(0.16, 0.84, 0.24, 1.0, duration: animationDuration)
            : .easeInOut(duration: animationDuration)

        withAnimation(animation) {
            dragOffset = CGSize(width: isLike ? exitWidth : -exitWidth, height: exitHeight)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
            if isLike {
                onLike()
            } else {
                onPass()
            }
            stackProgress = 0
            isDetailTriggeredSwipe = false
            detailSwipeBadgeIsLike = nil
        }
    }

    private func resetCard() {
        withAnimation(.interactiveSpring(response: 0.26, dampingFraction: 0.88)) {
            dragOffset = .zero
            isAnimatingAway = false
            stackProgress = 0
        }
    }

    private func playUndoReturnIfNeeded() {
        guard undoReturnEdge != nil, !hasPlayedUndoReturn else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            withAnimation(.interpolatingSpring(stiffness: 135, damping: 19)) {
                hasPlayedUndoReturn = true
            }
        }
    }
}


private struct DiscoveryProfileCard: View {
    let profile: Profile
    let currentProfile: Profile?
    let compatibilitySummary: CompatibilitySummary?
    let sharedHighlights: [String]
    let cardHeight: CGFloat
    var preloadedPhotoImage: UIImage? = nil
    @AppStorage(PrivacyPreferenceKey.showDistance) private var showDistance = true

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            DiscoveryCardPhotoView(urlString: profile.profilePhotoURL, preloadedImage: preloadedPhotoImage)
                .id(profile.id)

            if let compatibilitySummary {
                VStack {
                    HStack {
                        CompatibilityScoreBadge(summary: compatibilitySummary)
                        Spacer()
                        if let proximityBadgeText {
                            DiscoveryProximityBadge(text: proximityBadgeText)
                        }
                    }
                    Spacer()
                }
                .padding(16)
            } else if let proximityBadgeText {
                VStack {
                    HStack {
                        Spacer()
                        DiscoveryProximityBadge(text: proximityBadgeText)
                    }
                    Spacer()
                }
                .padding(16)
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.38), .black.opacity(0.82)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(nameAgeText)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(genderText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 8) {
                    FlexibleDiscoveryPillRow {
                        if showDistance {
                            DiscoveryInfoPill(icon: "location.fill", text: distanceText)
                        }
                        DiscoveryInfoPill(icon: "ruler", text: heightText)
                        DiscoveryInfoPill(icon: "heart.fill", text: relationshipGoalText)
                    }

                    if !sharedSignalTexts.isEmpty {
                        FlexibleDiscoveryPillRow {
                            ForEach(sharedSignalTexts, id: \.self) { text in
                                DiscoverySharedSignalPill(text: text)
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cardAccessibilityLabel)
    }

    private var cardAccessibilityLabel: String {
        String.localizedStringWithFormat(
            AppLanguageManager.localized("discovery_card_accessibility_label_format"),
            nameAgeText,
            genderText,
            distanceText,
            relationshipGoalText
        )
    }

    private var nameAgeText: String {
        let name = profile.publicName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? AppLanguageManager.localized("common_verified_user")

        if let age = profile.displayAge {
            return String.localizedStringWithFormat(AppLanguageManager.localized("profile_name_age_format"), name, age)
        }

        return name
    }

    private var genderText: String {
        guard let gender = profile.gender else {
            return AppLanguageManager.localized("profile_gender_not_added")
        }

        return localizedGender(gender.rawValue)
    }

    private var relationshipGoalText: String {
        guard let goal = profile.relationshipGoal else {
            return AppLanguageManager.localized("profile_relationship_goal_not_added")
        }

        return localizedRelationshipGoal(goal.rawValue)
    }

    private var heightText: String {
        guard let height = profile.heightCm else {
            return AppLanguageManager.localized("profile_height_not_added")
        }

        return String.localizedStringWithFormat(AppLanguageManager.localized("profile_height_cm_format"), height)
    }


    private var distanceText: String {
        guard let distance = distanceKm else {
            return AppLanguageManager.localized("profile_distance_unavailable")
        }

        if distance < 1 {
            return AppLanguageManager.localized("profile_distance_less_than_1km")
        }

        return String.localizedStringWithFormat(AppLanguageManager.localized("profile_distance_km_away_format"), Int(distance.rounded()))
    }

    private var proximityBadgeText: String? {
        guard showDistance else { return nil }
        guard let distance = distanceKm else { return nil }

        if distance <= 0.35 {
            return AppLanguageManager.localized("profile_proximity_very_near")
        }

        if distance <= 1 {
            return AppLanguageManager.localized("profile_proximity_nearby_now")
        }

        return nil
    }

    private var distanceKm: Double? {
        guard
            let currentLatitude = currentProfile?.latitude,
            let currentLongitude = currentProfile?.longitude,
            let profileLatitude = profile.latitude,
            let profileLongitude = profile.longitude
        else {
            return nil
        }

        return haversineDistanceKm(
            fromLatitude: currentLatitude,
            fromLongitude: currentLongitude,
            toLatitude: profileLatitude,
            toLongitude: profileLongitude
        )
    }

    private var sharedSignalTexts: [String] {
        var signals: [String] = sharedHighlights.map {
            String.localizedStringWithFormat(AppLanguageManager.localized("profile_shared_both_like_format"), $0)
        }

        if let sharedLanguage {
            signals.append(String.localizedStringWithFormat(AppLanguageManager.localized("profile_shared_both_speak_format"), sharedLanguage))
        }

        if let sharedLifestyle {
            signals.append(sharedLifestyle)
        }

        return Array(signals.prefix(3))
    }

    private var sharedLanguage: String? {
        firstSharedMultiValue(currentProfile?.languages, profile.languages)
    }

    private var sharedLifestyle: String? {
        if let exercise = matchingSingleValue(currentProfile?.exercise, profile.exercise) {
            return String.localizedStringWithFormat(AppLanguageManager.localized("profile_shared_both_format"), localizedLifestyleValue(exercise).lowercased())
        }

        if let pet = firstSharedMultiValue(currentProfile?.pets, profile.pets) {
            return String.localizedStringWithFormat(AppLanguageManager.localized("profile_shared_both_colon_format"), pet)
        }

        return nil
    }

    private func matchingSingleValue(_ lhs: String?, _ rhs: String?) -> String? {
        guard let lhs = lhs?.trimmingCharacters(in: .whitespacesAndNewlines),
              let rhs = rhs?.trimmingCharacters(in: .whitespacesAndNewlines),
              !lhs.isEmpty,
              !rhs.isEmpty,
              lhs.localizedCaseInsensitiveCompare(rhs) == .orderedSame else {
            return nil
        }

        return rhs
    }

    private func firstSharedMultiValue(_ lhs: String?, _ rhs: String?) -> String? {
        let leftValues = splitValues(lhs)
        guard !leftValues.isEmpty else { return nil }

        let leftSet = Set(leftValues.map(normalizedValue))
        return splitValues(rhs).first { leftSet.contains(normalizedValue($0)) }
    }

    private func splitValues(_ value: String?) -> [String] {
        value?
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    private func normalizedValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func haversineDistanceKm(
        fromLatitude: Double,
        fromLongitude: Double,
        toLatitude: Double,
        toLongitude: Double
    ) -> Double {
        let earthRadiusKm = 6_371.0
        let latitudeDelta = degreesToRadians(toLatitude - fromLatitude)
        let longitudeDelta = degreesToRadians(toLongitude - fromLongitude)
        let fromLatitudeRadians = degreesToRadians(fromLatitude)
        let toLatitudeRadians = degreesToRadians(toLatitude)

        let a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(fromLatitudeRadians) * cos(toLatitudeRadians)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))

        return earthRadiusKm * c
    }

    private func degreesToRadians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }

}

private struct ProfilePhotoView: View {
    let urlString: String?

    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    photoPlaceholder
                        .overlay {
                            if isLoading {
                                ProgressView()
                                    .accessibilityHidden(true)
                            }
                        }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 340)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        }
        .accessibilityLabel(AppLanguageManager.localized("profile_photo_accessibility_label"))
        .task(id: urlString) {
            await loadSignedURL()
        }
    }

    private var photoPlaceholder: some View {
        ZStack {
            Color.secondary.opacity(0.12)
            Image(systemName: "person.crop.square")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private func loadSignedURL() async {
        guard let path = urlString?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            image = nil
            isLoading = false
            return
        }

        if let cachedImage = ProfilePhotoService.shared.cachedImage(for: path) {
            image = cachedImage
            isLoading = false
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let loadedImage: UIImage
            if let directURL = URL(string: path), directURL.scheme?.hasPrefix("http") == true {
                let (data, _) = try await URLSession.shared.data(from: directURL)
                guard let decodedImage = UIImage(data: data) else { return }
                loadedImage = decodedImage
            } else {
                loadedImage = try await ProfilePhotoService.shared.image(for: path)
            }
            guard path == urlString else { return }
            image = loadedImage
        } catch {
            print("Failed to load signed URL:", error.localizedDescription)
        }
    }
}

private struct DiscoveryCardPhotoView: View {
    let urlString: String?
    var preloadedImage: UIImage? = nil

    @State private var image: UIImage?
    @MainActor private static let imageCache = NSCache<NSURL, UIImage>()
    @MainActor private static let pathImageCache = NSCache<NSString, UIImage>()

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let image = image ?? preloadedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    photoPlaceholder
                        .overlay {
                            ProgressView()
                                .tint(.white)
                                .accessibilityHidden(true)
                        }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .accessibilityLabel(AppLanguageManager.localized("profile_photo_accessibility_label"))
        .task(id: urlString) {
            await loadImage()
        }
    }

    private var photoPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.secondary.opacity(0.22), Color.secondary.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "person.crop.square.fill")
                .font(.system(size: 64))
                .foregroundStyle(.white.opacity(0.72))
                .accessibilityHidden(true)
        }
    }

    @MainActor
    static func cachedImage(for path: String?) -> UIImage? {
        guard let path, !path.isEmpty else { return nil }
        return pathImageCache.object(forKey: path as NSString)
    }

    @MainActor
    private func loadImage() async {
        guard let path = urlString, !path.isEmpty else {
            image = nil
            return
        }

        if preloadedImage != nil {
            return
        }

        let pathKey = path as NSString
        if let cachedImage = Self.pathImageCache.object(forKey: pathKey) {
            image = cachedImage
            return
        }

        image = nil

        do {
            let loadedURL = try await ProfilePhotoService.shared.signedURL(for: path)
            guard path == urlString else { return }

            if let cachedImage = Self.imageCache.object(forKey: loadedURL as NSURL) {
                Self.pathImageCache.setObject(cachedImage, forKey: pathKey)
                image = cachedImage
                return
            }

            let (data, _) = try await URLSession.shared.data(from: loadedURL)
            guard path == urlString, let loadedImage = UIImage(data: data) else { return }

            Self.imageCache.setObject(loadedImage, forKey: loadedURL as NSURL)
            Self.pathImageCache.setObject(loadedImage, forKey: pathKey)
            image = loadedImage
        } catch {
            print("Failed to load signed URL:", error.localizedDescription)
        }
    }
}
private struct CompatibilityScoreBadge: View {
    let summary: CompatibilitySummary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.caption.weight(.bold))
                .accessibilityHidden(true)

            Text(summary.label)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)

            Text("·")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
                .accessibilityHidden(true)

            Text(String.localizedStringWithFormat(AppLanguageManager.localized("compatibility_score_percent_format"), summary.score))
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.24), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String.localizedStringWithFormat(AppLanguageManager.localized("compatibility_score_accessibility_format"), summary.label, summary.score))
    }
}

private enum CompatibilityReasonValue {
    static let verifiedProfile = "Verified Profile"
}

private struct CompatibilitySummaryCard: View {
    let summary: CompatibilitySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.pink.opacity(0.12))
                        .accessibilityHidden(true)

                    Text(String.localizedStringWithFormat(AppLanguageManager.localized("compatibility_score_percent_format"), summary.score))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.pink)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.label)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(AppLanguageManager.localized("compatibility_guide_subtitle"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if !displayReasons.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(displayReasons, id: \.self) { reason in
                        Label(reason, systemImage: "checkmark.circle.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(AppLanguageManager.localized("compatibility_guide_message"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 16, y: 8)
        .accessibilityElement(children: .combine)
    }

    private var displayReasons: [String] {
        summary.reasons.filter { reason in
            reason.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(CompatibilityReasonValue.verifiedProfile) != .orderedSame
        }
    }
}

private struct DiscoveryInfoPill: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
    }
}

private struct FlexibleDiscoveryPillRow<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 7) {
            content
        }
    }
}

private struct DiscoverySharedSignalPill: View {
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkle")
                .font(.caption2.weight(.bold))
                .accessibilityHidden(true)

            Text(text)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.80)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            LinearGradient(
                colors: [.pink.opacity(0.72), .purple.opacity(0.58)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.26), lineWidth: 1)
        }
        .shadow(color: .pink.opacity(0.20), radius: 12, y: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

private struct DiscoveryProximityBadge: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "figure.walk.motion")
            .font(.caption2.weight(.black))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.green.opacity(0.86), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.42), lineWidth: 1)
            }
            .shadow(color: .green.opacity(0.30), radius: 14, y: 6)
            .accessibilityElement(children: .combine)
    }
}

struct DiscoveryProfileDetailView: View {
    @EnvironmentObject var session: SessionViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PrivacyPreferenceKey.showDistance) private var showDistance = true
    @StateObject private var safetyVM = SafetyViewModel()
    @State private var isShowingReport = false
    @State private var isShowingBlockAlert = false
    @State private var noticeMessage: String?

    let profile: Profile
    let currentProfile: Profile?
    let compatibilitySummary: CompatibilitySummary?
    let onBlocked: () -> Void
    var onLike: (() -> Void)? = nil
    var onPass: (() -> Void)? = nil
    var isPreview = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                PublicProfilePreviewContent(
                    profile: profile,
                    currentProfile: currentProfile,
                    showsPreviewLabel: isPreview
                )

                if let compatibilitySummary {
                    CompatibilitySummaryCard(summary: compatibilitySummary)
                }

                if !isPreview {
                    DiscoveryProfileActionPanel(
                        showsDiscoveryActions: showsDiscoveryActions,
                        isSubmittingSafetyAction: safetyVM.isSubmitting,
                        onPass: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            dismiss()
                            onPass?()
                        },
                        onLike: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            dismiss()
                            onLike?()
                        },
                        onReport: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            isShowingReport = true
                        },
                        onBlock: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            isShowingBlockAlert = true
                        }
                    )
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(isPreview ? AppLanguageManager.localized("profile_preview_title") : AppLanguageManager.localized("profile_detail_title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingReport) {
            if let userId = session.currentUserId {
                SafetyReportSheet(
                    reporterUserId: userId,
                    reportedUserId: profile.id,
                    matchId: nil,
                    reportedName: profile.publicName ?? AppLanguageManager.localized("common_user")
                )
            }
        }
        .alert(AppLanguageManager.localized("safety_block_user_title"), isPresented: $isShowingBlockAlert) {
            Button(AppLanguageManager.localized("common_cancel"), role: .cancel) {}
            Button(AppLanguageManager.localized("safety_block_button"), role: .destructive) {
                Task {
                    await blockUser()
                }
            }
        } message: {
            Text(AppLanguageManager.localized("safety_block_user_message"))
        }
        .alert(AppLanguageManager.localized("safety_alert_title"), isPresented: noticeBinding) {
            Button(AppLanguageManager.localized("common_ok")) {
                noticeMessage = nil
                if safetyVM.successMessage != nil {
                    dismiss()
                }
            }
        } message: {
            Text(noticeMessage ?? "")
        }
    }

    private var showsDiscoveryActions: Bool {
        onLike != nil && onPass != nil
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailRow(title: AppLanguageManager.localized("profile_detail_location_label"), value: locationDetailText)
            DetailRow(title: AppLanguageManager.localized("profile_detail_work_label"), value: joinParts([profile.displayJobTitle, profile.displayCompanyName]))
            DetailRow(title: AppLanguageManager.localized("profile_detail_education_label"), value: joinParts([profile.educationLevel, profile.schoolName]))
            DetailRow(title: AppLanguageManager.localized("profile_detail_height_label"), value: profile.heightCm.map { String.localizedStringWithFormat(AppLanguageManager.localized("profile_height_cm_format"), $0) } ?? AppLanguageManager.localized("common_not_provided"))
            DetailRow(title: AppLanguageManager.localized("profile_detail_marital_status_label"), value: maritalStatusText)
            DetailRow(title: AppLanguageManager.localized("profile_detail_relationship_goal_label"), value: relationshipGoalText)
            DetailRow(title: AppLanguageManager.localized("profile_detail_bio_label"), value: profile.bio?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? AppLanguageManager.localized("common_not_provided"))
        }
    }

    private var summaryText: String {
        joinParts([ageText, genderText, showDistance ? distanceText : nil])
    }

    private var ageText: String {
        if let age = profile.displayAge {
            return String.localizedStringWithFormat(AppLanguageManager.localized("profile_age_format"), age)
        }

        return AppLanguageManager.localized("profile_age_not_added")
    }

    private var genderText: String {
        profile.gender.map { localizedGender($0.rawValue) } ?? AppLanguageManager.localized("profile_gender_not_added")
    }

    private var relationshipGoalText: String {
        profile.relationshipGoal.map { localizedRelationshipGoal($0.rawValue) } ?? AppLanguageManager.localized("common_not_provided")
    }

    private var maritalStatusText: String {
        profile.maritalStatus.map { localizedMaritalStatus($0.rawValue) } ?? AppLanguageManager.localized("common_not_provided")
    }

    private var locationDetailText: String {
        let currentlyLiving = joinParts([profile.currentlyLiving ?? profile.city, profile.country])
        let cleanCurrentlyLiving = currentlyLiving.isEmpty ? AppLanguageManager.localized("profile_location_not_added") : currentlyLiving

        guard let hometown = profile.hometown?.trimmingCharacters(in: .whitespacesAndNewlines),
              !hometown.isEmpty else {
            return cleanCurrentlyLiving
        }

        return String.localizedStringWithFormat(AppLanguageManager.localized("profile_location_from_format"), cleanCurrentlyLiving, hometown)
    }

    private var distanceText: String {
        guard showDistance else { return "" }
        guard
            let currentLatitude = currentProfile?.latitude,
            let currentLongitude = currentProfile?.longitude,
            let profileLatitude = profile.latitude,
            let profileLongitude = profile.longitude
        else {
            return AppLanguageManager.localized("profile_distance_unavailable")
        }

        let distance = haversineDistanceKm(
            fromLatitude: currentLatitude,
            fromLongitude: currentLongitude,
            toLatitude: profileLatitude,
            toLongitude: profileLongitude
        )

        if distance < 1 {
            return AppLanguageManager.localized("profile_distance_less_than_1km")
        }

        return String.localizedStringWithFormat(AppLanguageManager.localized("profile_distance_km_away_format"), Int(distance.rounded()))
    }

    private var noticeBinding: Binding<Bool> {
        Binding(
            get: { noticeMessage != nil },
            set: { isPresented in
                if !isPresented {
                    noticeMessage = nil
                    safetyVM.errorMessage = nil
                    safetyVM.successMessage = nil
                }
            }
        )
    }

    private func blockUser() async {
        guard let userId = session.currentUserId else { return }
        let didBlock = await safetyVM.blockUser(
            blockerUserId: userId,
            blockedUserId: profile.id,
            matchId: nil
        )

        if didBlock {
            onBlocked()
            noticeMessage = safetyVM.successMessage
        } else {
            noticeMessage = safetyVM.errorMessage
        }
    }

    private func joinParts(_ parts: [String?]) -> String {
        parts
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: AppLanguageManager.localized("common_list_separator"))
    }



    private func haversineDistanceKm(
        fromLatitude: Double,
        fromLongitude: Double,
        toLatitude: Double,
        toLongitude: Double
    ) -> Double {
        let earthRadiusKm = 6_371.0
        let latitudeDelta = degreesToRadians(toLatitude - fromLatitude)
        let longitudeDelta = degreesToRadians(toLongitude - fromLongitude)
        let fromLatitudeRadians = degreesToRadians(fromLatitude)
        let toLatitudeRadians = degreesToRadians(toLatitude)

        let a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(fromLatitudeRadians) * cos(toLatitudeRadians)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))

        return earthRadiusKm * c
    }

    private func degreesToRadians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }

}

private struct DiscoveryProfileActionPanel: View {
    let showsDiscoveryActions: Bool
    let isSubmittingSafetyAction: Bool
    let onPass: () -> Void
    let onLike: () -> Void
    let onReport: () -> Void
    let onBlock: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            if showsDiscoveryActions {
                HStack(spacing: 18) {
                    DiscoveryProfileDecisionButton(
                        title: AppLanguageManager.localized("discovery_pass_button"),
                        systemImage: "xmark",
                        tint: .secondary,
                        style: .secondary,
                        action: onPass
                    )

                    DiscoveryProfileDecisionButton(
                        title: AppLanguageManager.localized("discovery_like_button"),
                        systemImage: "heart.fill",
                        tint: .pink,
                        style: .primary,
                        action: onLike
                    )
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(AppLanguageManager.localized("safety_section_title"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)

                HStack(spacing: 10) {
                    DiscoveryProfileSafetyButton(
                        title: AppLanguageManager.localized("safety_report_button"),
                        systemImage: "exclamationmark.bubble",
                        tint: .orange,
                        isLoading: false,
                        action: onReport
                    )
                    .accessibilityLabel(AppLanguageManager.localized("safety_report_button"))

                    DiscoveryProfileSafetyButton(
                        title: AppLanguageManager.localized("safety_block_button"),
                        systemImage: "hand.raised.fill",
                        tint: .red,
                        isLoading: isSubmittingSafetyAction,
                        action: onBlock
                    )
                    .disabled(isSubmittingSafetyAction)
                    .accessibilityLabel(AppLanguageManager.localized("safety_block_button"))
                    .opacity(isSubmittingSafetyAction ? 0.70 : 1)
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 16, y: 8)
    }
}

private struct DiscoveryProfileDecisionButton: View {
    enum Style {
        case primary
        case secondary
    }

    let title: String
    let systemImage: String
    let tint: Color
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .bold))
                    .accessibilityHidden(true)

                Text(title)
                    .font(.headline.weight(.bold))
            }
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(backgroundView)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
            .shadow(color: shadowColor, radius: 14, y: 7)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var foregroundColor: Color {
        style == .primary ? .white : tint
    }

    @ViewBuilder
    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(style == .primary ? tint.gradient : Color(.secondarySystemBackground).gradient)
    }

    private var borderColor: Color {
        style == .primary ? Color.white.opacity(0.18) : tint.opacity(0.18)
    }

    private var shadowColor: Color {
        style == .primary ? tint.opacity(0.25) : Color.black.opacity(0.04)
    }
}

private struct DiscoveryProfileSafetyButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: systemImage)
                            .font(.system(size: 14, weight: .semibold))
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: 22, height: 22)

                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(tint.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct DetailRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String.localizedStringWithFormat(AppLanguageManager.localized("profile_detail_row_accessibility_format"), title, value))
    }
}

private func localizedGender(_ value: String) -> String {
    LocalizedProfileDisplay.option(value)
}

private func localizedRelationshipGoal(_ value: String) -> String {
    LocalizedProfileDisplay.option(value)
}

private func localizedMaritalStatus(_ value: String) -> String {
    LocalizedProfileDisplay.option(value)
}

private func localizedLifestyleValue(_ value: String) -> String {
    switch value {
    case "daily":
        return AppLanguageManager.localized("lifestyle.daily")
    case "often":
        return AppLanguageManager.localized("lifestyle.often")
    case "sometimes":
        return AppLanguageManager.localized("lifestyle.sometimes")
    case "rarely":
        return AppLanguageManager.localized("lifestyle.rarely")
    case "never":
        return AppLanguageManager.localized("lifestyle.never")
    default:
        return LocalizedProfileDisplay.option(value)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
