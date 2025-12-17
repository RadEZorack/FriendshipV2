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
    let constraintNames: [String]  // Made public so UI can force IK updates
    
    private var updateTimer: Timer?
    var currentAnimationTask: Task<Void, Never>?
    
    /// Initializes the avatar rig controller.
    /// - Parameters:
    ///   - entity: The ModelEntity to control
    ///   - anchor: The anchor entity (parent of the model)
    ///   - limbs: Dictionary of limb definitions for IK
    ///   - initialTargetMatrices: Optional dictionary of target names to initial matrices (in animation space: cm, X=left/right, Y=forward/back, Z=up/down)
    ///   - jointRefinements: Optional dictionary of joint names to refinement settings
    ///   - modelRotation: Rotation to apply when converting pose space to IK space (default: -90° around X)
    /// - Throws: Error if IK rig cannot be built
    init(
        entity: ModelEntity,
        anchor: Entity,
        limbs: [String: IKLimb],
        initialTargetMatrices: [String: simd_float4x4] = [:],
        jointRefinements: [String: SIMD3<Float>] = [:],
        modelRotation: simd_quatf = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
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
        
        // Set model rotation for pose→IK conversion
        targetController.modelRotation = modelRotation
        
        // Set initial target transforms from joint matrices
        // Convert from animation space (cm, X=left/right, Y=forward/back, Z=up/down) to pose space (m, X=left/right, Y=up/down, Z=forward/back)
        for (targetName, matrix) in initialTargetMatrices {
            let poseTarget = targetController.poseTarget(named: targetName)
            
            // Extract translation from matrix (in cm, animation space)
            let animTranslation = SIMD3<Float>(
                matrix.columns.3.x,
                matrix.columns.3.y,
                matrix.columns.3.z
            )
            
            // Convert to pose space: cm→m, swap Y and Z
            // Animation: (x, y, z) = (left/right, forward/back, up/down) in cm
            // Pose: (x, y, z) = (left/right, up/down, forward/back) in m
            let poseTranslation = SIMD3<Float>(
                animTranslation.x * 0.01,  // X stays X, cm→m
                animTranslation.z * 0.01,  // Z (up/down) becomes Y (up/down), cm→m
                animTranslation.y * 0.01   // Y (forward/back) becomes Z (forward/back), cm→m
            )
            
            // Extract rotation from matrix (preserve it)
            let rotation = simd_quatf(matrix)
            
            // Set pose target transform (clean pose space)
            poseTarget.transform = Transform(
                scale: SIMD3<Float>(1, 1, 1),
                rotation: rotation,
                translation: poseTranslation
            )
        }
        
        // Sync all pose targets to IK targets
        targetController.syncAllPoseToIK()
        
        // Bind constraints to IK targets
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
    
    /// Forces an immediate update of IK constraints and joints.
    /// This should be called after manually moving pose targets (e.g., via orb sliders).
    func updateJoints() {
        // Sync all pose targets to IK targets
        targetController.syncAllPoseToIK()
        
        // Update IK constraints
        IKConstraintBinder.updateTargets(
            entity: entity,
            controller: targetController,
            constraintNames: constraintNames
        )
        
        // Force RealityKit to process the IK solver by re-applying the component
        // This ensures joints are updated immediately
        if var ikComponent = entity.components[IKComponent.self] {
            entity.components.set(ikComponent)
        }
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
        let poseTarget = targetController.poseTarget(named: targetName)
        let startPosition = poseTarget.position(relativeTo: targetController.poseRoot)
        
        // Calculate raised position (move up in Y direction in pose space)
        // Pose space: X=left/right, Y=up/down, Z=forward/back
        let raisedPosition = startPosition + SIMD3<Float>(0.0, 0.5, 0.0)  // Raise 0.5m up
        
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
    /// Transforms should be in pose space.
    /// - Parameter poseDelta: Dictionary of joint names to transforms
    func applyPoseDelta(_ poseDelta: [String: Transform]) {
        // Future: Apply server-driven pose deltas
        // For now, this is a placeholder
        for (targetName, transform) in poseDelta {
            let poseTarget = targetController.poseTarget(named: targetName)
            poseTarget.transform = transform
        }
        // Sync to IK targets
        targetController.syncAllPoseToIK()
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
                    for (jointPath, matrixArray) in animation.changes {
                        // Check for cancellation
                        guard !Task.isCancelled else { break }
                        
                        // 1️⃣ Get or create the pose target entity (for UI editing)
                        let poseTarget = targetController.poseTarget(named: jointPath)
                        
                        // 2️⃣ Calculate target transform from matrix (in animation space: cm, X=left/right, Y=forward/back, Z=up/down)
                        let animMatrix = JointAnimation.toSimdMatrix(from: matrixArray)
                        let animTransform = Transform(matrix: animMatrix)
                        
                        // 3️⃣ Convert from animation space to pose space
                        // Animation: (x, y, z) = (left/right, forward/back, up/down) in cm
                        // Pose: (x, y, z) = (left/right, up/down, forward/back) in m
                        let animTranslation = animTransform.translation
                        let poseTranslation = SIMD3<Float>(
                            animTranslation.x * 0.01,  // X stays X, cm→m
                            animTranslation.z * 0.01,  // Z (up/down) becomes Y (up/down), cm→m
                            animTranslation.y * 0.01   // Y (forward/back) becomes Z (forward/back), cm→m
                        )
                        
                        let poseTransform = Transform(
                            scale: animTransform.scale,
                            rotation: animTransform.rotation,
                            translation: poseTranslation
                        )
                        
                        // 4️⃣ Start the move animation on pose target
                        // The update timer will sync pose→IK automatically
                        poseTarget.move(
                            to: poseTransform,
                            relativeTo: targetController.poseRoot,
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

