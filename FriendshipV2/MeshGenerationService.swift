//
//  MeshGenerationService.swift
//  FriendshipV2
//
//  Created by Travis Miller on 2025-12-08.
//

import Foundation
import Combine

/// Service for managing avatar/mesh generation
@MainActor
final class MeshGenerationService: ObservableObject {
    static let shared = MeshGenerationService()
    
    // MARK: - Published Properties
    
    @Published private(set) var currentMesh: MeshStatus?
    @Published private(set) var userAvatars: [MeshStatus] = []
    @Published private(set) var isGenerating: Bool = false
    @Published private(set) var error: String?
    
    // MARK: - Private Properties
    
    private let backendBaseURL = URL(string: "https://dev3.augmego.com")!
    private var pollingTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var pollingStartTime: Date?
    private let maxPollingDuration: TimeInterval = 30 * 60 // 30 minutes
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public API
    
    /// Generates a new avatar from a prompt
    func generateAvatar(prompt: String) async throws {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MeshError.invalidPrompt
        }
        
        isGenerating = true
        error = nil
        
        // Use authenticated request helper which handles token refresh automatically
        let url = backendBaseURL.appendingPathComponent("/api/v1/meshy/generate")
        let body: [String: Any] = ["prompt": prompt.trimmingCharacters(in: .whitespacesAndNewlines)]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        
        let (data, httpResponse) = try await AuthService.shared.makeAuthenticatedRequest(
            url: url,
            method: "POST",
            body: bodyData
        )
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let errorMessage = errorData?["error"] as? String ?? "Failed to start mesh generation"
            throw MeshError.backendError(message: errorMessage, statusCode: httpResponse.statusCode)
        }
        
        let generationResponse = try JSONDecoder().decode(MeshGenerationResponse.self, from: data)
        
        // Initialize current mesh with default values
        currentMesh = MeshStatus(
            id: generationResponse.meshId,
            userId: "",
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            taskId: "pending",
            status: .inProgress,
            previewStatus: .pending,
            previewProgress: 0,
            refineStatus: .pending,
            refineProgress: 0,
            riggingStatus: .pending,
            riggingProgress: 0,
            animationStatus: .pending,
            animationProgress: 0,
            glbFilePath: nil,
            riggedCharacterGlbUrl: nil,
            animationGlbUrl: nil,
            animationUsdzUrl: nil,
            errorMessage: nil,
            createdAt: nil,
            updatedAt: nil
        )
        
        // Start polling for status updates
        startPolling(meshId: generationResponse.meshId)
    }
    
    /// Fetches a specific mesh by ID
    func fetchMesh(meshId: String) async throws -> MeshStatus {
        let url = backendBaseURL.appendingPathComponent("/api/v1/meshes/\(meshId)")
        
        let (data, httpResponse) = try await AuthService.shared.makeAuthenticatedRequest(
            url: url,
            method: "GET"
        )
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 404 {
                throw MeshError.notFound
            }
            throw MeshError.backendError(message: "Failed to fetch mesh", statusCode: httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(MeshStatus.self, from: data)
    }
    
    /// Fetches the user's current avatar
    func fetchUserAvatar() async throws -> MeshStatus? {
        let url = backendBaseURL.appendingPathComponent("/api/meshes/my-avatar")
        
        let (data, httpResponse) = try await AuthService.shared.makeAuthenticatedRequest(
            url: url,
            method: "GET"
        )
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 404 {
                return nil
            }
            throw MeshError.backendError(message: "Failed to fetch user avatar", statusCode: httpResponse.statusCode)
        }
        
        // Check if response indicates no avatar
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           json["message"] as? String != nil {
            return nil
        }
        
        return try JSONDecoder().decode(MeshStatus.self, from: data)
    }
    
    /// Fetches all user's avatars (for companion avatars)
    func fetchUserAvatars() async throws {
        let url = backendBaseURL.appendingPathComponent("/api/v1/meshes")
        
        let (data, httpResponse) = try await AuthService.shared.makeAuthenticatedRequest(
            url: url,
            method: "GET"
        )
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw MeshError.backendError(message: "Failed to fetch avatars", statusCode: httpResponse.statusCode)
        }
        
        let avatars = try JSONDecoder().decode([MeshStatus].self, from: data)
        userAvatars = avatars
    }
    
    /// Stops polling for status updates
    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        pollingStartTime = nil
    }
    
    /// Clears current generation state
    func clearCurrentMesh() {
        stopPolling()
        currentMesh = nil
        isGenerating = false
        error = nil
    }
    
    // MARK: - Private Methods
    
    private func startPolling(meshId: String) {
        stopPolling()
        pollingStartTime = Date()
        
        // Use RunLoop to ensure timer runs on main thread
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Check for timeout
            if let startTime = self.pollingStartTime,
               Date().timeIntervalSince(startTime) > self.maxPollingDuration {
                print("⏰ Polling timeout after \(self.maxPollingDuration/60) minutes, stopping...")
                self.isGenerating = false
                self.stopPolling()
                self.error = "Generation is taking longer than expected. Please check the status manually."
                return
            }
            
            Task { @MainActor in
                do {
                    let updatedMesh = try await self.fetchMesh(meshId: meshId)
                    self.currentMesh = updatedMesh
                    
                    // Debug logging
                    print("📊 Polling mesh \(meshId):")
                    print("   Overall status: \(updatedMesh.status.rawValue)")
                    print("   Preview: \(updatedMesh.previewStatus?.rawValue ?? "nil") (\(updatedMesh.previewProgress ?? 0)%)")
                    print("   Refine: \(updatedMesh.refineStatus?.rawValue ?? "nil") (\(updatedMesh.refineProgress ?? 0)%)")
                    print("   Rigging: \(updatedMesh.riggingStatus?.rawValue ?? "nil") (\(updatedMesh.riggingProgress ?? 0)%)")
                    print("   Animation: \(updatedMesh.animationStatus?.rawValue ?? "nil") (\(updatedMesh.animationProgress ?? 0)%)")
                    
                    // Check overall status first - if succeeded or failed, stop polling
                    if updatedMesh.status == .succeeded || updatedMesh.status == .failed {
                        print("✅ Generation complete with status: \(updatedMesh.status.rawValue)")
                        self.isGenerating = false
                        self.stopPolling()
                        
                        // Refresh user avatars if generation succeeded
                        if updatedMesh.status == .succeeded {
                            try? await self.fetchUserAvatars()
                        }
                        return
                    }
                    
                    // Also check if all stages are complete (as a backup check)
                    let previewDone = (updatedMesh.previewStatus ?? .pending) != .pending && (updatedMesh.previewStatus ?? .pending) != .inProgress
                    let refineDone = (updatedMesh.refineStatus ?? .pending) != .pending && (updatedMesh.refineStatus ?? .pending) != .inProgress
                    let riggingDone = (updatedMesh.riggingStatus ?? .pending) != .pending && (updatedMesh.riggingStatus ?? .pending) != .inProgress
                    let animationDone = (updatedMesh.animationStatus ?? .pending) != .pending && (updatedMesh.animationStatus ?? .pending) != .inProgress
                    
                    let allStagesComplete = previewDone && refineDone && riggingDone && animationDone
                    
                    if allStagesComplete && updatedMesh.status == .inProgress {
                        // All stages done but status still IN_PROGRESS - wait a bit more
                        print("⚠️ All stages complete but status still IN_PROGRESS, continuing to poll...")
                    }
                } catch {
                    print("❌ Failed to poll mesh status: \(error.localizedDescription)")
                    // Don't stop polling on error, just log it
                }
            }
        }
        
        // Add timer to main run loop
        RunLoop.main.add(pollingTimer!, forMode: .common)
    }
}

// MARK: - MeshError

enum MeshError: LocalizedError {
    case invalidPrompt
    case unauthorized
    case invalidResponse
    case notFound
    case backendError(message: String, statusCode: Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidPrompt:
            return "Prompt cannot be empty"
        case .unauthorized:
            return "You must be logged in to generate avatars"
        case .invalidResponse:
            return "Invalid response from server"
        case .notFound:
            return "Mesh not found"
        case .backendError(let message, let statusCode):
            return "Server error (\(statusCode)): \(message)"
        }
    }
}
