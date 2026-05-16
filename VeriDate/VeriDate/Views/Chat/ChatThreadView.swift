import AVFoundation
import AVKit
import Combine
import Photos
import PhotosUI
import QuickLook
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private extension Notification.Name {
    static let scrollToMessage = Notification.Name("ScrollToMessage")
}

struct ChatThreadView: View {
    @EnvironmentObject var session: SessionViewModel
    @StateObject private var vm = ChatThreadViewModel()
    @StateObject private var safetyVM = SafetyViewModel()
    @StateObject private var voiceRecorder = VoiceMessageRecorder()
    @State private var messageText = ""
    @State private var isShowingReportAlert = false
    @State private var isShowingBlockAlert = false
    @State private var typingDebounceTask: Task<Void, Never>?
    @State private var stopTypingTask: Task<Void, Never>?
    @State private var hasPerformedInitialScroll = false
    @State private var isAtBottom = true
    @State private var showNewMessagesButton = false
    @State private var unreadNewMessageCount = 0
    @State private var knownMessageIds = Set<UUID>()
    @State private var shouldShowUnreadSeparator = false
    @State private var unreadAnchorMessageId: UUID?
    @State private var pendingUnreadAnchorMessageId: UUID?
    @State private var isChoosingAttachmentSource = false
    @State private var isPickingPhoto = false
    @State private var isUsingCamera = false
    @State private var isImportingFile = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var pendingAttachments: [PendingChatAttachment] = []
    @State private var replyTarget: Message?
    @State private var reactionTarget: Message?
    @State private var editTarget: Message?
    @State private var deleteTarget: Message?
    @State private var actionMenuMessage: Message?
    @State private var isShowingDeleteConfirm = false
    @State private var customReactionMessage: Message?
    @State private var customReactionText = ""
    @State private var highlightedMessageId: UUID?
    @State private var selectedCompatibilityInsight: ChatCompatibilityInsight?
    @FocusState private var isComposerFocused: Bool
    @State private var sendButtonPulse = false
    let row: MatchRow
    private let bottomAnchorId = "chat-bottom-anchor"

