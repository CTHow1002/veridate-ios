import Combine
import CoreLocation
import Foundation
import MapKit
import SwiftUI
import PostgREST
import Supabase
import UIKit
import UserNotifications

struct ProfileView: View {
    @EnvironmentObject var session: SessionViewModel
    @State private var showEditProfile = false
    @StateObject private var locationManager = LocationManager()
    @State private var readableLocation: String?
    @State private var isUpdatingLocation = false
    @State private var profilePhotoCount = 0
    @State private var profilePromptCount = 0
    @State private var showVisibilitySettings = false
    @State private var showProfilePreview = false
    @State private var showSettings = false
    @State private var settingsNotice: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                List {
                if let profile = session.currentProfile {
                    ProfileSummaryCard(
                        profile: profile,
                        locationText: locationText(for: profile)
                    )
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    ProfilePrimaryActionRow(
                        onEdit: {
                            HapticManager.light()
                            showEditProfile = true
                        },
                        onPreview: {
                            HapticManager.light()
                            showProfilePreview = true
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    ProfileStrengthCard(
                        strength: ProfileStrength(
                            profile: profile,
                            photoCount: profilePhotoCount,
                            promptCount: profilePromptCount
                        ),
                        onSuggestionTap: {
                            HapticManager.light()
                            showEditProfile = true
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    VerificationTrustCard(status: profile.verificationStatus)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    AccountStatusCard(
                        profile: profile,
                        onVisibilitySettingsTap: {
                            HapticManager.light()
                            showVisibilitySettings = true
                        }
                    )
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    EmptyStateView(
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        title: AppLanguageManager.localized("profile.empty.title"),
                        message: AppLanguageManager.localized("profile.empty.message"),
                        actionTitle: AppLanguageManager.localized("profile.edit.title"),
                        action: {
                            showEditProfile = true
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(AppLanguageManager.localized("profile.me.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        HapticManager.light()
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 34, height: 34)
                            .background(Color(.secondarySystemGroupedBackground), in: Circle())
                    }
                    .accessibilityLabel(AppLanguageManager.localized("profile.settings.title"))
                }
            }
            .sheet(isPresented: $showEditProfile) {
                EditProfileView()
                    .environmentObject(session)
            }
            .sheet(isPresented: $showVisibilitySettings) {
                VisibilitySettingsSheet()
                    .environmentObject(session)
            }
            .sheet(isPresented: $showProfilePreview) {
                if let profile = session.currentProfile {
                    ProfilePreviewSheet(
                        profile: profile,
                        locationText: locationText(for: profile)
                    )
                        .environmentObject(session)
                }
            }
            .sheet(isPresented: $showSettings) {
                MeSettingsSheet(notice: $settingsNotice)
                    .environmentObject(session)
            }
            .task {
                await session.loadProfile()
                await loadProfileCompletionCounts()
                locationManager.requestLocation()
                await loadReadableLocation()
            }
            .onChange(of: session.currentProfile?.id) { _, _ in
                Task {
                    await loadProfileCompletionCounts()
                }
            }
            .onChange(of: showEditProfile) { _, isPresented in
                guard !isPresented else { return }
                Task {
                    await session.loadProfile()
                    await loadProfileCompletionCounts()
                }
            }
            .onReceive(locationManager.$coordinate.compactMap { $0 }) { coordinate in
                Task {
                    isUpdatingLocation = true
                    _ = await session.updateProfileLocation(coordinate)
                    await session.loadProfile()
                    await loadReadableLocation()
                    isUpdatingLocation = false
                }
            }
            .alert(AppLanguageManager.localized("profile.settings.title"), isPresented: Binding(
                get: { settingsNotice != nil },
                set: { isPresented in
                    if !isPresented {
                        settingsNotice = nil
                    }
                }
            )) {
                Button(AppLanguageManager.localized("common.ok"), role: .cancel) { }
            } message: {
                Text(settingsNotice ?? "")
            }
            }
        }
    }

    private func loadProfileCompletionCounts() async {
        guard let userId = session.currentProfile?.id else {
            profilePhotoCount = 0
            profilePromptCount = 0
            return
        }

        let fallbackPhotoCount = session.currentProfile?.profilePhotoURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? 1 : 0

        do {
            let photos = try await ProfilePhotoService.shared.fetchPhotos(userId: userId)
            profilePhotoCount = max(photos.count, fallbackPhotoCount)
        } catch {
            profilePhotoCount = fallbackPhotoCount
        }

        struct PromptCountRow: Decodable {
            let id: UUID
            let answer: String
        }

        do {
            let prompts: [PromptCountRow] = try await SupabaseManager.shared.client
                .from("profile_prompts")
                .select("id,answer")
                .eq("user_id", value: userId)
                .execute()
                .value

            profilePromptCount = prompts
                .map { $0.answer.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .count
        } catch {
            profilePromptCount = 0
        }
    }

    private func locationText(for profile: Profile) -> String {
        if let readableLocation {
            return readableLocation
        }

        guard profile.latitude != nil,
              profile.longitude != nil else {
            return isUpdatingLocation ? AppLanguageManager.localized("profile.location.updating") : AppLanguageManager.localized("profile.location.notAvailable")
        }

        return isUpdatingLocation ? AppLanguageManager.localized("profile.location.updating") : AppLanguageManager.localized("profile.location.resolving")
    }

    private func loadReadableLocation() async {
        guard let latitude = session.currentProfile?.latitude,
              let longitude = session.currentProfile?.longitude else {
            readableLocation = nil
            return
        }

        readableLocation = nil
        await loadReadableLocationUsingMapKit(latitude: latitude, longitude: longitude, fallback: AppLanguageManager.localized("profile.location.added"))
    }

    @available(iOS 26.0, *)
    private func loadReadableLocationUsingMapKit(latitude: Double, longitude: Double, fallback: String) async {
        do {
            guard let request = MKReverseGeocodingRequest(location: CLLocation(latitude: latitude, longitude: longitude)),
                  let mapItem = try await request.mapItems.first else {
                readableLocation = fallback
                return
            }

            if let cityWithContext = mapItem.addressRepresentations?.cityWithContext,
               let cityState = conciseCityState(from: cityWithContext) {
                readableLocation = cityState
            } else if let fullAddress = mapItem.address?.fullAddress,
                      let cityState = conciseCityState(from: fullAddress) {
                readableLocation = cityState
            } else if let name = mapItem.name, !name.isEmpty {
                readableLocation = name
            } else {
                readableLocation = fallback
            }
        } catch {
            readableLocation = fallback
        }
    }

    private func conciseCityState(from address: String) -> String? {
        var parts = address
            .replacingOccurrences(of: "\n", with: ",")
            .components(separatedBy: ",")
            .map { cleanAddressPart($0) }
            .filter { !$0.isEmpty }

        parts.removeAll { part in
            let lowercased = part.lowercased()
            return lowercased == "malaysia" || lowercased == "my"
        }

        guard parts.count >= 2 else {
            return parts.first
        }

        let city = parts[parts.count - 2]
        let state = parts[parts.count - 1]
        return "\(city), \(state)"
    }

    private func cleanAddressPart(_ part: String) -> String {
        part
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: #"^\d{4,6}\s*"#,
                with: "",
                options: .regularExpression
            )
    }
}

private extension MaritalStatus {
    var displayTitle: String {
        switch self {
        case .single:
            return AppLanguageManager.localized("profile.maritalStatus.single")
        case .divorced:
            return AppLanguageManager.localized("profile.maritalStatus.divorced")
        case .widowed:
            return AppLanguageManager.localized("profile.maritalStatus.widowed")
        case .separated:
            return AppLanguageManager.localized("profile.maritalStatus.separated")
        case .prefer_not_to_say:
            return AppLanguageManager.localized("profile.maritalStatus.preferNotToSay")
        }
    }
}

private struct ProfileSummaryCard: View {
    let profile: Profile
    let locationText: String
    @State private var profileImage: UIImage?

    private var displayName: String {
        profile.publicName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? profile.publicName ?? AppLanguageManager.localized("profile.name.noName")
            : AppLanguageManager.localized("profile.name.noName")
    }

    private var initials: String {
        let parts = displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let value = String(parts).uppercased()
        return value.isEmpty ? "?" : value
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                ProfileSummaryAvatar(
                    initials: initials,
                    image: profileImage,
                    size: 112
                )

                if profile.verificationStatus == .verified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                        .background(Circle().fill(Color(.systemBackground)).frame(width: 30, height: 30))
                        .offset(x: -4, y: -4)
                }
            }

            VStack(spacing: 6) {
                Text(displayName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)

                Label(locationText, systemImage: "location.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .appCard()
        .task(id: profile.profilePhotoURL) {
            await resolvePhotoURL()
        }
    }

    private func resolvePhotoURL() async {
        guard let path = profile.profilePhotoURL,
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            profileImage = nil
            return
        }

        if let directURL = URL(string: path), directURL.scheme?.hasPrefix("http") == true {
            do {
                let (data, _) = try await URLSession.shared.data(from: directURL)
                profileImage = UIImage(data: data)
            } catch {
                profileImage = nil
            }
            return
        }

        do {
            profileImage = try await ProfilePhotoService.shared.image(for: path)
        } catch {
            profileImage = nil
        }
    }
}


private struct ProfileSummaryAvatar: View {
    let initials: String
    let image: UIImage?
    var size: CGFloat = 112

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.pink.opacity(0.14))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                fallbackInitials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(Color.white.opacity(0.9), lineWidth: 3)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }

