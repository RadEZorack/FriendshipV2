//
//  IKTargetController.swift
//  FriendshipV2
//
//  Created by Travis Miller on 2025-12-08.
//

import Foundation
import RealityKit

/// Responsible for creating and owning target entities for IK constraints.
final class IKTargetController {
    let anchor: Entity
    private(set) var targets: [String: Entity] = [:]
    
    init(anchor: Entity) {
        self.anchor = anchor
    }
    
    /// Gets or creates a target entity with the given name.
    /// - Parameter name: The name of the target (should match constraint name)
    /// - Returns: The target entity, creating it if it doesn't exist
    func target(named name: String) -> Entity {
        if let existing = targets[name] {
            return existing
        }
        
        let entity = Entity()
        entity.name = name
        anchor.addChild(entity)
        targets[name] = entity
        return entity
    }
    
    /// Removes all target entities.
    func removeAllTargets() {
        for target in targets.values {
            target.removeFromParent()
        }
        targets.removeAll()
    }
}