    var body: some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composer
            }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                NavigationLink {
                    DiscoveryProfileDetailView(
                        profile: vm.otherProfile ?? row.profile,
                        currentProfile: session.currentProfile,
                        compatibilitySummary: nil,
                        onBlocked: {
                            vm.isBlocked = true
                        }
                    )
                } label: {
                    ChatHeader(
                        profile: vm.otherProfile ?? row.profile,
                        isTyping: vm.isOtherUserTyping,
                        isPresent: vm.isOtherUserPresent
                    )
                    .frame(width: 210, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        isShowingBlockAlert = true
                    } label: {
                        Label(AppLanguageManager.localized("safety_block_button"), systemImage: "hand.raised")
                    }

                    Button(role: .destructive) {
                        isShowingReportAlert = true
                    } label: {
                        Label(AppLanguageManager.localized("safety_report_button"), systemImage: "exclamationmark.bubble")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isShowingReportAlert) {
            if let userId = session.currentUserId {
                SafetyReportSheet(
                    reporterUserId: userId,
                    reportedUserId: row.otherUserId(for: userId),
                    matchId: row.match.id,
                    reportedName: (vm.otherProfile ?? row.profile).publicName ?? AppLanguageManager.localized("common_user")
                )
            }
        }
        .alert(AppLanguageManager.localized("chat_block_user_title"), isPresented: $isShowingBlockAlert) {
            Button("common_cancel", role: .cancel) {}
            Button("safety_block_button", role: .destructive) {
                Task {
                    await blockUser()
                }
            }
        } message: {
            Text("chat_block_user_message")
        }
        .alert(AppLanguageManager.localized("chat_delete_message_title"), isPresented: $isShowingDeleteConfirm) {
            Button("common_cancel", role: .cancel) {
                deleteTarget = nil
            }
            Button("chat_action_delete", role: .destructive) {
                if let deleteTarget {
                    Task {
                        await deleteSelectedMessage(deleteTarget)
                    }
                }
            }
        } message: {
            Text("chat_delete_message_message")
        }
        .alert(AppLanguageManager.localized("common_notice"), isPresented: actionAlertBinding) {
            Button("common_ok") {
                vm.actionMessage = nil
            }
        } message: {
            Text(vm.actionMessage ?? "")
        }
        .sheet(isPresented: customReactionBinding) {
            if let customReactionMessage {
                CustomEmojiReactionSheet(
                    onCancel: {
                        self.customReactionMessage = nil
                        customReactionText = ""
                    },
                    onSelect: { emoji in
                        submitCustomReaction(emoji, for: customReactionMessage)
                    }
                )
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(item: $selectedCompatibilityInsight) { insight in
            ChatCompatibilityInsightDetailSheet(insight: insight)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task(id: row.id) {
            hasPerformedInitialScroll = false
            NotificationCenter.default.post(name: .didOpenChatMatch, object: row.match.id)
            vm.setInitialProfile(row.profile)
            await load()

            if let userId = session.currentUserId {
                await vm.loadOtherUserProfile(match: row.match, currentUserId: userId)
            }

            Task {
                await vm.subscribeToTyping(matchId: row.match.id)
            }

            // Force delayed scroll after load completes.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                NotificationCenter.default.post(name: Notification.Name("ForceScrollToBottom"), object: nil)
            }

            await keepChatSynced()
        }
        .onDisappear {
            NotificationCenter.default.post(name: .didCloseChatMatch, object: row.match.id)
            voiceRecorder.cancelRecording()
            vm.unsubscribeMessages()
            typingDebounceTask?.cancel()
            stopTypingTask?.cancel()
            if let userId = session.currentUserId {
                Task { await vm.stopTyping(matchId: row.match.id, userId: userId) }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if session.currentProfile?.verificationStatus != .verified {
            ContentUnavailableView(
                AppLanguageManager.localized("chat_verification_required_title"),
                systemImage: "checkmark.seal",
                description: Text("chat_verification_required_message")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.isLoading {
            ProgressView("chat_loading_messages")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = vm.errorMessage, vm.messages.isEmpty, !error.localizedCaseInsensitiveContains("cancellation") {
            ContentUnavailableView(AppLanguageManager.localized("chat_could_not_load_chat_title"), systemImage: "exclamationmark.triangle", description: Text(error))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            if vm.messages.isEmpty {
                VStack(spacing: 12) {
                    chatCompatibilityInsightSection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)

                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)

                    Text("chat_empty_title")
                        .font(.headline)

                    Text(String.localizedStringWithFormat(
                        AppLanguageManager.localized("chat_empty_message_format"),
                        vm.otherProfile?.publicName ?? row.profile.publicName ?? AppLanguageManager.localized("chat_your_match")
                    ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            chatCompatibilityInsightSection
                                .padding(.bottom, 10)

                            ForEach(vm.chatItems) { item in
                                chatItemRow(for: item)
                                    .id(item.id)
                            }

                            Color.clear
                                .frame(height: 1)
                                .id(bottomAnchorId)
                        }
                        .padding()
                        .padding(.bottom, isComposerFocused ? 24 : 0)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .safeAreaPadding(.bottom, 8)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                            dismissMessageOverlays()
                        }
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .opacity(hasPerformedInitialScroll ? 1 : 0)
                    .animation(nil, value: hasPerformedInitialScroll)
                    .onAppear {
                        guard !hasPerformedInitialScroll else { return }
                        if !vm.messages.isEmpty {
                            scrollToInitialTarget(using: proxy, messages: vm.messages)
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                        guard isComposerFocused, isAtBottom else { return }
                        scrollToBottom(using: proxy, animated: true)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { _ in
                        guard isComposerFocused, isAtBottom else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                            scrollToBottom(using: proxy, animated: true)
                        }
                    }
                    .onChange(of: isComposerFocused) { _, focused in
                        guard focused, isAtBottom else { return }
                        DispatchQueue.main.async {
                            scrollToBottom(using: proxy, animated: true)
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ForceScrollToBottom"))) { _ in
                        DispatchQueue.main.async {
                            scrollToBottom(using: proxy, animated: false)
                            isAtBottom = true
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .scrollToMessage)) { notification in
                        guard let messageId = notification.object as? UUID else { return }
                        DispatchQueue.main.async {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo(messageId.uuidString, anchor: .center)
                            }
                            glowMessage(messageId)
                        }
                    }
                    .onChange(of: vm.messages) { _, messages in
                        guard !messages.isEmpty else { return }

                        let previousKnownMessageIds = knownMessageIds
                        let currentMessageIds = Set(messages.map { $0.id })
                        let newlyAddedMessages = messages.filter { !previousKnownMessageIds.contains($0.id) }
                        knownMessageIds = currentMessageIds

                        if !hasPerformedInitialScroll {
                            knownMessageIds = Set(messages.map { $0.id })
                            scrollToInitialTarget(using: proxy, messages: messages)
                            return
                        }

                        if isAtBottom {
                            scrollToBottom(using: proxy, animated: true)
                            unreadNewMessageCount = 0
                            showNewMessagesButton = false
                            markVisibleMessagesRead()

                            // ✅ Ensure separator disappears when new message arrives at bottom
                            shouldShowUnreadSeparator = false
                            unreadAnchorMessageId = nil
                            pendingUnreadAnchorMessageId = nil
                        } else {
                            if let userId = session.currentUserId {
                                let newIncomingMessages = newlyAddedMessages.filter { message in
                                    message.senderId != userId
                                }

                                if !newIncomingMessages.isEmpty {
                                    unreadNewMessageCount += newIncomingMessages.count

                                    // Save where the unread batch starts immediately when the messages arrive.
                                    // Do not rely on isRead later, because messages may already be marked read by tap time.
                                    if pendingUnreadAnchorMessageId == nil {
                                        pendingUnreadAnchorMessageId = newIncomingMessages.first?.id
                                    }

                                    shouldShowUnreadSeparator = false
                                    unreadAnchorMessageId = nil
                                }
                            }
                            showNewMessagesButton = unreadNewMessageCount > 0
                        }

                        // Realtime already updates messages; avoid extra refresh to reduce lag.
                    }
                    .overlay(alignment: .bottom) {
                        if showNewMessagesButton {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                scrollToBottom(using: proxy, animated: true)
                                unreadNewMessageCount = 0
                                knownMessageIds = Set(vm.messages.map { $0.id })
                                showNewMessagesButton = false
                                isAtBottom = true
                                unreadAnchorMessageId = pendingUnreadAnchorMessageId
                                shouldShowUnreadSeparator = pendingUnreadAnchorMessageId != nil
                            } label: {
                                Text(unreadNewMessageCount > 1 ? String.localizedStringWithFormat(AppLanguageManager.localized("chat_new_messages_button_format"), unreadNewMessageCount) : AppLanguageManager.localized("chat_new_message_button"))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                            }
                            .padding(.bottom, 12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .onChange(of: isAtBottom) { _, newValue in
                        if newValue {
                            unreadNewMessageCount = 0
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showNewMessagesButton = false
                            }
                        }
                    }
                }
            }
        }
    }
    @ViewBuilder
    private var chatCompatibilityInsightSection: some View {
        let insights = chatCompatibilityInsights

        if !insights.isEmpty {
            VStack(spacing: 8) {
                ForEach(insights) { insight in
                    ChatCompatibilityInsightCard(insight: insight) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selectedCompatibilityInsight = insight
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var chatCompatibilityInsights: [ChatCompatibilityInsight] {
        let currentProfile = session.currentProfile
        let otherProfile = vm.otherProfile ?? row.profile
        var insights: [ChatCompatibilityInsight] = []

        if let currentZodiac = zodiacSign(from: currentProfile?.dateOfBirth),
           let otherZodiac = zodiacSign(from: otherProfile.dateOfBirth) {
            insights.append(ChatCompatibilityInsight.zodiac(current: currentZodiac, other: otherZodiac))
        }

        if let currentMBTI = normalizedMBTI(currentProfile?.mbti),
           let otherMBTI = normalizedMBTI(otherProfile.mbti) {
            insights.append(ChatCompatibilityInsight.mbti(current: currentMBTI, other: otherMBTI))
        }

        return insights
    }

    private func normalizedMBTI(_ value: String?) -> String? {
        let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        guard cleaned.count == 4 else { return nil }
        return cleaned
    }

    private func zodiacSign(from dateString: String?) -> ChatZodiacSign? {
        guard let dateString, !dateString.isEmpty else { return nil }

        let date: Date?
        if let parsed = sharedISOFormatter.date(from: dateString) {
            date = parsed
        } else if let parsed = ISO8601DateFormatter().date(from: dateString) {
            date = parsed
        } else {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            date = formatter.date(from: dateString)
        }

        guard let date else { return nil }
        let components = Calendar.current.dateComponents([.month, .day], from: date)
        guard let month = components.month, let day = components.day else { return nil }
        return ChatZodiacSign(month: month, day: day)
    }

    private func dismissMessageOverlays() {
        guard actionMenuMessage != nil || reactionTarget != nil else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        actionMenuMessage = nil
        reactionTarget = nil
    }

    private func chatItemRow(for item: ChatThreadViewModel.ChatItem) -> ChatItemRowView {
        let currentUserId = session.currentUserId
        let pendingIds = vm.pendingMessageIds
        let lastId = vm.messages.last?.id
        let showSeparator = shouldShowUnreadSeparator
        let anchorId = unreadAnchorMessageId

        return ChatItemRowView(
            item: item,
            allMessages: vm.messages,
            reactionsByMessageId: vm.reactionsByMessageId,
            currentUserId: currentUserId,
            pendingMessageIds: pendingIds,
            failedMessageIds: vm.failedMessageIds,
            activeActionMessageId: actionMenuMessage?.id,
            activeReactionMessageId: reactionTarget?.id,
            highlightedMessageId: highlightedMessageId,
            hasActiveMessageOverlay: actionMenuMessage != nil || reactionTarget != nil,
            shouldShowUnreadSeparator: showSeparator,
            unreadAnchorMessageId: anchorId,
            lastMessageId: lastId,
            onAppearLast: handleReachedBottom,
            onDisappearLast: handleLastMessageDisappeared,
            onMessageLongPress: showMessageActionMenu,
            onMessageAction: handleMessageAction,
            onSwipeReply: startReply,
            onReactionSelected: handleReactionSelected,
            onMoreReactions: showCustomReactionSheet,
            onDismissMessageOverlays: {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                    dismissMessageOverlays()
                }
            },
            onRetry: handleRetryFailedMessage
        )
    }

    private func handleLastMessageDisappeared() {
        isAtBottom = false
    }

    private func handleRetryFailedMessage(_ message: Message) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            _ = await vm.retryFailedMessage(message, currentProfile: session.currentProfile)
        }
    }

    private func handleReachedBottom() {
        isAtBottom = true

        withAnimation(.easeInOut(duration: 0.2)) {
            showNewMessagesButton = false
        }

        unreadNewMessageCount = 0
        updateKnownMessageIds()
        markVisibleMessagesRead()
    }

    private func updateKnownMessageIds() {
        let ids = vm.messages.map { $0.id }
        knownMessageIds = Set(ids)
    }

    private func markVisibleMessagesRead() {
        guard let userId = session.currentUserId else { return }
        guard vm.messages.contains(where: { $0.senderId != userId && $0.readAt == nil }) else { return }

        Task {
            await vm.markMessagesRead(matchId: row.match.id)
        }
    }

    private var composerPlaceholder: String {
        if vm.isBlocked { return AppLanguageManager.localized("chat_messaging_unavailable_placeholder") }
        let name = vm.otherProfile?.publicName ?? row.profile.publicName ?? AppLanguageManager.localized("chat_your_match")
        return String.localizedStringWithFormat(AppLanguageManager.localized("chat_message_placeholder_format"), name)
    }

    private var canSend: Bool {
        (!messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty)
            && !vm.isSending
            && !vm.isUploadingAttachment
            && !vm.isBlocked
    }

    private func handleMessageAction(_ action: ChatMessageAction, message: Message) {
        guard message.canShowActionMenu else { return }
        guard message.allowedActions(isMine: message.senderId == session.currentUserId).contains(action) else { return }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
            actionMenuMessage = nil
        }

        switch action {
        case .reply:
            startReply(message)
        case .react:
            reactionTarget = message
        case .copy:
            UIPasteboard.general.string = message.copyText
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            vm.actionMessage = AppLanguageManager.localized("chat_message_copied")
        case .edit:
            guard message.senderId == session.currentUserId else { return }
            editTarget = message
            replyTarget = nil
            messageText = message.captionText
            isComposerFocused = true
        case .delete:
            deleteTarget = message
            isShowingDeleteConfirm = true
        }
    }

    private func startReply(_ message: Message) {
        guard message.canShowActionMenu else { return }

        replyTarget = message
        editTarget = nil
        actionMenuMessage = nil
        reactionTarget = nil
        isComposerFocused = true
    }

    private func handleReactionSelected(_ emoji: String, message: Message) {
        guard let userId = session.currentUserId else { return }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
            reactionTarget = nil
        }

        Task {
            let didReact = await vm.setReaction(emoji, for: message, userId: userId)
            if didReact {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    private func showCustomReactionSheet(for message: Message) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
            reactionTarget = nil
        }
        customReactionText = ""
        customReactionMessage = message
    }

    private func submitCustomReaction(for message: Message) {
        let emoji = customReactionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !emoji.isEmpty else { return }
        submitCustomReaction(emoji, for: message)
    }

    private func submitCustomReaction(_ emoji: String, for message: Message) {
        customReactionMessage = nil
        customReactionText = ""
        handleReactionSelected(emoji, message: message)
    }

    private func deleteSelectedMessage(_ message: Message) async {
        guard let userId = session.currentUserId else { return }
        let didDelete = await vm.deleteMessage(message, userId: userId)
        if didDelete {
            deleteTarget = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func showMessageActionMenu(for message: Message) {
        guard message.canShowActionMenu else { return }

        let shouldClose = actionMenuMessage?.id == message.id
        UIImpactFeedbackGenerator(style: shouldClose ? .light : .medium).impactOccurred()
        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
            actionMenuMessage = shouldClose ? nil : message
            reactionTarget = nil
        }
    }

    private func glowMessage(_ messageId: UUID) {
        highlightedMessageId = messageId
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            withAnimation(.easeOut(duration: 0.65)) {
                if highlightedMessageId == messageId {
                    highlightedMessageId = nil
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {


            if vm.isBlocked {
                Text("chat_blocked_composer_message")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let replyTarget {
                ChatComposerModeBanner(
                    title: AppLanguageManager.localized("chat_replying_to_title"),
                    message: replyTarget.previewText,
                    systemImage: "arrowshape.turn.up.left",
                    onClear: { self.replyTarget = nil }
                )
            }

            if let editTarget {
                ChatComposerModeBanner(
                    title: AppLanguageManager.localized("chat_editing_message_title"),
                    message: editTarget.previewText,
                    systemImage: "pencil",
                    onClear: { self.editTarget = nil }
                )
            }

            if !pendingAttachments.isEmpty {
                pendingAttachmentPreview
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if voiceRecorder.isRecording {
                VoiceRecordingPreview(
                    duration: voiceRecorder.elapsedTime,
                    levels: voiceRecorder.levels
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    isChoosingAttachmentSource = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(vm.isBlocked || vm.isUploadingAttachment ? Color.secondary.opacity(0.5) : Color.accentColor)
                        .frame(width: 36, height: 36)
                        .background(Color.secondary.opacity(0.10))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(vm.isBlocked || vm.isUploadingAttachment)
                .popover(
                    isPresented: $isChoosingAttachmentSource,
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .bottom
                ) {
                    AttachmentSourcePopup(
                        onPhotos: {
                            isChoosingAttachmentSource = false
                            isPickingPhoto = true
                        },
                        onCamera: {
                            isChoosingAttachmentSource = false
                            guard ChatPhotoCamera.isCameraAvailable else {
                                vm.errorMessage = AppLanguageManager.localized("chat_camera_unavailable_message")
                                return
                            }

                            isUsingCamera = true
                        },
                        onFiles: {
                            isChoosingAttachmentSource = false
                            isImportingFile = true
                        }
                    )
                    .presentationCompactAdaptation(.popover)
                }
                .photosPicker(
                    isPresented: $isPickingPhoto,
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 10,
                    matching: .any(of: [.images, .videos])
                )
                .fileImporter(
                    isPresented: $isImportingFile,
                    allowedContentTypes: [.item],
                    allowsMultipleSelection: true
                ) { result in
                    handleImportedFile(result)
                }
                .onChange(of: selectedPhotoItems) { _, newItems in
                    Task {
                        await addPhotoAttachments(newItems)
                    }
                }
                .sheet(isPresented: $isUsingCamera) {
                    ChatPhotoCamera { image in
                        addCameraAttachment(image)
                    }
                    .ignoresSafeArea()
                }

                TextField(composerPlaceholder, text: $messageText, axis: .vertical)
                    .focused($isComposerFocused)
                    .disabled(vm.isBlocked)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 21, style: .continuous)
                            .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
                    }
                    .tint(.accentColor)
                    .animation(.spring(response: 0.25, dampingFraction: 0.82), value: messageText)
                    .onChange(of: messageText) { oldValue, newValue in
                        guard oldValue != newValue else { return }
                        guard let userId = session.currentUserId else { return }

                        typingDebounceTask?.cancel()
                        stopTypingTask?.cancel()

                        let isEmpty = newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                        if isEmpty {
                            Task { await vm.stopTyping(matchId: row.match.id, userId: userId) }
                            return
                        }

                        typingDebounceTask = Task {
                            await vm.startTyping(matchId: row.match.id, userId: userId)
                        }

                        stopTypingTask = Task {
                            try? await Task.sleep(for: .seconds(2))
                            if !Task.isCancelled {
                                await vm.stopTyping(matchId: row.match.id, userId: userId)
                            }
                        }
                    }
                    .onSubmit {
                        if canSend {
                            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                            Task { await sendComposer() }
                        }
                    }

                if canSend {
                    Button {
                        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                        sendButtonPulse = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                            sendButtonPulse = false
                        }
                        Task {
                            await sendComposer()
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 38, height: 38)
                                .overlay {
                                    Circle()
                                        .stroke(Color.accentColor.opacity(0.45), lineWidth: 2)
                                        .blur(radius: 2)
                                        .opacity(0.8)
                                }

                            Image(systemName: vm.isSending || vm.isUploadingAttachment ? "paperplane.fill" : "arrow.up")
                                .font(.system(size: vm.isSending || vm.isUploadingAttachment ? 14 : 16, weight: .bold))
                                .contentTransition(.symbolEffect(.replace))
                                .foregroundStyle(Color.white)
                                .rotationEffect(.degrees(vm.isSending || vm.isUploadingAttachment ? 18 : 0))
                                .offset(y: sendButtonPulse ? -6 : 0)
                                .scaleEffect(sendButtonPulse ? 0.82 : 1)
                                .opacity(vm.isSending || vm.isUploadingAttachment ? 0.75 : 1)
                                .animation(.spring(response: 0.22, dampingFraction: 0.65), value: sendButtonPulse)
                                .animation(.easeInOut(duration: 0.2), value: vm.isSending || vm.isUploadingAttachment)
                        }
                    }
                    .disabled(vm.isSending || vm.isUploadingAttachment || vm.isBlocked)
                    .buttonStyle(.plain)
                    .scaleEffect(1)
                    .opacity(vm.isSending || vm.isUploadingAttachment ? 1 : 1)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: canSend)
                    .animation(.easeInOut(duration: 0.18), value: vm.isSending || vm.isUploadingAttachment)
                } else {
                    VoiceRecordButton(
                        isRecording: voiceRecorder.isRecording,
                        isDisabled: vm.isBlocked || vm.isUploadingAttachment || editTarget != nil,
                        onStart: {
                            await beginVoiceRecording()
                        },
                        onFinish: {
                            Task {
                                await finishVoiceRecording()
                            }
                        },
                        onCancel: {
                            voiceRecorder.cancelRecording()
                        }
                    )
                    .disabled(vm.isBlocked || vm.isUploadingAttachment || editTarget != nil)
                    .opacity(vm.isBlocked || vm.isUploadingAttachment || editTarget != nil ? 0.55 : 1)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: voiceRecorder.isRecording)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
        .fixedSize(horizontal: false, vertical: true)
        .animation(.easeInOut(duration: 0.2), value: vm.isOtherUserTyping)
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: voiceRecorder.isRecording)
    }

    private func beginVoiceRecording() async {
        guard !vm.isBlocked, !vm.isUploadingAttachment, editTarget == nil else { return }
        isComposerFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        do {
            try await voiceRecorder.startRecording()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } catch {
            vm.errorMessage = String.localizedStringWithFormat(AppLanguageManager.localized("chat_could_not_start_voice_recording_format"), error.localizedDescription)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func finishVoiceRecording() async {
        guard voiceRecorder.isRecording else { return }

        do {
            let recording = try voiceRecorder.stopRecording()
            guard recording.duration >= 0.6 else {
                vm.errorMessage = AppLanguageManager.localized("chat_hold_longer_voice_message")
                return
            }

            let data = try Data(contentsOf: recording.url)
            let file = ChatAttachmentFile(
                data: data,
                fileName: "voice-\(UUID().uuidString).m4a",
                contentType: "audio/mp4",
                kind: "audio"
            )

            guard let userId = session.currentUserId else { return }
            let didSend = await vm.sendAttachment(
                file,
                match: row.match,
                userId: userId,
                currentProfile: session.currentProfile,
                body: AppLanguageManager.localized("chat_voice_message"),
                attachmentGroupId: nil
            )

            if didSend {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    NotificationCenter.default.post(name: Notification.Name("ForceScrollToBottom"), object: nil)
                }
            }
        } catch {
            vm.errorMessage = String.localizedStringWithFormat(AppLanguageManager.localized("chat_could_not_send_voice_message_format"), error.localizedDescription)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private var pendingAttachmentPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String.localizedStringWithFormat(AppLanguageManager.localized("chat_attachments_selected_format"), pendingAttachments.count))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("common_clear") {
                    pendingAttachments.removeAll()
                }
                .font(.caption.weight(.medium))
                .disabled(vm.isUploadingAttachment)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(pendingAttachments) { attachment in
                        PendingAttachmentTile(
                            attachment: attachment,
                            onRemove: {
                                pendingAttachments.removeAll { $0.id == attachment.id }
                            }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func scrollToInitialTarget(using proxy: ScrollViewProxy, messages: [Message]) {
        guard !messages.isEmpty else {
            hasPerformedInitialScroll = true
            return
        }

        // Always open at the latest message by default.
        // Keep the list hidden until SwiftUI has actually applied the scroll position.
        DispatchQueue.main.async {
            scrollToBottom(using: proxy, animated: false)
            isAtBottom = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                scrollToBottom(using: proxy, animated: false)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                scrollToBottom(using: proxy, animated: false)
                hasPerformedInitialScroll = true
                updateKnownMessageIds()
                markVisibleMessagesRead()
            }
        }
    }

    private func scrollToBottom(using proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(bottomAnchorId, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomAnchorId, anchor: .bottom)
        }
    }

    private var actionAlertBinding: Binding<Bool> {
        Binding(
            get: { vm.actionMessage != nil },
            set: { isShowing in
                if !isShowing {
                    vm.actionMessage = nil
                }
            }
        )
    }

    private var customReactionBinding: Binding<Bool> {
        Binding(
            get: { customReactionMessage != nil },
            set: { isShowing in
                if !isShowing {
                    customReactionMessage = nil
                    customReactionText = ""
                }
            }
        )
    }

    private func load() async {
        guard let userId = session.currentUserId else { return }
        await vm.loadMessages(match: row.match, userId: userId, currentProfile: session.currentProfile)
    }

    private func keepChatSynced() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }

            let changed = await vm.refreshMessages(matchId: row.match.id)
            await vm.refreshTypingStatus(matchId: row.match.id)
            await vm.refreshOtherProfile(match: row.match)
            if changed, isAtBottom {
                markVisibleMessagesRead()
            }
        }
    }

    private func addPhotoAttachments(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }

        defer {
            selectedPhotoItems = []
        }

        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    vm.errorMessage = AppLanguageManager.localized("chat_could_not_read_attachment")
                    continue
                }

                let type = item.supportedContentTypes.first ?? .jpeg
                let fileExtension = type.preferredFilenameExtension ?? "jpg"
                let contentType = type.preferredMIMEType ?? "application/octet-stream"
                let kind = attachmentKind(for: contentType, type: type)
                let fileName = "\(UUID().uuidString).\(fileExtension)"

                pendingAttachments.append(
                    PendingChatAttachment(
                        data: data,
                        fileName: fileName,
                        contentType: contentType,
                        kind: kind
                    )
                )
            } catch {
                vm.errorMessage = String.localizedStringWithFormat(AppLanguageManager.localized("chat_could_not_read_attachment_format"), error.localizedDescription)
            }
        }
    }

    private func addCameraAttachment(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            vm.errorMessage = AppLanguageManager.localized("chat_could_not_read_camera_photo")
            return
        }

        pendingAttachments.append(
            PendingChatAttachment(
                data: data,
                fileName: "\(UUID().uuidString).jpg",
                contentType: "image/jpeg",
                kind: "image"
            )
        )
    }

    private func handleImportedFile(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task {
                await addFileAttachments(from: urls)
            }
        case .failure(let error):
            vm.errorMessage = String.localizedStringWithFormat(AppLanguageManager.localized("chat_could_not_import_file_format"), error.localizedDescription)
        }
    }

    private func addFileAttachments(from urls: [URL]) async {
        for url in urls {
            do {
                let hasScopedAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if hasScopedAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let data = try Data(contentsOf: url)
                let contentType = contentType(for: url)
                let kind = attachmentKind(for: contentType, type: UTType(filenameExtension: url.pathExtension))

                pendingAttachments.append(
                    PendingChatAttachment(
                        data: data,
                        fileName: url.lastPathComponent.isEmpty ? AppLanguageManager.localized("chat_attachment_message") : url.lastPathComponent,
                        contentType: contentType,
                        kind: kind
                    )
                )
            } catch {
                vm.errorMessage = String.localizedStringWithFormat(AppLanguageManager.localized("chat_could_not_read_named_file_format"), url.lastPathComponent, error.localizedDescription)
            }
        }
    }

    private func sendComposer() async {
        if pendingAttachments.isEmpty {
            await send()
        } else {
            await sendPendingAttachments()
        }
    }

    private func sendPendingAttachments() async {
        guard let userId = session.currentUserId else { return }
        guard !pendingAttachments.isEmpty else { return }

        typingDebounceTask?.cancel()
        stopTypingTask?.cancel()

        let attachmentsToSend = pendingAttachments
        let caption = messageText.trimmingCharacters(in: .whitespacesAndNewlines)

        withAnimation(.easeOut(duration: 0.12)) {
            pendingAttachments.removeAll()
            messageText = ""
        }

        var failedAttachments: [PendingChatAttachment] = []
        for (index, pendingAttachment) in attachmentsToSend.enumerated() {
            let didSend = await vm.sendAttachment(
                pendingAttachment.chatAttachmentFile,
                match: row.match,
                userId: userId,
                currentProfile: session.currentProfile,
                body: index == 0 && !caption.isEmpty ? caption : nil,
                attachmentGroupId: nil
            )

            if !didSend {
                failedAttachments.append(pendingAttachment)
            }
        }

        if failedAttachments.isEmpty {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            pendingAttachments = failedAttachments
            messageText = caption
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func contentType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension),
           let mimeType = type.preferredMIMEType {
            return mimeType
        }

        return "application/octet-stream"
    }

    private func attachmentKind(for contentType: String, type: UTType?) -> String {
        if contentType.hasPrefix("image/") || type?.conforms(to: .image) == true {
            return "image"
        }

        if contentType.hasPrefix("video/") || type?.conforms(to: .movie) == true {
            return "video"
        }

        if contentType.hasPrefix("audio/") || type?.conforms(to: .audio) == true {
            return "audio"
        }

        return "file"
    }


    private func send() async {
        guard let userId = session.currentUserId else { return }

        let textToSend = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textToSend.isEmpty || editTarget?.attachmentFilePath != nil else { return }

        typingDebounceTask?.cancel()
        stopTypingTask?.cancel()

        // Clear composer immediately for instant UX. Restore only if send fails.
        withAnimation(.easeOut(duration: 0.12)) {
            messageText = ""
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task {
            await vm.stopTyping(matchId: row.match.id, userId: userId)
        }

        let didSend: Bool
        let shouldScrollAfterSend = editTarget == nil && replyTarget != nil
        if let editTarget {
            didSend = await vm.editMessage(editTarget, newBody: textToSend, userId: userId)
            if didSend {
                self.editTarget = nil
            }
        } else {
            didSend = await vm.sendMessage(
                body: textToSend,
                match: row.match,
                userId: userId,
                currentProfile: session.currentProfile,
                replyToMessageId: replyTarget?.id
            )
            if didSend {
                replyTarget = nil
            }
        }

        // Do NOT restore text if message already exists as failed bubble
        // Retry should happen via tapping the failed message, not composer resend
        if !didSend {
            // Only restore text if no optimistic message was created
            // (i.e. truly blocked before send)
            if !vm.failedMessageIds.contains(where: { _ in true }) {
                withAnimation(.easeOut(duration: 0.12)) {
                    messageText = textToSend
                }
            }
        }
        if didSend {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if shouldScrollAfterSend {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    NotificationCenter.default.post(name: Notification.Name("ForceScrollToBottom"), object: nil)
                }
            }
        }
    }

    private func blockUser() async {
        guard let userId = session.currentUserId else { return }
        let didBlock = await safetyVM.blockUser(
            blockerUserId: userId,
            blockedUserId: row.otherUserId(for: userId),
            matchId: row.match.id
        )

        if didBlock {
            vm.isBlocked = true
            vm.actionMessage = safetyVM.successMessage
        } else {
            vm.errorMessage = safetyVM.errorMessage
        }
    }


} // END ChatThreadView

private enum ChatCompatibilityInsightKind: String, Identifiable {
    case zodiac
    case mbti

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .zodiac:
            return "sparkles"
        case .mbti:
            return "brain.head.profile"
        }
    }

    var title: String {
        switch self {
        case .zodiac:
            return AppLanguageManager.localized("chat.compatibility.zodiac.title")
        case .mbti:
            return AppLanguageManager.localized("chat.compatibility.mbti.title")
        }
    }
}

