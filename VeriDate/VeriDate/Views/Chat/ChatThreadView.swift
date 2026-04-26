import SwiftUI

struct ChatThreadView: View {
    @EnvironmentObject var session: SessionViewModel
    @StateObject private var vm = ChatThreadViewModel()
    @State private var messageText = ""
    @State private var reportReason = ""
    @State private var blockReason = ""
    @State private var isShowingReportAlert = false
    @State private var isShowingBlockAlert = false

    let row: MatchRow

    var body: some View {
        VStack(spacing: 0) {
            content
            composer
        }
        .navigationTitle(row.profile.fullName ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button(role: .destructive) {
                    blockReason = ""
                    isShowingBlockAlert = true
                } label: {
                    Label("Block", systemImage: "hand.raised")
                }

                Button(role: .destructive) {
                    reportReason = ""
                    isShowingReportAlert = true
                } label: {
                    Label("Report", systemImage: "exclamationmark.bubble")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .alert("Report User", isPresented: $isShowingReportAlert) {
            TextField("Reason", text: $reportReason)
            Button("Cancel", role: .cancel) {}
            Button("Submit", role: .destructive) {
                Task {
                    await reportUser()
                }
            }
        } message: {
            Text("Tell us briefly what happened.")
        }
        .alert("Block User", isPresented: $isShowingBlockAlert) {
            TextField("Optional reason", text: $blockReason)
            Button("Cancel", role: .cancel) {}
            Button("Block", role: .destructive) {
                Task {
                    await blockUser()
                }
            }
        } message: {
            Text("This saves a block record for admin review and future safety controls.")
        }
        .alert("Notice", isPresented: actionAlertBinding) {
            Button("OK") {
                vm.actionMessage = nil
            }
        } message: {
            Text(vm.actionMessage ?? "")
        }
        .task(id: row.id) {
            await load()
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
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isSending)
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
        await vm.blockUser(
            match: row.match,
            blockedUserId: row.otherUserId(for: userId),
            userId: userId,
            reason: blockReason
        )
    }

    private func reportUser() async {
        guard let userId = session.currentUserId else { return }
        await vm.reportUser(
            match: row.match,
            reportedUserId: row.otherUserId(for: userId),
            userId: userId,
            reason: reportReason
        )
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

                Text(timeText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
