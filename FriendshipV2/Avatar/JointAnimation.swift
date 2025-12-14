//
//  JointAnimation.swift
//  FriendshipV2
//
//  Created by Travis Miller on 2025-12-08.
//

import Foundation
import RealityKit

/// Represents a joint animation instruction from AI/JSON.
struct JointAnimation: Codable {
    let duration: Double
    let space: String  // "local" or "world"
    let changes: [String: [[Double]]]
    
    /// Converts a 2D array matrix to simd_float4x4
    static func toSimdMatrix(from matrix: [[Double]]) -> simd_float4x4 {
        guard matrix.count == 4,
              matrix[0].count == 4,
              matrix[1].count == 4,
              matrix[2].count == 4,
              matrix[3].count == 4 else {
            // Return identity matrix if invalid
            return simd_float4x4(1.0)
        }
        
        return simd_float4x4(
            SIMD4<Float>(Float(matrix[0][0]), Float(matrix[0][1]), Float(matrix[0][2]), Float(matrix[0][3])),
            SIMD4<Float>(Float(matrix[1][0]), Float(matrix[1][1]), Float(matrix[1][2]), Float(matrix[1][3])),
            SIMD4<Float>(Float(matrix[2][0]), Float(matrix[2][1]), Float(matrix[2][2]), Float(matrix[2][3])),
            SIMD4<Float>(Float(matrix[3][0]), Float(matrix[3][1]), Float(matrix[3][2]), Float(matrix[3][3]))
        )
    }
}