private struct ChatCompatibilityInsight: Identifiable, Equatable {
    let id: String
    let kind: ChatCompatibilityInsightKind
    let pairingTitle: String
    let summary: String
    let overview: String
    let strengths: [String]
    let challenges: [String]
    let communication: String
    let outlook: String

    static func zodiac(current: ChatZodiacSign, other: ChatZodiacSign) -> ChatCompatibilityInsight {
        let pairing = "\(current.displayName) × \(other.displayName)"
        return ChatCompatibilityInsight(
            id: "zodiac-\(current.rawValue)-\(other.rawValue)",
            kind: .zodiac,
            pairingTitle: pairing,
            summary: zodiacSummary(current: current, other: other),
            overview: AppLanguageManager.localized("chat.compatibility.zodiac.overview"),
            strengths: zodiacStrengths(current: current, other: other),
            challenges: zodiacChallenges(current: current, other: other),
            communication: AppLanguageManager.localized("chat.compatibility.zodiac.communication"),
            outlook: AppLanguageManager.localized("chat.compatibility.shared.outlook")
        )
    }

    static func mbti(current: String, other: String) -> ChatCompatibilityInsight {
        let pairing = "\(current) × \(other)"
        return ChatCompatibilityInsight(
            id: "mbti-\(current)-\(other)",
            kind: .mbti,
            pairingTitle: pairing,
            summary: mbtiSummary(current: current, other: other),
            overview: AppLanguageManager.localized("chat.compatibility.mbti.overview"),
            strengths: mbtiStrengths(current: current, other: other),
            challenges: mbtiChallenges(current: current, other: other),
            communication: AppLanguageManager.localized("chat.compatibility.mbti.communication"),
            outlook: AppLanguageManager.localized("chat.compatibility.mbti.outlook")
        )
    }

    private static func zodiacSummary(current: ChatZodiacSign, other: ChatZodiacSign) -> String {
        if current.element == other.element {
            return AppLanguageManager.localized("chat.compatibility.zodiac.summary.sameElement")
        }

        if current.element.isComplementary(with: other.element) {
            return AppLanguageManager.localized("chat.compatibility.zodiac.summary.complementary")
        }

        return AppLanguageManager.localized("chat.compatibility.zodiac.summary.contrast")
    }

    private static func zodiacStrengths(current: ChatZodiacSign, other: ChatZodiacSign) -> [String] {
        if current.element == other.element {
            return [
                AppLanguageManager.localized("chat.compatibility.zodiac.strength.same.1"),
                AppLanguageManager.localized("chat.compatibility.zodiac.strength.same.2"),
                AppLanguageManager.localized("chat.compatibility.zodiac.strength.same.3")
            ]
        }

        if current.element.isComplementary(with: other.element) {
            return [
                AppLanguageManager.localized("chat.compatibility.zodiac.strength.complementary.1"),
                AppLanguageManager.localized("chat.compatibility.zodiac.strength.complementary.2"),
                AppLanguageManager.localized("chat.compatibility.zodiac.strength.complementary.3")
            ]
        }

        return [
            AppLanguageManager.localized("chat.compatibility.zodiac.strength.contrast.1"),
            AppLanguageManager.localized("chat.compatibility.zodiac.strength.contrast.2"),
            AppLanguageManager.localized("chat.compatibility.zodiac.strength.contrast.3")
        ]
    }

    private static func zodiacChallenges(current: ChatZodiacSign, other: ChatZodiacSign) -> [String] {
        if current.element == other.element {
            return [
                AppLanguageManager.localized("chat.compatibility.zodiac.challenge.same.1"),
                AppLanguageManager.localized("chat.compatibility.zodiac.challenge.same.2")
            ]
        }

        if current.element.isComplementary(with: other.element) {
            return [
                AppLanguageManager.localized("chat.compatibility.zodiac.challenge.complementary.1"),
                AppLanguageManager.localized("chat.compatibility.zodiac.challenge.complementary.2")
            ]
        }

        return [
            AppLanguageManager.localized("chat.compatibility.zodiac.challenge.contrast.1"),
            AppLanguageManager.localized("chat.compatibility.zodiac.challenge.contrast.2")
        ]
    }

    private static func mbtiSummary(current: String, other: String) -> String {
        let sharedLetters = zip(current, other).filter { $0 == $1 }.count

        switch sharedLetters {
        case 3...4:
            return AppLanguageManager.localized("chat.compatibility.mbti.summary.similar")
        case 2:
            return AppLanguageManager.localized("chat.compatibility.mbti.summary.balanced")
        default:
            return AppLanguageManager.localized("chat.compatibility.mbti.summary.contrast")
        }
    }

    private static func mbtiStrengths(current: String, other: String) -> [String] {
        let sharedLetters = zip(current, other).filter { $0 == $1 }.count

        switch sharedLetters {
        case 3...4:
            return [
                AppLanguageManager.localized("chat.compatibility.mbti.strength.similar.1"),
                AppLanguageManager.localized("chat.compatibility.mbti.strength.similar.2"),
                AppLanguageManager.localized("chat.compatibility.mbti.strength.similar.3")
            ]
        case 2:
            return [
                AppLanguageManager.localized("chat.compatibility.mbti.strength.balanced.1"),
                AppLanguageManager.localized("chat.compatibility.mbti.strength.balanced.2"),
                AppLanguageManager.localized("chat.compatibility.mbti.strength.balanced.3")
            ]
        default:
            return [
                AppLanguageManager.localized("chat.compatibility.mbti.strength.contrast.1"),
                AppLanguageManager.localized("chat.compatibility.mbti.strength.contrast.2"),
                AppLanguageManager.localized("chat.compatibility.mbti.strength.contrast.3")
            ]
        }
    }

