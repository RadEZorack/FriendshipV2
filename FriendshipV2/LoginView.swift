import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @ObservedObject private var auth = AuthService.shared
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var emailForPasskey: String = ""
    @State private var showEmailInput = false

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
                .frame(maxWidth: 375, minHeight: 50, maxHeight: 50)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onTapGesture {
                    auth.startSignInWithApple()
                }

                Button(action: {
                    showEmailInput = true
                }) {
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
                .sheet(isPresented: $showEmailInput) {
                    NavigationView {
                        VStack(spacing: 20) {
                            Text("Enter your email to sign in with a passkey")
                                .font(.headline)
                                .padding()
                            
                            TextField("Email", text: $emailForPasskey)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .padding(.horizontal)
                            
                            Button("Continue") {
                                if !emailForPasskey.isEmpty {
                                    showEmailInput = false
                                    startPasskeySignIn(email: emailForPasskey)
                                    emailForPasskey = ""
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(emailForPasskey.isEmpty)
                            .padding()
                            
                            Spacer()
                        }
                        .padding()
                        .navigationTitle("Passkey Sign In")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Cancel") {
                                    showEmailInput = false
                                    emailForPasskey = ""
                                }
                            }
                        }
                    }
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
        .overlay(alignment: .bottom) {
            if isWorking { ProgressView().padding(.bottom, 32) }
        }
    }

    private func startPasskeySignIn(email: String) {
        // Capture the observed object into a strong reference so we don't interact with the property wrapper inside Task
        let authService = auth
        errorMessage = nil
        Task { @MainActor in
            isWorking = true
            defer { isWorking = false }
            do {
                // Store email for use in delegate callback
                authService.pendingPasskeyEmail = email
                
                let (challenge, rpId, allowedCredentialIDs) = try await authService.beginPasskeySignIn(email: email)
                
                print("🔐 Creating passkey assertion request:")
                print("   rpId: \(rpId)")
                print("   challenge length: \(challenge.count) bytes")
                print("   allowed credentials count: \(allowedCredentialIDs.count)")
                
                let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpId)
                let assertionRequest = provider.createCredentialAssertionRequest(challenge: challenge)
                
                // Set allowed credential IDs if provided
                if !allowedCredentialIDs.isEmpty {
                    let descriptors = allowedCredentialIDs.map { credentialID in
                        ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: credentialID)
                    }
                    assertionRequest.allowedCredentials = descriptors
                    print("   ✅ Set \(descriptors.count) allowed credential descriptors")
                } else {
                    print("   ⚠️ No allowed credentials - using discovery mode")
                }
                
                // Set user verification preference
                assertionRequest.userVerificationPreference = .preferred
                
                print("   ✅ Request configured, performing authorization...")

                let controller = ASAuthorizationController(authorizationRequests: [assertionRequest])
                controller.delegate = authService
                controller.presentationContextProvider = authService
                controller.performRequests()
            } catch {
                print("❌ Error starting passkey sign-in: \(error)")
                errorMessage = "Passkey sign-in failed: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    LoginView()
}
