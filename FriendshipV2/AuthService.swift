import Foundation
import AuthenticationServices
import Combine
import SwiftUI

@MainActor
final class AuthService: NSObject, ObservableObject {
    static let shared = AuthService()

    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var userDisplayName: String?

    private let backendBaseURL = URL(string: "https://dev3.augmego.com")!

    // Persist a simple session token (you can replace with Keychain as needed)
    private let sessionTokenKey = "AuthService.sessionToken"

    private override init() {
        super.init()
        if let token = UserDefaults.standard.string(forKey: sessionTokenKey), !token.isEmpty {
            isAuthenticated = true
        }
    }

    // MARK: - Public API

    func signOut() {
        UserDefaults.standard.removeObject(forKey: sessionTokenKey)
        isAuthenticated = false
        userDisplayName = nil
    }

    // MARK: - Sign in with Apple

    func startSignInWithApple() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    // MARK: - Passkey Sign In (WebAuthn)

    // This is a simplified flow: begin -> complete
    func beginPasskeySignIn() async throws -> (challenge: Data, rpId: String) {
        // Placeholder endpoint: POST /passkeys/begin
        var request = URLRequest(url: backendBaseURL.appendingPathComponent("/passkeys/begin"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["purpose": "signIn"], options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        // Expecting JSON: { challenge: base64url, rpId: string }
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let challengeB64 = obj?["challenge"] as? String,
              let rpId = obj?["rpId"] as? String,
              let challengeData = Data(base64URLEncoded: challengeB64) else {
            throw URLError(.cannotParseResponse)
        }
        return (challengeData, rpId)
    }

    func completePasskeySignIn(assertion: ASAuthorizationPlatformPublicKeyCredentialAssertion) async throws {
        // Build payload to send to server for verification
        // Convert raw data to base64url strings
        let clientDataJSON = assertion.rawClientDataJSON.base64URLEncodedString()
        let authenticatorData = assertion.rawAuthenticatorData?.base64URLEncodedString()
        let signature = assertion.signature?.base64URLEncodedString()
        let userHandle = assertion.userID.base64URLEncodedString()
        let credentialId = assertion.credentialID.base64URLEncodedString()

        let payload: [String: Any?] = [
            "clientDataJSON": clientDataJSON,
            "authenticatorData": authenticatorData,
            "signature": signature,
            "userHandle": userHandle,
            "credentialId": credentialId
        ]

        var request = URLRequest(url: backendBaseURL.appendingPathComponent("/passkeys/complete"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload.compactMapValues { $0 }, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let token = obj?["token"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        UserDefaults.standard.set(token, forKey: sessionTokenKey)
        isAuthenticated = true
    }
}

// MARK: - ASAuthorizationControllerDelegate & Presentation

extension AuthService: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
            // Send identityToken to backend for validation and session issuance
            guard let identityTokenData = credential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8) else {
                return
            }
            Task { @MainActor in
                do {
                    var request = URLRequest(url: backendBaseURL.appendingPathComponent("/auth/apple"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    let body: [String: Any] = ["identityToken": identityToken]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        return
                    }
                    let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    if let token = obj?["token"] as? String {
                        UserDefaults.standard.set(token, forKey: sessionTokenKey)
                        self.isAuthenticated = true
                        if let fullName = credential.fullName, let given = fullName.givenName {
                            self.userDisplayName = given
                        }
                    }
                } catch {
                    // Handle error as needed
                }
            }
        } else if let assertion = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
            Task {
                try? await self.completePasskeySignIn(assertion: assertion)
            }
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        // Handle errors from AppleID or Passkey flows
    }
}

extension AuthService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Prefer the current key window if available
        if let keyWindow = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) {
            return keyWindow
        }

        // Find a foreground (or inactive) window scene to construct an anchor window from
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }) {
            // Create a temporary window tied to this scene. Do not show it; just use it as the anchor.
            let tempWindow = UIWindow(windowScene: windowScene)
            return tempWindow
        }

        // As a last resort, use any available window scene
        if let anyScene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            let tempWindow = UIWindow(windowScene: anyScene)
            return tempWindow
        }

        // If no scenes are available, this is an unexpected state on iOS 26+. Assert in debug and return a minimal anchor.
        assertionFailure("No UIWindowScene available for presentation anchor")
        // Return a plain ASPresentationAnchor() is permitted but should rarely happen.
        return ASPresentationAnchor()
    }
}

// MARK: - Utilities

private extension Data {
    func base64URLEncodedString() -> String {
        let b64 = self.base64EncodedString()
        return b64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension Data {
    init?(base64URLEncoded: String) {
        var s = base64URLEncoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = 4 - (s.count % 4)
        if padding < 4 { s += String(repeating: "=", count: padding) }
        guard let data = Data(base64Encoded: s) else { return nil }
        self = data
    }
}