    private static func mbtiChallenges(current: String, other: String) -> [String] {
        let sharedLetters = zip(current, other).filter { $0 == $1 }.count

        switch sharedLetters {
        case 3...4:
            return [
                AppLanguageManager.localized("chat.compatibility.mbti.challenge.similar.1"),
                AppLanguageManager.localized("chat.compatibility.mbti.challenge.similar.2")
            ]
        case 2:
            return [
                AppLanguageManager.localized("chat.compatibility.mbti.challenge.balanced.1"),
                AppLanguageManager.localized("chat.compatibility.mbti.challenge.balanced.2")
            ]
        default:
            return [
                AppLanguageManager.localized("chat.compatibility.mbti.challenge.contrast.1"),
                AppLanguageManager.localized("chat.compatibility.mbti.challenge.contrast.2")
            ]
        }
    }
}

private enum ChatZodiacElement {
    case fire
    case earth
    case air
    case water

    func isComplementary(with other: ChatZodiacElement) -> Bool {
        switch (self, other) {
        case (.fire, .air), (.air, .fire), (.earth, .water), (.water, .earth):
            return true
        default:
            return false
        }
    }
}

private enum ChatZodiacSign: String {
    case aries
    case taurus
    case gemini
    case cancer
    case leo
    case virgo
    case libra
    case scorpio
    case sagittarius
    case capricorn
    case aquarius
    case pisces

    init?(month: Int, day: Int) {
        switch (month, day) {
        case (3, 21...31), (4, 1...19): self = .aries
        case (4, 20...30), (5, 1...20): self = .taurus
        case (5, 21...31), (6, 1...20): self = .gemini
        case (6, 21...30), (7, 1...22): self = .cancer
        case (7, 23...31), (8, 1...22): self = .leo
        case (8, 23...31), (9, 1...22): self = .virgo
        case (9, 23...30), (10, 1...22): self = .libra
        case (10, 23...31), (11, 1...21): self = .scorpio
        case (11, 22...30), (12, 1...21): self = .sagittarius
        case (12, 22...31), (1, 1...19): self = .capricorn
        case (1, 20...31), (2, 1...18): self = .aquarius
        case (2, 19...29), (3, 1...20): self = .pisces
        default: return nil
        }
    }

    var displayName: String {
        switch self {
        case .aries: return AppLanguageManager.localized("zodiac.aries")
        case .taurus: return AppLanguageManager.localized("zodiac.taurus")
        case .gemini: return AppLanguageManager.localized("zodiac.gemini")
        case .cancer: return AppLanguageManager.localized("zodiac.cancer")
        case .leo: return AppLanguageManager.localized("zodiac.leo")
        case .virgo: return AppLanguageManager.localized("zodiac.virgo")
        case .libra: return AppLanguageManager.localized("zodiac.libra")
        case .scorpio: return AppLanguageManager.localized("zodiac.scorpio")
        case .sagittarius: return AppLanguageManager.localized("zodiac.sagittarius")
        case .capricorn: return AppLanguageManager.localized("zodiac.capricorn")
        case .aquarius: return AppLanguageManager.localized("zodiac.aquarius")
        case .pisces: return AppLanguageManager.localized("zodiac.pisces")
        }
    }

    var element: ChatZodiacElement {
        switch self {
        case .aries, .leo, .sagittarius:
            return .fire
        case .taurus, .virgo, .capricorn:
            return .earth
        case .gemini, .libra, .aquarius:
            return .air
        case .cancer, .scorpio, .pisces:
            return .water
        }
    }
}

private struct ChatCompatibilityInsightCard: View {
    let insight: ChatCompatibilityInsight
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: insight.kind.iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.10), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(insight.pairingTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(insight.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(AppLanguageManager.localized("chat.compatibility.tapToKnowMore"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 6)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.05), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
    }
}

private struct ChatCompatibilityInsightDetailSheet: View {
    let insight: ChatCompatibilityInsight

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                insightSection(title: AppLanguageManager.localized("chat.compatibility.section.overview"), text: insight.overview)
                insightListSection(title: AppLanguageManager.localized("chat.compatibility.section.strengths"), items: insight.strengths, systemImage: "checkmark.circle.fill")
                insightListSection(title: AppLanguageManager.localized("chat.compatibility.section.challenges"), items: insight.challenges, systemImage: "exclamationmark.circle.fill")
                insightSection(title: AppLanguageManager.localized("chat.compatibility.section.communication"), text: insight.communication)
                insightSection(title: AppLanguageManager.localized("chat.compatibility.section.outlook"), text: insight.outlook)
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: insight.kind.iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 42, height: 42)
                    .background(Color.accentColor.opacity(0.10), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(insight.kind.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(insight.pairingTitle)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                }
            }

            Text(insight.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func insightSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline.weight(.semibold))

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func insightListSection(title: String, items: [String], systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Label(item, systemImage: systemImage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct PendingChatAttachment: Identifiable, Equatable {
    let id = UUID()
    let data: Data
    let fileName: String
    let contentType: String
    let kind: String

    var chatAttachmentFile: ChatAttachmentFile {
        ChatAttachmentFile(
            data: data,
            fileName: fileName,
            contentType: contentType,
            kind: kind
        )
    }

    var isImage: Bool {
        kind == "image" || contentType.hasPrefix("image/")
    }

    var isVideo: Bool {
        kind == "video" || contentType.hasPrefix("video/")
    }

    var previewImage: UIImage? {
        guard isImage else { return nil }
        return UIImage(data: data)
    }
}

private struct PendingAttachmentTile: View {
    let attachment: PendingChatAttachment
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            attachmentPreview
                .frame(width: 74, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
                }

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Circle())
            }
            .offset(x: 6, y: -6)
        }
        .frame(width: 82, height: 82)
    }

    @ViewBuilder
    private var attachmentPreview: some View {
        if let image = attachment.previewImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if attachment.isVideo {
            ZStack {
                Color.secondary.opacity(0.12)

                VStack(spacing: 6) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.title3)

                    Text("chat_video_message")
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "doc.fill")
                    .font(.title3)

                Text(attachment.fileName)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.secondary.opacity(0.10))
        }
    }
}

private struct VoiceRecording: Equatable {
    let url: URL
    let duration: TimeInterval
}

@MainActor
private final class VoiceMessageRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var elapsedTime: TimeInterval = 0
    @Published var levels: [CGFloat] = Array(repeating: 0.18, count: 28)

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var startedAt: Date?
    private var meterTask: Task<Void, Never>?

    func startRecording() async throws {
        guard !isRecording else { return }
        guard await requestMicrophonePermission() else {
            throw NSError(
                domain: "VoiceMessageRecorder",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: AppLanguageManager.localized("chat_microphone_permission_required")]
            )
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("veridate-voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        recorder.record()

        self.recorder = recorder
        recordingURL = url
        startedAt = Date()
        elapsedTime = 0
        levels = Array(repeating: 0.18, count: 28)
        isRecording = true
        startMetering()
    }

    func stopRecording() throws -> VoiceRecording {
        guard let recorder, let recordingURL, let startedAt else {
            throw NSError(
                domain: "VoiceMessageRecorder",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: AppLanguageManager.localized("chat_no_active_recording_found")]
            )
        }

        meterTask?.cancel()
        recorder.stop()
        self.recorder = nil
        self.recordingURL = nil
        self.startedAt = nil
        isRecording = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return VoiceRecording(url: recordingURL, duration: Date().timeIntervalSince(startedAt))
    }

    func cancelRecording() {
        meterTask?.cancel()
        recorder?.stop()
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recorder = nil
        recordingURL = nil
        startedAt = nil
        elapsedTime = 0
        levels = Array(repeating: 0.18, count: 28)
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startMetering() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                guard let self, let recorder = self.recorder, let startedAt = self.startedAt else { continue }
                recorder.updateMeters()
                let power = recorder.averagePower(forChannel: 0)
                let normalized = max(0.12, min(1, CGFloat((power + 55) / 55)))
                self.levels.append(normalized)
                if self.levels.count > 28 {
                    self.levels.removeFirst()
                }
                self.elapsedTime = Date().timeIntervalSince(startedAt)
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }
}

private struct VoiceRecordButton: View {
    let isRecording: Bool
    let isDisabled: Bool
    let onStart: () async -> Void
    let onFinish: () -> Void
    let onCancel: () -> Void

    @State private var hasStarted = false
    @State private var isStarting = false
    @State private var shouldCancelAfterStart = false

    var body: some View {
        ZStack {
            Circle()
                .fill(isRecording ? Color.red : Color.accentColor)
                .frame(width: 38, height: 38)
                .shadow(color: (isRecording ? Color.red : Color.accentColor).opacity(isRecording ? 0.35 : 0), radius: 10)

            Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
        }
        .scaleEffect(isRecording ? 1.08 : 1)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !hasStarted, !isDisabled else { return }
                    hasStarted = true
                    isStarting = true
                    Task {
                        await onStart()
                        isStarting = false
                        if !hasStarted {
                            if shouldCancelAfterStart {
                                shouldCancelAfterStart = false
                                onCancel()
                            } else {
                                onFinish()
                            }
                        }
                    }
                }
                .onEnded { value in
                    guard hasStarted else { return }
                    hasStarted = false

                    if value.translation.height < -70 {
                        if isStarting {
                            shouldCancelAfterStart = true
                            return
                        }
                        onCancel()
                    } else {
                        guard !isStarting else { return }
                        onFinish()
                    }
                }
        )
        .accessibilityLabel(isRecording ? AppLanguageManager.localized("chat_release_to_send_voice_accessibility") : AppLanguageManager.localized("chat_hold_to_record_accessibility"))
    }
}

private struct VoiceRecordingPreview: View {
    let duration: TimeInterval
    let levels: [CGFloat]

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.red)

            VoiceWaveformView(levels: levels, tint: .red.opacity(0.85))
                .frame(height: 28)

            Text(formatted(duration))
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.red.opacity(0.15), lineWidth: 1)
        }
    }

    private func formatted(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value.rounded(.down)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct VoiceWaveformView: View {
    let levels: [CGFloat]
    let tint: Color
    var progress: Double = 1
    var inactiveTint: Color?

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                Capsule()
                    .fill(color(for: index))
                    .frame(width: 3, height: max(5, 26 * min(max(level, 0.1), 1)))
                    .animation(.easeInOut(duration: 0.16), value: progress)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func color(for index: Int) -> Color {
        guard let inactiveTint else { return tint }
        guard levels.count > 1 else { return tint }

        let playedIndex = Int((Double(levels.count - 1) * progress).rounded(.down))
        return index <= playedIndex ? tint : inactiveTint
    }
}

private struct ChatVoiceAttachmentBubble: View {
    let url: URL
    let isMine: Bool

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var progress: Double = 0
    @State private var playbackTask: Task<Void, Never>?
    @State private var suppressPlaybackTapUntil: Date?
    @State private var waveformLevels: [CGFloat] = defaultVoiceWaveformLevels

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isMine ? Color.accentColor : .white)
                .frame(width: 32, height: 32)
                .background(isMine ? Color.white : Color.accentColor)
                .clipShape(Circle())
                .contentShape(Circle())
                .onTapGesture {
                    guard canOpenAfterPress(suppressPlaybackTapUntil) else { return }
                    togglePlayback()
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.30)
                        .onEnded { _ in
                            suppressPlaybackTapUntil = Date().addingTimeInterval(0.7)
                        }
                )

            VStack(alignment: .leading, spacing: 5) {
                VoiceWaveformView(
                    levels: waveformLevels,
                    tint: isMine ? Color.white.opacity(0.92) : Color.accentColor.opacity(0.92),
                    progress: progress,
                    inactiveTint: isMine ? Color.white.opacity(0.28) : Color.secondary.opacity(0.26)
                )
                .frame(height: 24)

                Text(isPlaying ? AppLanguageManager.localized("chat_voice_playing") : AppLanguageManager.localized("chat_voice_message"))
                    .font(.caption2)
                    .foregroundStyle(isMine ? Color.white.opacity(0.75) : Color.secondary)
            }
        }
        .frame(width: 220, alignment: .leading)
        .onDisappear {
            stopPlayback()
        }
        .task(id: url) {
            waveformLevels = await makeAudioWaveformLevels(from: url)
        }
    }

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
            return
        }

        let player = AVPlayer(url: url)
        self.player = player
        isPlaying = true
        player.play()
        startProgressUpdates(for: player)
    }

    private func stopPlayback() {
        playbackTask?.cancel()
        player?.pause()
        player = nil
        isPlaying = false
        progress = 0
    }

    private func startProgressUpdates(for player: AVPlayer) {
        playbackTask?.cancel()
        playbackTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(120))
                let duration = player.currentItem?.duration.seconds ?? 0
                let current = player.currentTime().seconds

                guard duration.isFinite, duration > 0 else { continue }
                progress = min(max(current / duration, 0), 1)

                if current >= duration {
                    stopPlayback()
                    return
                }
            }
        }
    }

    private func canOpenAfterPress(_ date: Date?) -> Bool {
        guard let date else { return true }
        return Date() >= date
    }
}

private let defaultVoiceWaveformLevels: [CGFloat] = [
    0.25, 0.55, 0.35, 0.76, 0.48, 0.9, 0.42, 0.62,
    0.3, 0.82, 0.52, 0.68, 0.36, 0.58, 0.28, 0.74,
    0.46, 0.88, 0.34, 0.6, 0.4, 0.7, 0.3, 0.52,
    0.38, 0.66, 0.44, 0.8, 0.32, 0.54, 0.28, 0.5
]

