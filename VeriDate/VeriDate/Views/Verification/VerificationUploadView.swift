import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct VerificationUploadView: View {
    @EnvironmentObject var session: SessionViewModel
    @StateObject private var vm = VerificationUploadViewModel()
    @State private var isShowingCamera = false

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

                Section("Video Verification") {
                    Text(vm.livenessPrompt)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        guard VideoCameraRecorder.isCameraAvailable else {
                            vm.errorMessage = "Camera is not available on this device. Please test video verification on a real iPhone."
                            return
                        }

                        isShowingCamera = true
                    } label: {
                        Label(vm.selfieVideoData == nil ? "Record Short Video" : "Retake Verification Video", systemImage: "video")
                    }
                }

                Section("Documents") {
                    documentImporter(
                        title: "ID Document",
                        systemImage: "person.text.rectangle",
                        selection: $vm.idDocument
                    )

                    documentImporter(
                        title: "Job Proof",
                        systemImage: "briefcase",
                        selection: $vm.jobProof
                    )

                    documentImporter(
                        title: "Education Proof",
                        systemImage: "graduationcap",
                        selection: $vm.educationProof
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

    private func documentImporter(
        title: String,
        systemImage: String,
        selection: Binding<VerificationDocument?>
    ) -> some View {
        DocumentPickerRow(title: title, systemImage: systemImage, selection: selection)
    }

    private func loadCapturedSelfieVideo(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            vm.selfieVideoData = data
            vm.selfieVideoFileName = "\(UUID().uuidString).mov"
            vm.errorMessage = nil
        } catch {
            vm.errorMessage = "Could not read that verification video. \(error.localizedDescription)"
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

private struct DocumentPickerRow: View {
    let title: String
    let systemImage: String
    @Binding var selection: VerificationDocument?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isChoosingSource = false
    @State private var isPickingPhoto = false
    @State private var isUsingCamera = false
    @State private var isImporting = false
    @State private var importerError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                isChoosingSource = true
            } label: {
                HStack(spacing: 12) {
                    Label(title, systemImage: systemImage)

                    Spacer()

                    Text(selection?.displayName ?? "Choose")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .confirmationDialog("Choose \(title)", isPresented: $isChoosingSource, titleVisibility: .visible) {
                Button("Photos") {
                    isPickingPhoto = true
                }

                Button("Camera") {
                    guard DocumentPhotoCamera.isCameraAvailable else {
                        importerError = "Camera is not available on this device. Please use Photos or Files."
                        return
                    }

                    isUsingCamera = true
                }

                Button("Files") {
                    isImporting = true
                }

                Button("Cancel", role: .cancel) {}
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
                    }
                    importerError = nil
                case .failure(let error):
                    importerError = error.localizedDescription
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
            }
        }
        .accessibilityLabel(title)
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                importerError = "Could not read that photo."
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
            importerError = error.localizedDescription
        }
    }

    private func loadCameraImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            importerError = "Could not read that camera photo."
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
