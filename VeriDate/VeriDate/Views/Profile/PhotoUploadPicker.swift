import SwiftUI
import PhotosUI

struct PhotoUploadPicker: View {
    let userId: UUID
    let displayOrder: Int
    let slotNumber: Int
    var maxSelectionCount = 1
    let onUploaded: (ProfilePhoto) async -> Void

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isUploading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: max(1, maxSelectionCount),
                matching: .images
            ) {
                pickerContent
            }
            .disabled(isUploading)
        }
        .onChange(of: selectedItems) { _, newItems in
            guard !newItems.isEmpty else { return }

            Task {
                await upload(items: newItems)
            }
        }
    }

    private var pickerContent: some View {
        VStack(spacing: 8) {
            if isUploading {
                ProgressView()
                    .tint(.pink)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "plus")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.pink)
                    .accessibilityHidden(true)
            }

            Text(pickerTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)

            Text(errorMessage ?? AppLanguageManager.localized("photoUpload.tapToChoose"))
                .font(.caption2.weight(.medium))
                .foregroundStyle(errorMessage == nil ? Color.secondary : Color.red)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(0.76, contentMode: .fit)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                .foregroundStyle(Color.pink.opacity(0.35))
                .accessibilityHidden(true)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(pickerAccessibilityLabel)
        .accessibilityValue(errorMessage ?? pickerAccessibilityValue)
    }

    private var pickerTitle: String {
        if isUploading {
            return AppLanguageManager.localized("photoUpload.uploading")
        }

        return slotNumber == 1 ? AppLanguageManager.localized("photoUpload.addPrimary") : AppLanguageManager.localized("photoUpload.addPhoto")
    }

    private var pickerAccessibilityLabel: String {
        String.localizedStringWithFormat(AppLanguageManager.localized("photoUpload.slot.accessibilityLabelFormat"), slotNumber)
    }

    private var pickerAccessibilityValue: String {
        isUploading ? AppLanguageManager.localized("photoUpload.uploading") : AppLanguageManager.localized("photoUpload.tapToChoose")
    }

    private func upload(items: [PhotosPickerItem]) async {
        isUploading = true
        errorMessage = nil

        do {
            for (index, item) in items.prefix(maxSelectionCount).enumerated() {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw NSError(domain: "PhotoUpload", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: AppLanguageManager.localized("photoUpload.error.readSelectedPhoto")
                    ])
                }

                let uploadedPhoto = try await ProfilePhotoService.shared.uploadProfilePhoto(
                    userId: userId,
                    imageData: data,
                    displayOrder: displayOrder + index
                )

                await onUploaded(uploadedPhoto)
            }

            selectedItems = []
        } catch {
            errorMessage = String.localizedStringWithFormat(AppLanguageManager.localized("photoUpload.error.uploadFailedFormat"), error.localizedDescription)
        }

        isUploading = false
    }
}
