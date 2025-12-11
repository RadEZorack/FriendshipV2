import SwiftUI
import AuthenticationServices

/// Minimal Sign in with Apple login view
struct LoginView: View {
    @ObservedObject private var auth = AuthService.shared
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Text("Welcome")
                .font(.largeTitle)
                .bold()
            
            VStack(spacing: 16) {
                SignInWithAppleButton(.signIn, onRequest: { request in
                    // Request email and full name on first login
                    request.requestedScopes = [.fullName, .email]
                }, onCompletion: { result in
                    // Handled via AuthService delegate
                    if case .failure(let error) = result {
                        errorMessage = "Sign in failed: \(error.localizedDescription)"
                    }
                })
                .signInWithAppleButtonStyle(.black)
                .frame(maxWidth: 375, minHeight: 50, maxHeight: 50)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onTapGesture {
                    errorMessage = nil
                    auth.signInWithApple()
                }
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
    }
}

#Preview {
    LoginView()
}