private func makeAudioWaveformLevels(from url: URL, sampleCount: Int = 32) async -> [CGFloat] {
    do {
        let localURL: URL
        if url.isFileURL {
            localURL = url
        } else {
            let (downloadedURL, _) = try await URLSession.shared.download(from: url)
            localURL = downloadedURL
        }

        let file = try AVAudioFile(forReading: localURL)
        let frameLength = min(file.length, AVAudioFramePosition(44_100 * 60 * 5))
        guard frameLength > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(frameLength)
              ) else {
            return defaultVoiceWaveformLevels
        }

        try file.read(into: buffer, frameCount: AVAudioFrameCount(frameLength))
        guard let channelData = buffer.floatChannelData else {
            return defaultVoiceWaveformLevels
        }

        let frames = Int(buffer.frameLength)
        let channels = Int(file.processingFormat.channelCount)
        guard frames > 0, channels > 0 else {
            return defaultVoiceWaveformLevels
        }

        let framesPerSample = max(1, frames / sampleCount)
        var levels: [CGFloat] = []
        levels.reserveCapacity(sampleCount)

        for sampleIndex in 0..<sampleCount {
            let start = sampleIndex * framesPerSample
            let end = sampleIndex == sampleCount - 1 ? frames : min(frames, start + framesPerSample)
            guard start < end else {
                levels.append(0.12)
                continue
            }

            var total: Float = 0
            var count: Float = 0

            for frame in start..<end {
                var framePeak: Float = 0
                for channel in 0..<channels {
                    framePeak = max(framePeak, abs(channelData[channel][frame]))
                }
                total += framePeak
                count += 1
            }

            levels.append(CGFloat(total / max(count, 1)))
        }

        let peak = max(levels.max() ?? 0, 0.001)
        return levels.map { level in
            let normalized = pow(Double(level / peak), 0.72)
            return CGFloat(min(1, max(0.12, 0.14 + normalized * 0.86)))
        }
    } catch {
        return defaultVoiceWaveformLevels
    }
}

private struct VoiceBubblePlaceholder: View {
    let title: String
    let isMine: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.headline)

            Text(title)
                .font(.caption)
        }
        .foregroundStyle(isMine ? Color.white.opacity(0.85) : Color.secondary)
        .padding(10)
        .frame(width: 220, alignment: .leading)
        .background(isMine ? Color.white.opacity(0.14) : Color.secondary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

private struct ChatVideoAttachmentThumbnail: View {
    let url: URL
    let isMine: Bool
    let size: CGSize

    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack {
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(isMine ? 0.18 : 0.08))
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()

            Image(systemName: "play.circle.fill")
                .font(.system(size: 50, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 2)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(isMine ? 0.10 : 0.06), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppLanguageManager.localized("chat_video_message"))
        .accessibilityHint(AppLanguageManager.localized("chat_open_attachment_hint"))
        .task(id: url) {
            thumbnail = try? await makeVideoThumbnail(from: url)
        }
    }
}


private struct ChatHeader: View {
    let profile: Profile
    let isTyping: Bool
    let isPresent: Bool

    @State private var signedPhotoURL: URL?
    @State private var delayedTyping = false
    @State private var typingDotCount = 1

    var body: some View {
        HStack(spacing: 7) {
            avatar

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(publicDisplayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Circle()
                        .fill(isPresent ? .green : .secondary.opacity(0.45))
                        .frame(width: 6, height: 6)
                }

                ZStack(alignment: .leading) {
                    Text(presenceText)
                        .opacity(delayedTyping ? 0 : 1)

                    Text(String.localizedStringWithFormat(AppLanguageManager.localized("chat_typing_format"), typingDots))
                        .opacity(delayedTyping ? 1 : 0)
                        .foregroundStyle(Color.accentColor)
                }
                .font(.caption2)
                .lineLimit(1)
                .animation(.easeInOut(duration: 0.25), value: delayedTyping)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .task(id: profile.profilePhotoURL) {
            await loadSignedPhotoURL()
        }
        .onChange(of: isTyping) { _, newValue in
            if newValue {
                Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    if isTyping {
                        delayedTyping = true
                    }
                }
            } else {
                delayedTyping = false
                typingDotCount = 1
            }
        }
        .task(id: delayedTyping) {
            guard delayedTyping else { return }

            while !Task.isCancelled && delayedTyping {
                try? await Task.sleep(for: .milliseconds(420))
                typingDotCount = typingDotCount == 3 ? 1 : typingDotCount + 1
            }
        }
    }

    private var publicDisplayName: String {
        let trimmed = profile.publicName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? AppLanguageManager.localized("chat_default_title") : trimmed
    }

    private var avatar: some View {
        Group {
            if let signedPhotoURL {
                AsyncImage(url: signedPhotoURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        avatarPlaceholder
                    }
                }
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        }
    }

    private var avatarPlaceholder: some View {
        ZStack {
            Circle()
                .fill(Color.secondary.opacity(0.12))

            Image(systemName: "person.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func loadSignedPhotoURL() async {
        signedPhotoURL = nil
        guard let path = profile.profilePhotoURL, !path.isEmpty else { return }

        do {
            signedPhotoURL = try await ProfilePhotoService.shared.signedURL(for: path)
        } catch {
            signedPhotoURL = nil
        }
    }

    private var typingDots: String {
        String(repeating: ".", count: typingDotCount)
    }

    private var presenceText: String {
        if isPresent {
            return AppLanguageManager.localized("chat_presence_online")
        }

        guard let lastSeenAt = profile.lastSeenAt, let date = parseDate(lastSeenAt) else {
            return AppLanguageManager.localized("chat_presence_offline")
        }

        return String.localizedStringWithFormat(
            AppLanguageManager.localized("chat_presence_last_seen_format"),
            date.formatted(.relative(presentation: .named))
        )
    }


    private func parseDate(_ value: String) -> Date? {
        sharedISOFormatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private enum ChatMessageAction: Hashable {
    case reply
    case react
    case copy
    case edit
    case delete
}

private struct ChatMessageActionMenuModifier: ViewModifier {
    let message: Message
    let onLongPress: (Message) -> Void

    func body(content: Content) -> some View {
        if message.canShowActionMenu {
            content
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.35)
                        .onEnded { _ in
                            onLongPress(message)
                        }
                )
        } else {
            content
        }
    }
}

private extension View {
    func messageActionMenu(
        message: Message,
        onLongPress: @escaping (Message) -> Void
    ) -> some View {
        modifier(
            ChatMessageActionMenuModifier(
                message: message,
                onLongPress: onLongPress
            )
        )
    }
}

private struct ChatBubbleActionMenu: View {
    let message: Message
    let isMine: Bool
    let onAction: (ChatMessageAction) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(message.allowedActions(isMine: isMine), id: \.self) { action in
                actionButton(
                    action,
                    title: action.title,
                    systemImage: action.systemImage,
                    isDestructive: action == .delete
                )
            }
        }
        .padding(6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 7)
    }

    private func actionButton(
        _ action: ChatMessageAction,
        title: String,
        systemImage: String,
        isDestructive: Bool = false
    ) -> some View {
        Button {
            onAction(action)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))

                Text(title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isDestructive ? Color.red : Color.primary)
            .frame(width: 52, height: 42)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private extension ChatMessageAction {
    var title: String {
        switch self {
        case .reply:
            return AppLanguageManager.localized("chat_action_reply")
        case .react:
            return AppLanguageManager.localized("chat_action_react")
        case .copy:
            return AppLanguageManager.localized("chat_action_copy")
        case .edit:
            return AppLanguageManager.localized("chat_action_edit")
        case .delete:
            return AppLanguageManager.localized("chat_action_delete")
        }
    }

    var systemImage: String {
        switch self {
        case .reply:
            return "arrowshape.turn.up.left"
        case .react:
            return "face.smiling"
        case .copy:
            return "doc.on.doc"
        case .edit:
            return "pencil"
        case .delete:
            return "trash"
        }
    }
}

private struct ChatEmojiReactionPicker: View {
    private let emojis = ["👍", "❤️", "😂", "😮", "😢", "🙏"]
    let onSelect: (String) -> Void
    let onMore: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(emojis, id: \.self) { emoji in
                Button {
                    onSelect(emoji)
                } label: {
                    Text(emoji)
                        .font(.system(size: 24))
                        .frame(width: 38, height: 38)
                        .background(Color.secondary.opacity(0.001))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String.localizedStringWithFormat(AppLanguageManager.localized("chat_react_with_emoji_format"), emoji))
            }

            Button {
                onMore()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLanguageManager.localized("chat_more_reactions"))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Color(.systemBackground).opacity(0.97))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.16), radius: 18, x: 0, y: 8)
    }
}

private struct AttachmentSourcePopup: View {
    @Environment(\.dismiss) private var dismiss
    let onPhotos: () -> Void
    let onCamera: () -> Void
    let onFiles: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(AppLanguageManager.localized("chat_attach_title"))
                        .font(.headline)

                    Text(AppLanguageManager.localized("chat_attach_subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color.secondary.opacity(0.10))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLanguageManager.localized("common_close"))
            }

            VStack(spacing: 8) {
                sourceButton(
                    title: AppLanguageManager.localized("chat_attach_photos_title"),
                    subtitle: AppLanguageManager.localized("chat_attach_photos_subtitle"),
                    systemImage: "photo.on.rectangle.angled",
                    tint: .pink,
                    action: onPhotos
                )

                sourceButton(
                    title: AppLanguageManager.localized("chat_attach_camera_title"),
                    subtitle: AppLanguageManager.localized("chat_attach_camera_subtitle"),
                    systemImage: "camera.fill",
                    tint: .blue,
                    action: onCamera
                )

                sourceButton(
                    title: AppLanguageManager.localized("chat_attach_files_title"),
                    subtitle: AppLanguageManager.localized("chat_attach_files_subtitle"),
                    systemImage: "folder.fill",
                    tint: .orange,
                    action: onFiles
                )
            }
        }
        .padding(14)
        .frame(width: 305)
    }

    private func sourceButton(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 13) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.13))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}

private struct CustomEmojiReactionSheet: View {
    private let emojis = [
        "😀", "😃", "😄", "😁", "😆", "😅", "😂", "🤣",
        "🥲", "☺️", "😊", "😇", "🙂", "🙃", "😉", "😌",
        "😍", "🥰", "😘", "😗", "😙", "😚", "😋", "😛",
        "😝", "😜", "🤪", "🤨", "🧐", "🤓", "😎", "🥸",
        "🤩", "🥳", "🙂‍↕️", "😏", "😒", "🙂‍↔️", "😞", "😔",
        "😟", "😕", "🙁", "☹️", "😣", "😖", "😫", "😩",
        "🥺", "😢", "😭", "😤", "😠", "😡", "🤬", "🤯",
        "😳", "🥵", "🥶", "😱", "😨", "😰", "😥", "😓",
        "🫣", "🤗", "🫡", "🤔", "🫢", "🤭", "🤫", "🤥",
        "😶", "😐", "😑", "😬", "🫨", "🙄", "😯", "😦",
        "😧", "😮", "😲", "🥱", "😴", "🤤", "😪", "😵",
        "🤐", "🥴", "🤢", "🤮", "🤧", "😷", "🤒", "🤕",
        "🤑", "🤠", "😈", "👿", "💀", "☠️", "💩", "🤡",
        "👻", "👽", "🤖", "🎃", "😺", "😸", "😹", "😻",
        "😼", "😽", "🙀", "😿", "😾", "🙈", "🙉", "🙊",
        "💌", "💘", "💝", "💖", "💗", "💓", "💞", "💕",
        "💟", "❣️", "💔", "❤️‍🔥", "❤️‍🩹", "❤️", "🩷", "🧡",
        "💛", "💚", "💙", "🩵", "💜", "🤎", "🖤", "🩶",
        "🤍", "💋", "💯", "💢", "💥", "💫", "💦", "💨",
        "🕳️", "💬", "👋", "🤚", "🖐️", "✋", "🖖", "👌",
        "🤌", "🤏", "✌️", "🤞", "🫰", "🤟", "🤘", "🤙",
        "👈", "👉", "👆", "👇", "☝️", "🫵", "👍", "👎",
        "✊", "👊", "🤛", "🤜", "👏", "🙌", "🫶", "👐",
        "🤲", "🤝", "🙏", "✍️", "💅", "🤳", "💪", "🦾",
        "🦵", "🦶", "👂", "👃", "🧠", "🫀", "🫁", "🦷",
        "👀", "👁️", "👅", "👄", "🫦", "👶", "🧒", "👦",
        "👧", "🧑", "👩", "👨", "🙋", "🙆", "🙅", "🤷",
        "🤦", "🙇", "🧏", "💁", "🙍", "🙎", "🧘", "🏃",
        "🚶", "💃", "🕺", "👯", "🧑‍🤝‍🧑", "👫", "👬", "👭",
        "💑", "💏", "🌹", "🌷", "🌺", "🌸", "🌼", "🌻",
        "🌞", "🌝", "🌙", "⭐", "🌟", "✨", "⚡", "🔥",
        "🌈", "☀️", "⛅", "🌧️", "☔", "❄️", "💧", "🌊",
        "🍏", "🍎", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓",
        "🫐", "🍒", "🍑", "🥭", "🍍", "🥥", "🥝", "🍅",
        "🥑", "🍔", "🍟", "🍕", "🌭", "🥪", "🌮", "🌯",
        "🥗", "🍝", "🍜", "🍣", "🍱", "🍛", "🍲", "🥘",
        "🍰", "🎂", "🧁", "🍫", "🍿", "☕", "🧋", "🍺",
        "🍻", "🥂", "🍷", "🍸", "🍹", "🎁", "🎈", "🎉",
        "🎊", "🎀", "🏆", "🥇", "🎵", "🎶", "🎤", "🎧",
        "📸", "🎬", "🎮", "🎲", "♟️", "⚽", "🏀", "🏈",
        "⚾", "🎾", "🏐", "🏸", "🥊", "🏋️", "🚗", "✈️",
        "🏠", "🏝️", "⛰️", "💎", "💡", "📌", "📍", "📎",
        "🔒", "🔑", "🛍️", "🧸", "💊", "🩹", "🪩", "🪄",
        "✅", "☑️", "✔️", "❌", "❎", "⚠️", "🚫", "❓",
        "❗", "‼️", "⁉️", "🔴", "🟠", "🟡", "🟢", "🔵",
        "🟣", "⚫", "⚪", "🔔", "🔕", "📣", "🔁", "🔂"
    ]

