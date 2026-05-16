import SwiftUI

struct ProfilePromptDisplayView: View {
    let prompts: [ProfilePrompt]

    var body: some View {
        if !prompts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppLanguageManager.localized("profile.prompts.title"))
                    .font(.headline)

                ForEach(prompts) { prompt in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(LocalizedProfileDisplay.option(prompt.prompt))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text(prompt.answer)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }
}
