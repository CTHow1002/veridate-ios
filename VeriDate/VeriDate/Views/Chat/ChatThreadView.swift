import SwiftUI

struct ChatThreadView: View {
    @EnvironmentObject var session: SessionViewModel
    @StateObject private var vm = ChatThreadViewModel()
    @StateObject private var safetyVM = SafetyViewModel()
    @State private var messageText = ""
    @State private var isShowingReportAlert = false
    @State private var isShowingBlockAlert = false

    let row: MatchRow

    var body: some View {
        VStack(spacing: 0) {
            content
            composer
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ChatHeader(profile: vm.otherProfile ?? row.profile)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        isShowingBlockAlert = true
                    } label: {
                        Label("Block", systemImage: "hand.raised")
                    }

                    Button(role: .destructive) {
                        isShowingReportAlert = true
                    } label: {
                        Label("Report", systemImage: "exclamationmark.bubble")
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
                    reportedName: (vm.otherProfile ?? row.profile).fullName ?? "User"
                )
            }
        }
        .alert("Block User", isPresented: $isShowingBlockAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Block", role: .destructive) {
                Task {
                    await blockUser()
                }
            }
        } message: {
            Text("This hides the match and stops messaging both ways.")
        }
        .alert("Notice", isPresented: actionAlertBinding) {
            Button("OK") {
                vm.actionMessage = nil
            }
        } message: {
            Text(vm.actionMessage ?? "")
        }
        .task(id: row.id) {
            vm.setInitialProfile(row.profile)
            await load()
            await keepChatSynced()
        }
    }

    @ViewBuilder
    private var content: some View {
        if session.currentProfile?.verificationStatus != .verified {
            ContentUnavailableView(
                "Verification Required",
                systemImage: "checkmark.seal",
                description: Text("Only verified users can message matches.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.isLoading {
            ProgressView("Loading messages...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = vm.errorMessage, vm.messages.isEmpty {
            ContentUnavailableView("Could Not Load Chat", systemImage: "exclamationmark.triangle", description: Text(error))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(vm.messages) { message in
                            MessageBubble(message: message, isMine: message.senderId == session.currentUserId)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .refreshable {
                    await load()
                }
                .onChange(of: vm.messages) { _, messages in
                    guard let lastId = messages.last?.id else { return }
                    withAnimation {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if let error = vm.errorMessage, !vm.messages.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if vm.isBlocked {
                Text("Messaging is unavailable because one of you blocked the other.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                TextField("Message", text: $messageText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)

                Button {
                    Task {
                        await send()
                    }
                } label: {
                    if vm.isSending {
                        ProgressView()
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isSending || vm.isBlocked)
            }
        }
        .padding()
        .background(.bar)
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

    private func load() async {
        guard let userId = session.currentUserId else { return }
        await vm.loadMessages(match: row.match, userId: userId, currentProfile: session.currentProfile)
    }

    private func keepChatSynced() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(800))

            guard !Task.isCancelled, let userId = session.currentUserId else {
                return
            }

            await vm.refreshMessages(
                match: row.match,
                userId: userId,
                currentProfile: session.currentProfile
            )
        }
    }

    private func send() async {
        guard let userId = session.currentUserId else { return }
        let didSend = await vm.sendMessage(
            body: messageText,
            match: row.match,
            userId: userId,
            currentProfile: session.currentProfile
        )

        if didSend {
            messageText = ""
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
}

private struct ChatHeader: View {
    let profile: Profile

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                Text(profile.fullName ?? "Chat")
                    .font(.headline)
                    .lineLimit(1)

                Circle()
                    .fill(isRecentlyOnline ? .green : .secondary.opacity(0.45))
                    .frame(width: 7, height: 7)
            }

            Text(presenceText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var presenceText: String {
        if isRecentlyOnline {
            return "Online"
        }

        guard let lastSeenAt = profile.lastSeenAt, let date = parseDate(lastSeenAt) else {
            return "Offline"
        }

        return "Last seen \(date.formatted(.relative(presentation: .named)))"
    }

    private var isRecentlyOnline: Bool {
        guard profile.isOnline else { return false }
        guard let lastSeenAt = profile.lastSeenAt, let date = parseDate(lastSeenAt) else {
            return true
        }

        return Date().timeIntervalSince(date) < 90
    }

    private func parseDate(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return fractionalFormatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private struct MessageBubble: View {
    let message: Message
    let isMine: Bool

    var body: some View {
        HStack {
            if isMine {
                Spacer(minLength: 40)
            }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                Text(message.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .foregroundStyle(isMine ? .white : .primary)
                    .background(isMine ? Color.accentColor : Color.secondary.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 4) {
                    Text(timeText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if isMine {
                        MessageStatusTicks(message: message)
                    }
                }
            }

            if !isMine {
                Spacer(minLength: 40)
            }
        }
    }

    private var timeText: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let date = formatter.date(from: message.createdAt) ?? ISO8601DateFormatter().date(from: message.createdAt) else {
            return ""
        }

        return date.formatted(date: .omitted, time: .shortened)
    }
}