    private var fallbackInitials: some View {
        Text(initials)
            .font(.system(size: max(14, size * 0.34), weight: .bold))
            .foregroundStyle(.pink)
    }
}

private struct ProfilePrimaryActionRow: View {
    let onEdit: () -> Void
    let onPreview: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ProfileActionButton(
                title: AppLanguageManager.localized("profile.edit.title"),
                systemImage: "pencil",
                isPrimary: true,
                action: onEdit
            )

            ProfileActionButton(
                title: AppLanguageManager.localized("profile.previewProfile.title"),
                systemImage: "eye.fill",
                isPrimary: false,
                action: onPreview
            )
        }
    }
}

private struct ProfileActionButton: View {
    let title: String
    let systemImage: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.bold))

                Text(title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(isPrimary ? .white : .pink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(buttonBackground)
            .shadow(color: shadowColor, radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    private var buttonBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(isPrimary ? Color.pink : Color(.systemBackground))
            .overlay {
                if !isPrimary {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.pink.opacity(0.10), lineWidth: 1)
                }
            }
    }

    private var shadowColor: Color {
        isPrimary ? Color.pink.opacity(0.22) : Color.black.opacity(0.06)
    }
}

private struct ProfilePreviewSheet: View {
    @EnvironmentObject var session: SessionViewModel
    @Environment(\.dismiss) private var dismiss

    let profile: Profile
    let locationText: String

    var body: some View {
        NavigationStack {
            ScrollView {
                PublicProfilePreviewContent(
                    profile: profile,
                    currentProfile: session.currentProfile,
                    locationTextOverride: locationText,
                    showsPreviewLabel: true
                )
                .padding(20)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(AppLanguageManager.localized("profile.previewProfile.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLanguageManager.localized("common.close")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct MeSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionViewModel
    @Binding var notice: String?
    @State private var showDeleteConfirmation = false
    @State private var isRequestingDeletion = false
    @State private var showSignOutConfirmation = false
    @State private var isSigningOut = false
    @State private var actionError: String?

    var body: some View {
        ZStack {
            NavigationStack {
                List {
                    Section {
                        NavigationLink {
                            AccountSettingsView(
                                notice: $notice,
                                onSignOut: {
                                    showSignOutConfirmation = true
                                }
                            )
                            .environmentObject(session)
                        } label: {
                        SettingsStaticRow(systemImage: "person.crop.circle.badge.checkmark", title: AppLanguageManager.localized("profile.settings.accountSecurity"), showsChevron: false)
                        }
                        NavigationLink {
                            NotificationSettingsView()
                        } label: {
                            SettingsStaticRow(systemImage: "bell.badge.fill", title: AppLanguageManager.localized("profile.notifications.settings"), showsChevron: false)
                        }
                        NavigationLink {
                            LanguageSettingsView()
                        } label: {
                            SettingsStaticRow(systemImage: "globe.asia.australia.fill", title: AppLanguageManager.localized("profile.language.settings"), showsChevron: false)
                        }
                        NavigationLink {
                            PrivacySettingsView()
                                .environmentObject(session)
                        } label: {
                            SettingsStaticRow(systemImage: "lock.shield.fill", title: AppLanguageManager.localized("profile.privacy.settings"), showsChevron: false)
                        }
                        NavigationLink {
                            VisibilitySettingsSheet()
                                .environmentObject(session)
                        } label: {
                            SettingsStaticRow(systemImage: "eye.fill", title: AppLanguageManager.localized("profile.visibility.settings"), showsChevron: false)
                        }
                        SettingsRow(systemImage: "crown.fill", title: AppLanguageManager.localized("profile.subscription.title")) {
                            showComingSoon(AppLanguageManager.localized("profile.subscription.vipPremiumFeatures"))
                        }
                        NavigationLink {
                            DataStorageSettingsView()
                                .environmentObject(session)
                        } label: {
                            SettingsStaticRow(systemImage: "externaldrive.fill", title: AppLanguageManager.localized("profile.dataStorage.title"), showsChevron: false)
                        }
                    }

                    Section {
                        NavigationLink {
                            ContactUsSettingsView()
                                .environmentObject(session)
                        } label: {
                            SettingsStaticRow(systemImage: "message.fill", title: AppLanguageManager.localized("profile.contact.title"), showsChevron: false)
                        }
                        NavigationLink {
                            PoliciesSettingsView()
                        } label: {
                            SettingsStaticRow(systemImage: "doc.text.fill", title: AppLanguageManager.localized("profile.policies.title"), showsChevron: false)
                        }
                        NavigationLink {
                            TermsOfServiceSettingsView()
                        } label: {
                            SettingsStaticRow(systemImage: "checkmark.shield.fill", title: AppLanguageManager.localized("profile.settings.termsOfService"), showsChevron: false)
                        }
                        ShareLink(item: AppLanguageManager.localized("profile.settings.shareMessage")) {
                            SettingsStaticRow(systemImage: "square.and.arrow.up.fill", title: AppLanguageManager.localized("profile.settings.shareVeriDate"))
                        }
                    }

                    Section {
                        Button(role: .destructive) {
                            HapticManager.warning()
                            showDeleteConfirmation = true
                        } label: {
                            SettingsStaticRow(
                                systemImage: "trash.fill",
                                title: AppLanguageManager.localized("profile.settings.deleteAccount"),
                                tint: .red,
                                showsChevron: false
                            )
                        }

                        Button(role: .destructive) {
                            HapticManager.warning()
                            showSignOutConfirmation = true
                        } label: {
                            SettingsStaticRow(systemImage: "rectangle.portrait.and.arrow.right", title: AppLanguageManager.localized("profile.settings.signOut"), tint: .red)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground))
                .navigationTitle(AppLanguageManager.localized("profile.settings.title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(AppLanguageManager.localized("common.close")) {
                            dismiss()
                        }
                    }
                }
            }

            settingsConfirmationOverlay
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: showDeleteConfirmation)
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: showSignOutConfirmation)
        .alert(AppLanguageManager.localized("profile.settings.title"), isPresented: Binding(
            get: { actionError != nil },
            set: { isPresented in
                if !isPresented {
                    actionError = nil
                }
            }
        )) {
            Button(AppLanguageManager.localized("common.ok"), role: .cancel) { }
        } message: {
            Text(actionError ?? "")
        }
    }

    @ViewBuilder
    private var settingsConfirmationOverlay: some View {
        if showDeleteConfirmation {
            PremiumConfirmationOverlay(
                icon: "trash.fill",
                tint: .red,
                title: AppLanguageManager.localized("profile.account.deleteConfirm.title"),
                message: AppLanguageManager.localized("profile.account.deleteConfirm.message"),
                confirmTitle: AppLanguageManager.localized("profile.account.requestDeletion"),
                isProcessing: isRequestingDeletion,
                onCancel: {
                    HapticManager.light()
                    showDeleteConfirmation = false
                },
                onConfirm: {
                    HapticManager.warning()
                    requestDeletion()
                }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        } else if showSignOutConfirmation {
            PremiumConfirmationOverlay(
                icon: "rectangle.portrait.and.arrow.right",
                tint: .red,
                title: AppLanguageManager.localized("profile.settings.signOutConfirm.title"),
                message: AppLanguageManager.localized("profile.settings.signOutConfirm.message"),
                confirmTitle: AppLanguageManager.localized("profile.settings.signOut"),
                isProcessing: isSigningOut,
                onCancel: {
                    HapticManager.light()
                    showSignOutConfirmation = false
                },
                onConfirm: {
                    HapticManager.warning()
                    signOut()
                }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    private func showComingSoon(_ feature: String) {
        HapticManager.light()
        notice = String(
            format: AppLanguageManager.localized("profile.settings.comingSoonFormat"),
            feature
        )
    }

    private func requestDeletion() {
        guard !isRequestingDeletion else { return }
        isRequestingDeletion = true

        Task {
            let didRequest = await session.requestAccountDeletion()
            isRequestingDeletion = false

            if didRequest {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                showDeleteConfirmation = false
                notice = AppLanguageManager.localized("profile.account.deletionScheduled")
            } else {
                actionError = session.errorMessage ?? AppLanguageManager.localized("profile.account.deleteRequestFailed")
            }
        }
    }

    private func signOut() {
        guard !isSigningOut else { return }
        isSigningOut = true

        Task {
            await session.signOut()
            isSigningOut = false
            showSignOutConfirmation = false
        }
    }
}

private struct NotificationSettingsView: View {
    @Environment(\.openURL) private var openURL
    @AppStorage(NotificationPreferenceKey.pushEnabled) private var pushEnabled = true
    @AppStorage(NotificationPreferenceKey.inAppMessagesEnabled) private var inAppMessagesEnabled = true
    @AppStorage(NotificationPreferenceKey.messageAlertsEnabled) private var messageAlertsEnabled = true
    @AppStorage(NotificationPreferenceKey.matchAlertsEnabled) private var matchAlertsEnabled = true
    @AppStorage(NotificationPreferenceKey.accountAlertsEnabled) private var accountAlertsEnabled = true

    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isUpdatingPermission = false
    @State private var notice: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                notificationPermissionCard

                NotificationSettingsGroup(title: AppLanguageManager.localized("profile.notifications.section.inAppAlerts")) {
                    NotificationToggleRow(
                        icon: "bubble.left.and.bubble.right.fill",
                        title: AppLanguageManager.localized("profile.notifications.messageBanners"),
                        subtitle: AppLanguageManager.localized("profile.notifications.messageBanners.subtitle"),
                        tint: .pink,
                        isOn: $inAppMessagesEnabled
                    )

                    NotificationToggleRow(
                        icon: "heart.fill",
                        title: AppLanguageManager.localized("profile.notifications.newMatches"),
                        subtitle: AppLanguageManager.localized("profile.notifications.newMatches.subtitle"),
                        tint: .red,
                        isOn: $matchAlertsEnabled
                    )
                }

                NotificationSettingsGroup(title: AppLanguageManager.localized("profile.notifications.section.notificationTypes")) {
                    NotificationToggleRow(
                        icon: "message.fill",
                        title: AppLanguageManager.localized("profile.notifications.messages"),
                        subtitle: AppLanguageManager.localized("profile.notifications.messages.subtitle"),
                        tint: .blue,
                        isOn: $messageAlertsEnabled
                    )

                    NotificationToggleRow(
                        icon: "checkmark.shield.fill",
                        title: AppLanguageManager.localized("profile.notifications.accountVerification"),
                        subtitle: AppLanguageManager.localized("profile.notifications.accountVerification.subtitle"),
                        tint: .green,
                        isOn: $accountAlertsEnabled
                    )
                }

                Text(AppLanguageManager.localized("profile.notifications.footer"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(AppLanguageManager.localized("profile.notifications.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshAuthorizationStatus()
        }
        .onChange(of: pushEnabled) { _, isEnabled in
            handlePushToggle(isEnabled)
        }
        .alert(AppLanguageManager.localized("profile.notifications.title"), isPresented: Binding(
            get: { notice != nil },
            set: { isPresented in
                if !isPresented {
                    notice = nil
                }
            }
        )) {
            Button(AppLanguageManager.localized("common.ok"), role: .cancel) { }
        } message: {
            Text(notice ?? "")
        }
    }

    private var notificationPermissionCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: permissionIcon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(permissionTint)
                    .frame(width: 42, height: 42)
                    .background(permissionTint.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(AppLanguageManager.localized("profile.notifications.systemNotifications"))
                        .font(.headline.weight(.semibold))

                    Text(permissionSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            Toggle(isOn: $pushEnabled) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(AppLanguageManager.localized("profile.notifications.allowPush"))
                        .font(.subheadline.weight(.semibold))
                    Text(AppLanguageManager.localized("profile.notifications.allowPush.subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            if authorizationStatus == .denied {
                Button {
                    HapticManager.light()
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Label(AppLanguageManager.localized("profile.notifications.openIPhoneSettings"), systemImage: "gearshape.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            } else if authorizationStatus == .notDetermined {
                Button {
                    requestPushPermission()
                } label: {
                    HStack {
                        if isUpdatingPermission {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isUpdatingPermission ? AppLanguageManager.localized("profile.notifications.requesting") : AppLanguageManager.localized("profile.notifications.turnOnNotifications"))
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(isUpdatingPermission)
            }
        }
        .padding(18)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 8)
    }

    private var permissionIcon: String {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "bell.badge.fill"
        case .denied:
            return "bell.slash.fill"
        case .notDetermined:
            return "bell.fill"
        @unknown default:
            return "bell.fill"
        }
    }

    private var permissionTint: Color {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .green
        case .denied:
            return .red
        case .notDetermined:
            return .orange
        @unknown default:
            return .orange
        }
    }

    private var permissionSubtitle: String {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return AppLanguageManager.localized("profile.notifications.permission.allowed")
        case .denied:
            return AppLanguageManager.localized("profile.notifications.permission.blocked")
        case .notDetermined:
            return AppLanguageManager.localized("profile.notifications.permission.notDetermined")
        @unknown default:
            return AppLanguageManager.localized("profile.notifications.permission.needsCheck")
        }
    }

    private func handlePushToggle(_ isEnabled: Bool) {
        HapticManager.light()

        if isEnabled {
            if authorizationStatus == .notDetermined {
                requestPushPermission()
            } else if authorizationStatus == .denied {
                notice = AppLanguageManager.localized("profile.notifications.blockedNotice")
            } else {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } else {
            UIApplication.shared.unregisterForRemoteNotifications()
        }
    }

    private func requestPushPermission() {
        guard !isUpdatingPermission else { return }
        isUpdatingPermission = true

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                isUpdatingPermission = false
                pushEnabled = granted

                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                    HapticManager.success()
                } else {
                    HapticManager.warning()
                    notice = AppLanguageManager.localized("profile.notifications.notAllowedNotice")
                }

                Task {
                    await refreshAuthorizationStatus()
                }
            }
        }
    }

    private func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus

        if authorizationStatus == .denied {
            pushEnabled = false
        }
    }
}

private struct NotificationSettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline.weight(.bold))
                .padding(.horizontal, 2)

            VStack(spacing: 10) {
                content
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.035), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 7)
    }
}

private struct NotificationToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 18)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onChange(of: isOn) { _, _ in
            HapticManager.light()
        }
    }
}

private struct PrivacySettingsView: View {
    @EnvironmentObject private var session: SessionViewModel
    @AppStorage(PrivacyPreferenceKey.showOnlineStatus) private var showOnlineStatus = true
    @AppStorage(PrivacyPreferenceKey.sendReadReceipts) private var sendReadReceipts = true
    @AppStorage(PrivacyPreferenceKey.showDistance) private var showDistance = true
    @State private var notice: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                privacyHeaderCard

