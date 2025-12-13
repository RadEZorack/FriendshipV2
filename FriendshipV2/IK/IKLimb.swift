//
//  IKLimb.swift
//  FriendshipV2
//
//  Created by Travis Miller on 2025-12-08.
//

import Foundation
import RealityKit

/// Data-only description of a controllable limb for IK.
struct IKLimb {
    let baseJoint: String
    let endJoint: String
    let baseWeight: SIMD3<Float>
    let endPositionWeight: SIMD3<Float>
    let endOrientationWeight: SIMD3<Float>
}

