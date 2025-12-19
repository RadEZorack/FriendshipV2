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
    let initialPose: [[String: Any]]?
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
        case initialPose
        case createdAt
        case updatedAt
    }
    
    // Memberwise initializer for programmatic creation
    init(
        id: String,
        userId: String,
        prompt: String,
        taskId: String,
        status: GenerationStatus,
        previewStatus: StageStatus? = nil,
        previewProgress: Int? = nil,
        refineStatus: StageStatus? = nil,
        refineProgress: Int? = nil,
        riggingStatus: StageStatus? = nil,
        riggingProgress: Int? = nil,
        animationStatus: StageStatus? = nil,
        animationProgress: Int? = nil,
        glbFilePath: String? = nil,
        riggedCharacterGlbUrl: String? = nil,
        animationGlbUrl: String? = nil,
        animationUsdzUrl: String? = nil,
        errorMessage: String? = nil,
        initialPose: [[String: Any]]? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.prompt = prompt
        self.taskId = taskId
        self.status = status
        self.previewStatus = previewStatus
        self.previewProgress = previewProgress
        self.refineStatus = refineStatus
        self.refineProgress = refineProgress
        self.riggingStatus = riggingStatus
        self.riggingProgress = riggingProgress
        self.animationStatus = animationStatus
        self.animationProgress = animationProgress
        self.glbFilePath = glbFilePath
        self.riggedCharacterGlbUrl = riggedCharacterGlbUrl
        self.animationGlbUrl = animationGlbUrl
        self.animationUsdzUrl = animationUsdzUrl
        self.errorMessage = errorMessage
        self.initialPose = initialPose
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // Custom decoder to handle initialPose as nested JSON
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        prompt = try container.decode(String.self, forKey: .prompt)
        taskId = try container.decode(String.self, forKey: .taskId)
        status = try container.decode(GenerationStatus.self, forKey: .status)
        previewStatus = try container.decodeIfPresent(StageStatus.self, forKey: .previewStatus)
        previewProgress = try container.decodeIfPresent(Int.self, forKey: .previewProgress)
        refineStatus = try container.decodeIfPresent(StageStatus.self, forKey: .refineStatus)
        refineProgress = try container.decodeIfPresent(Int.self, forKey: .refineProgress)
        riggingStatus = try container.decodeIfPresent(StageStatus.self, forKey: .riggingStatus)
        riggingProgress = try container.decodeIfPresent(Int.self, forKey: .riggingProgress)
        animationStatus = try container.decodeIfPresent(StageStatus.self, forKey: .animationStatus)
        animationProgress = try container.decodeIfPresent(Int.self, forKey: .animationProgress)
        glbFilePath = try container.decodeIfPresent(String.self, forKey: .glbFilePath)
        riggedCharacterGlbUrl = try container.decodeIfPresent(String.self, forKey: .riggedCharacterGlbUrl)
        animationGlbUrl = try container.decodeIfPresent(String.self, forKey: .animationGlbUrl)
        animationUsdzUrl = try container.decodeIfPresent(String.self, forKey: .animationUsdzUrl)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        
        // Decode initialPose as nested JSON array
        if container.contains(.initialPose) {
            if let initialPoseArray = try? container.decode([[String: AnyCodable]].self, forKey: .initialPose) {
                initialPose = initialPoseArray.map { dict in
                    dict.mapValues { $0.value }
                }
            } else {
                initialPose = nil
            }
        } else {
            initialPose = nil
        }
        
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }
    
    // Custom encoder to handle initialPose as nested JSON
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(taskId, forKey: .taskId)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(previewStatus, forKey: .previewStatus)
        try container.encodeIfPresent(previewProgress, forKey: .previewProgress)
        try container.encodeIfPresent(refineStatus, forKey: .refineStatus)
        try container.encodeIfPresent(refineProgress, forKey: .refineProgress)
        try container.encodeIfPresent(riggingStatus, forKey: .riggingStatus)
        try container.encodeIfPresent(riggingProgress, forKey: .riggingProgress)
        try container.encodeIfPresent(animationStatus, forKey: .animationStatus)
        try container.encodeIfPresent(animationProgress, forKey: .animationProgress)
        try container.encodeIfPresent(glbFilePath, forKey: .glbFilePath)
        try container.encodeIfPresent(riggedCharacterGlbUrl, forKey: .riggedCharacterGlbUrl)
        try container.encodeIfPresent(animationGlbUrl, forKey: .animationGlbUrl)
        try container.encodeIfPresent(animationUsdzUrl, forKey: .animationUsdzUrl)
        try container.encodeIfPresent(errorMessage, forKey: .errorMessage)
        
        // Encode initialPose as nested JSON
        if let initialPose = initialPose {
            let codableArray = initialPose.map { dict in
                dict.mapValues { AnyCodable($0) }
            }
            try container.encodeIfPresent(codableArray, forKey: .initialPose)
        }
        
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
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

// Helper struct for encoding/decoding Any values in JSON
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            let codableArray = array.map { AnyCodable($0) }
            try container.encode(codableArray)
        case let dict as [String: Any]:
            let codableDict = dict.mapValues { AnyCodable($0) }
            try container.encode(codableDict)
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "AnyCodable value cannot be encoded"))
        }
    }
}