    let onCancel: () -> Void
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(Color.secondary.opacity(0.25))
                .frame(width: 36, height: 4)

            HStack {
                Text(AppLanguageManager.localized("chat_choose_reaction_title"))
                    .font(.headline)

                Spacer()

                Button(AppLanguageManager.localized("common_cancel")) { onCancel() }
                    .font(.subheadline.weight(.medium))
            }

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 10) {
                    ForEach(emojis, id: \.self) { emoji in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onSelect(emoji)
                        } label: {
                            Text(emoji)
                                .font(.system(size: 28))
                                .frame(width: 36, height: 36)
                                .background(Color.secondary.opacity(0.08))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String.localizedStringWithFormat(AppLanguageManager.localized("chat_react_with_emoji_format"), emoji))
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
    }
}

private struct ChatReplyPreview: View {
    let message: Message
    let isMine: Bool
    let onTap: (UUID) -> Void

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(isMine ? Color.white.opacity(0.75) : Color.accentColor)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 1) {
                Text(AppLanguageManager.localized("chat_reply_label"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isMine ? Color.white.opacity(0.82) : Color.accentColor)

                Text(compactPreviewText)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(isMine ? Color.white.opacity(0.78) : Color.secondary)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .fixedSize(horizontal: false, vertical: true)
        .background(isMine ? Color.white.opacity(0.12) : Color.secondary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .gesture(
            LongPressGesture(minimumDuration: 0.35)
                .exclusively(before: TapGesture())
                .onEnded { value in
                    if case .second = value {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onTap(message.id)
                    }
                }
        )
    }

    private var compactPreviewText: String {
        let text = message.previewText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 26 else { return text }
        return "\(text.prefix(26))..."
    }
}

private struct ChatReactionSummary: View {
    let reactions: [MessageReaction]
    let isMine: Bool

    var body: some View {
        HStack(spacing: 3) {
            ForEach(groupedReactions, id: \.emoji) { group in
                Text(group.count > 1 ? "\(group.emoji) \(group.count)" : group.emoji)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        }
        .frame(maxWidth: 300, alignment: isMine ? .trailing : .leading)
        .padding(.top, -1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var groupedReactions: [(emoji: String, count: Int)] {
        let groups = Dictionary(grouping: reactions, by: \.emoji)
        return groups
            .map { (emoji: $0.key, count: $0.value.count) }
            .sorted { $0.emoji < $1.emoji }
    }

    private var accessibilityText: String {
        let summary = groupedReactions
            .map { group in
                String.localizedStringWithFormat(AppLanguageManager.localized("chat_reaction_summary_item_format"), group.emoji, group.count)
            }
            .joined(separator: ", ")

        return String.localizedStringWithFormat(AppLanguageManager.localized("chat_reaction_summary_format"), summary)
    }
}

private struct ChatComposerModeBanner: View {
    let title: String
    let message: String
    let systemImage: String
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(message)
                    .font(.subheadline)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onClear()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLanguageManager.localized("chat_clear_composer_mode"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
    }
}
private enum ChatAttachmentBodyPlaceholder {
    static let photo = "Photo"
    static let video = "Video"
}

private extension Message {
    var canShowActionMenu: Bool {
        deletedAt == nil
    }

    var isVoiceAttachment: Bool {
        if attachmentKind == "audio" {
            return true
        }

        return attachmentContentType?.hasPrefix("audio/") == true
    }

    var hasDownloadableAttachment: Bool {
        attachmentFilePath != nil && !isVoiceAttachment
    }

    var captionText: String {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard attachmentFilePath != nil else { return trimmedBody }

        if attachmentKind == "image", trimmedBody == ChatAttachmentBodyPlaceholder.photo {
            return ""
        }

        if attachmentKind == "video", trimmedBody == ChatAttachmentBodyPlaceholder.video {
            return ""
        }

        if trimmedBody == attachmentFileName {
            return ""
        }

        return trimmedBody
    }

    func allowedActions(isMine: Bool) -> [ChatMessageAction] {
        guard canShowActionMenu else { return [] }

        if isVoiceAttachment {
            return isMine ? [.reply, .react, .delete] : [.reply, .react]
        }

        if hasDownloadableAttachment {
            return isMine ? [.reply, .react, .edit, .delete] : [.reply, .react]
        }

        if isMine {
            return [.reply, .react, .copy, .edit, .delete]
        }

        return [.reply, .react, .copy]
    }

    var copyText: String {
        if deletedAt != nil {
            return AppLanguageManager.localized("chat_message_deleted")
        }

        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBody.isEmpty,
           trimmedBody != ChatAttachmentBodyPlaceholder.photo,
           trimmedBody != ChatAttachmentBodyPlaceholder.video,
           trimmedBody != attachmentFileName {
            return trimmedBody
        }

        if attachmentKind == "audio" {
            return AppLanguageManager.localized("chat_voice_message")
        }

        if attachmentKind == "video" {
            return AppLanguageManager.localized("chat_video_message")
        }

        if let fileName = attachmentFileName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fileName.isEmpty {
            return fileName
        }

        if attachmentFilePath != nil {
            if attachmentKind == "image" {
                return AppLanguageManager.localized("chat_photo_message")
            }

            if attachmentKind == "audio" {
                return AppLanguageManager.localized("chat_voice_message")
            }

            if attachmentKind == "video" {
                return AppLanguageManager.localized("chat_video_message")
            }

            return AppLanguageManager.localized("chat_attachment_message")
        }

        return trimmedBody
    }

    var previewText: String {
        let text = copyText
        return text.isEmpty ? AppLanguageManager.localized("chat_generic_message") : text
    }
}

private struct ChatItemRowView: View {
    let item: ChatThreadViewModel.ChatItem
    let allMessages: [Message]
    let reactionsByMessageId: [UUID: [MessageReaction]]
    let currentUserId: UUID?
    let pendingMessageIds: Set<UUID>
    let failedMessageIds: Set<UUID>
    let activeActionMessageId: UUID?
    let activeReactionMessageId: UUID?
    let highlightedMessageId: UUID?
    let hasActiveMessageOverlay: Bool
    let shouldShowUnreadSeparator: Bool
    let unreadAnchorMessageId: UUID?
    let lastMessageId: UUID?
    let onAppearLast: () -> Void
    let onDisappearLast: () -> Void
    let onMessageLongPress: (Message) -> Void
    let onMessageAction: (ChatMessageAction, Message) -> Void
    let onSwipeReply: (Message) -> Void
    let onReactionSelected: (String, Message) -> Void
    let onMoreReactions: (Message) -> Void
    let onDismissMessageOverlays: () -> Void
    let onRetry: (Message) -> Void

    var body: some View {
        if case let .date(date) = item {
            return AnyView(DateSeparatorView(date: date))
        }

        if case let .message(message, isGroupedWithPrevious, isGroupedWithNext) = item {
            let shouldShowSeparator = shouldShowUnreadSeparator && message.id == unreadAnchorMessageId
            let isMine = message.senderId == currentUserId
            let isPending = pendingMessageIds.contains(message.id)
            let isFailed = failedMessageIds.contains(message.id)
            let isLastMessage = message.id == lastMessageId

            let content = VStack(spacing: 0) {
                if shouldShowSeparator {
                    UnreadSeparatorView()
                        .blur(radius: activeActionMessageId == nil ? 0 : 1.5)
                        .opacity(activeActionMessageId == nil ? 1 : 0.55)
                }

                MessageRowView(
                    message: message,
                    allMessages: allMessages,
                    reactions: reactionsByMessageId[message.id] ?? [],
                    isMine: isMine,
                    isActionMenuVisible: activeActionMessageId == message.id,
                    isReactionPickerVisible: activeReactionMessageId == message.id,
                    isDimmedByActionMenu: activeActionMessageId != nil && activeActionMessageId != message.id,
                    isHighlighted: highlightedMessageId == message.id,
                    hasActiveMessageOverlay: hasActiveMessageOverlay,
                    isGroupedWithPrevious: isGroupedWithPrevious,
                    isGroupedWithNext: isGroupedWithNext,
                    isPending: isPending,
                    isFailed: isFailed,
                    isLastMessage: isLastMessage,
                    onAppearLast: onAppearLast,
                    onDisappearLast: onDisappearLast,
                    onMessageLongPress: onMessageLongPress,
                    onMessageAction: onMessageAction,
                    onSwipeReply: onSwipeReply,
                    onReactionSelected: onReactionSelected,
                    onMoreReactions: onMoreReactions,
                    onDismissMessageOverlays: onDismissMessageOverlays,
                    onRetry: onRetry
                )
            }

            return AnyView(content)
        }

        return AnyView(EmptyView())
    }
}

private struct MessageBubble: View {
    let message: Message
    let allMessages: [Message]
    let reactions: [MessageReaction]
    let isMine: Bool
    let isActionMenuVisible: Bool
    let isReactionPickerVisible: Bool
    let isDimmedByActionMenu: Bool
    let isHighlighted: Bool
    let hasActiveMessageOverlay: Bool
    let isGroupedWithPrevious: Bool
    let isGroupedWithNext: Bool
    let isPending: Bool
    let isFailed: Bool
    let onMessageLongPress: (Message) -> Void
    let onMessageAction: (ChatMessageAction, Message) -> Void
    let onSwipeReply: (Message) -> Void
    let onReactionSelected: (String, Message) -> Void
    let onMoreReactions: (Message) -> Void
    let onDismissMessageOverlays: () -> Void
    let onRetry: (Message) -> Void

    @GestureState private var dragTranslation: CGSize = .zero
    @State private var shake = false

    var body: some View {
        HStack(alignment: .bottom) {
            if isMine {
                Spacer(minLength: 56)
            }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                if isReactionPickerVisible && message.canShowActionMenu {
                    ChatEmojiReactionPicker(
                        onSelect: { emoji in
                            onReactionSelected(emoji, message)
                        },
                        onMore: {
                            onMoreReactions(message)
                        }
                    )
                    .frame(maxWidth: 300, alignment: isMine ? .trailing : .leading)
                    .transition(
                        .scale(scale: 0.92, anchor: menuTransitionAnchor)
                        .combined(with: .opacity)
                    )
                    .zIndex(1)
                }

                if isActionMenuVisible && message.canShowActionMenu {
                    ChatBubbleActionMenu(message: message, isMine: isMine) { action in
                        onMessageAction(action, message)
                    }
                    .frame(maxWidth: 300, alignment: isMine ? .trailing : .leading)
                    .transition(
                        .scale(scale: 0.92, anchor: menuTransitionAnchor)
                        .combined(with: .opacity)
                    )
                    .zIndex(1)
                }

                VStack(alignment: isMine ? .trailing : .leading, spacing: 8) {
                    if let replyPreview {
                        ChatReplyPreview(
                            message: replyPreview,
                            isMine: isMine,
                            onTap: { messageId in
                                if hasActiveMessageOverlay {
                                    onDismissMessageOverlays()
                                    return
                                }

                                NotificationCenter.default.post(name: .scrollToMessage, object: messageId)
                            }
                        )
                    }

                    if message.deletedAt == nil, message.attachmentFilePath != nil {
                        ChatAttachmentView(message: message, isMine: isMine, galleryMessages: allMessages)
                    }

                    if shouldShowBodyText {
                        Text(message.body)
                            .font(.body)
                            .italic(message.deletedAt != nil)
                            .lineSpacing(2)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundStyle(isMine ? Color.white : Color.primary)
                .background(bubbleBackground)
                .clipShape(bubbleShape)
                .overlay {
                    if isHighlighted {
                        ZStack {
                            bubbleShape
                                .fill(Color.white.opacity(isMine ? 0.16 : 0.34))

                            bubbleShape
                                .stroke(Color.white.opacity(0.92), lineWidth: 2)

                            bubbleShape
                                .stroke(Color.white.opacity(0.48), lineWidth: 1)
                                .padding(3)
                        }
                        .shadow(color: Color.white.opacity(0.72), radius: 18, x: 0, y: 0)
                        .transition(.opacity)
                    }
                }
                .shadow(color: Color.black.opacity(isMine ? 0.08 : 0.04), radius: 2, x: 0, y: 1)
                .frame(maxWidth: 300, alignment: isMine ? .trailing : .leading)
                .messageActionMenu(
                    message: message,
                    onLongPress: onMessageLongPress
                )
                .onTapGesture {
                    if hasActiveMessageOverlay {
                        onDismissMessageOverlays()
                        return
                    }

                    if isFailed {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onRetry(message)
                    }
                }

                if !reactions.isEmpty {
                    ChatReactionSummary(reactions: reactions, isMine: isMine)
                }

                if shouldShowFooter {
                    HStack(spacing: 4) {
                        Text(timeText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if isMine {
                            if isFailed {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                    Text(AppLanguageManager.localized("chat_not_sent_retry"))
                                }
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Color.red)
                                .accessibilityLabel(AppLanguageManager.localized("chat_not_sent_retry_accessibility"))
                            } else {
                                AnimatedMessageStatusTicks(message: message, isPending: isPending)
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 1)
                }
            }
            .padding(.top, isGroupedWithPrevious ? 1 : 7)
            .padding(.bottom, isGroupedWithNext ? 1 : 9)

            if !isMine {
                Spacer(minLength: 56)
            }
        }
        .padding(.horizontal, 2)
        .offset(x: swipeOffset + (shake ? -6 : 0))
        .blur(radius: isDimmedByActionMenu ? 1.8 : 0)
        .opacity(isDimmedByActionMenu ? 0.42 : 1)
        .overlay {
            if isDimmedByActionMenu {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onDismissMessageOverlays()
                    }
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: dragTranslation)
        .animation(.easeInOut(duration: 0.08).repeatCount(3, autoreverses: true), value: shake)
        .animation(.easeInOut(duration: 0.18), value: isDimmedByActionMenu)
        .animation(.easeOut(duration: 0.9), value: isHighlighted)
        .onChange(of: isFailed) { _, newValue in
            if newValue {
                shake = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    shake = false
                }
            }
        }
        .simultaneousGesture(replySwipeGesture)
    }

    private var swipeOffset: CGFloat {
        guard message.canShowActionMenu else { return 0 }
        guard dragTranslation.width < 0 else { return 0 }
        guard abs(dragTranslation.width) > abs(dragTranslation.height) else { return 0 }
        return max(dragTranslation.width * 0.42, -54)
    }

    private var replySwipeGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .updating($dragTranslation) { value, state, _ in
                guard message.canShowActionMenu else { return }
                guard value.translation.width < 0 else { return }
                guard abs(value.translation.width) > abs(value.translation.height) * 1.4 else { return }
                state = value.translation
            }
            .onEnded { value in
                guard message.canShowActionMenu else { return }
                guard value.translation.width < -58 else { return }
                guard abs(value.translation.width) > abs(value.translation.height) * 1.4 else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onSwipeReply(message)
            }
    }

    private var menuTransitionAnchor: UnitPoint {
        isMine ? .bottomTrailing : .bottomLeading
    }

    private var replyPreview: Message? {
        guard let replyToMessageId = message.replyToMessageId else { return nil }
        return allMessages.first { $0.id == replyToMessageId }
    }

    private var shouldShowFooter: Bool {
        !isGroupedWithNext || (message.editedAt != nil && message.deletedAt == nil)
    }

    private var shouldShowBodyText: Bool {
        let body = message.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return false }
        if message.deletedAt != nil { return true }
        guard message.attachmentFilePath != nil else { return true }
        if message.attachmentKind == "audio" { return false }
        if message.attachmentKind == "video" { return false }
        return body != ChatAttachmentBodyPlaceholder.photo && body != ChatAttachmentBodyPlaceholder.video && body != message.attachmentFileName
    }

    private var bubbleBackground: some ShapeStyle {
        if isFailed {
            return AnyShapeStyle(Color.red.opacity(isMine ? 0.22 : 0.10))
        }

        if isMine {
            return AnyShapeStyle(Color.accentColor)
        } else {
            return AnyShapeStyle(Color.secondary.opacity(0.12))
        }
    }

    private var bubbleShape: UnevenRoundedRectangle {
        let large: CGFloat = 20
        let medium: CGFloat = 14
        let small: CGFloat = 7

        if isMine {
            return UnevenRoundedRectangle(
                topLeadingRadius: large,
                bottomLeadingRadius: large,
                bottomTrailingRadius: isGroupedWithNext ? small : medium,
                topTrailingRadius: isGroupedWithPrevious ? small : medium
            )
        } else {
            return UnevenRoundedRectangle(
                topLeadingRadius: isGroupedWithPrevious ? small : medium,
                bottomLeadingRadius: isGroupedWithNext ? small : medium,
                bottomTrailingRadius: large,
                topTrailingRadius: large
            )
        }
    }

    private var timeText: String {
        if message.deletedAt == nil,
           let editedAt = message.editedAt,
           let editedDate = sharedISOFormatter.date(from: editedAt) ?? ISO8601DateFormatter().date(from: editedAt) {
            return String.localizedStringWithFormat(
                AppLanguageManager.localized("chat_edited_time_format"),
                editedDate.formatted(date: .omitted, time: .shortened)
            )
        }

        guard let date = sharedISOFormatter.date(from: message.createdAt) ?? ISO8601DateFormatter().date(from: message.createdAt) else {
            return ""
        }

        return date.formatted(date: .omitted, time: .shortened)
    }

}

private struct ChatAttachmentView: View {
    let message: Message
    let isMine: Bool
    var thumbnailSize = CGSize(width: 220, height: 180)
    var galleryMessages: [Message] = []

    @State private var signedURL: URL?
    @State private var errorMessage: String?
    @State private var galleryPreview: AttachmentGalleryPreviewState?
    @State private var videoPreview: AttachmentVideoPreviewState?
    @State private var filePreviewItem: AttachmentPreviewItem?
    @State private var isPreparingFilePreview = false
    @State private var suppressAttachmentTapUntil: Date?

    var body: some View {
        Group {
            if isAudio {
                voiceAttachment
            } else if isVideo {
                videoAttachment
            } else if isImage {
                imageAttachment
            } else {
                fileAttachment
            }
        }
        .task(id: message.attachmentFilePath) {
            await loadSignedURL()
        }
        .fullScreenCover(item: $galleryPreview) { preview in
            AttachmentImageGalleryPreview(preview: preview)
        }
        .fullScreenCover(item: $videoPreview) { preview in
            AttachmentVideoPreview(preview: preview)
        }
        .sheet(item: $filePreviewItem) { item in
            AttachmentFilePreview(url: item.url)
        }
    }

    @ViewBuilder
    private var voiceAttachment: some View {
        if let signedURL {
            ChatVoiceAttachmentBubble(url: signedURL, isMine: isMine)
        } else {
            VoiceBubblePlaceholder(title: errorMessage ?? AppLanguageManager.localized("chat_loading_voice_message"), isMine: isMine)
        }
    }

    @ViewBuilder
    private var imageAttachment: some View {
        if let signedURL {
            AsyncImage(url: signedURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: thumbnailSize.width, height: thumbnailSize.height)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onTapGesture {
                            guard canOpenAttachmentPreview else { return }
                            Task {
                                await openImageGallery()
                            }
                        }
                        .simultaneousGesture(attachmentLongPressSuppressor)
                        .accessibilityLabel(AppLanguageManager.localized("chat_photo_message"))
                        .accessibilityHint(AppLanguageManager.localized("chat_open_attachment_hint"))
                case .failure:
                    attachmentPlaceholder(title: AppLanguageManager.localized("chat_photo_unavailable"), systemImage: "photo")
                default:
                    attachmentPlaceholder(title: AppLanguageManager.localized("chat_loading_photo"), systemImage: "photo")
                }
            }
        } else {
            attachmentPlaceholder(title: errorMessage ?? AppLanguageManager.localized("chat_loading_photo"), systemImage: "photo")
        }
    }

    @ViewBuilder
    private var videoAttachment: some View {
        if let signedURL {
            ChatVideoAttachmentThumbnail(url: signedURL, isMine: isMine, size: thumbnailSize)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture {
                guard canOpenAttachmentPreview else { return }
                videoPreview = AttachmentVideoPreviewState(url: signedURL, fileName: fileName)
            }
            .simultaneousGesture(attachmentLongPressSuppressor)
        } else {
            attachmentPlaceholder(title: errorMessage ?? AppLanguageManager.localized("chat_loading_video"), systemImage: "video")
        }
    }

    @ViewBuilder
    private var fileAttachment: some View {
        fileLabel
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture {
                guard canOpenAttachmentPreview else { return }
                guard signedURL != nil, !isPreparingFilePreview else { return }
                Task {
                    await openFilePreview()
                }
            }
            .simultaneousGesture(attachmentLongPressSuppressor)
            .opacity(signedURL == nil || isPreparingFilePreview ? 0.65 : 1)
    }

    private var attachmentLongPressSuppressor: some Gesture {
        LongPressGesture(minimumDuration: 0.30)
            .onEnded { _ in
                suppressAttachmentTapUntil = Date().addingTimeInterval(0.7)
            }
    }

    private var canOpenAttachmentPreview: Bool {
        guard let suppressAttachmentTapUntil else { return true }
        return Date() >= suppressAttachmentTapUntil
    }

    private var fileLabel: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(fileName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)

                Text(fileStatusText)
                    .font(.caption2)
                    .foregroundStyle(isMine ? Color.white.opacity(0.75) : Color.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: 240, alignment: .leading)
        .background(isMine ? Color.white.opacity(0.14) : Color.secondary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint(AppLanguageManager.localized("chat_open_attachment_hint"))
    }

    private func attachmentPlaceholder(title: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)

            Text(title)
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(isMine ? Color.white.opacity(0.85) : Color.secondary)
        .frame(width: thumbnailSize.width, height: min(thumbnailSize.height, 150))
        .background(isMine ? Color.white.opacity(0.14) : Color.secondary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var fileName: String {
        guard let name = message.attachmentFileName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return AppLanguageManager.localized("chat_attachment_message")
        }

        return name
    }

    private var fileStatusText: String {
        if isPreparingFilePreview {
            return AppLanguageManager.localized("chat_opening_file")
        }

        if let errorMessage {
            return errorMessage
        }

        return signedURL == nil ? AppLanguageManager.localized("chat_loading_file") : AppLanguageManager.localized("chat_tap_to_preview")
    }

    private var isImage: Bool {
        if message.attachmentKind == "image" {
            return true
        }

        return message.attachmentContentType?.hasPrefix("image/") == true
    }

    private var isAudio: Bool {
        if message.attachmentKind == "audio" {
            return true
        }

        return message.attachmentContentType?.hasPrefix("audio/") == true
    }

    private var isVideo: Bool {
        if message.attachmentKind == "video" {
            return true
        }

        return message.attachmentContentType?.hasPrefix("video/") == true
    }

    private func loadSignedURL() async {
        guard let path = message.attachmentFilePath else { return }

        do {
            signedURL = try await ChatAttachmentService.shared.signedURL(for: path)
            errorMessage = nil
        } catch {
            errorMessage = AppLanguageManager.localized("chat_could_not_load_attachment")
        }
    }

    private func openFilePreview() async {
        guard let signedURL else { return }

        isPreparingFilePreview = true
        errorMessage = nil
        defer { isPreparingFilePreview = false }

        do {
            let (temporaryURL, _) = try await URLSession.shared.download(from: signedURL)
            let destinationURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString)-\(fileName)")

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
            filePreviewItem = AttachmentPreviewItem(url: destinationURL)
        } catch {
            errorMessage = AppLanguageManager.localized("chat_could_not_preview_file")
        }
    }

    private func openImageGallery() async {
        let sourceMessages = galleryMessages.isEmpty ? [message] : galleryMessages
        let imageMessages = sourceMessages.filter { isImageMessage($0) }

        do {
            let photos = try await signedGalleryPhotos(from: imageMessages)
            guard !photos.isEmpty else { return }

            let selectedId = photos.contains(where: { $0.id == message.id }) ? message.id : photos[0].id
            galleryPreview = AttachmentGalleryPreviewState(photos: photos, selectedId: selectedId)
            errorMessage = nil
        } catch {
            errorMessage = AppLanguageManager.localized("chat_could_not_load_photo")
        }
    }

    private func signedGalleryPhotos(from messages: [Message]) async throws -> [AttachmentGalleryPhoto] {
        var photos: [AttachmentGalleryPhoto] = []

        for item in messages {
            guard let path = item.attachmentFilePath else { continue }
            let url = try await ChatAttachmentService.shared.signedURL(for: path)
            photos.append(
                AttachmentGalleryPhoto(
                    id: item.id,
                    url: url,
                    fileName: item.attachmentFileName ?? AppLanguageManager.localized("chat_photo_message")
                )
            )
        }

        return photos
    }

    private func isImageMessage(_ item: Message) -> Bool {
        if item.attachmentKind == "image" {
            return true
        }

        return item.attachmentContentType?.hasPrefix("image/") == true
    }
}

