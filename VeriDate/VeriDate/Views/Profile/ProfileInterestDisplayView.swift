import SwiftUI

struct ProfileInterestDisplayView: View {
    let interests: [String]

    var body: some View {
        if !interests.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppLanguageManager.localized("profile.interests.title"))
                    .font(.headline)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(interests, id: \.self) { interest in
                        Text(LocalizedProfileDisplay.option(interest))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.secondarySystemBackground), in: Capsule())
                    }
                }
            }
        }
    }
}
