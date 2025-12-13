//
//  TargetMotion.swift
//  FriendshipV2
//
//  Created by Travis Miller on 2025-12-08.
//

import Foundation
import RealityKit

/// Describes a motion as data - a sequence of transforms for a target entity.
struct TargetMotion {
    let targetName: String
    let duration: TimeInterval
    let transforms: [Transform]
    let timing: [AnimationTimingFunction]
    
    /// Creates a motion with a single transform.
    /// - Parameters:
    ///   - targetName: Name of the target entity to animate
    ///   - duration: Duration of the animation
    ///   - transform: The target transform
    ///   - timing: Timing function for the animation
    init(
        targetName: String,
        duration: TimeInterval,
        transform: Transform,
        timing: AnimationTimingFunction = .easeInOut
    ) {
        self.targetName = targetName
        self.duration = duration
        self.transforms = [transform]
        self.timing = [timing]
    }
    
    /// Creates a motion with multiple transforms.
    /// - Parameters:
    ///   - targetName: Name of the target entity to animate
    ///   - duration: Total duration of the animation
    ///   - transforms: Sequence of transforms to animate through
    ///   - timing: Timing functions for each transform (must match transforms count)
    init(
        targetName: String,
        duration: TimeInterval,
        transforms: [Transform],
        timing: [AnimationTimingFunction]
    ) {
        self.targetName = targetName
        self.duration = duration
        self.transforms = transforms
        self.timing = timing
    }
}

