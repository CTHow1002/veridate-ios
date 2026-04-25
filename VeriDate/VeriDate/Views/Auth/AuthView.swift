import SwiftUI

struct AuthView: View {
    @EnvironmentObject var session: SessionViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("VeriDate")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Strictly verified dating for serious people.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .textFieldStyle(.roundedBorder)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task {
                        isWorking = true
                        defer { isWorking = false }

                        if isSignUp {
                            await session.signUp(email: email, password: password)
                        } else {
                            await session.signIn(email: email, password: password)
                        }
                    }
                } label: {
                    if isWorking {
                        ProgressView()
                    } else {
                        Text(isSignUp ? "Create Account" : "Sign In")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking)

                Button(isSignUp ? "Already have an account? Sign in" : "New here? Create account") {
                    isSignUp.toggle()
                }
                .font(.footnote)
                .disabled(isWorking)

                if let error = session.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
    }
}