private struct AttachmentPreviewItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ChatDownloadedAttachment: Identifiable {
    let id = UUID()
    let url: URL
}

private struct AttachmentVideoPreviewState: Identifiable {
    let id = UUID()
    let url: URL
    let fileName: String
}

private struct AttachmentGalleryPreviewState: Identifiable {
    let id = UUID()
    let photos: [AttachmentGalleryPhoto]
    let selectedId: UUID
}

private struct AttachmentGalleryPhoto: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let fileName: String
}

private struct AttachmentImageGalleryPreview: View {
    let preview: AttachmentGalleryPreviewState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedId: UUID
    @State private var errorMessage: String?
    @State private var successMessage: String?

    init(preview: AttachmentGalleryPreviewState) {
        self.preview = preview
        _selectedId = State(initialValue: preview.selectedId)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black
                .ignoresSafeArea()

            TabView(selection: $selectedId) {
                ForEach(preview.photos) { photo in
                    AsyncImage(url: photo.url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        case .failure:
                            ContentUnavailableView(AppLanguageManager.localized("chat_could_not_load_photo_title"), systemImage: "photo")
                                .foregroundStyle(.white)
                        default:
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .padding(.horizontal, 10)
                    .tag(photo.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: preview.photos.count > 1 ? .automatic : .never))
            .ignoresSafeArea()

            HStack {
                Spacer()

                if preview.photos.count > 1 {
                    Text(counterText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.18))
                        .clipShape(Capsule())
                }

                Spacer()
            }
            .padding(.top, 16)

            HStack {
                Button {
                    Task {
                        await downloadSelectedPhoto()
                    }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.18))
                        .clipShape(Circle())
                }
                .accessibilityLabel(AppLanguageManager.localized("chat_download_photo"))
                .padding()

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.18))
                        .clipShape(Circle())
                }
                .accessibilityLabel(AppLanguageManager.localized("common_close"))
                .padding()
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.72))
                    .clipShape(Capsule())
                    .padding(.top, 62)
            }

            if let successMessage {
                Text(successMessage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.72))
                    .clipShape(Capsule())
                    .padding(.top, 62)
            }
        }
    }

    private var counterText: String {
        guard let index = preview.photos.firstIndex(where: { $0.id == selectedId }) else {
            return String.localizedStringWithFormat(AppLanguageManager.localized("chat_gallery_counter_format"), 1, preview.photos.count)
        }

        return String.localizedStringWithFormat(AppLanguageManager.localized("chat_gallery_counter_format"), index + 1, preview.photos.count)
    }

    private var selectedPhoto: AttachmentGalleryPhoto? {
        preview.photos.first { $0.id == selectedId } ?? preview.photos.first
    }

    private func downloadSelectedPhoto() async {
        guard let selectedPhoto else { return }

        do {
            try await saveImageURLToPhotos(selectedPhoto.url)
            errorMessage = nil
            successMessage = AppLanguageManager.localized("chat_saved_to_photos")
        } catch {
            successMessage = nil
            errorMessage = AppLanguageManager.localized("chat_could_not_save_photo")
        }
    }
}

