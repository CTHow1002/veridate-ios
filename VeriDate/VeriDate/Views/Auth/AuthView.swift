import SwiftUI

struct AuthView: View {
    @EnvironmentObject var session: SessionViewModel
    @State private var step: AuthStep = .chooseMethod
    @State private var selectedMethod: LoginMethod = .phone
    @State private var phoneNumber = ""
    @State private var otpCode = ""
    @State private var isWorking = false
    @State private var localMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    header

                    switch step {
                    case .chooseMethod:
                        loginMethodCard
                    case .phoneOtp:
                        otpCard
                    }

                    if let message = localMessage ?? session.errorMessage {
                        Text(message)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 18)
                            .accessibilityLabel(message)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 22)
                .padding(.top, 42)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 46, weight: .bold))
                .foregroundStyle(.pink)
                .frame(width: 76, height: 76)
                .background(Color.pink.opacity(0.10), in: Circle())
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("VeriDate")
                    .font(.largeTitle.weight(.bold))

                Text(AppLanguageManager.localized("auth_header_subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var loginMethodCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(AppLanguageManager.localized("auth_login_with_title"))
                .font(.title3.weight(.bold))

            VStack(spacing: 10) {
                loginButton(
                    method: .phone,
                    subtitle: AppLanguageManager.localized("auth_phone_login_subtitle")
                ) {
                    selectedMethod = .phone
                    localMessage = nil
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        step = .phoneOtp
                    }
                }

                loginButton(
                    method: .apple,
                    subtitle: AppLanguageManager.localized("auth_apple_login_subtitle")
                ) {
                    beginSocialPlaceholder(.apple)
                }

                loginButton(
                    method: .google,
                    subtitle: AppLanguageManager.localized("auth_google_login_subtitle")
                ) {
                    beginSocialPlaceholder(.google)
                }
            }

            Text(AppLanguageManager.localized("auth_first_time_note"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 16, y: 8)
        .accessibilityElement(children: .contain)
    }

    private var otpCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                HapticManager.light()
                localMessage = nil
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                    step = .chooseMethod
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .accessibilityHidden(true)
                    Text(AppLanguageManager.localized("common_back"))
                }
                .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLanguageManager.localized("common_back"))
            .disabled(isWorking)

            VStack(alignment: .leading, spacing: 6) {
                Text(AppLanguageManager.localized("auth_verify_phone_title"))
                    .font(.title3.weight(.bold))

                Text(otpSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            TextField(AppLanguageManager.localized("auth_phone_number_placeholder"), text: $phoneNumber)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .font(.body.weight(.semibold))
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityLabel(AppLanguageManager.localized("auth_phone_number_placeholder"))
                .disabled(isWorking)

            TextField(AppLanguageManager.localized("auth_otp_code_placeholder"), text: $otpCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.title3.weight(.bold))
                .tracking(4)
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityLabel(AppLanguageManager.localized("auth_otp_code_placeholder"))
                .disabled(isWorking)

            Text(AppLanguageManager.localized("auth_demo_otp_note"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Button {
                Task {
                    await verifyOtpAndContinue()
                }
            } label: {
                HStack {
                    if isWorking {
                        ProgressView()
                            .tint(.white)
                            .accessibilityHidden(true)
                    } else {
                        Text(AppLanguageManager.localized("auth_verify_continue_button"))
                            .font(.headline.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.pink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isWorking ? AppLanguageManager.localized("auth_verifying_button") : AppLanguageManager.localized("auth_verify_continue_button"))
            .disabled(isWorking)
        }
        .padding(18)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 16, y: 8)
        .accessibilityElement(children: .contain)
    }

    private var otpSubtitle: String {
        switch selectedMethod {
        case .phone:
            return AppLanguageManager.localized("auth_phone_otp_subtitle")
        case .apple:
            return AppLanguageManager.localized("auth_apple_otp_subtitle")
        case .google:
            return AppLanguageManager.localized("auth_google_otp_subtitle")
        }
    }

    private func loginButton(method: LoginMethod, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: method.icon)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(method.tint)
                    .frame(width: 42, height: 42)
                    .background(method.tint.opacity(0.10), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(method.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(13)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(method.title)
        .accessibilityValue(subtitle)
        .accessibilityAddTraits(.isButton)
        .disabled(isWorking)
    }

    private func beginSocialPlaceholder(_ method: LoginMethod) {
        selectedMethod = method
        localMessage = String.localizedStringWithFormat(
            AppLanguageManager.localized("auth_social_placeholder_message_format"),
            method.title
        )
        HapticManager.light()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            step = .phoneOtp
        }
    }

    @MainActor
    private func verifyOtpAndContinue() async {
        localMessage = nil
        session.errorMessage = nil

        let trimmedPhone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPhone.isEmpty else {
            localMessage = AppLanguageManager.localized("auth_enter_phone_error")
            HapticManager.warning()
            return
        }

        guard otpCode.trimmingCharacters(in: .whitespacesAndNewlines) == "123456" else {
            localMessage = AppLanguageManager.localized("auth_invalid_demo_otp_error")
            HapticManager.warning()
            return
        }

        isWorking = true
        defer { isWorking = false }

        let didContinue = await session.signInOrCreateRoughLoginAccount(
            identifier: trimmedPhone,
            source: selectedMethod.rawValue
        )

        if didContinue {
            HapticManager.success()
        } else {
            HapticManager.warning()
        }
    }
}

private enum AuthStep {
    case chooseMethod
    case phoneOtp
}

private enum LoginMethod: String {
    case phone
    case apple
    case google

    var title: String {
        switch self {
        case .phone:
            return AppLanguageManager.localized("auth_phone_method_title")
        case .apple:
            return AppLanguageManager.localized("auth_apple_method_title")
        case .google:
            return AppLanguageManager.localized("auth_google_method_title")
        }
    }

    var icon: String {
        switch self {
        case .phone:
            return "phone.fill"
        case .apple:
            return "apple.logo"
        case .google:
            return "g.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .phone:
            return .pink
        case .apple:
            return .primary
        case .google:
            return .blue
        }
    }
}
