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
    private var currentAnimationTask: Task<Void, Never>?
    
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
    // func wave(targetName: String = "leftArm_end") {
    //     // Define the waving motion based on the current implementation
    //     // This matches the hard-coded waving logic from ContentView
    //     let endTarget = targetController.target(named: targetName)
    //     let startPosition = endTarget.position
        
    //     // Calculate wave positions
    //     // Coordinate system: X=left/right, Y=forward/back, Z=up/down (after -90° X rotation)
    //     let rightPos = startPosition + SIMD3<Float>(15.0, 0.0, 0.0)
    //     let leftPos = startPosition + SIMD3<Float>(-15.0, 0.0, 0.0)
        
    //     let waveDuration: TimeInterval = 1.0
        
    //     // Create motion with three steps: right -> left -> center
    //     let motion = TargetMotion(
    //         targetName: targetName,
    //         duration: waveDuration,
    //         transforms: [
    //             Transform(translation: rightPos),
    //             Transform(translation: leftPos),
    //             Transform(translation: startPosition)
    //         ],
    //         timing: [.easeOut, .easeInOut, .easeIn]
    //     )
        
    //     motionPlayer.play(motion, loop: true)
    // }
    
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
    /// Animations are played sequentially in order, looping continuously until a new animation is requested.
    /// - Parameter animations: Array of joint animations to apply in sequence
    func applyJointAnimation(_ animations: [JointAnimation]) {
        guard var ikComponent = entity.components[IKComponent.self] else {
            print("❌ No IKComponent on entity")
            return
        }

        // Cancel any existing animation task
        currentAnimationTask?.cancel()
        
        let solverIndex = 0

        // Flag to indicate if the animation should be cancelled when there is no animation to play
        var shouldCancel = true
        
        // Create new animation task that loops until cancelled
        currentAnimationTask = Task { @MainActor in
            // Loop continuously until task is cancelled
            while !Task.isCancelled {
                for animation in animations {
                    // Check for cancellation before each animation
                    guard !Task.isCancelled else { break }
                    
                    // Get fresh reference to solver for each animation
                    let solver = ikComponent.solvers[solverIndex]
                    
                    // Process all targets in this animation
                    for (jointPath, jointMatrix) in animation.changes {
                        // Check for cancellation
                        guard !Task.isCancelled else { break }
                        
                        // 1️⃣ Get or create the target entity
                        let targetEntity = targetController.target(named: jointPath)
                        
                        // 2️⃣ Calculate target transform from matrix
                        let targetTransform = Transform(matrix: jointMatrix.toSimdMatrix())
                        
                        // 3️⃣ Update the IK constraint target to the final transform we're moving to
                        // This tells the IK solver where to aim
                        if var constraint = solver.constraints[jointPath] {
                            constraint.target = targetTransform
                            ikComponent.solvers[solverIndex].constraints[jointPath] = constraint
                        } else {
                            print("⚠️ No IK constraint found for \(jointPath)")
                        }
                        
                        // 4️⃣ Start the move animation (this will animate the target entity)
                        // RealityKit's IK solver will automatically follow the moving target
                        targetEntity.move(
                            to: targetTransform,
                            relativeTo: targetController.anchor,
                            duration: animation.duration,
                            timingFunction: .easeInOut
                        )
                    }
                    
                    // 5️⃣ Re-apply the IKComponent so RealityKit picks up constraint updates
                    entity.components.set(ikComponent)
                    
                    // 6️⃣ Wait for this animation to complete before starting the next one
                    // Check for cancellation during sleep
                    if animation.duration > 0.0 {
                        // If the animation has a duration, set the shouldCancel flag to false
                        shouldCancel = false
                        do {
                            try await Task.sleep(nanoseconds: UInt64(animation.duration * 1_000_000_000))
                        } catch {
                            // Task was cancelled
                            shouldCancel = true
                            break
                        }
                    }
                }
                if shouldCancel {
                    break
                }
            }
        }
    }

    
    /// Cleans up resources.
    func cleanup() {
        stopUpdateTimer()
        motionPlayer.stopAll()
        targetController.removeAllTargets()
        currentAnimationTask?.cancel()
        currentAnimationTask = nil
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