                NotificationSettingsGroup(title: AppLanguageManager.localized("profile.privacy.chatPresence")) {
                    NotificationToggleRow(
                        icon: "circle.fill",
                        title: AppLanguageManager.localized("profile.privacy.showOnlineStatus"),
                        subtitle: AppLanguageManager.localized("profile.privacy.showOnlineStatus.subtitle"),
                        tint: .green,
                        isOn: $showOnlineStatus
                    )

                    NotificationToggleRow(
                        icon: "checkmark.circle.fill",
                        title: AppLanguageManager.localized("profile.privacy.sendReadReceipts"),
                        subtitle: AppLanguageManager.localized("profile.privacy.sendReadReceipts.subtitle"),
                        tint: .indigo,
                        isOn: $sendReadReceipts
                    )
                }

                NotificationSettingsGroup(title: AppLanguageManager.localized("profile.privacy.discoveryPrivacy")) {
                    NotificationToggleRow(
                        icon: "location.circle.fill",
                        title: AppLanguageManager.localized("profile.privacy.showDistance"),
                        subtitle: AppLanguageManager.localized("profile.privacy.showDistance.subtitle"),
                        tint: .orange,
                        isOn: $showDistance
                    )
                }

                NotificationSettingsGroup(title: AppLanguageManager.localized("profile.safety.title")) {
                    NavigationLink {
                        BlockedAccountsView()
                            .environmentObject(session)
                    } label: {
                        PrivacyNavigationRow(
                            icon: "hand.raised.fill",
                            title: AppLanguageManager.localized("profile.blocked.title"),
                            subtitle: AppLanguageManager.localized("profile.blocked.footer"),
                            tint: .red
                        )
                    }
                    .buttonStyle(.plain)
                }

