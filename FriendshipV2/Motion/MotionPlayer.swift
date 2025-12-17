//
//  MotionPlayer.swift
//  FriendshipV2
//
//  Created by Travis Miller on 2025-12-08.
//

import Foundation
import RealityKit

/// Plays motions by animating target entities.
final class MotionPlayer {
    let controller: IKTargetController
    private var currentTimers: [Timer] = []
    private var isPlaying = false
    
    init(controller: IKTargetController) {
        self.controller = controller
    }
    
    /// Plays a motion by animating the pose target entity through its transforms.
    /// Transforms should be in pose space (clean coordinate system).
    /// - Parameter motion: The motion to play
    /// - Parameter loop: Whether to loop the motion (default: false)
    func play(_ motion: TargetMotion, loop: Bool = false) {
        let poseTarget = controller.poseTarget(named: motion.targetName)
        let stepDuration = motion.duration / Double(motion.transforms.count)
        
        // Clear any existing timers for this target
        stop(targetName: motion.targetName)
        
        isPlaying = true
        
        func playStep(index: Int) {
            guard index < motion.transforms.count, isPlaying else {
                if loop && isPlaying {
                    // Loop: restart from beginning after a brief pause
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        playStep(index: 0)
                    }
                } else {
                    isPlaying = false
                }
                return
            }
            
            let transform = motion.transforms[index]
            let timing = index < motion.timing.count ? motion.timing[index] : .easeInOut
            
            // Animate pose target (update timer will sync to IK target)
            poseTarget.move(
                to: transform,
                relativeTo: controller.poseRoot,
                duration: stepDuration,
                timingFunction: timing
            )
            
            // Schedule next step
            let timer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: false) { _ in
                playStep(index: index + 1)
            }
            RunLoop.main.add(timer, forMode: .common)
            currentTimers.append(timer)
        }
        
        // Start playing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            playStep(index: 0)
        }
    }
    
    /// Stops all motions.
    func stopAll() {
        isPlaying = false
        for timer in currentTimers {
            timer.invalidate()
        }
        currentTimers.removeAll()
    }
    
    /// Stops motion for a specific target.
    /// - Parameter targetName: Name of the target to stop
    func stop(targetName: String) {
        // Invalidate timers (they'll be cleared on next play)
        for timer in currentTimers {
            timer.invalidate()
        }
        currentTimers.removeAll()
    }
    
    deinit {
        stopAll()
    }
}

