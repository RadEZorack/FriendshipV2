//
//  IKTargetController.swift
//  FriendshipV2
//
//  Created by Travis Miller on 2025-12-08.
//

import Foundation
import RealityKit

/// Responsible for creating and owning target entities for IK constraints.
/// Uses a clean pose space architecture:
/// - poseRoot: Identity transform space for UI interactions
/// - poseTarget: Entities in pose space (edited by UI)
/// - ikTarget: Entities in IK space (consumed by solver, with model rotation applied)
final class IKTargetController {
    let anchor: Entity
    let poseRoot: Entity
    private(set) var poseTargets: [String: Entity] = [:]
    private(set) var ikTargets: [String: Entity] = [:]
    
    /// Model rotation to apply when converting pose space to IK space
    /// This is typically -90° around X axis for models imported from USDZ
    var modelRotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    
    init(anchor: Entity) {
        self.anchor = anchor
        
        // Create pose root with identity transform (no rotation, no scale)
        self.poseRoot = Entity()
        self.poseRoot.name = "poseRoot"
        self.poseRoot.transform = Transform()
        anchor.addChild(poseRoot)
    }
    
    /// Gets or creates a pose target entity (for UI editing).
    /// UI code should only modify poseTarget.transform.translation.
    /// - Parameter name: The name of the target (should match constraint name)
    /// - Returns: The pose target entity, creating it if it doesn't exist
    func poseTarget(named name: String) -> Entity {
        if let existing = poseTargets[name] {
            return existing
        }
        
        let entity = Entity()
        entity.name = "\(name)_pose"
        poseRoot.addChild(entity)
        poseTargets[name] = entity
        
        // Also create corresponding IK target
        let ikEntity = Entity()
        ikEntity.name = "\(name)_ik"
        anchor.addChild(ikEntity)
        ikTargets[name] = ikEntity
        
        // Sync initial state
        syncPoseToIK(targetName: name)
        
        return entity
    }
    
    /// Gets the IK target entity (for IK solver consumption).
    /// This is automatically synced from poseTarget with model rotation applied.
    /// - Parameter name: The name of the target
    /// - Returns: The IK target entity
    func ikTarget(named name: String) -> Entity {
        // Ensure both targets exist
        _ = poseTarget(named: name)
        return ikTargets[name]!
    }
    
    /// Legacy method for backward compatibility during refactor.
    /// Returns poseTarget (for UI editing).
    func target(named name: String) -> Entity {
        return poseTarget(named: name)
    }
    
    /// Syncs poseTarget transform to ikTarget, applying model rotation.
    /// This converts from clean pose space (meters) to IK solver space (centimeters).
    /// Both poseTarget and ikTarget are relative to anchor, but ikTarget has model rotation applied.
    /// - Parameter targetName: The name of the target to sync
    func syncPoseToIK(targetName: String) {
        guard let poseTarget = poseTargets[targetName],
              let ikTarget = ikTargets[targetName] else {
            return
        }
        
        // Get pose target transform in pose space (relative to poseRoot, which is identity)
        // Pose space: (x, y, z) = (left/right, up/down, forward/back) in meters
        // IK space: (x, y, z) = (left/right, forward/back, up/down) in centimeters
        let poseTransform = poseTarget.transform
        let poseTranslation = poseTransform.translation
        
        // Convert meters to centimeters first (IK system expects cm)
        let poseTranslationCm = poseTranslation * 100.0
        
        // Apply model rotation - this handles coordinate system conversion
        // The -90° X rotation converts from pose space to IK space
        let rotatedTranslation = modelRotation.act(poseTranslationCm)
        
        // Now swap Y and Z to reverse the animation→pose conversion
        // Animation→Pose: anim(x,y,z) → pose(x,z,y) 
        // After rotation, swap to get: (x, z, y) which matches animation space
        let ikTranslation = SIMD3<Float>(
            rotatedTranslation.x,  // X stays X
            rotatedTranslation.z,  // Z becomes Y (swap)
            rotatedTranslation.y   // Y becomes Z (swap)
        )
        
        // Combine rotations
        let rotatedRotation = modelRotation * poseTransform.rotation
        
        // Set IK target transform (relative to anchor, with model rotation applied, in centimeters)
        ikTarget.transform = Transform(
            scale: poseTransform.scale,
            rotation: rotatedRotation,
            translation: ikTranslation
        )
    }
    
    /// Syncs all pose targets to their IK targets.
    func syncAllPoseToIK() {
        for targetName in poseTargets.keys {
            syncPoseToIK(targetName: targetName)
        }
    }
    
    /// Removes all target entities.
    func removeAllTargets() {
        for target in poseTargets.values {
            target.removeFromParent()
        }
        poseTargets.removeAll()
        
        for target in ikTargets.values {
            target.removeFromParent()
        }
        ikTargets.removeAll()
        
        poseRoot.removeFromParent()
    }
    
    /// Legacy property for backward compatibility.
    /// Returns ikTargets (what IK solver actually uses).
    var targets: [String: Entity] {
        return ikTargets
    }
}

