import Foundation
import PostgREST
import Supabase

final class ProfilePromptService {
    static let shared = ProfilePromptService()
    private let supabase = SupabaseManager.shared.client

    private init() {}

    func loadProfilePrompts(userId: UUID) async throws -> [ProfilePrompt] {
        try await supabase
            .from("profile_prompts")
            .select()
            .eq("user_id", value: userId)
            .order("display_order", ascending: true)
            .execute()
            .value
    }

    func saveProfilePrompts(userId: UUID, prompts: [ProfilePrompt]) async throws {
        struct InsertPrompt: Encodable {
            let id: UUID
            let user_id: UUID
            let prompt: String
            let answer: String
            let display_order: Int
        }

        try await supabase
            .from("profile_prompts")
            .delete()
            .eq("user_id", value: userId)
            .execute()

        let cleanedPrompts = prompts
            .map { prompt in
                ProfilePrompt(
                    id: prompt.id,
                    userId: userId,
                    prompt: prompt.prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                    answer: prompt.answer.trimmingCharacters(in: .whitespacesAndNewlines),
                    displayOrder: prompt.displayOrder,
                    createdAt: prompt.createdAt,
                    updatedAt: prompt.updatedAt
                )
            }
            .filter { !$0.prompt.isEmpty && !$0.answer.isEmpty }
            .prefix(3)

        let payloads = cleanedPrompts.enumerated().map { index, prompt in
            InsertPrompt(
                id: prompt.id,
                user_id: userId,
                prompt: prompt.prompt,
                answer: prompt.answer,
                display_order: index
            )
        }

        guard !payloads.isEmpty else { return }

        try await supabase
            .from("profile_prompts")
            .insert(payloads)
            .execute()
    }
}