private struct AttachmentVideoPreview: View {
    let preview: AttachmentVideoPreviewState
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var isShowingControls = false
    @State private var hideControlsTask: Task<Void, Never>?

    init(preview: AttachmentVideoPreviewState) {
        self.preview = preview
        _player = State(initialValue: AVPlayer(url: preview.url))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black
                .ignoresSafeArea()

            VideoPlayer(player: player)
                .ignoresSafeArea()
                .simultaneousGesture(
                    TapGesture().onEnded {
                        toggleControls()
                    }
                )

            if isShowingControls {
                HStack(spacing: 10) {
                    Button {
                        showControls()
                        Task {
                            await downloadVideo()
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .overlay(Circle().fill(Color.white.opacity(0.06)))
                                    .overlay(Circle().fill(Color.black.opacity(0.1)))
                                    .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 0.5))
                            }
                    }
                    .accessibilityLabel(AppLanguageManager.localized("chat_download_video"))

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .overlay(Circle().fill(Color.white.opacity(0.06)))
                                    .overlay(Circle().fill(Color.black.opacity(0.1)))
                                    .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 0.5))
                            }
                    }
                    .accessibilityLabel(AppLanguageManager.localized("common_close"))
                }
                .padding(.top, 6)
                .transition(
                    .asymmetric(
                        insertion: .offset(y: -10).combined(with: .opacity),
                        removal: .offset(y: -10).combined(with: .opacity)
                    )
                )
                .zIndex(1)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.72))
                    .clipShape(Capsule())
                    .padding(.top, 86)
            }

            if let successMessage {
                Text(successMessage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.72))
                    .clipShape(Capsule())
                    .padding(.top, 86)
            }
        }
        .onAppear {
            player.play()
        }
        .onDisappear {
            hideControlsTask?.cancel()
            player.pause()
        }
        .onReceive(player.publisher(for: \.timeControlStatus)) { status in
            handlePlaybackStatusChange(status)
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            guard notification.object as? AVPlayerItem === player.currentItem else { return }
            cancelControlsAutohide()
        }
        .animation(.easeInOut(duration: 0.18), value: isShowingControls)
    }

    private func downloadVideo() async {
        do {
            try await saveVideoURLToPhotos(preview.url, fileName: preview.fileName)
            errorMessage = nil
            successMessage = AppLanguageManager.localized("chat_saved_to_photos")
        } catch {
            successMessage = nil
            errorMessage = AppLanguageManager.localized("chat_could_not_save_video")
        }
    }

    private func toggleControls() {
        if isShowingControls {
            hideControls()
        } else {
            showControls()
        }
    }

    private func showControls() {
        hideControlsTask?.cancel()
        isShowingControls = true
        scheduleControlsAutohideIfNeeded()
    }

    private func hideControls() {
        hideControlsTask?.cancel()
        isShowingControls = false
    }

    private func handlePlaybackStatusChange(_ status: AVPlayer.TimeControlStatus) {
        if status == .playing {
            scheduleControlsAutohideIfNeeded()
        } else {
            cancelControlsAutohide()
        }
    }

    private func scheduleControlsAutohideIfNeeded() {
        guard isShowingControls, player.timeControlStatus == .playing else { return }
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            isShowingControls = false
        }
    }

    private func cancelControlsAutohide() {
        hideControlsTask?.cancel()
        hideControlsTask = nil
    }
}

private struct AttachmentFilePreview: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var downloadItem: ChatDownloadedAttachment?

    var body: some View {
        NavigationStack {
            QuickLookPreview(url: url)
                .ignoresSafeArea()
                .navigationTitle(url.lastPathComponent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(AppLanguageManager.localized("common_close"))
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            downloadItem = ChatDownloadedAttachment(url: url)
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .accessibilityLabel(AppLanguageManager.localized("chat_download_file"))
                    }
                }
        }
        .sheet(item: $downloadItem) { item in
            ChatAttachmentActivityView(url: item.url)
        }
    }
}

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}

private struct ChatAttachmentActivityView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private func downloadedAttachmentCopy(from sourceURL: URL, fileName: String) async throws -> URL {
    let (temporaryURL, _) = try await URLSession.shared.download(from: sourceURL)
    let safeName = safeAttachmentDownloadFileName(fileName)
    let destinationURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(UUID().uuidString)-\(safeName)")

    if FileManager.default.fileExists(atPath: destinationURL.path) {
        try FileManager.default.removeItem(at: destinationURL)
    }

    try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
    return destinationURL
}

private func safeAttachmentDownloadFileName(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
    let cleaned = value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .unicodeScalars
        .map { allowed.contains($0) ? Character($0) : "-" }
        .reduce(into: "") { result, character in
            result.append(character)
        }

    return cleaned.isEmpty ? AppLanguageManager.localized("chat_attachment_default_file_name") : cleaned
}

private func makeVideoThumbnail(from url: URL) async throws -> UIImage {
    let asset = AVURLAsset(url: url)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 640, height: 640)

    let requestedTime = CMTime(seconds: 0.4, preferredTimescale: 600)
    let image: CGImage = try await withCheckedThrowingContinuation { continuation in
        generator.generateCGImageAsynchronously(for: requestedTime) { image, _, error in
            if let error {
                continuation.resume(throwing: error)
                return
            }

            guard let image else {
                continuation.resume(
                    throwing: NSError(
                        domain: "VeriDateVideoThumbnail",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: AppLanguageManager.localized("chat_error_generate_video_thumbnail")]
                    )
                )
                return
            }

            continuation.resume(returning: image)
        }
    }
    return UIImage(cgImage: image)
}

private func saveImageURLToPhotos(_ url: URL) async throws {
    try await requestPhotoLibraryAddAccess()
    let (data, _) = try await URLSession.shared.data(from: url)

    guard let image = UIImage(data: data) else {
        throw NSError(
            domain: "VeriDatePhotoSave",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: AppLanguageManager.localized("chat_error_read_image_data")]
        )
    }

    try await PHPhotoLibrary.shared().performChanges {
        PHAssetChangeRequest.creationRequestForAsset(from: image)
    }
}

private func saveVideoURLToPhotos(_ url: URL, fileName: String) async throws {
    try await requestPhotoLibraryAddAccess()
    let localURL = try await downloadedAttachmentCopy(from: url, fileName: fileName)

    try await PHPhotoLibrary.shared().performChanges {
        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: localURL)
    }
}

private func requestPhotoLibraryAddAccess() async throws {
    let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    if status == .authorized || status == .limited {
        return
    }

    let requestedStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    guard requestedStatus == .authorized || requestedStatus == .limited else {
        throw NSError(
            domain: "VeriDatePhotoSave",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: AppLanguageManager.localized("chat_error_photos_permission_required")]
        )
    }
}

private struct MessageRowView: View {
    let message: Message
    let allMessages: [Message]
    let reactions: [MessageReaction]
    let isMine: Bool
    let isActionMenuVisible: Bool
    let isReactionPickerVisible: Bool
    let isDimmedByActionMenu: Bool
    let isHighlighted: Bool
    let hasActiveMessageOverlay: Bool
    let isGroupedWithPrevious: Bool
    let isGroupedWithNext: Bool
    let isPending: Bool
    let isFailed: Bool
    let isLastMessage: Bool
    let onAppearLast: () -> Void
    let onDisappearLast: () -> Void
    let onMessageLongPress: (Message) -> Void
    let onMessageAction: (ChatMessageAction, Message) -> Void
    let onSwipeReply: (Message) -> Void
    let onReactionSelected: (String, Message) -> Void
    let onMoreReactions: (Message) -> Void
    let onDismissMessageOverlays: () -> Void
    let onRetry: (Message) -> Void

    var body: some View {
        MessageBubble(
            message: message,
            allMessages: allMessages,
            reactions: reactions,
            isMine: isMine,
            isActionMenuVisible: isActionMenuVisible,
            isReactionPickerVisible: isReactionPickerVisible,
            isDimmedByActionMenu: isDimmedByActionMenu,
            isHighlighted: isHighlighted,
            hasActiveMessageOverlay: hasActiveMessageOverlay,
            isGroupedWithPrevious: isGroupedWithPrevious,
            isGroupedWithNext: isGroupedWithNext,
            isPending: isPending,
            isFailed: isFailed,
            onMessageLongPress: onMessageLongPress,
            onMessageAction: onMessageAction,
            onSwipeReply: onSwipeReply,
            onReactionSelected: onReactionSelected,
            onMoreReactions: onMoreReactions,
            onDismissMessageOverlays: onDismissMessageOverlays,
            onRetry: onRetry
        )
        .id(message.id)
        .transition(.opacity)
        .onAppear {
            if isLastMessage {
                onAppearLast()
            }
        }
        .onDisappear {
            if isLastMessage {
                onDisappearLast()
            }
        }
    }
}

private struct AnimatedMessageStatusTicks: View {
    let message: Message
    let isPending: Bool

    private enum Status: Equatable {
        case pending
        case sent
        case delivered
        case read
    }

    @State private var didAnimate = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.caption2)
            .fontWeight(status == .pending ? .regular : .semibold)
            .foregroundStyle(tintColor)
            .symbolEffect(.bounce, value: status)
            .scaleEffect(didAnimate ? 1 : 0.86)
            .opacity(didAnimate ? 1 : 0.65)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: status)
            .animation(.easeOut(duration: 0.18), value: didAnimate)
            .onAppear {
                didAnimate = true
            }
            .onChange(of: status) { _, _ in
                didAnimate = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                    didAnimate = true
                }
            }
            .accessibilityLabel(accessibilityText)
    }

    private var systemImage: String {
        switch status {
        case .pending:
            return "clock"
        case .sent:
            return "checkmark.circle"
        case .delivered:
            return "checkmark.circle.fill"
        case .read:
            return "checkmark.circle.fill"
        }
    }

    private var tintColor: Color {
        switch status {
        case .pending, .sent:
            return .secondary
        case .delivered:
            return .secondary
        case .read:
            return .blue
        }
    }

    private var status: Status {
        if isPending {
            return .pending
        } else if message.readAt != nil {
            return .read
        } else if message.deliveredAt != nil {
            return .delivered
        } else {
            return .sent
        }
    }

    private var accessibilityText: String {
        switch status {
        case .pending:
            return AppLanguageManager.localized("chat_status_sending")
        case .sent:
            return AppLanguageManager.localized("chat_status_sent")
        case .delivered:
            return AppLanguageManager.localized("chat_status_delivered")
        case .read:
            return AppLanguageManager.localized("chat_status_read")
        }
    }
}


private struct UnreadSeparatorView: View {
    @State private var isVisible = false

    var body: some View {
        Text(AppLanguageManager.localized("chat_new_messages_separator"))
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .opacity(isVisible ? 0.95 : 0)
            .scaleEffect(isVisible ? 1 : 0.96)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
            .animation(.easeInOut(duration: 0.28), value: isVisible)
            .onAppear {
                isVisible = true
            }
            .onDisappear {
                isVisible = false
            }
    }
}

private struct ChatPhotoCamera: UIViewControllerRepresentable {
    static var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    let onImageCaptured: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier]
        picker.cameraCaptureMode = .photo
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageCaptured: onImageCaptured)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImageCaptured: (UIImage) -> Void

        init(onImageCaptured: @escaping (UIImage) -> Void) {
            self.onImageCaptured = onImageCaptured
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImageCaptured(image)
            }

            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

private struct DateSeparatorView: View {
    let date: Date

    var body: some View {
        Text(formatted(date))
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1))
            .clipShape(Capsule())
            .frame(maxWidth: .infinity)
    }

    private func formatted(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return AppLanguageManager.localized("common_today")
        } else if Calendar.current.isDateInYesterday(date) {
            return AppLanguageManager.localized("common_yesterday")
        } else {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
    }
}


private let sharedISOFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()
