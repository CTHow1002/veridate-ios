import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct VerificationUploadView: View {
    @EnvironmentObject var session: SessionViewModel
    @StateObject private var vm = VerificationUploadViewModel()
    @State private var selfieItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                if session.currentProfile?.verificationStatus == .rejected {
                    Section("Review Feedback") {
                        if vm.isLoadingRejectionReason {
                            ProgressView("Loading feedback...")
                        } else if let rejectionReason = vm.rejectionReason, !rejectionReason.isEmpty {
                            Label(rejectionReason, systemImage: "exclamationmark.circle")
                                .foregroundStyle(.red)
                        } else {
                            Text("Your verification was rejected. Please upload updated documents and submit again.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Selfie") {
                    SelfiePickerRow(hasSelfie: vm.selfieData != nil, selfieItem: $selfieItem)
                }

                Section("Documents") {
                    documentImporter(
                        title: "ID Document",
                        systemImage: "person.text.rectangle",
                        selection: $vm.idDocumentURL
                    )

                    documentImporter(
                        title: "Job Proof",
                        systemImage: "briefcase",
                        selection: $vm.jobProofURL
                    )

                    documentImporter(
                        title: "Education Proof",
                        systemImage: "graduationcap",
                        selection: $vm.educationProofURL
                    )
                }

                Section {
                    Button {
                        Task {
                            guard let userId = session.currentUserId else {
                                vm.errorMessage = "Please sign in again before submitting verification."
                                return
                            }

                            let submitted = await vm.submitVerification(userId: userId)
                            guard submitted else { return }

                            let didMarkPending = await session.markVerificationPending()
                            if !didMarkPending {
                                vm.errorMessage = "Files uploaded, but Supabase blocked updating your verification status."
                            }
                        }
                    } label: {
                        if vm.isSubmitting {
                            ProgressView()
                        } else {
                            Text("Submit Verification")
                        }
                    }
                    .disabled(!vm.canSubmit)
                }

                if let error = vm.errorMessage ?? session.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Verify Account")
            .toolbar {
                Button("Sign Out") {
                    Task { await session.signOut() }
                }
            }
            .onChange(of: selfieItem) { _, item in
                Task {
                    await loadSelfie(from: item)
                }
            }
            .task(id: session.currentUserId) {
                guard session.currentProfile?.verificationStatus == .rejected,
                      let userId = session.currentUserId else {
                    return
                }

                await vm.loadRejectionReason(userId: userId)
            }
        }
    }

    private func documentImporter(
        title: String,
        systemImage: String,
        selection: Binding<URL?>
    ) -> some View {
        LabeledContent(title) {
            FileImporterButton(title: title, systemImage: systemImage, selection: selection)
        }
    }

    private func loadSelfie(from item: PhotosPickerItem?) async {
        do {
            guard let item else { return }
            guard let data = try await item.loadTransferable(type: Data.self) else {
                vm.errorMessage = "Could not read that selfie photo."
                return
            }

            vm.selfieData = data
            vm.selfieFileName = "\(UUID().uuidString).jpg"
            vm.errorMessage = nil
        } catch {
            vm.errorMessage = "Could not read that selfie photo. \(error.localizedDescription)"
        }
    }
}

private struct SelfiePickerRow: View {
    let hasSelfie: Bool
    @Binding var selfieItem: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $selfieItem, matching: .images) {
            Label(hasSelfie ? "Selfie Photo Added" : "Choose Selfie Photo", systemImage: "camera")
        }
    }
}

private struct FileImporterButton: View {
    let title: String
    let systemImage: String
    @Binding var selection: URL?
    @State private var isImporting = false
    @State private var importerError: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button {
                isImporting = true
            } label: {
                Label(selection == nil ? "Choose" : "Replace", systemImage: systemImage)
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.pdf, .image],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    selection = urls.first
                    importerError = nil
                case .failure(let error):
                    importerError = error.localizedDescription
                }
            }

            if let selection {
                Text(selection.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let importerError {
                Text(importerError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .accessibilityLabel(title)
    }
}