                Text(AppLanguageManager.localized("profile.privacy.footer"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(AppLanguageManager.localized("profile.privacy.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: showOnlineStatus) { _, isEnabled in
            updatePresenceForOnlinePrivacy(isEnabled)
        }
        .alert(AppLanguageManager.localized("profile.privacy.title"), isPresented: Binding(
            get: { notice != nil },
            set: { isPresented in
                if !isPresented {
                    notice = nil
                }
            }
        )) {
            Button(AppLanguageManager.localized("common.ok"), role: .cancel) { }
        } message: {
            Text(notice ?? "")
        }
    }

    private var privacyHeaderCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.pink)
                    .frame(width: 42, height: 42)
                    .background(Color.pink.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLanguageManager.localized("profile.privacy.controls"))
                        .font(.headline.weight(.semibold))

                    Text(AppLanguageManager.localized("profile.privacy.controls.subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.green)

                Text(AppLanguageManager.localized("profile.privacy.privateDetailsNotice"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(18)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 8)
    }

    private func updatePresenceForOnlinePrivacy(_ isEnabled: Bool) {
        HapticManager.light()
        Task {
            await session.updatePresence(isOnline: isEnabled, reportErrors: false)
        }
    }
}

private struct PrivacyNavigationRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 18)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct BlockedAccountsView: View {
    @EnvironmentObject private var session: SessionViewModel
    @StateObject private var safetyVM = SafetyViewModel()
    @State private var processingBlockedUserId: UUID?
    @State private var notice: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                headerCard

                if safetyVM.isLoadingBlockedUsers {
                    ProgressView(AppLanguageManager.localized("profile.blocked.loading"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                } else if safetyVM.blockedUsers.isEmpty {
                    emptyState
                } else {
                    NotificationSettingsGroup(title: AppLanguageManager.localized("profile.blocked.section.blocked")) {
                        VStack(spacing: 10) {
                            ForEach(safetyVM.blockedUsers) { blockedUser in
                                BlockedAccountRow(
                                    blockedUser: blockedUser,
                                    isProcessing: processingBlockedUserId == blockedUser.blockedUserId
                                ) {
                                    HapticManager.light()
                                    Task {
                                        await unblockUser(blockedUser)
                                    }
                                }
                            }
                        }
                    }
                }

                Text(AppLanguageManager.localized("profile.blocked.footer"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(AppLanguageManager.localized("profile.blocked.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.currentUserId) {
            await loadBlockedUsers()
        }
        .refreshable {
            await loadBlockedUsers()
        }
        .alert(AppLanguageManager.localized("profile.blocked.title"), isPresented: Binding(
            get: { notice != nil },
            set: { isPresented in
                if !isPresented {
                    notice = nil
                    safetyVM.errorMessage = nil
                    safetyVM.successMessage = nil
                }
            }
        )) {
            Button(AppLanguageManager.localized("common.ok"), role: .cancel) {}
        } message: {
            Text(notice ?? "")
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.red)
                    .frame(width: 42, height: 42)
                    .background(Color.red.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLanguageManager.localized("profile.blocked.header.title"))
                        .font(.headline.weight(.semibold))

                    Text(AppLanguageManager.localized("profile.blocked.header.subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
        }
        .padding(18)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 8)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .font(.title2.weight(.bold))
                .foregroundStyle(.green)
                .frame(width: 48, height: 48)
                .background(Color.green.opacity(0.12), in: Circle())

            Text(AppLanguageManager.localized("profile.blocked.empty.title"))
                .font(.headline.weight(.semibold))

            Text(AppLanguageManager.localized("profile.blocked.empty.description"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func loadBlockedUsers() async {
        guard let userId = session.currentUserId else { return }
        await safetyVM.loadBlockedUsers(blockerUserId: userId)
        if let error = safetyVM.errorMessage {
            notice = error
        }
    }

    private func unblockUser(_ blockedUser: SafetyBlockedUser) async {
        guard let userId = session.currentUserId else { return }
        processingBlockedUserId = blockedUser.blockedUserId
        let didUnblock = await safetyVM.unblockUser(
            blockerUserId: userId,
            blockedUserId: blockedUser.blockedUserId
        )
        processingBlockedUserId = nil
        notice = didUnblock ? safetyVM.successMessage : safetyVM.errorMessage

        if didUnblock {
            await loadBlockedUsers()
        }
    }
}

private struct BlockedAccountRow: View {
    let blockedUser: SafetyBlockedUser
    let isProcessing: Bool
    let onUnblock: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            BlockedAccountAvatar(profile: blockedUser.profile)

            VStack(alignment: .leading, spacing: 4) {
                Text(blockedUser.profile.publicName ?? AppLanguageManager.localized("profile.blocked.defaultUser"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 18)

            Button {
                onUnblock()
            } label: {
                if isProcessing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(AppLanguageManager.localized("profile.blocked.unblock"))
                        .font(.caption.weight(.bold))
                }
            }
            .buttonStyle(.bordered)
            .tint(.pink)
            .disabled(isProcessing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var subtitle: String {
        if let reason = blockedUser.reason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
            return reason
        }

        return AppLanguageManager.localized("profile.blocked.accountSubtitle")
    }
}

private struct BlockedAccountAvatar: View {
    let profile: Profile
    @State private var image: UIImage?

    var body: some View {
        ProfileSummaryAvatar(
            initials: initials,
            image: image,
            size: 38
        )
        .task(id: profile.profilePhotoURL) {
            await loadImage()
        }
    }

    private var initials: String {
        let name = profile.publicName ?? AppLanguageManager.localized("profile.blocked.avatarFallbackName")
        let initial = String(name.prefix(1)).uppercased()
        return initial.isEmpty ? AppLanguageManager.localized("profile.account.fallbackInitial") : initial
    }

    private func loadImage() async {
        guard let path = profile.profilePhotoURL, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            image = nil
            return
        }

        image = try? await ProfilePhotoService.shared.image(for: path)
    }
}

private struct LanguageSettingsView: View {
    @AppStorage(AppLanguagePreferenceKey.selectedLanguage) private var selectedLanguage = AppLanguage.english.rawValue
    @State private var languageViewRefreshID = UUID()
    @Environment(\.appLanguageRefreshID) private var appLanguageRefreshID

    private var currentLanguage: AppLanguage {
        AppLanguage(rawValue: selectedLanguage) ?? .english
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                headerCard

                NotificationSettingsGroup(title: AppLanguageManager.localized("language.chooseLanguage")) {
                    VStack(spacing: 10) {
                        ForEach(AppLanguage.allCases) { language in
                            Button {
                                HapticManager.light()
                                selectedLanguage = language.rawValue
                                AppLanguageManager.apply(language)
                                AppLanguageManager.notifyChange()
                                languageViewRefreshID = UUID()
                            } label: {
                                LanguageOptionRow(
                                    language: language,
                                    isSelected: language == currentLanguage
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Text(AppLanguageManager.localized("language.note"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .id(languageViewRefreshID)
        .onChange(of: appLanguageRefreshID) { _, _ in
            languageViewRefreshID = UUID()
        }
        .navigationTitle(AppLanguageManager.localized("profile.language.settings"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            AppLanguageManager.apply(currentLanguage)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "globe.asia.australia.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.pink)
                    .frame(width: 42, height: 42)
                    .background(Color.pink.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLanguageManager.localized("language.title"))
                        .font(.headline.weight(.semibold))

                    Text(String.localizedStringWithFormat(AppLanguageManager.localized("language.currentFormat"), currentLanguage.localizedTitle))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
        }
        .padding(18)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 8)
    }
}

private struct LanguageOptionRow: View {
    let language: AppLanguage
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(isSelected ? .pink : .secondary.opacity(0.45))

            VStack(alignment: .leading, spacing: 3) {
                Text(language.localizedTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(language.nativeTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .background(
            isSelected ? Color.pink.opacity(0.08) : Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? Color.pink.opacity(0.20) : Color.clear, lineWidth: 1)
        }
    }
}

private struct DataStorageSettingsView: View {
    @EnvironmentObject private var session: SessionViewModel
    @AppStorage(DataStoragePreferenceKey.reducePhotoPreloading) private var reducePhotoPreloading = false
    @AppStorage(DataStoragePreferenceKey.useCellularForMedia) private var useCellularForMedia = true
    @AppStorage(DataStoragePreferenceKey.autoDownloadReceivedMedia) private var autoDownloadReceivedMedia = false

    @State private var showExportSheet = false
    @State private var exportText = ""
    @State private var isPreparingExport = false
    @State private var isClearingCache = false
    @State private var notice: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                dataStorageHeaderCard

                NotificationSettingsGroup(title: AppLanguageManager.localized("profile.dataStorage.mediaUsage")) {
                    NotificationToggleRow(
                        icon: "photo.on.rectangle.angled",
                        title: AppLanguageManager.localized("profile.dataStorage.reducePhotoPreloading"),
                        subtitle: AppLanguageManager.localized("profile.dataStorage.reducePhotoPreloading.subtitle"),
                        tint: .purple,
                        isOn: $reducePhotoPreloading
                    )

                    NotificationToggleRow(
                        icon: "antenna.radiowaves.left.and.right",
                        title: AppLanguageManager.localized("profile.dataStorage.useCellularForMedia"),
                        subtitle: AppLanguageManager.localized("profile.dataStorage.useCellularForMedia.subtitle"),
                        tint: .blue,
                        isOn: $useCellularForMedia
                    )

                    NotificationToggleRow(
                        icon: "square.and.arrow.down.fill",
                        title: AppLanguageManager.localized("profile.dataStorage.autoDownloadReceivedMedia"),
                        subtitle: AppLanguageManager.localized("profile.dataStorage.autoDownloadReceivedMedia.subtitle"),
                        tint: .green,
                        isOn: $autoDownloadReceivedMedia
                    )
                }

                NotificationSettingsGroup(title: AppLanguageManager.localized("profile.dataStorage.storage")) {
                    DataStorageActionRow(
                        icon: "trash.fill",
                        title: AppLanguageManager.localized("profile.dataStorage.clearCachedMedia"),
                        subtitle: AppLanguageManager.localized("profile.dataStorage.clearCachedMedia.subtitle"),
                        tint: .orange,
                        isLoading: isClearingCache
                    ) {
                        clearCachedMedia()
                    }
                }

                NotificationSettingsGroup(title: AppLanguageManager.localized("profile.account.myData")) {
                    DataStorageActionRow(
                        icon: "doc.text.fill",
                        title: AppLanguageManager.localized("profile.dataStorage.exportMyData"),
                        subtitle: AppLanguageManager.localized("profile.dataStorage.exportMyData.subtitle"),
                        tint: .pink,
                        isLoading: isPreparingExport
                    ) {
                        prepareExport()
                    }
                }

                Text(AppLanguageManager.localized("profile.dataStorage.cacheFooter"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(AppLanguageManager.localized("profile.dataStorage.title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showExportSheet) {
            AccountDataExportSheet(exportText: exportText)
        }
        .alert(AppLanguageManager.localized("profile.dataStorage.title"), isPresented: Binding(
            get: { notice != nil },
            set: { isPresented in
                if !isPresented {
                    notice = nil
                }
            }
        )) {
            Button(AppLanguageManager.localized("common.ok"), role: .cancel) { }
        } message: {
            Text(notice ?? "")
        }
    }

    private var dataStorageHeaderCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.pink)
                    .frame(width: 42, height: 42)
                    .background(Color.pink.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLanguageManager.localized("profile.dataStorage.title"))
                        .font(.headline.weight(.semibold))

                    Text(AppLanguageManager.localized("profile.dataStorage.header.subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "icloud.and.arrow.down.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)

                Text(AppLanguageManager.localized("profile.dataStorage.header.notice"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(18)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 8)
        .accessibilityElement(children: .contain)
    }

    private func clearCachedMedia() {
        guard !isClearingCache else { return }
        HapticManager.light()
        isClearingCache = true

        Task {
            ProfilePhotoService.shared.clearCache()
            URLCache.shared.removeAllCachedResponses()

            try? await Task.sleep(for: .milliseconds(250))
            isClearingCache = false
            HapticManager.success()
            notice = AppLanguageManager.localized("profile.dataStorage.cacheCleared")
        }
    }

    private func prepareExport() {
        guard !isPreparingExport else { return }
        HapticManager.light()
        isPreparingExport = true

        Task {
            do {
                exportText = try await buildDataExport()
                showExportSheet = true
            } catch {
                notice = String(
                    format: AppLanguageManager.localized("profile.account.dataExportFailedFormat"),
                    error.localizedDescription
                )
            }

            isPreparingExport = false
        }
    }

    private func buildDataExport() async throws -> String {
        guard let userId = session.currentUserId else {
            throw NSError(domain: "DataStorageExport", code: 1, userInfo: [
                NSLocalizedDescriptionKey: AppLanguageManager.localized("auth.error.signInAgain")
            ])
        }

        struct DataStorageExportPayload: Codable {
            let exportedAt: String
            let email: String?
            let profile: Profile?
            let photos: [ProfilePhoto]
            let prompts: [ProfilePrompt]
            let interests: [ProfileInterest]
            let filters: [DatingFilter]
            let preferences: ExportedDataStoragePreferences
        }

        struct ExportedDataStoragePreferences: Codable {
            let reducePhotoPreloading: Bool
            let useCellularForMedia: Bool
            let autoDownloadReceivedMedia: Bool
        }

        let client = SupabaseManager.shared.client
        let photos = (try? await ProfilePhotoService.shared.fetchPhotos(userId: userId)) ?? []

        let prompts: [ProfilePrompt] = (try? await client
            .from("profile_prompts")
            .select()
            .eq("user_id", value: userId)
            .order("display_order", ascending: true)
            .execute()
            .value) ?? []

        let interests: [ProfileInterest] = (try? await client
            .from("profile_interests")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value) ?? []

        let filters: [DatingFilter] = (try? await client
            .from("dating_filters")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value) ?? []

        let payload = DataStorageExportPayload(
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            email: session.currentUserEmail,
            profile: session.currentProfile,
            photos: photos,
            prompts: prompts,
            interests: interests,
            filters: filters,
            preferences: ExportedDataStoragePreferences(
                reducePhotoPreloading: reducePhotoPreloading,
                useCellularForMedia: useCellularForMedia,
                autoDownloadReceivedMedia: autoDownloadReceivedMedia
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)

        return String(data: data, encoding: .utf8) ?? AppLanguageManager.localized("profile.dataStorage.emptyExportFallback")
    }
}

private struct DataStorageActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 14)

                if isLoading {
                    ProgressView()
                        .tint(tint)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle)
        .disabled(isLoading)
    }
}

private struct ContactUsSettingsView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var session: SessionViewModel
    @State private var notice: String?

    private let supportEmail = "support@veridate.app"

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SettingsDocumentHeaderCard(
                    icon: "message.fill",
                    title: AppLanguageManager.localized("profile.contact.title"),
                    message: AppLanguageManager.localized("profile.contact.headerMessage")
                )

                NotificationSettingsGroup(title: AppLanguageManager.localized("profile.contact.support")) {
                    DataStorageActionRow(
                        icon: "envelope.fill",
                        title: AppLanguageManager.localized("profile.contact.emailSupport"),
                        subtitle: supportEmail,
                        tint: .pink,
                        isLoading: false
                    ) {
                        openSupportEmail(subject: AppLanguageManager.localized("profile.contact.subject.supportRequest"))
                    }

                    DataStorageActionRow(
                        icon: "checkmark.shield.fill",
                        title: AppLanguageManager.localized("profile.contact.verificationHelp"),
                        subtitle: AppLanguageManager.localized("profile.contact.verificationHelp.subtitle"),
                        tint: .green,
                        isLoading: false
                    ) {
                        openSupportEmail(subject: AppLanguageManager.localized("profile.contact.subject.verificationHelp"))
                    }

                    DataStorageActionRow(
                        icon: "exclamationmark.triangle.fill",
                        title: AppLanguageManager.localized("profile.contact.safetyConcern"),
                        subtitle: AppLanguageManager.localized("profile.contact.safetyConcern.subtitle"),
                        tint: .orange,
                        isLoading: false
                    ) {
                        openSupportEmail(subject: AppLanguageManager.localized("profile.contact.subject.safetyConcern"))
                    }
                }

                NotificationSettingsGroup(title: AppLanguageManager.localized("profile.contact.accountReference")) {
                    ContactInfoRow(
                        icon: "number",
                        title: AppLanguageManager.localized("profile.account.userId"),
                        value: session.currentUserId?.uuidString ?? AppLanguageManager.localized("common.notAvailable"),
                        tint: .blue
                    )

                    ContactInfoRow(
                        icon: "envelope.badge.shield.half.filled.fill",
                        title: AppLanguageManager.localized("profile.contact.accountEmail"),
                        value: session.currentUserEmail ?? AppLanguageManager.localized("common.notAvailable"),
                        tint: .purple
                    )

                    DataStorageActionRow(
                        icon: "doc.on.doc.fill",
                        title: AppLanguageManager.localized("profile.contact.copySupportDetails"),
                        subtitle: AppLanguageManager.localized("profile.contact.copySupportDetails.subtitle"),
                        tint: .indigo,
                        isLoading: false
                    ) {
                        copySupportDetails()
                    }
                }

                Text(AppLanguageManager.localized("profile.contact.footer"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(AppLanguageManager.localized("profile.contact.title"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(AppLanguageManager.localized("profile.contact.title"), isPresented: Binding(
            get: { notice != nil },
            set: { isPresented in
                if !isPresented {
                    notice = nil
                }
            }
        )) {
            Button(AppLanguageManager.localized("common.ok"), role: .cancel) { }
        } message: {
            Text(notice ?? "")
        }
    }

    private func openSupportEmail(subject: String) {
        HapticManager.light()

        let body = """


\(AppLanguageManager.localized("profile.contact.supportDetails.userId")): \(session.currentUserId?.uuidString ?? AppLanguageManager.localized("common.notAvailable"))
\(AppLanguageManager.localized("profile.contact.supportDetails.accountEmail")): \(session.currentUserEmail ?? AppLanguageManager.localized("common.notAvailable"))
\(AppLanguageManager.localized("profile.contact.supportDetails.app")): \(AppLanguageManager.localized("profile.contact.supportDetails.appValue"))
"""

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]

        if let url = components.url {
            openURL(url) { didOpen in
                if !didOpen {
                    UIPasteboard.general.string = supportEmail
                    notice = AppLanguageManager.localized("profile.contact.mailOpenFailed")
                }
            }
        }
    }

    private func copySupportDetails() {
        HapticManager.success()
        UIPasteboard.general.string = """
\(AppLanguageManager.localized("profile.contact.supportDetailsHeader"))
\(AppLanguageManager.localized("profile.contact.supportDetails.userId")): \(session.currentUserId?.uuidString ?? AppLanguageManager.localized("common.notAvailable"))
\(AppLanguageManager.localized("profile.contact.supportDetails.accountEmail")): \(session.currentUserEmail ?? AppLanguageManager.localized("common.notAvailable"))
\(AppLanguageManager.localized("profile.contact.supportDetails.app")): \(AppLanguageManager.localized("profile.contact.supportDetails.appValue"))
"""
        notice = AppLanguageManager.localized("profile.contact.supportDetailsCopied")
    }
}

private struct PoliciesSettingsView: View {
    var body: some View {
        SettingsDocumentView(
            title: AppLanguageManager.localized("profile.policies.title"),
            headerIcon: "doc.text.fill",
            headerTitle: AppLanguageManager.localized("profile.policies.headerTitle"),
            headerMessage: AppLanguageManager.localized("profile.policies.headerMessage"),
            sections: [
                SettingsDocumentSection(
                    title: AppLanguageManager.localized("profile.policies.privacy.title"),
                    systemImage: "lock.shield.fill",
                    tint: .pink,
                    paragraphs: [
                        AppLanguageManager.localized("profile.policies.privacy.p1"),
                        AppLanguageManager.localized("profile.policies.privacy.p2"),
                        AppLanguageManager.localized("profile.policies.privacy.p3")
                    ]
                ),
                SettingsDocumentSection(
                    title: AppLanguageManager.localized("profile.policies.verification.title"),
                    systemImage: "checkmark.seal.fill",
                    tint: .green,
                    paragraphs: [
                        AppLanguageManager.localized("profile.policies.verification.p1"),
                        AppLanguageManager.localized("profile.policies.verification.p2"),
                        AppLanguageManager.localized("profile.policies.verification.p3")
                    ]
                ),
                SettingsDocumentSection(
                    title: AppLanguageManager.localized("profile.policies.safety.title"),
                    systemImage: "exclamationmark.shield.fill",
                    tint: .orange,
                    paragraphs: [
                        AppLanguageManager.localized("profile.policies.safety.p1"),
                        AppLanguageManager.localized("profile.policies.safety.p2"),
                        AppLanguageManager.localized("profile.policies.safety.p3")
                    ]
                ),
                SettingsDocumentSection(
                    title: AppLanguageManager.localized("profile.policies.dataStorage.title"),
                    systemImage: "externaldrive.fill",
                    tint: .blue,
                    paragraphs: [
                        AppLanguageManager.localized("profile.policies.dataStorage.p1"),
                        AppLanguageManager.localized("profile.policies.dataStorage.p2"),
                        AppLanguageManager.localized("profile.policies.dataStorage.p3")
                    ]
                )
            ],
            footer: AppLanguageManager.localized("profile.policies.footer")
        )
    }
}

private struct TermsOfServiceSettingsView: View {
    var body: some View {
        SettingsDocumentView(
            title: AppLanguageManager.localized("profile.terms.title"),
            headerIcon: "checkmark.shield.fill",
            headerTitle: AppLanguageManager.localized("profile.terms.headerTitle"),
            headerMessage: AppLanguageManager.localized("profile.terms.headerMessage"),
            sections: [
                SettingsDocumentSection(
                    title: AppLanguageManager.localized("profile.terms.eligibility.title"),
                    systemImage: "person.fill.checkmark",
                    tint: .green,
                    paragraphs: [
                        AppLanguageManager.localized("profile.terms.eligibility.p1"),
                        AppLanguageManager.localized("profile.terms.eligibility.p2"),
                        AppLanguageManager.localized("profile.terms.eligibility.p3")
                    ]
                ),
                SettingsDocumentSection(
                    title: AppLanguageManager.localized("profile.terms.profile.title"),
                    systemImage: "person.text.rectangle.fill",
                    tint: .pink,
                    paragraphs: [
                        AppLanguageManager.localized("profile.terms.profile.p1"),
                        AppLanguageManager.localized("profile.terms.profile.p2"),
                        AppLanguageManager.localized("profile.terms.profile.p3")
                    ]
                ),
                SettingsDocumentSection(
                    title: AppLanguageManager.localized("profile.terms.respectfulUse.title"),
                    systemImage: "heart.text.square.fill",
                    tint: .orange,
                    paragraphs: [
                        AppLanguageManager.localized("profile.terms.respectfulUse.p1"),
                        AppLanguageManager.localized("profile.terms.respectfulUse.p2"),
                        AppLanguageManager.localized("profile.terms.respectfulUse.p3")
                    ]
                ),
                SettingsDocumentSection(
                    title: AppLanguageManager.localized("profile.terms.messaging.title"),
                    systemImage: "bubble.left.and.bubble.right.fill",
                    tint: .blue,
                    paragraphs: [
                        AppLanguageManager.localized("profile.terms.messaging.p1"),
                        AppLanguageManager.localized("profile.terms.messaging.p2"),
                        AppLanguageManager.localized("profile.terms.messaging.p3")
                    ]
                ),
                SettingsDocumentSection(
                    title: AppLanguageManager.localized("profile.terms.accountChanges.title"),
                    systemImage: "gearshape.fill",
                    tint: .purple,
                    paragraphs: [
                        AppLanguageManager.localized("profile.terms.accountChanges.p1"),
                        AppLanguageManager.localized("profile.terms.accountChanges.p2"),
                        AppLanguageManager.localized("profile.terms.accountChanges.p3")
                    ]
                )
            ],
            footer: AppLanguageManager.localized("profile.terms.footer")
        )
    }
}

private struct SettingsDocumentView: View {
    let title: String
    let headerIcon: String
    let headerTitle: String
    let headerMessage: String
    let sections: [SettingsDocumentSection]
    let footer: String

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SettingsDocumentHeaderCard(
                    icon: headerIcon,
                    title: headerTitle,
                    message: headerMessage
                )

                ForEach(sections) { section in
                    SettingsDocumentSectionCard(section: section)
                }

                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsDocumentSection: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let tint: Color
    let paragraphs: [String]
}

private struct SettingsDocumentHeaderCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.pink)
                .frame(width: 42, height: 42)
                .background(Color.pink.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline.weight(.semibold))

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(18)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 8)
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsDocumentSectionCard: View {
    let section: SettingsDocumentSection

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(section.tint)
                    .frame(width: 36, height: 36)
                    .background(section.tint.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)

                Text(section.title)
                    .font(.headline.weight(.bold))

                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(section.paragraphs, id: \.self) { paragraph in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(section.tint.opacity(0.45))
                            .frame(width: 5, height: 5)
                            .padding(.top, 7)
                            .accessibilityHidden(true)

                        Text(paragraph)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(18)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.035), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 7)
        .accessibilityElement(children: .contain)
    }
}

private struct ContactInfoRow: View {
    let icon: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 14)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct AccountSettingsView: View {
    @EnvironmentObject private var session: SessionViewModel
    @Binding var notice: String?
    let onSignOut: () -> Void
    @State private var showChangePassword = false
    @State private var showExportSheet = false
    @State private var showDeleteConfirmation = false
    @State private var isRequestingDeletion = false
    @State private var isPreparingExport = false
    @State private var exportText = ""
    @State private var actionError: String?

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 14) {
                    AccountSettingsHeader(profile: session.currentProfile)

                    AccountSettingsCard(title: AppLanguageManager.localized("profile.account.section.account")) {
                        AccountInfoRow(
                            icon: "envelope.fill",
                            title: AppLanguageManager.localized("profile.account.email"),
                            value: session.currentUserEmail ?? AppLanguageManager.localized("common.notAvailable")
                        )

                        AccountInfoRow(
                            icon: "number",
                            title: AppLanguageManager.localized("profile.account.userId"),
                            value: session.currentUserId?.uuidString ?? AppLanguageManager.localized("common.notAvailable"),
                            isMonospaced: true
                        )

                        AccountInfoRow(
                            icon: "checkmark.seal.fill",
                            title: AppLanguageManager.localized("profile.account.verification"),
                            value: verificationText
                        )
                    }

                    AccountSettingsCard(title: AppLanguageManager.localized("profile.account.section.security")) {
                        AccountActionRow(
                            icon: "key.fill",
                            title: AppLanguageManager.localized("profile.account.changePassword"),
                            subtitle: AppLanguageManager.localized("profile.account.changePassword.subtitle")
                        ) {
                            HapticManager.light()
                            showChangePassword = true
                        }
                    }

                    AccountSettingsCard(title: AppLanguageManager.localized("profile.account.section.accountControl")) {
                        AccountActionRow(
                            icon: "square.and.arrow.down.fill",
                            title: AppLanguageManager.localized("profile.account.downloadMyData"),
                            subtitle: AppLanguageManager.localized("profile.account.downloadMyData.subtitle")
                        ) {
                            prepareExport()
                        }

                        AccountActionRow(
                            icon: "trash.fill",
                            title: AppLanguageManager.localized("profile.settings.deleteAccount"),
                            subtitle: AppLanguageManager.localized("profile.account.deleteAccount.subtitle"),
                            tint: .red
                        ) {
                            HapticManager.warning()
                            showDeleteConfirmation = true
                        }
                    }

                    Button(role: .destructive) {
                        HapticManager.warning()
                        onSignOut()
                    } label: {
                        Label(AppLanguageManager.localized("profile.settings.signOut"), systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .padding(.top, 4)
                }
                .padding(16)
            }

            if showDeleteConfirmation {
                PremiumConfirmationOverlay(
                    icon: "trash.fill",
                    tint: .red,
                    title: AppLanguageManager.localized("profile.account.deleteConfirm.title"),
                    message: AppLanguageManager.localized("profile.account.deleteConfirm.message"),
                    confirmTitle: AppLanguageManager.localized("profile.account.requestDeletion"),
                    isProcessing: isRequestingDeletion,
                    onCancel: {
                        HapticManager.light()
                        showDeleteConfirmation = false
                    },
                    onConfirm: {
                        HapticManager.warning()
                        requestDeletion()
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: showDeleteConfirmation)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(AppLanguageManager.localized("profile.account.title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showChangePassword) {
            ChangePasswordSheet()
                .environmentObject(session)
        }
        .sheet(isPresented: $showExportSheet) {
            AccountDataExportSheet(exportText: exportText)
        }
        .alert(AppLanguageManager.localized("profile.account.title"), isPresented: Binding(
            get: { actionError != nil },
            set: { isPresented in
                if !isPresented {
                    actionError = nil
                }
            }
        )) {
            Button(AppLanguageManager.localized("common.ok"), role: .cancel) { }
        } message: {
            Text(actionError ?? "")
        }
    }

    private var verificationText: String {
        guard let profile = session.currentProfile else { return AppLanguageManager.localized("common.notAvailable") }

        switch profile.verificationStatus {
        case .verified:
            return AppLanguageManager.localized("profile.verificationStatus.verified")
        case .pending:
            return AppLanguageManager.localized("profile.verificationStatus.pendingReview")
        case .rejected:
            return AppLanguageManager.localized("profile.verificationStatus.rejected")
        case .unsubmitted:
            return AppLanguageManager.localized("profile.verificationStatus.notSubmitted")
        }
    }

    private func showComingSoon(_ feature: String) {
        HapticManager.light()
        notice = String(
            format: AppLanguageManager.localized("profile.settings.comingSoonFormat"),
            feature
        )
    }

    private func prepareExport() {
        guard !isPreparingExport else { return }
        HapticManager.light()
        isPreparingExport = true

        Task {
            do {
                exportText = try await buildAccountExport()
                showExportSheet = true
            } catch {
                actionError = String(
                    format: AppLanguageManager.localized("profile.account.dataExportFailedFormat"),
                    error.localizedDescription
                )
            }

            isPreparingExport = false
        }
    }

    private func requestDeletion() {
        guard !isRequestingDeletion else { return }
        isRequestingDeletion = true

        Task {
            let didRequest = await session.requestAccountDeletion()
            isRequestingDeletion = false

            if didRequest {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                showDeleteConfirmation = false
                notice = AppLanguageManager.localized("profile.account.deletionScheduled")
            } else {
                actionError = session.errorMessage ?? AppLanguageManager.localized("profile.account.deleteRequestFailed")
            }
        }
    }

    private func buildAccountExport() async throws -> String {
        guard let userId = session.currentUserId else {
            throw NSError(domain: "AccountExport", code: 1, userInfo: [
                NSLocalizedDescriptionKey: AppLanguageManager.localized("auth.error.signInAgain")
            ])
        }

        struct AccountExportPayload: Codable {
            let exportedAt: String
            let email: String?
            let profile: Profile?
            let photos: [ProfilePhoto]
            let prompts: [ProfilePrompt]
            let interests: [ProfileInterest]
            let filters: [DatingFilter]
        }

        let client = SupabaseManager.shared.client
        let photos = (try? await ProfilePhotoService.shared.fetchPhotos(userId: userId)) ?? []

        let prompts: [ProfilePrompt] = (try? await client
            .from("profile_prompts")
            .select()
            .eq("user_id", value: userId)
            .order("display_order", ascending: true)
            .execute()
            .value) ?? []

        let interests: [ProfileInterest] = (try? await client
            .from("profile_interests")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value) ?? []

        let filters: [DatingFilter] = (try? await client
            .from("dating_filters")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value) ?? []

        let payload = AccountExportPayload(
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            email: session.currentUserEmail,
            profile: session.currentProfile,
            photos: photos,
            prompts: prompts,
            interests: interests,
            filters: filters
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)

        return String(data: data, encoding: .utf8) ?? AppLanguageManager.localized("profile.account.emptyExportFallback")
    }
}

private struct AccountSettingsHeader: View {
    let profile: Profile?
    @State private var profileImage: UIImage?

    var body: some View {
        HStack(spacing: 14) {
            ProfileSummaryAvatar(
                initials: initials,
                image: profileImage,
                size: 44
            )
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(profile?.verificationStatus == .verified ? .green : .secondary)
                    .padding(2.5)
                    .background(Color(.systemBackground), in: Circle())
                    .offset(x: 1, y: 1)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(profile?.publicName ?? AppLanguageManager.localized("profile.account.yourAccount"))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)

                Text(AppLanguageManager.localized("profile.account.header.subtitle"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .task(id: profile?.profilePhotoURL) {
            await loadPhoto()
        }
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.black.opacity(0.045), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.045), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
    }

    private var initials: String {
        let fallbackInitial = AppLanguageManager.localized("profile.account.fallbackInitial")
        let source = profile?.publicName ?? profile?.displayName ?? fallbackInitial
        let parts = source
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }

        let value = String(parts).uppercased()
        return value.isEmpty ? fallbackInitial : value
    }

    private func loadPhoto() async {
        guard let path = profile?.profilePhotoURL,
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            profileImage = nil
            return
        }

        profileImage = try? await ProfilePhotoService.shared.image(for: path)
    }
}

private struct AccountSettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline.weight(.bold))

            VStack(spacing: 0) {
                content
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.045), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.04), radius: 12, y: 6)
        .accessibilityElement(children: .contain)
    }
}

private struct AccountInfoRow: View {
    let icon: String
    let title: String
    let value: String
    var isMonospaced = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.pink)
                .frame(width: 30, height: 30)
                .background(Color.pink.opacity(0.10), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(isMonospaced ? .caption.monospaced() : .subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(isMonospaced ? 2 : 1)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .accessibilityElement(children: .combine)
    }
}

private struct AccountActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var tint: Color = .pink
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.10), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint == .red ? .red : .primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle)
    }
}

private struct PremiumConfirmationOverlay: View {
    let icon: String
    let tint: Color
    let title: String
    let message: String
    let confirmTitle: String
    var isProcessing = false
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .onTapGesture {
                    guard !isProcessing else { return }
                    onCancel()
                }

            VStack(spacing: 18) {
                Image(systemName: icon)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 46, height: 46)
                    .background(tint.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.title3.weight(.bold))
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 10) {
                    Button {
                        onConfirm()
                    } label: {
                        HStack(spacing: 8) {
                            if isProcessing {
                                ProgressView()
                                    .tint(.white)
                                    .accessibilityHidden(true)
                            }

                            Text(isProcessing ? AppLanguageManager.localized("common.pleaseWait") : confirmTitle)
                        }
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isProcessing ? AppLanguageManager.localized("common.pleaseWait") : confirmTitle)
                    .disabled(isProcessing)

                    Button {
                        onCancel()
                    } label: {
                        Text(AppLanguageManager.localized("common.cancel"))
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppLanguageManager.localized("common.cancel"))
                    .disabled(isProcessing)
                }
            }
            .padding(22)
            .frame(maxWidth: 340)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.38), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 28, y: 16)
            .padding(.horizontal, 24)
            .accessibilityElement(children: .contain)
        }
    }
}

private struct ChangePasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionViewModel
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(AppLanguageManager.localized("profile.account.changePassword.newPassword"), text: $password)
                        .textContentType(.newPassword)

