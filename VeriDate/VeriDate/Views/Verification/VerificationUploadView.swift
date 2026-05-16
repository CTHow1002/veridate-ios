import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct VerificationUploadView: View {
    @EnvironmentObject var session: SessionViewModel
    @StateObject private var vm = VerificationUploadViewModel()
    @State private var isShowingCamera = false
    var onBackToProfileSetup: (() -> Void)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VerificationIntroCard()

                    if session.currentProfile?.verificationStatus == .rejected {
                        VerificationCard(title: AppLanguageManager.localized("verificationUpload.feedback.title"), systemImage: "exclamationmark.circle.fill") {
                            if vm.isLoadingRejectionReason {
                                ProgressView(AppLanguageManager.localized("verificationUpload.feedback.loading"))
                                    .accessibilityLabel(AppLanguageManager.localized("verificationUpload.feedback.loading"))
                            } else if let rejectionReason = vm.rejectionReason, !rejectionReason.isEmpty {
                                Label(rejectionReason, systemImage: "exclamationmark.circle")
                                    .foregroundStyle(.red)
                                    .accessibilityElement(children: .combine)
                            } else {
                                Text(AppLanguageManager.localized("verificationUpload.feedback.defaultRejected"))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    VerificationCard(title: AppLanguageManager.localized("verificationUpload.video.title"), systemImage: "video.fill") {
                        Text(AppLanguageManager.localized("verificationUpload.video.livenessPrompt"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            guard VideoCameraRecorder.isCameraAvailable else {
                                vm.errorMessage = AppLanguageManager.localized("verificationUpload.error.cameraUnavailableVideo")
                                return
                            }

                            isShowingCamera = true
                        } label: {
                            VerificationActionRow(
                                title: vm.selfieVideoData == nil ? AppLanguageManager.localized("verificationUpload.video.record") : AppLanguageManager.localized("verificationUpload.video.retake"),
                                subtitle: vm.selfieVideoData == nil ? AppLanguageManager.localized("verificationUpload.video.recordSubtitle") : AppLanguageManager.localized("verificationUpload.video.captured"),
                                systemImage: "video.badge.checkmark",
                                isComplete: vm.selfieVideoData != nil
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(vm.selfieVideoData == nil ? AppLanguageManager.localized("verificationUpload.video.record") : AppLanguageManager.localized("verificationUpload.video.retake"))
                        .accessibilityValue(vm.selfieVideoData == nil ? AppLanguageManager.localized("verificationUpload.item.status.incomplete") : AppLanguageManager.localized("verificationUpload.item.status.complete"))
                    }

                    VerificationCard(title: AppLanguageManager.localized("verificationUpload.documents.title"), systemImage: "doc.text.viewfinder") {
                        documentImporter(
                            title: AppLanguageManager.localized("verificationUpload.document.icPhoto"),
                            systemImage: "person.text.rectangle",
                            selection: $vm.idDocument,
                            sourceMode: .cameraOnly,
                            disabledReason: nil
                        )

                        documentImporter(
                            title: AppLanguageManager.localized("verificationUpload.document.jobProof"),
                            systemImage: "briefcase",
                            selection: $vm.jobProof,
                            sourceMode: .allSources,
                            disabledReason: requiresJobProof ? nil : AppLanguageManager.localized("verificationUpload.document.jobProofSkipped")
                        )

                        documentImporter(
                            title: AppLanguageManager.localized("verificationUpload.document.educationProof"),
                            systemImage: "graduationcap",
                            selection: $vm.educationProof,
                            sourceMode: .allSources,
                            disabledReason: requiresEducationProof ? nil : AppLanguageManager.localized("verificationUpload.document.educationProofSkipped")
                        )
                    }

                    Button {
                        Task {
                            guard let userId = session.currentUserId else {
                                vm.errorMessage = AppLanguageManager.localized("verificationUpload.error.signInAgain")
                                return
                            }

                            let submitted = await vm.submitVerification(
                                userId: userId,
                                requiresJobProof: requiresJobProof,
                                requiresEducationProof: requiresEducationProof
                            )
                            guard submitted else { return }

                            let didMarkPending = await session.markVerificationPending()
                            if !didMarkPending {
                                vm.errorMessage = AppLanguageManager.localized("verificationUpload.error.statusUpdateBlocked")
                            }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if vm.isSubmitting {
                                ProgressView()
                                    .tint(.white)
                                    .accessibilityHidden(true)
                            } else {
                                Text(AppLanguageManager.localized("verificationUpload.submit.title"))
                                Image(systemName: "checkmark.shield.fill")
                                    .accessibilityHidden(true)
                            }
                            Spacer()
                        }
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(height: 52)
                        .background(Color.pink, in: Capsule())
                        .shadow(color: Color.pink.opacity(0.22), radius: 14, y: 7)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(vm.isSubmitting ? AppLanguageManager.localized("verificationUpload.submit.submitting") : AppLanguageManager.localized("verificationUpload.submit.title"))
                    .disabled(!vm.canSubmit(requiresJobProof: requiresJobProof, requiresEducationProof: requiresEducationProof))
                    .opacity(vm.canSubmit(requiresJobProof: requiresJobProof, requiresEducationProof: requiresEducationProof) ? 1 : 0.46)

                    if let error = vm.errorMessage ?? session.errorMessage {
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
            .navigationTitle(AppLanguageManager.localized("verificationUpload.navigationTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let onBackToProfileSetup {
                        Button {
                            HapticManager.light()
                            onBackToProfileSetup()
                        } label: {
                            Label(AppLanguageManager.localized("verificationUpload.editSetup"), systemImage: "chevron.left")
                        }
                        .fontWeight(.semibold)
                        .accessibilityLabel(AppLanguageManager.localized("verificationUpload.editSetup"))
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLanguageManager.localized("common_sign_out")) {
                        Task { await session.signOut() }
                    }
                    .accessibilityLabel(AppLanguageManager.localized("common_sign_out"))
                }
            }
            .sheet(isPresented: $isShowingCamera) {
                VideoCameraRecorder(maximumDuration: 6) { videoURL in
                    loadCapturedSelfieVideo(from: videoURL)
                }
                .ignoresSafeArea()
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

    private var requiresJobProof: Bool {
        let job = session.currentProfile?.jobTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let company = session.currentProfile?.companyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if job.localizedCaseInsensitiveCompare("Student") == .orderedSame { return false }
        if job.localizedCaseInsensitiveCompare("Unemployed") == .orderedSame { return false }
        return !job.isEmpty || !company.isEmpty
    }

    private var requiresEducationProof: Bool {
        let level = session.currentProfile?.educationLevel?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return level != "primary school" && level != "high school"
    }

    private func documentImporter(
        title: String,
        systemImage: String,
        selection: Binding<VerificationDocument?>,
        sourceMode: DocumentSourceMode,
        disabledReason: String?
    ) -> some View {
        DocumentPickerRow(
            title: title,
            systemImage: systemImage,
            selection: selection,
            sourceMode: sourceMode,
            disabledReason: disabledReason
        )
    }

    private func loadCapturedSelfieVideo(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            vm.selfieVideoData = data
            vm.selfieVideoFileName = "\(UUID().uuidString).mov"
            vm.errorMessage = nil
        } catch {
            vm.errorMessage = String.localizedStringWithFormat(AppLanguageManager.localized("verificationUpload.error.readVideoFormat"), error.localizedDescription)
        }
    }
}

private struct VideoCameraRecorder: UIViewControllerRepresentable {
    static var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    let maximumDuration: TimeInterval
    let onVideoCaptured: (URL) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.movie.identifier]
        picker.cameraCaptureMode = .video
        picker.videoMaximumDuration = maximumDuration
        picker.videoQuality = .typeMedium
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onVideoCaptured: onVideoCaptured)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onVideoCaptured: (URL) -> Void

        init(onVideoCaptured: @escaping (URL) -> Void) {
            self.onVideoCaptured = onVideoCaptured
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let videoURL = info[.mediaURL] as? URL {
                onVideoCaptured(videoURL)
            }

            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

private struct VerificationIntroCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .font(.title2.weight(.bold))
                .foregroundStyle(.pink)
                .accessibilityHidden(true)

            Text(AppLanguageManager.localized("verificationUpload.intro.title"))
                .font(.title3.weight(.bold))

            Text(AppLanguageManager.localized("verificationUpload.intro.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 16, y: 8)
        .accessibilityElement(children: .combine)
    }
}

private struct VerificationCard<Content: View>: View {
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
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 16, y: 8)
        .accessibilityElement(children: .contain)
    }
}

private struct VerificationActionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isComplete: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.bold))
                .foregroundStyle(isComplete ? .green : .pink)
                .frame(width: 38, height: 38)
                .background((isComplete ? Color.green : Color.pink).opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: isComplete ? "checkmark.circle.fill" : "chevron.right")
                .foregroundStyle(isComplete ? .green : .secondary)
                .accessibilityHidden(true)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityValue(isComplete ? AppLanguageManager.localized("verificationUpload.item.status.complete") : AppLanguageManager.localized("verificationUpload.item.status.incomplete"))
    }
}

private enum DocumentSourceMode {
    case cameraOnly
    case allSources
}

private struct DocumentPickerRow: View {
    let title: String
    let systemImage: String
    @Binding var selection: VerificationDocument?
    let sourceMode: DocumentSourceMode
    let disabledReason: String?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isChoosingSource = false
    @State private var isPickingPhoto = false
    @State private var isUsingCamera = false
    @State private var isImporting = false
    @State private var importerError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                guard disabledReason == nil else { return }
                if sourceMode == .cameraOnly {
                    openCamera()
                } else {
                    isChoosingSource = true
                }
            } label: {
                VerificationActionRow(
                    title: title,
                    subtitle: disabledReason ?? (selection?.displayName ?? sourceSubtitle),
                    systemImage: systemImage,
                    isComplete: selection != nil || disabledReason != nil
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(disabledReason ?? (selection?.displayName ?? sourceSubtitle))
            .accessibilityHint(disabledReason == nil ? AppLanguageManager.localized("verificationUpload.document.selectHint") : AppLanguageManager.localized("verificationUpload.document.disabledHint"))
            .disabled(disabledReason != nil)
            .opacity(disabledReason == nil ? 1 : 0.58)
            .confirmationDialog(String.localizedStringWithFormat(AppLanguageManager.localized("verificationUpload.document.chooseSourceFormat"), title), isPresented: $isChoosingSource, titleVisibility: .visible) {
                if sourceMode == .allSources {
                    Button(AppLanguageManager.localized("verificationUpload.document.source.photos")) {
                        isPickingPhoto = true
                    }

                    Button(AppLanguageManager.localized("verificationUpload.document.source.camera")) {
                        openCamera()
                    }

                    Button(AppLanguageManager.localized("verificationUpload.document.source.files")) {
                        isImporting = true
                    }
                }

                Button(AppLanguageManager.localized("common_cancel"), role: .cancel) {}
            }
            .photosPicker(isPresented: $isPickingPhoto, selection: $selectedPhotoItem, matching: .images)
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.pdf, .image],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        selection = .file(url: url, contentType: contentType(for: url))
                        importerError = nil
                    } else {
                        importerError = AppLanguageManager.localized("verificationUpload.error.noFileSelected")
                    }
                case .failure(let error):
                    importerError = String.localizedStringWithFormat(AppLanguageManager.localized("verificationUpload.error.importFileFormat"), error.localizedDescription)
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    await loadPhoto(newItem)
                }
            }
            .sheet(isPresented: $isUsingCamera) {
                DocumentPhotoCamera { image in
                    loadCameraImage(image)
                }
                .ignoresSafeArea()
            }

            if let importerError {
                Text(importerError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel(importerError)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var sourceSubtitle: String {
        sourceMode == .cameraOnly ? AppLanguageManager.localized("verificationUpload.document.cameraOnly") : AppLanguageManager.localized("verificationUpload.document.chooseSources")
    }

    private func openCamera() {
        guard DocumentPhotoCamera.isCameraAvailable else {
            importerError = sourceMode == .cameraOnly
                ? AppLanguageManager.localized("verificationUpload.error.cameraRequiredForIC")
                : AppLanguageManager.localized("verificationUpload.error.cameraUnavailableUsePhotosFiles")
            return
        }

        isUsingCamera = true
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                importerError = AppLanguageManager.localized("verificationUpload.error.readPhoto")
                return
            }

            let type = item.supportedContentTypes.first { $0.conforms(to: .image) } ?? .jpeg
            let fileExtension = type.preferredFilenameExtension ?? "jpg"
            let contentType = type.preferredMIMEType ?? "image/jpeg"
            selection = .photo(
                data: data,
                fileName: "\(UUID().uuidString).\(fileExtension)",
                contentType: contentType
            )
            importerError = nil
        } catch {
            importerError = String.localizedStringWithFormat(AppLanguageManager.localized("verificationUpload.error.readPhotoFormat"), error.localizedDescription)
        }
    }

    private func loadCameraImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            importerError = AppLanguageManager.localized("verificationUpload.error.readCameraPhoto")
            return
        }

        selection = .photo(
            data: data,
            fileName: "\(UUID().uuidString).jpg",
            contentType: "image/jpeg"
        )
        importerError = nil
    }

    private func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "heic":
            return "image/heic"
        case "pdf":
            return "application/pdf"
        default:
            return "application/octet-stream"
        }
    }
}

private struct DocumentPhotoCamera: UIViewControllerRepresentable {
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
