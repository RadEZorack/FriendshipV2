//
//  AvatarRigController.swift
//  FriendshipV2
//
//  Created by Travis Miller on 2025-12-08.
//

import Foundation
import RealityKit

/// High-level orchestration for an avatar with IK rigging and motion control.
final class AvatarRigController {
    let entity: ModelEntity
    let anchor: Entity
    let targetController: IKTargetController
    let motionPlayer: MotionPlayer
    private let constraintNames: [String]
    
    private var updateTimer: Timer?
    
    /// Initializes the avatar rig controller.
    /// - Parameters:
    ///   - entity: The ModelEntity to control
    ///   - anchor: The anchor entity (parent of the model)
    ///   - limbs: Dictionary of limb definitions for IK
    ///   - initialTargetPositions: Optional dictionary of target names to initial positions
    ///   - jointRefinements: Optional dictionary of joint names to refinement settings
    /// - Throws: Error if IK rig cannot be built
    init(
        entity: ModelEntity,
        anchor: Entity,
        limbs: [String: IKLimb],
        initialTargetMatrices: [String: simd_float4x4] = [:],
        jointRefinements: [String: SIMD3<Float>] = [:]
    ) throws {
        self.entity = entity
        self.anchor = anchor
        
        // Get skeleton from mesh
        guard let meshResource = entity.components[ModelComponent.self]?.mesh else {
            throw AvatarRigError.noMeshFound
        }
        
        // Build IK rig using IKRigBuilder (handles skeleton extraction, refinements, and constraints)
        let ikResource = try IKRigBuilder.buildIKRig(
            meshResource: meshResource,
            limbs: limbs,
            jointRefinements: jointRefinements
        )
        
        // Add IK component to entity
        entity.components.set(IKComponent(resource: ikResource))
        
        // Generate constraint names from limb names
        // Each limb creates two constraints: "{name}_base" and "{name}_end"
        self.constraintNames = limbs.flatMap { (name, _) in
            ["\(name)_base", "\(name)_end"]
        }
        
        // Create target controller
        self.targetController = IKTargetController(anchor: anchor)
        
        // Set initial target transforms from joint matrices
        for (targetName, matrix) in initialTargetMatrices {
            let target = targetController.target(named: targetName)
            // Convert simd_float4x4 to Transform
            target.transform = Transform(matrix: matrix)
        }
        
        // Bind constraints to targets
        guard IKConstraintBinder.bindTargets(
            entity: entity,
            controller: targetController,
            constraintNames: constraintNames
        ) else {
            throw AvatarRigError.failedToBindConstraints
        }
        
        // Create motion player
        self.motionPlayer = MotionPlayer(controller: targetController)
        
        // Start update timer to keep IK in sync
        startUpdateTimer()
    }
    
    /// Starts a timer to continuously update IK constraint targets.
    private func startUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            IKConstraintBinder.updateTargets(
                entity: self.entity,
                controller: self.targetController,
                constraintNames: self.constraintNames
            )
        }
    }
    
    /// Stops the update timer.
    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    /// Plays a waving motion on the left arm.
    /// This is a convenience method that creates and plays a waving motion.
    /// - Parameter targetName: Name of the target to wave (default: "leftArm_end")
    func wave(targetName: String = "leftArm_end") {
        // Define the waving motion based on the current implementation
        // This matches the hard-coded waving logic from ContentView
        let endTarget = targetController.target(named: targetName)
        let startPosition = endTarget.position
        
        // Calculate wave positions
        // Coordinate system: X=left/right, Y=forward/back, Z=up/down (after -90° X rotation)
        let rightPos = startPosition + SIMD3<Float>(15.0, 0.0, 0.0)
        let leftPos = startPosition + SIMD3<Float>(-15.0, 0.0, 0.0)
        
        let waveDuration: TimeInterval = 1.0
        
        // Create motion with three steps: right -> left -> center
        let motion = TargetMotion(
            targetName: targetName,
            duration: waveDuration,
            transforms: [
                Transform(translation: rightPos),
                Transform(translation: leftPos),
                Transform(translation: startPosition)
            ],
            timing: [.easeOut, .easeInOut, .easeIn]
        )
        
        motionPlayer.play(motion, loop: true)
    }
    
    /// Raises the right hand up.
    /// - Parameter targetName: Name of the target to raise (default: "rightArm_end")
    func raiseRightHand(targetName: String = "rightArm_end") {
        let endTarget = targetController.target(named: targetName)
        let startPosition = endTarget.position
        
        // Calculate raised position (move up in Z direction)
        // Coordinate system: X=left/right, Y=forward/back, Z=up/down (after -90° X rotation)
        let raisedPosition = startPosition + SIMD3<Float>(0.0, 0.0, 50.0)  // Raise 50 units up
        
        let raiseDuration: TimeInterval = 0.8
        
        // Create motion: raise up, then lower back down
        let motion = TargetMotion(
            targetName: targetName,
            duration: raiseDuration,
            transforms: [
                Transform(translation: raisedPosition),
                Transform(translation: startPosition)
            ],
            timing: [.easeOut, .easeIn]
        )
        
        motionPlayer.play(motion, loop: true)
    }
    
    /// Applies a pose delta from server data.
    /// - Parameter poseDelta: Dictionary of joint names to transforms
    func applyPoseDelta(_ poseDelta: [String: Transform]) {
        // Future: Apply server-driven pose deltas
        // For now, this is a placeholder
        for (targetName, transform) in poseDelta {
            let target = targetController.target(named: targetName)
            target.transform = transform
        }
    }
    
    /// Applies a joint animation from JSON/AI response.
    /// Interprets joint paths as IK target names and animates target entities.
    /// RealityKit's IK solver handles joint interpolation and blending.
    /// - Parameter animation: The joint animation to apply
    func applyJointAnimation(_ animation: JointAnimation) {
        guard var ikComponent = entity.components[IKComponent.self] else {
            print("❌ No IKComponent on entity")
            return
        }

        let solverIndex = 0
        let solver = ikComponent.solvers[solverIndex]

        for (jointPath, jointMatrix) in animation.changes {

            // 1️⃣ Get or create the target entity
            let targetEntity = targetController.target(named: jointPath)

            // 2️⃣ Move the target entity (this defines intent)
            let targetTransform = Transform(matrix: jointMatrix.toSimdMatrix())
            targetEntity.move(
                to: targetTransform,
                relativeTo: targetController.anchor,
                duration: animation.duration,
                timingFunction: .easeInOut
            )

            // 3️⃣ Update the corresponding IK constraint to follow this target
            // Constraint name MUST match jointPath (as created in rig builder)
            if var constraint = solver.constraints[jointPath] {
                constraint.target = targetEntity.transform
                ikComponent.solvers[solverIndex].constraints[jointPath] = constraint
            } else {
                print("⚠️ No IK constraint found for \(jointPath)")
            }
        }

        // 4️⃣ Re-apply the IKComponent so RealityKit picks up constraint updates
        entity.components.set(ikComponent)
    }

    
    /// Cleans up resources.
    func cleanup() {
        stopUpdateTimer()
        motionPlayer.stopAll()
        targetController.removeAllTargets()
    }
    
    deinit {
        cleanup()
    }
}

/// Errors that can occur when creating or using AvatarRigController.
enum AvatarRigError: Error {
    case noMeshFound
    case noSkeletonFound
    case failedToBindConstraints
}

