import SwiftUI

struct AuthView: View {
    @EnvironmentObject var session: SessionViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false

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

                Button(isSignUp ? "Create Account" : "Sign In") {
                    Task {
                        if isSignUp {
                            await session.signUp(email: email, password: password)
                        } else {
                            await session.signIn(email: email, password: password)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)

                Button(isSignUp ? "Already have an account? Sign in" : "New here? Create account") {
                    isSignUp.toggle()
                }
                .font(.footnote)

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
