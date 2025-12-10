import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @StateObject private var auth = AuthService.shared
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Welcome")
                .font(.largeTitle).bold()

            VStack(spacing: 12) {
                SignInWithAppleButton(.signIn, onRequest: { request in
                    // Configure here if needed; actual perform is in AuthService
                }, onCompletion: { _ in
                    // Handled via AuthService delegate
                })
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onTapGesture {
                    auth.startSignInWithApple()
                }

                Button(action: startPasskeySignIn) {
                    HStack {
                        Image(systemName: "key.fill")
                        Text("Sign in with Passkey")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isWorking)
            }
            .padding(.horizontal)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .overlay(alignment: .bottom) {
            if isWorking { ProgressView().padding(.bottom, 32) }
        }
    }

    private func startPasskeySignIn() {
        Task { @MainActor in
            isWorking = true
            defer { isWorking = false }
            do {
                let (challenge, rpId) = try await auth.beginPasskeySignIn()
                let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpId)
                let assertionRequest = provider.createCredentialAssertionRequest(challenge: challenge)

                let controller = ASAuthorizationController(authorizationRequests: [assertionRequest])
                controller.delegate = auth
                controller.presentationContextProvider = auth
                controller.performRequests()
            } catch {
                errorMessage = "Passkey sign-in failed to start."
            }
        }
    }
}

#Preview {
    LoginView()
}
