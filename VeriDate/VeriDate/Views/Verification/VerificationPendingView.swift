import SwiftUI

struct VerificationPendingView: View {
    @EnvironmentObject var session: SessionViewModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 56))

            Text("Verification Pending")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Your account is under review. You can start matching after approval.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Refresh Status") {
                Task { await session.loadProfile() }
            }

            Button("Sign Out") {
                Task { await session.signOut() }
            }
            .foregroundStyle(.red)
        }
        .padding()
    }
}
