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
        
        // Bind each constraint to its corresponding target entity
        for constraintName in constraintNames {
            guard var constraint = ikComponent.solvers[0].constraints[constraintName] else {
                continue
            }
            
            let target = controller.target(named: constraintName)
            constraint.target = target.transform
            
            // For end constraints, set animation override weight
            if constraintName.hasSuffix("_end") {
                constraint.animationOverrideWeight.position = 1.0
            }
            
            ikComponent.solvers[0].constraints[constraintName] = constraint
        }
        
        entity.components.set(ikComponent)
        return true
    }
    
    /// Updates constraint targets to follow their target entities.
    /// This should be called periodically (e.g., in a timer) to keep IK in sync.
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
        
        // Update each constraint target to match its target entity's transform
        for constraintName in constraintNames {
            guard var constraint = ikComponent.solvers[0].constraints[constraintName],
                  let target = controller.targets[constraintName] else {
                continue
            }
            
            constraint.target = target.transform
            ikComponent.solvers[0].constraints[constraintName] = constraint
        }
        
        entity.components.set(ikComponent)
    }
}