                    SecureField(AppLanguageManager.localized("profile.account.changePassword.confirmPassword"), text: $confirmPassword)
                        .textContentType(.newPassword)
                } header: {
                    Text(AppLanguageManager.localized("profile.account.password"))
                } footer: {
                    Text(AppLanguageManager.localized("profile.account.changePassword.footer"))
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(AppLanguageManager.localized("profile.account.changePassword"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLanguageManager.localized("common.cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text(AppLanguageManager.localized("common.save"))
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func save() {
        errorMessage = nil

        guard password == confirmPassword else {
            errorMessage = AppLanguageManager.localized("profile.account.changePassword.passwordMismatch")
            return
        }

        isSaving = true
        Task {
            let didSave = await session.updateAccountPassword(password)
            isSaving = false

            if didSave {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } else {
                errorMessage = session.errorMessage ?? AppLanguageManager.localized("profile.account.changePassword.updateFailed")
            }
        }
    }
}

private struct ChangeEmailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionViewModel
    @State private var email: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(initialEmail: String) {
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(AppLanguageManager.localized("profile.account.changeEmail.emailAddress"), text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text(AppLanguageManager.localized("profile.account.email"))
                } footer: {
                    Text(AppLanguageManager.localized("profile.account.changeEmail.footer"))
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(AppLanguageManager.localized("profile.account.changeEmail"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLanguageManager.localized("common.cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text(AppLanguageManager.localized("common.save"))
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil

        Task {
            let didSave = await session.updateAccountEmail(email)
            isSaving = false

            if didSave {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } else {
                errorMessage = session.errorMessage ?? AppLanguageManager.localized("profile.account.changeEmail.updateFailed")
            }
        }
    }
}

private struct AccountDataExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let exportText: String

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(exportText)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(AppLanguageManager.localized("profile.account.myData"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLanguageManager.localized("common.close")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: exportText) {
                        Label(AppLanguageManager.localized("common.share"), systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}

private struct SettingsRow: View {
    let systemImage: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsStaticRow(systemImage: systemImage, title: title)
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsStaticRow: View {
    let systemImage: String
    let title: String
    var tint: Color = .pink
    var showsChevron = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.10), in: Circle())

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint == .red ? .red : .primary)

            Spacer()

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct PreviewMyProfileButton: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.rectangle")
                .font(.headline)
                .foregroundStyle(.pink)
                .frame(width: 34, height: 34)
                .background(.pink.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(AppLanguageManager.localized("profile.preview.title"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(AppLanguageManager.localized("profile.preview.subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .appCard()
    }
}

private struct AccountStatusCard: View {
    let profile: Profile
    let onVisibilitySettingsTap: () -> Void

    private var isVisible: Bool {
        profile.isDiscoverable && !profile.isCurrentlyBanned && !profile.isDeactivated
    }

    private var visibilityTitle: String {
        isVisible
            ? AppLanguageManager.localized("profile.visibility.visibleInDiscovery")
            : AppLanguageManager.localized("profile.visibility.notVisible")
    }

    private var visibilityMessage: String {
        if profile.isCurrentlyBanned {
            return AppLanguageManager.localized("profile.visibility.hiddenRestricted")
        }

        if profile.isDeactivated {
            return AppLanguageManager.localized("profile.visibility.hiddenDeletionPending")
        }

        return isVisible
            ? AppLanguageManager.localized("profile.visibility.visibleDescription")
            : AppLanguageManager.localized("profile.visibility.pausedDescription")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Text(AppLanguageManager.localized("profile.visibility.accountStatus"))
                    .font(.headline.weight(.semibold))

                Spacer()

                Text(isVisible ? AppLanguageManager.localized("profile.visibility.active") : AppLanguageManager.localized("profile.visibility.hidden"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isVisible ? .green : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(isVisible ? Color.green.opacity(0.10) : Color(.secondarySystemFill), in: Capsule())
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isVisible ? "eye.fill" : "eye.slash.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isVisible ? .green : .secondary)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(visibilityTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(visibilityMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            Divider()

            Button {
                onVisibilitySettingsTap()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.pink)
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppLanguageManager.localized("profile.visibility.settings"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text(AppLanguageManager.localized("profile.visibility.settings.subtitle"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .appCard()
    }
}

private struct VisibilitySettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionViewModel
    @AppStorage(VisibilityPreferenceKey.reduceRecentPassResurfacing) private var reduceRecentPassResurfacing = false
    @State private var isDiscoverable = true
    @State private var isSavingDiscoverable = false
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    visibilityHeader

                    NotificationSettingsGroup(title: AppLanguageManager.localized("profile.visibility.discovery")) {
                        VisibilityToggleRow(
                            icon: isDiscoverable ? "eye.fill" : "eye.slash.fill",
                            title: AppLanguageManager.localized("profile.visibility.showInDiscovery"),
                            subtitle: AppLanguageManager.localized("profile.visibility.showInDiscovery.subtitle"),
                            tint: isDiscoverable ? .green : .secondary,
                            isOn: Binding(
                                get: { isDiscoverable },
                                set: { newValue in
                                    Task {
                                        await updateDiscoverable(newValue)
                                    }
                                }
                            ),
                            isLoading: isSavingDiscoverable
                        )
                    }

                    NotificationSettingsGroup(title: AppLanguageManager.localized("profile.visibility.discoveryPriority")) {
                        VisibilityToggleRow(
                            icon: "arrow.uturn.backward.circle.fill",
                            title: AppLanguageManager.localized("profile.visibility.reduceResurfacing"),
                            subtitle: AppLanguageManager.localized("profile.visibility.reduceResurfacing.subtitle"),
                            tint: .purple,
                            isOn: $reduceRecentPassResurfacing
                        )
                    }

                    Text(AppLanguageManager.localized("profile.visibility.footer"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(AppLanguageManager.localized("profile.visibility.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLanguageManager.localized("common.done")) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                isDiscoverable = session.currentProfile?.isDiscoverable ?? true
            }
            .alert(AppLanguageManager.localized("profile.visibility.title"), isPresented: Binding(
                get: { notice != nil },
                set: { isPresented in
                    if !isPresented {
                        notice = nil
                    }
                }
            )) {
                Button(AppLanguageManager.localized("common.ok"), role: .cancel) { }
            } message: {
                Text(notice ?? "")
            }
        }
    }

    private var visibilityHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: isDiscoverable ? "eye.circle.fill" : "eye.slash.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(isDiscoverable ? .green : .pink)
                    .frame(width: 48, height: 48)
                    .background((isDiscoverable ? Color.green : Color.pink).opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(isDiscoverable ? AppLanguageManager.localized("profile.visibility.visibleInDiscovery") : AppLanguageManager.localized("profile.visibility.discoveryPaused"))
                        .font(.headline.weight(.semibold))

                    Text(isDiscoverable ? AppLanguageManager.localized("profile.visibility.visibleHeaderDescription") : AppLanguageManager.localized("profile.visibility.hiddenHeaderDescription"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.green)

                Text(AppLanguageManager.localized("profile.visibility.privacyNotice"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(18)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 8)
    }

    @MainActor
    private func updateDiscoverable(_ newValue: Bool) async {
        guard !isSavingDiscoverable else { return }

        let oldValue = isDiscoverable
        isDiscoverable = newValue
        isSavingDiscoverable = true
        HapticManager.light()

        let didSave = await session.updateDiscoveryVisibility(isDiscoverable: newValue)
        isSavingDiscoverable = false

        if !didSave {
            isDiscoverable = oldValue
            notice = session.errorMessage ?? AppLanguageManager.localized("profile.visibility.updateFailed")
        }
    }
}

enum VisibilityPreferenceKey {
    static let reduceRecentPassResurfacing = "visibility.reduceRecentPassResurfacing"
}

private struct VisibilityToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    @Binding var isOn: Bool
    var isLoading = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Toggle(AppLanguageManager.localized("common.toggle"), isOn: $isOn)
                    .labelsHidden()
                    .tint(.pink)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onChange(of: isOn) { _, _ in
            HapticManager.light()
        }
    }
}

private struct ProfileStrength {
    let percentage: Int
    let completedCount: Int
    let totalCount: Int
    let suggestions: [String]

    init(profile: Profile, photoCount: Int, promptCount: Int) {
        let bio = profile.bio?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let jobTitle = profile.jobTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let education = profile.educationLevel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hometown = profile.hometown?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let currentlyLiving = profile.currentlyLiving?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lifestyleCount = [
            profile.smoking,
            profile.drinking,
            profile.exercise,
            profile.pets,
            profile.communicationStyle,
            profile.loveLanguage,
            profile.mbti,
            profile.languages,
            profile.familyPlans
        ].filter { value in
            value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }.count

        let checks: [(isComplete: Bool, suggestion: String)] = [
            (photoCount >= 1 || profile.profilePhotoURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false, AppLanguageManager.localized("profile.strength.suggestion.addProfilePhoto")),
            (photoCount >= 3, AppLanguageManager.localized("profile.strength.suggestion.addMorePhotos")),
            (!bio.isEmpty, AppLanguageManager.localized("profile.strength.suggestion.completeBio")),
            (!jobTitle.isEmpty, AppLanguageManager.localized("profile.strength.suggestion.addWorkTitle")),
            (!education.isEmpty, AppLanguageManager.localized("profile.strength.suggestion.addEducation")),
            (profile.relationshipGoal != nil, AppLanguageManager.localized("profile.strength.suggestion.addRelationshipGoal")),
            (lifestyleCount >= 3, AppLanguageManager.localized("profile.strength.suggestion.addLifestyleDetails")),
            (!hometown.isEmpty || !currentlyLiving.isEmpty, AppLanguageManager.localized("profile.strength.suggestion.addLocation")),
            (profile.verificationStatus == .verified, AppLanguageManager.localized("profile.strength.suggestion.verifyProfile")),
            (promptCount >= 1, AppLanguageManager.localized("profile.strength.suggestion.answerPrompts"))
        ]

        completedCount = checks.filter { $0.isComplete }.count
        totalCount = checks.count
        percentage = Int((Double(completedCount) / Double(totalCount) * 100).rounded())

        let missingSuggestions = checks
            .filter { !$0.isComplete }
            .map { $0.suggestion }

        suggestions = Array(missingSuggestions.prefix(3))
    }
}

private struct ProfileStrengthCard: View {
    let strength: ProfileStrength
    let onSuggestionTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(AppLanguageManager.localized("profile.strength.title"))
                        .font(.headline.weight(.semibold))

                    Text(String(
                        format: AppLanguageManager.localized("profile.strength.completedFormat"),
                        strength.completedCount,
                        strength.totalCount
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(strength.percentage)%")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.pink)
            }

            ProgressView(value: Double(strength.percentage), total: 100)
                .tint(.pink)

            if strength.suggestions.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)

                    Text(AppLanguageManager.localized("profile.strength.looksStrong"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(strength.suggestions, id: \.self) { suggestion in
                        Button {
                            onSuggestionTap()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkle")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.pink)

                                Text(suggestion)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .appCard()
    }
}

struct VerificationTrustCard: View {
    let status: VerificationStatus

    private var isVerified: Bool {
        status == .verified
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Text(AppLanguageManager.localized("profile.verification.title"))
                    .font(.headline.weight(.semibold))

                Spacer()

                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isVerified ? .green : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(statusBackground, in: Capsule())
            }

            VStack(spacing: 10) {
                VerificationTrustRow(title: AppLanguageManager.localized("profile.verification.identity"), status: status)
                VerificationTrustRow(title: AppLanguageManager.localized("profile.verification.work"), status: status)
                VerificationTrustRow(title: AppLanguageManager.localized("profile.verification.education"), status: status)
            }

            Divider()

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isVerified ? .green : .secondary)
                    .frame(width: 24, height: 24)

                Text(AppLanguageManager.localized("profile.verification.reviewNotice"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
        }
        .padding(16)
        .appCard()
    }

    private var statusText: String {
        switch status {
        case .pending:
            return AppLanguageManager.localized("profile.verificationStatus.underReview")
        case .rejected:
            return AppLanguageManager.localized("profile.verificationStatus.notCompleted")
        case .unsubmitted:
            return AppLanguageManager.localized("profile.verificationStatus.notCompleted")
        case .verified:
            return AppLanguageManager.localized("profile.verificationStatus.verified")
        }
    }

    private var statusBackground: Color {
        isVerified ? .green.opacity(0.10) : Color(.secondarySystemFill)
    }
}

private struct VerificationTrustRow: View {
    let title: String
    let status: VerificationStatus

    private var isVerified: Bool {
        status == .verified
    }

    private var statusText: String {
        switch status {
        case .verified:
            return AppLanguageManager.localized("profile.verificationStatus.verified")
        case .pending:
            return AppLanguageManager.localized("profile.verificationStatus.underReview")
        case .rejected, .unsubmitted:
            return AppLanguageManager.localized("profile.verificationStatus.notCompleted")
        }
    }

    private var systemImage: String {
        switch status {
        case .verified:
            return "checkmark.circle.fill"
        case .pending:
            return "clock.fill"
        case .rejected, .unsubmitted:
            return "circle"
        }
    }

    private var iconColor: Color {
        switch status {
        case .verified:
            return .green
        case .pending:
            return .orange
        case .rejected, .unsubmitted:
            return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 24, height: 24)

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)

            Spacer()

            Text(statusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isVerified ? .green : .secondary)
        }
    }
}
