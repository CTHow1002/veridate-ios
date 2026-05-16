import Foundation
import Supabase
import PostgREST
import UIKit

final class ProfilePhotoService {
    static let shared = ProfilePhotoService()
    private let supabase = SupabaseManager.shared.client
    private let signedURLCache = NSCache<NSString, NSURL>()
    private let imageCache = NSCache<NSString, UIImage>()

    private init() {}

    func uploadProfilePhoto(
        userId: UUID,
        imageData: Data,
        displayOrder: Int
    ) async throws -> ProfilePhoto {
        let fileName = "\(userId.uuidString)/\(UUID().uuidString).jpg"

        try await supabase.storage
            .from("profile-photos")
            .upload(
                fileName,
                data: imageData,
                options: FileOptions(contentType: "image/jpeg")
            )

        struct InsertPayload: Encodable {
            let user_id: UUID
            let photo_path: String
            let display_order: Int
        }

        let insertedPhoto: ProfilePhoto = try await supabase
            .from("profile_photos")
            .insert(
                InsertPayload(
                    user_id: userId,
                    photo_path: fileName,
                    display_order: displayOrder
                )
            )
            .select()
            .single()
            .execute()
            .value

        if displayOrder == 0 {
            struct UpdateProfile: Encodable {
                let profile_photo_url: String
            }

            try await supabase
                .from("profiles")
                .update(UpdateProfile(profile_photo_url: fileName))
                .eq("id", value: userId)
                .execute()
        }

        if let image = UIImage(data: imageData) {
            imageCache.setObject(image, forKey: fileName as NSString)
        }

        return insertedPhoto
    }

    func fetchPhotos(userId: UUID) async throws -> [ProfilePhoto] {
        let photos: [ProfilePhoto] = try await supabase
            .from("profile_photos")
            .select()
            .eq("user_id", value: userId)
            .order("display_order", ascending: true)
            .execute()
            .value

        return photos
    }

    func savePhotoOrder(userId: UUID, orderedPhotos: [ProfilePhoto]) async throws -> [ProfilePhoto] {
        guard !orderedPhotos.isEmpty else { return [] }

        struct PhotoOrderUpdatePayload: Encodable {
            let display_order: Int
        }

        for (index, photo) in orderedPhotos.enumerated() {
            let updatedRows: [ProfilePhoto] = try await supabase
                .from("profile_photos")
                .update(PhotoOrderUpdatePayload(display_order: 1_000 + index))
                .eq("id", value: photo.id)
                .eq("user_id", value: userId)
                .select()
                .execute()
                .value

            guard updatedRows.count == 1 else {
                throw NSError(domain: "ProfilePhotoService", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Could not update photo order. Please check the profile_photos update policy in Supabase."
                ])
            }
        }

        var savedRows: [ProfilePhoto] = []

        for (index, photo) in orderedPhotos.enumerated() {
            let updatedRows: [ProfilePhoto] = try await supabase
                .from("profile_photos")
                .update(PhotoOrderUpdatePayload(display_order: index))
                .eq("id", value: photo.id)
                .eq("user_id", value: userId)
                .select()
                .execute()
                .value

            guard updatedRows.count == 1 else {
                throw NSError(domain: "ProfilePhotoService", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Could not save photo order. Please check the profile_photos update policy in Supabase."
                ])
            }

            savedRows.append(updatedRows[0])
        }

        return savedRows.sorted { lhs, rhs in
            if lhs.displayOrder == rhs.displayOrder {
                return lhs.id.uuidString < rhs.id.uuidString
            }

            return lhs.displayOrder < rhs.displayOrder
        }
    }

    func deletePhoto(photo: ProfilePhoto) async throws {
        try await supabase.storage
            .from("profile-photos")
            .remove(paths: [photo.photoPath])

        try await supabase
            .from("profile_photos")
            .delete()
            .eq("id", value: photo.id)
            .execute()

        signedURLCache.removeObject(forKey: photo.photoPath as NSString)
        imageCache.removeObject(forKey: photo.photoPath as NSString)
    }

    func signedURL(for path: String) async throws -> URL {
        if let cachedURL = signedURLCache.object(forKey: path as NSString) {
            return cachedURL as URL
        }

        let signedURL = try await supabase.storage
            .from("profile-photos")
            .createSignedURL(path: path, expiresIn: 3600)

        signedURLCache.setObject(signedURL as NSURL, forKey: path as NSString)
        return signedURL
    }

    func cachedImage(for path: String) -> UIImage? {
        imageCache.object(forKey: path as NSString)
    }

    func clearCache() {
        signedURLCache.removeAllObjects()
        imageCache.removeAllObjects()
    }

    func image(for path: String) async throws -> UIImage {
        if let cachedImage = imageCache.object(forKey: path as NSString) {
            return cachedImage
        }

        let url = try await signedURL(for: path)
        let (data, _) = try await URLSession.shared.data(from: url)

        guard let image = UIImage(data: data) else {
            throw NSError(domain: "ProfilePhotoService", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Could not decode profile photo."
            ])
        }

        imageCache.setObject(image, forKey: path as NSString)
        return image
    }

    func preloadImages(for paths: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for path in paths where !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                group.addTask {
                    _ = try? await self.image(for: path)
                }
            }
        }
    }
}
