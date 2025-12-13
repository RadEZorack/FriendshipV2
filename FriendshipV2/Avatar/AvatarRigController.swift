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
    
    /// Linearly interpolates between two SIMD4<Float> vectors.
    /// - Parameters:
    ///   - a: Start vector
    ///   - b: End vector
    ///   - t: Interpolation factor in [0, 1]
    private func lerp(_ a: SIMD4<Float>, _ b: SIMD4<Float>, t: Float) -> SIMD4<Float> {
        return a + (b - a) * t
    }
    
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
        initialTargetPositions: [String: SIMD3<Float>] = [:],
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
        
        // Set initial target positions
        for (targetName, position) in initialTargetPositions {
            let target = targetController.target(named: targetName)
            target.position = position
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
    /// - Parameter animation: The joint animation to apply
    func applyJointAnimation(_ animation: JointAnimation) {
        // Find joint indices for each joint name in the animation
        var jointIndices: [String: Int] = [:]
        for (index, jointName) in entity.jointNames.enumerated() {
            jointIndices[jointName] = index
        }
        
        // Store original transforms for interpolation
        var originalTransforms: [String: simd_float4x4] = [:]
        var targetTransforms: [String: simd_float4x4] = [:]
        
        for (jointName, jointMatrix) in animation.changes {
            guard let jointIndex = jointIndices[jointName] else {
                print("⚠️ Joint '\(jointName)' not found in model")
                continue
            }
            
            // Get original transform
            originalTransforms[jointName] = entity.jointTransforms[jointIndex].matrix
            
            // Get target transform from JSON
            targetTransforms[jointName] = jointMatrix.toSimdMatrix()
        }
        
        // Animate each joint
        let duration = animation.duration
        let startTime = Date()
        
        // Use a timer to interpolate between original and target transforms
        let animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            let elapsed = Date().timeIntervalSince(startTime)
            let progress = min(elapsed / duration, 1.0)
            
            // Use easeInOut interpolation
            let easedProgress: Double
            if progress < 0.5 {
                easedProgress = 2 * progress * progress
            } else {
                let p = -2 * progress + 2
                easedProgress = 1 - (p * p) / 2
            }
            
            // Apply interpolated transforms to each joint
            for (jointName, originalMatrix) in originalTransforms {
                guard let targetMatrix = targetTransforms[jointName],
                      let jointIndex = jointIndices[jointName] else {
                    continue
                }
                
                let t: Float = Float(easedProgress)
                
                // Extract columns explicitly to help the type checker
                let o0: SIMD4<Float> = originalMatrix.columns.0
                let o1: SIMD4<Float> = originalMatrix.columns.1
                let o2: SIMD4<Float> = originalMatrix.columns.2
                let o3: SIMD4<Float> = originalMatrix.columns.3
                
                let d0: SIMD4<Float> = targetMatrix.columns.0
                let d1: SIMD4<Float> = targetMatrix.columns.1
                let d2: SIMD4<Float> = targetMatrix.columns.2
                let d3: SIMD4<Float> = targetMatrix.columns.3
                
                // Interpolate columns with explicit helper
                let c0: SIMD4<Float> = lerp(o0, d0, t: t)
                let c1: SIMD4<Float> = lerp(o1, d1, t: t)
                let c2: SIMD4<Float> = lerp(o2, d2, t: t)
                let c3: SIMD4<Float> = lerp(o3, d3, t: t)
                
                let interpolatedMatrix = simd_float4x4(c0, c1, c2, c3)
                let interpolatedTransform = Transform(matrix: interpolatedMatrix)
                
                // Apply the transform by directly modifying jointTransforms
                // Note: jointTransforms may be mutable depending on RealityKit version
                // If this doesn't work, we may need to use skeletal animation or entity hierarchy
                if jointIndex < self.entity.jointTransforms.count {
                    // Direct assignment - works if jointTransforms is mutable
                    self.entity.jointTransforms[jointIndex] = interpolatedTransform
                }
            }
            
            // Stop timer when animation is complete
            if progress >= 1.0 {
                timer.invalidate()
            }
        }
        
        RunLoop.main.add(animationTimer, forMode: .common)
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

