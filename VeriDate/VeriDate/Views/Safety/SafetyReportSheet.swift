import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct SafetyReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = SafetyViewModel()
    @State private var reason: SafetyReportReason = .inappropriateBehavior
    @State private var details = ""
    @State private var proof: ReportProofAttachment?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isPickingPhoto = false
    @State private var isImportingFile = false
    @State private var proofError: String?

    let reporterUserId: UUID
    let reportedUserId: UUID
    let matchId: UUID?
    let reportedName: String

    var body: some View {
        NavigationStack {
            Form {
                Section(AppLanguageManager.localized("safety.report.section.reason")) {
                    Picker(AppLanguageManager.localized("safety.report.section.reason"), selection: $reason) {
                        ForEach(SafetyReportReason.allCases) { reason in
                            Text(reason.localizedTitle).tag(reason)
                        }
                    }
                }

                Section(AppLanguageManager.localized("safety.report.section.details")) {
                    TextField(AppLanguageManager.localized("safety.report.details.placeholder"), text: $details, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section(AppLanguageManager.localized("safety.report.section.proof")) {
                    Button {
                        isPickingPhoto = true
                    } label: {
                        Label(
                            proof == nil ? AppLanguageManager.localized("safety.report.attachScreenshot") : AppLanguageManager.localized("safety.report.replaceScreenshot"),
                            systemImage: "photo"
                        )
                    }

                    Button {
                        isImportingFile = true
                    } label: {
                        Label(AppLanguageManager.localized("safety.report.chooseFromFiles"), systemImage: "folder")
                    }

                    if let proof {
                        Text(proof.fileName)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button(AppLanguageManager.localized("safety.report.removeAttachment"), role: .destructive) {
                            self.proof = nil
                        }
                    }

                    if let proofError {
                        Text(proofError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if let error = vm.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(String.localizedStringWithFormat(AppLanguageManager.localized("safety.report.navigationTitleFormat"), reportedName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLanguageManager.localized("common_cancel")) {
                        dismiss()
                    }
                    .disabled(vm.isSubmitting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSubmitting ? AppLanguageManager.localized("safety.report.submitting") : AppLanguageManager.localized("safety.report.submit")) {
                        Task {
                            let didSubmit = await vm.submitReport(
                                reporterUserId: reporterUserId,
                                reportedUserId: reportedUserId,
                                matchId: matchId,
                                reason: reason,
                                details: details,
                                proof: proof
                            )

                            if didSubmit {
                                dismiss()
                            }
                        }
                    }
                    .disabled(vm.isSubmitting)
                }
            }
            .photosPicker(isPresented: $isPickingPhoto, selection: $selectedPhotoItem, matching: .images)
            .fileImporter(
                isPresented: $isImportingFile,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                loadImportedFile(result)
            }
            .onChange(of: selectedPhotoItem) { _, item in
                Task {
                    await loadPhoto(item)
                }
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                proofError = AppLanguageManager.localized("safety.report.error.readScreenshot")
                return
            }

            let type = item.supportedContentTypes.first { $0.conforms(to: .image) } ?? .jpeg
            proof = ReportProofAttachment(
                data: data,
                fileName: "\(UUID().uuidString).\(type.preferredFilenameExtension ?? "jpg")",
                contentType: type.preferredMIMEType ?? "image/jpeg"
            )
            proofError = nil
        } catch {
            proofError = error.localizedDescription
        }
    }

    private func loadImportedFile(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let hasScopedAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasScopedAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try Data(contentsOf: url)
                proof = ReportProofAttachment(
                    data: data,
                    fileName: url.lastPathComponent,
                    contentType: contentType(for: url)
                )
                proofError = nil
            } catch {
                proofError = error.localizedDescription
            }
        case .failure(let error):
            proofError = error.localizedDescription
        }
    }

    private func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "heic":
            return "image/heic"
        default:
            return "application/octet-stream"
        }
    }
}
