//
//  IKRigBuilder.swift
//  FriendshipV2
//
//  Created by Travis Miller on 2025-12-08.
//

import Foundation
import RealityKit

/// Builds an IKResource from a skeleton and limb definitions.
enum IKRigBuilder {
    /// Builds an IKResource from a MeshResource and limb definitions.
    /// - Parameters:
    ///   - meshResource: The MeshResource containing the skeleton
    ///   - limbs: Dictionary of limb names to IKLimb definitions
    ///   - maxIterations: Maximum solver iterations (default: 30)
    ///   - jointRefinements: Optional dictionary of joint names to fkWeightPerAxis refinements
    /// - Returns: An IKResource ready to be used with IKComponent
    /// - Throws: Error if no skeleton is found in the mesh resource
    static func buildIKRig(
        meshResource: MeshResource,
        limbs: [String: IKLimb],
        maxIterations: Int = 30,
        jointRefinements: [String: SIMD3<Float>] = [:]
    ) throws -> IKResource {
        // Extract skeleton from mesh resource
        guard let skeleton = meshResource.contents.skeletons.first else {
            throw IKRigBuilderError.noSkeletonFound
        }
        
        var rig = try IKRig(for: skeleton)
        rig.maxIterations = maxIterations
        
        // Apply joint refinements
        for (jointName, fkWeight) in jointRefinements {
            rig.joints[jointName]?.fkWeightPerAxis = fkWeight
        }
        
        // Build constraints from limb definitions
        var constraints: [IKRig.Constraint] = []
        
        for (name, limb) in limbs {
            // Add base constraint (point constraint on base joint)
            constraints.append(
                .point(
                    named: "\(name)_base",
                    on: limb.baseJoint,
                    positionWeight: limb.baseWeight
                )
            )
            
            // Add end constraint (parent constraint on end joint)
            constraints.append(
                .parent(
                    named: "\(name)_end",
                    on: limb.endJoint,
                    positionWeight: limb.endPositionWeight,
                    orientationWeight: limb.endOrientationWeight
                )
            )
        }
        
        // Assign constraints to rig
        rig.constraints = IKRig.ConstraintsCollection(constraints)
        
        return try IKResource(rig: rig)
    }
}

/// Errors that can occur when building an IK rig.
enum IKRigBuilderError: Error {
    case noSkeletonFound
}

