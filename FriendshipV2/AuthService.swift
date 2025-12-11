//
//  AuthService.swift
//  FriendshipV2
//
//  Minimal, production-ready Sign in with Apple implementation
//

import Foundation
import AuthenticationServices
import Combine
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Main authentication service handling Sign in with Apple
@MainActor
final class AuthService: NSObject, ObservableObject {
    static let shared = AuthService()

    // MARK: - Published Properties
    
    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var userDisplayName: String?

    // MARK: - Private Properties
    
    // Use dev3.augmego.com if augmego.com has certificate issues
    // TODO: Fix SSL certificate for augmego.com and switch back
    private let backendBaseURL = URL(string: "https://dev3.augmego.com")!
    private let sessionTokenKey = "AuthService.sessionToken"
    private let refreshTokenKey = "AuthService.refreshToken"
    private let appleUserIdKey = "AuthService.appleUserId"
    private var isRefreshing = false
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        // Check for existing session on init
        checkExistingSession()
    }
    
    // MARK: - Public API
    
    /// Signs out the current user
    func signOut() {
        UserDefaults.standard.removeObject(forKey: sessionTokenKey)
        UserDefaults.standard.removeObject(forKey: refreshTokenKey)
        UserDefaults.standard.removeObject(forKey: appleUserIdKey)
        isAuthenticated = false
        userDisplayName = nil
    }
    
    /// Gets the current access token
    func getAccessToken() -> String? {
        return UserDefaults.standard.string(forKey: sessionTokenKey)
    }
    
    /// Refreshes the access token using the stored refresh token
    /// Returns true if refresh was successful, false otherwise
    func refreshAccessToken() async -> Bool {
        // Prevent concurrent refresh attempts
        guard !isRefreshing else {
            // Wait for the ongoing refresh to complete
            while isRefreshing {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
            return UserDefaults.standard.string(forKey: sessionTokenKey) != nil
        }
        
        guard let refreshToken = UserDefaults.standard.string(forKey: refreshTokenKey),
              !refreshToken.isEmpty else {
            print("❌ No refresh token available")
            // If no refresh token, user needs to sign in again
            signOut()
            return false
        }
        
        isRefreshing = true
        defer { isRefreshing = false }
        
        do {
            let url = backendBaseURL.appendingPathComponent("/api/auth/refresh")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Send refresh token in request body (more reliable for iOS)
            let body: [String: Any] = ["refreshToken": refreshToken]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            // Also send in Cookie header as fallback
            request.setValue("refresh=\(refreshToken)", forHTTPHeaderField: "Cookie")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }
            
            guard (200..<300).contains(httpResponse.statusCode) else {
                // If refresh fails, user needs to sign in again
                print("❌ Token refresh failed with status: \(httpResponse.statusCode)")
                signOut()
                return false
            }
            
            // Try to get token from response body first (preferred for iOS)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = json["token"] as? String {
                UserDefaults.standard.set(token, forKey: sessionTokenKey)
                print("✅ Token refreshed successfully (from body)")
                return true
            }
            
            // Fallback: Extract the new JWT token from the Set-Cookie header
            if let setCookieHeader = httpResponse.value(forHTTPHeaderField: "Set-Cookie") {
                // Parse the cookie string to extract the jwt value
                let cookies = setCookieHeader.components(separatedBy: ";")
                for cookie in cookies {
                    let parts = cookie.trimmingCharacters(in: .whitespaces).components(separatedBy: "=")
                    if parts.count == 2 && parts[0].trimmingCharacters(in: .whitespaces) == "jwt" {
                        let newToken = parts[1].trimmingCharacters(in: .whitespaces)
                        UserDefaults.standard.set(newToken, forKey: sessionTokenKey)
                        print("✅ Token refreshed successfully (from cookie header)")
                        return true
                    }
                }
            }
            
            throw AuthError.invalidResponse
        } catch {
            print("❌ Token refresh error: \(error.localizedDescription)")
            signOut()
            return false
        }
    }
    
    /// Makes an authenticated request, automatically refreshing the token if needed
    /// Returns the response data and HTTP response
    func makeAuthenticatedRequest(url: URL, method: String = "GET", body: Data? = nil, headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        // Try the request first
        var request = URLRequest(url: url)
        request.httpMethod = method
        
        // Set default headers
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Add authentication
        if let token = getAccessToken() {
            request.setValue("jwt=\(token)", forHTTPHeaderField: "Cookie")
        }
        
        if let body = body {
            request.httpBody = body
            if !headers.keys.contains("Content-Type") {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        
        // If we get a 401, try refreshing the token and retry once
        if httpResponse.statusCode == 401 {
            print("⚠️ Received 401, attempting token refresh...")
            let refreshed = await refreshAccessToken()
            
            if refreshed, let newToken = getAccessToken() {
                // Retry the request with the new token
                var retryRequest = URLRequest(url: url)
                retryRequest.httpMethod = method
                
                for (key, value) in headers {
                    retryRequest.setValue(value, forHTTPHeaderField: key)
                }
                
                retryRequest.setValue("jwt=\(newToken)", forHTTPHeaderField: "Cookie")
                
                if let body = body {
                    retryRequest.httpBody = body
                    if !headers.keys.contains("Content-Type") {
                        retryRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    }
                }
                
                let (retryData, retryResponse) = try await URLSession.shared.data(for: retryRequest)
                
                guard let retryHttpResponse = retryResponse as? HTTPURLResponse else {
                    throw AuthError.invalidResponse
                }
                
                return (retryData, retryHttpResponse)
            } else {
                // Refresh failed, user needs to sign in again
                throw AuthError.backendError(message: "Authentication expired. Please sign in again.", statusCode: 401)
            }
        }
        
        return (data, httpResponse)
    }
    
    /// Initiates Sign in with Apple flow
    func signInWithApple() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }
    
    /// Attempts silent sign-in using stored Apple user ID
    /// Returns true if user is still authorized, false otherwise
    func attemptSilentSignIn() async -> Bool {
        guard let appleUserId = UserDefaults.standard.string(forKey: appleUserIdKey),
              !appleUserId.isEmpty else {
            return false
        }
        
        let provider = ASAuthorizationAppleIDProvider()
        
        do {
            let credentialState = try await provider.credentialState(forUserID: appleUserId)
            
            switch credentialState {
            case .authorized:
                // User is still authorized, check if we have a valid session token
                if let token = UserDefaults.standard.string(forKey: sessionTokenKey), !token.isEmpty {
                    // Verify token is still valid by making a request to the backend
                    // For now, we'll assume the token is valid if it exists
                    // In production, you might want to verify it with the backend
                    isAuthenticated = true
                    return true
                }
                return false
            case .revoked, .notFound:
                // User has revoked authorization or account not found
                signOut()
                return false
            case .transferred:
                // Account was transferred to another device
                signOut()
                return false
            @unknown default:
                return false
            }
        } catch {
            // If credential state check fails, sign out for safety
            print("Failed to check credential state: \(error.localizedDescription)")
            signOut()
            return false
        }
    }
    
    // MARK: - Private Methods
    
    /// Checks for existing session on app launch
    private func checkExistingSession() {
        if let token = UserDefaults.standard.string(forKey: sessionTokenKey), !token.isEmpty {
            isAuthenticated = true
            // Attempt silent sign-in to verify credential state
            Task {
                let stillAuthorized = await attemptSilentSignIn()
                // If user is still authorized but token might be expired, try refreshing
                if stillAuthorized {
                    // Try to refresh token proactively
                    _ = await refreshAccessToken()
                }
            }
        }
    }
    
    /// Sends authentication request to backend
    private func authenticateWithBackend(userId: String, identityToken: String) async throws {
        let url = backendBaseURL.appendingPathComponent("/api/auth/apple")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "userId": userId,
            "identityToken": identityToken
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let errorMessage = errorData?["error"] as? String ?? "Authentication failed"
            throw AuthError.backendError(message: errorMessage, statusCode: httpResponse.statusCode)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let token = json?["token"] as? String else {
            throw AuthError.invalidResponse
        }
        
        // Store session token, refresh token, and user ID
        UserDefaults.standard.set(token, forKey: sessionTokenKey)
        
        // Store refresh token if provided
        if let refreshToken = json?["refreshToken"] as? String {
            UserDefaults.standard.set(refreshToken, forKey: refreshTokenKey)
        }
        
        UserDefaults.standard.set(userId, forKey: appleUserIdKey)
        
        // Update user info if available
        if let user = json?["user"] as? [String: Any],
           let displayName = user["displayName"] as? String {
            userDisplayName = displayName
        }
        
        isAuthenticated = true
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthService: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            return
        }
        
        // Extract required values
        let userId = credential.user
        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            print("❌ Failed to extract identity token")
            return
        }
        
        // Handle authentication with backend
        Task { @MainActor in
            do {
                try await authenticateWithBackend(userId: userId, identityToken: identityToken)
            } catch {
                print("❌ Authentication failed: \(error.localizedDescription)")
                // In production, you might want to show an error to the user
            }
        }
    }
    
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        if let authError = error as? ASAuthorizationError {
            switch authError.code {
            case .canceled:
                print("ℹ️ User canceled Sign in with Apple")
            case .failed:
                print("❌ Sign in with Apple failed")
            case .invalidResponse:
                print("❌ Invalid response from Apple")
            case .notHandled:
                print("❌ Sign in with Apple not handled")
            case .unknown:
                print("❌ Unknown error during Sign in with Apple")
                // Check for specific error codes that indicate configuration issues
                if let nsError = error as NSError? {
                    print("   Error domain: \(nsError.domain)")
                    print("   Error code: \(nsError.code)")
                    if nsError.userInfo["AKClientBundleID"] != nil {
                        print("   ⚠️ Configuration Error: Sign in with Apple is not properly configured")
                        print("   📋 Please ensure:")
                        print("      1. 'Sign in with Apple' capability is added in Xcode (Signing & Capabilities)")
                        print("      2. App ID has 'Sign in with Apple' enabled in Apple Developer Portal")
                        print("      3. You're testing on a physical device (not simulator)")
                        print("      4. Your provisioning profile includes the capability")
                    }
                }
            @unknown default:
                print("❌ Unknown error code: \(authError.code.rawValue)")
            }
        } else if let nsError = error as NSError? {
            // Check for AKAuthenticationError (error -7026)
            if nsError.domain == "com.apple.AuthenticationServices.AuthorizationError" || 
               (nsError.domain.contains("AK") && nsError.code == -7026) {
                print("❌ Sign in with Apple Configuration Error (-7026)")
                print("   This error means Sign in with Apple is not configured for your app.")
                print("   📋 Required steps:")
                print("      1. In Xcode: Target → Signing & Capabilities → + Capability → 'Sign in with Apple'")
                print("      2. In Apple Developer Portal: Enable 'Sign in with Apple' for App ID: com.Augmego.FriendshipV2")
                print("      3. Wait 5-10 minutes for changes to propagate")
                print("      4. Clean build folder (Cmd+Shift+K) and rebuild")
                print("      5. Test on a PHYSICAL DEVICE (simulator has known issues)")
            } else {
                print("❌ Sign in with Apple error: \(error.localizedDescription)")
                print("   Domain: \((error as NSError).domain)")
                print("   Code: \((error as NSError).code)")
            }
        } else {
            print("❌ Sign in with Apple error: \(error.localizedDescription)")
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AuthService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if canImport(UIKit)
        // Find the key window for presentation
        if let keyWindow = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) {
            return keyWindow
        }
        
        // Fallback to any available window scene
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first {
            return UIWindow(windowScene: windowScene)
        }
        #endif
        
        // Last resort - return a minimal anchor
        // This should work on iOS/macOS
        return ASPresentationAnchor()
    }
}

// MARK: - AuthError

enum AuthError: LocalizedError {
    case invalidResponse
    case backendError(message: String, statusCode: Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .backendError(let message, let statusCode):
            return "Server error (\(statusCode)): \(message)"
        }
    }
}

