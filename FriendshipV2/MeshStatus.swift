//
//  MeshStatus.swift
//  FriendshipV2
//
//  Created by Travis Miller on 2025-12-08.
//

import Foundation

/// Represents the status of a mesh generation process
struct MeshStatus: Codable, Identifiable {
    let id: String
    let userId: String
    let prompt: String
    let taskId: String
    let status: GenerationStatus
    let previewStatus: StageStatus?
    let previewProgress: Int?
    let refineStatus: StageStatus?
    let refineProgress: Int?
    let riggingStatus: StageStatus?
    let riggingProgress: Int?
    let animationStatus: StageStatus?
    let animationProgress: Int?
    let glbFilePath: String?
    let riggedCharacterGlbUrl: String?
    let animationGlbUrl: String?
    let animationUsdzUrl: String?
    let errorMessage: String?
    let createdAt: String?
    let updatedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case userId
        case prompt
        case taskId
        case status
        case previewStatus
        case previewProgress
        case refineStatus
        case refineProgress
        case riggingStatus
        case riggingProgress
        case animationStatus
        case animationProgress
        case glbFilePath
        case riggedCharacterGlbUrl
        case animationGlbUrl
        case animationUsdzUrl
        case errorMessage
        case createdAt
        case updatedAt
    }
}

enum GenerationStatus: String, Codable {
    case inProgress = "IN_PROGRESS"
    case succeeded = "SUCCEEDED"
    case failed = "FAILED"
}

enum StageStatus: String, Codable {
    case pending = "PENDING"
    case inProgress = "IN_PROGRESS"
    case succeeded = "SUCCEEDED"
    case failed = "FAILED"
}

/// Response from mesh generation endpoint
struct MeshGenerationResponse: Codable {
    let message: String
    let meshId: String
}
