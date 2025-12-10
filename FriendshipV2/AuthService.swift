import Foundation
import AuthenticationServices
import Combine
import SwiftUI

@MainActor
final class AuthService: NSObject, ObservableObject {
    static let shared = AuthService()

    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var userDisplayName: String?
    
    // Store email temporarily for passkey authentication
    var pendingPasskeyEmail: String?

    private let backendBaseURL = URL(string: "https://dev3.augmego.com")!
    
    // API endpoints
    private var apiBaseURL: URL {
        backendBaseURL.appendingPathComponent("/api")
    }

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
    
    /// Begins a passkey sign-in by retrieving authentication options from the backend.
    /// - Parameter email: The user's email address to look up their passkeys
    /// - Returns: A tuple containing the challenge bytes and the relying party identifier
    func beginPasskeySignIn(email: String) async throws -> (challenge: Data, rpId: String) {
        // Get authentication options from the API
        let options = try await getPasskeyAuthenticationOptions(email: email)
        
        // Extract challenge (base64url encoded string) and decode it
        guard let challengeB64 = options["challenge"] as? String else {
            throw NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing challenge in API response"])
        }
        
        // Decode base64url challenge to Data
        guard let challengeData = Data(base64URLEncoded: challengeB64) else {
            throw NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid challenge format"])
        }
        
        // Extract rpId from the response, or derive from backend URL
        // The rpId should be just the domain (e.g., "dev3.augmego.com"), not the full URL
        let rpId: String
        if let rpIdFromResponse = options["rpId"] as? String {
            rpId = rpIdFromResponse
        } else {
            // Fallback to extracting domain from backend URL
            rpId = backendBaseURL.host ?? "dev3.augmego.com"
        }
        
        return (challenge: challengeData, rpId: rpId)
    }
    
    // Get authentication options for passkey sign in
    // Note: This requires the user's email to look up their passkeys
    func getPasskeyAuthenticationOptions(email: String) async throws -> [String: Any] {
        var request = URLRequest(url: apiBaseURL.appendingPathComponent("/passkeys/authenticate/options"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email], options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let errorMessage = errorData?[("error")] as? String ?? "Failed to get authentication options"
            throw NSError(domain: "AuthService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
        
        guard let options = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        return options
    }

    func completePasskeySignIn(email: String, assertion: ASAuthorizationPlatformPublicKeyCredentialAssertion) async throws {
        // Convert iOS assertion to SimpleWebAuthn format expected by the API
        let credentialId = assertion.credentialID.base64URLEncodedString()
        let clientDataJSON = assertion.rawClientDataJSON.base64URLEncodedString()
        let authenticatorData = assertion.rawAuthenticatorData?.base64URLEncodedString()
        let signature = assertion.signature?.base64URLEncodedString()
        let userHandle = assertion.userID.base64URLEncodedString()

        // Build authenticationResponse in SimpleWebAuthn format
        var responseDict: [String: Any] = [
            "clientDataJSON": clientDataJSON
        ]
        if let authenticatorData = authenticatorData {
            responseDict["authenticatorData"] = authenticatorData
        }
        if let signature = signature {
            responseDict["signature"] = signature
        }
        if !userHandle.isEmpty {
            responseDict["userHandle"] = userHandle
        }

        let authenticationResponse: [String: Any] = [
            "id": credentialId,
            "rawId": credentialId,
            "response": responseDict,
            "type": "public-key"
        ]

        let payload: [String: Any] = [
            "email": email,
            "authenticationResponse": authenticationResponse
        ]

        var request = URLRequest(url: apiBaseURL.appendingPathComponent("/passkeys/authenticate/verify"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let errorMessage = errorData?["error"] as? String ?? "Failed to verify passkey"
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "AuthService", code: statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
        
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        // The API now returns tokens in the response body for mobile clients
        if let token = obj?["token"] as? String {
            UserDefaults.standard.set(token, forKey: sessionTokenKey)
            isAuthenticated = true
            if let user = obj?["user"] as? [String: Any], let displayName = user["displayName"] as? String {
                userDisplayName = displayName
            }
        } else {
            throw URLError(.cannotParseResponse)
        }
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
                    // Prepare full name if available
                    var fullNameDict: [String: String]? = nil
                    if let fullName = credential.fullName {
                        var nameDict: [String: String] = [:]
                        if let given = fullName.givenName {
                            nameDict["givenName"] = given
                        }
                        if let family = fullName.familyName {
                            nameDict["familyName"] = family
                        }
                        if !nameDict.isEmpty {
                            fullNameDict = nameDict
                        }
                    }
                    
                    var body: [String: Any] = ["identityToken": identityToken]
                    if let fullNameDict = fullNameDict {
                        body["fullName"] = fullNameDict
                    }
                    
                    var request = URLRequest(url: apiBaseURL.appendingPathComponent("/auth/apple/verify"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                        let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        let errorMessage = errorData?["error"] as? String ?? "Authentication failed"
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                        print("Apple Sign In error (status: \(statusCode)): \(errorMessage)")
                        return
                    }
                    
                    let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    if let token = obj?["token"] as? String {
                        UserDefaults.standard.set(token, forKey: sessionTokenKey)
                        self.isAuthenticated = true
                        if let user = obj?["user"] as? [String: Any], let displayName = user["displayName"] as? String {
                            self.userDisplayName = displayName
                        } else if let fullName = credential.fullName, let given = fullName.givenName {
                            self.userDisplayName = given
                        }
                    }
                } catch {
                    print("Apple Sign In error: \(error.localizedDescription)")
                }
            }
        } else if let assertion = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
            // For passkey authentication, we need the user's email
            Task { @MainActor in
                guard let email = self.pendingPasskeyEmail else {
                    print("Passkey assertion received, but email is missing")
                    return
                }
                
                do {
                    try await self.completePasskeySignIn(email: email, assertion: assertion)
                    // Clear the pending email after successful authentication
                    self.pendingPasskeyEmail = nil
                } catch {
                    print("Passkey authentication failed: \(error.localizedDescription)")
                }
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

