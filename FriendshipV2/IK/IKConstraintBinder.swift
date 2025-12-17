//
//  IKConstraintBinder.swift
//  FriendshipV2
//
//  Created by Travis Miller on 2025-12-08.
//

import Foundation
import RealityKit

/// Binds IK constraints to target entities generically.
enum IKConstraintBinder {
    /// Binds all constraints in an entity's IKComponent to target entities from the controller.
    /// Uses IK targets (not pose targets) since IK solver needs the rotated space.
    /// - Parameters:
    ///   - entity: The entity with the IKComponent
    ///   - controller: The controller providing target entities
    ///   - constraintNames: Array of constraint names to bind
    /// - Returns: True if binding was successful, false if entity has no IKComponent
    @discardableResult
    static func bindTargets(
        entity: Entity,
        controller: IKTargetController,
        constraintNames: [String]
    ) -> Bool {
        guard var ikComponent = entity.components[IKComponent.self] else {
            return false
        }
        
        // Sync all pose targets to IK targets before binding
        controller.syncAllPoseToIK()
        
        // Bind each constraint to its corresponding IK target entity
        for constraintName in constraintNames {
            guard var constraint = ikComponent.solvers[0].constraints[constraintName] else {
                continue
            }
            
            let ikTarget = controller.ikTarget(named: constraintName)
            constraint.target = ikTarget.transform
            
            // For end constraints, set animation override weight
            if constraintName.hasSuffix("_end") {
                constraint.animationOverrideWeight.position = 1.0
            }
            
            ikComponent.solvers[0].constraints[constraintName] = constraint
        }
        
        entity.components.set(ikComponent)
        return true
    }
    
    /// Updates constraint targets to follow their IK target entities.
    /// This should be called periodically (e.g., in a timer) to keep IK in sync.
    /// First syncs pose targets to IK targets, then updates constraints.
    /// - Parameters:
    ///   - entity: The entity with the IKComponent
    ///   - controller: The controller providing target entities
    ///   - constraintNames: Array of constraint names to update
    static func updateTargets(
        entity: Entity,
        controller: IKTargetController,
        constraintNames: [String]
    ) {
        guard var ikComponent = entity.components[IKComponent.self] else {
            return
        }
        
        // Sync all pose targets to IK targets first
        controller.syncAllPoseToIK()
        
        // Update each constraint target to match its IK target entity's transform
        for constraintName in constraintNames {
            guard var constraint = ikComponent.solvers[0].constraints[constraintName],
                  let ikTarget = controller.ikTargets[constraintName] else {
                continue
            }
            
            constraint.target = ikTarget.transform
            ikComponent.solvers[0].constraints[constraintName] = constraint
        }
        
        entity.components.set(ikComponent)
    }
}

