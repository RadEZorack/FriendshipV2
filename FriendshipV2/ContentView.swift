//
//  ContentView.swift
//  FriendshipV2
//
//  Created by Travis Miller on 2025-12-08.
//

import SwiftUI
import RealityKit
import ARKit
import ModelIO
import AuthenticationServices
import UIKit

// Import our new IK and Avatar modules
// Note: In Xcode, these will be automatically available if they're in the same target

struct ContentView: View {
    @StateObject private var auth = AuthService.shared
    @StateObject private var meshService = MeshGenerationService.shared
    @State private var selectedTab: TabSelection = .ar
    @State private var selectedMeshId: String?
    @State private var showingMeshSelector = false
    @State private var selectedIKTarget: String?
    @State private var shouldPlaceAvatar = false

    var body: some View {
        Group {
            if auth.isAuthenticated {
                TabView(selection: $selectedTab) {
                    ZStack {
                        ARViewContainer(
                            isActive: selectedTab == .ar,
                            selectedMeshId: selectedMeshId,
                            selectedIKTarget: $selectedIKTarget,
                            shouldPlaceAvatar: $shouldPlaceAvatar,
                            onAvatarPlaced: {
                                shouldPlaceAvatar = false
                            }
                        )
                        .edgesIgnoringSafeArea(.all)
                        
                        // UI Overlay
                        VStack {
                            HStack {
                                Spacer()
                                Button(action: {
                                    showingMeshSelector = true
                                }) {
                                    Image(systemName: "person.3.fill")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                        .padding()
                                        .background(Color.black.opacity(0.6))
                                        .clipShape(Circle())
                                }
                                .padding()
                            }
                            Spacer()
                            
                            // Place Avatar Button
                            Button(action: {
                                shouldPlaceAvatar = true
                            }) {
                                HStack {
                                    Image(systemName: "person.crop.circle.badge.plus")
                                    Text("Place Avatar")
                                }
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.blue.opacity(0.8))
                                .cornerRadius(12)
                            }
                            .padding(.bottom, 12)
                            
                            // IK Target Selection Buttons
                            HStack(spacing: 12) {
                                IKTargetButton(
                                    title: "Head",
                                    targetName: "head_end",
                                    selectedTarget: $selectedIKTarget
                                )
                                IKTargetButton(
                                    title: "L Arm",
                                    targetName: "leftArm_end",
                                    selectedTarget: $selectedIKTarget
                                )
                                IKTargetButton(
                                    title: "R Arm",
                                    targetName: "rightArm_end",
                                    selectedTarget: $selectedIKTarget
                                )
                                IKTargetButton(
                                    title: "L Leg",
                                    targetName: "leftLeg_end",
                                    selectedTarget: $selectedIKTarget
                                )
                                IKTargetButton(
                                    title: "R Leg",
                                    targetName: "rightLeg_end",
                                    selectedTarget: $selectedIKTarget
                                )
                            }
                            .padding(.bottom, 40)
                        }
                    }
                    .tabItem {
                        Label("AR", systemImage: "arkit")
                    }
                    .tag(TabSelection.ar)
                    .sheet(isPresented: $showingMeshSelector) {
                        MeshSelectorView(selectedMeshId: $selectedMeshId)
                    }
                    
                    AvatarGeneratorView()
                        .tabItem {
                            Label("Avatar", systemImage: "person.fill")
                        }
                        .tag(TabSelection.avatar)
                }
            } else {
                LoginView()
            }
        }
        .animation(.default, value: auth.isAuthenticated)
        .task {
            // Load user avatars after initial render (non-blocking)
            // Using .task instead of .onAppear ensures it runs asynchronously
            if auth.isAuthenticated {
                try? await meshService.fetchUserAvatars()
            }
        }
    }
}

enum TabSelection {
    case ar
    case avatar
}

struct ARViewContainer: UIViewRepresentable {
    let isActive: Bool
    let selectedMeshId: String?
    @Binding var selectedIKTarget: String?
    @Binding var shouldPlaceAvatar: Bool
    var onAvatarPlaced: (() -> Void)?
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        // Configure AR session with LiDAR scene depth
        let config = ARWorldTrackingConfiguration()
        
        // Enable LiDAR scene depth if available
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        
        // Enable plane detection
        config.planeDetection = [.horizontal, .vertical]
        
        // Enable scene depth for occlusion (requires LiDAR)
        if type(of: config).supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        
        // Store config in coordinator for later use
        context.coordinator.arConfig = config
        
        // Run the AR session only if active
        if isActive {
            arView.session.run(config)
            context.coordinator.isPaused = false
        } else {
            context.coordinator.isPaused = true
        }
        
        // Enable occlusion from people and scene depth
        arView.environment.sceneUnderstanding.options.insert(.occlusion)
        
        // Add coordinator as delegate
        context.coordinator.arView = arView
        arView.session.delegate = context.coordinator
        
        // Add a tap gesture recognizer to place cube at center
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tapGesture.isEnabled = isActive
        arView.addGestureRecognizer(tapGesture)
        context.coordinator.tapGesture = tapGesture
        
        // Add lighting
        arView.environment.lighting.intensityExponent = 1.5
        
        // Add a crosshair at the center of the screen
        addCrosshair(to: arView)
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // Update selected mesh ID
        updateCoordinator(context.coordinator)
        
        // Pause or resume AR session based on active state
        if isActive {
            // Resume AR session if it was paused
            if context.coordinator.isPaused {
                let config = context.coordinator.arConfig ?? {
                    let newConfig = ARWorldTrackingConfiguration()
                    if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                        newConfig.sceneReconstruction = .mesh
                    }
                    newConfig.planeDetection = [.horizontal, .vertical]
                    if type(of: newConfig).supportsFrameSemantics(.sceneDepth) {
                        newConfig.frameSemantics.insert(.sceneDepth)
                    }
                    return newConfig
                }()
                uiView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
                context.coordinator.isPaused = false
            }
            // Enable tap gesture and allow hit testing
            context.coordinator.tapGesture?.isEnabled = true
            uiView.isUserInteractionEnabled = true
        } else {
            // Pause AR session to save resources
            if !context.coordinator.isPaused {
                uiView.session.pause()
                context.coordinator.isPaused = true
            }
            // Disable tap gesture and hit testing to prevent interference
            context.coordinator.tapGesture?.isEnabled = false
            uiView.isUserInteractionEnabled = false
        }
    }
    
    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.selectedMeshId = selectedMeshId
        coordinator.selectedIKTarget = selectedIKTarget
        coordinator.shouldPlaceAvatar = shouldPlaceAvatar
        return coordinator
    }
    
    func updateCoordinator(_ coordinator: Coordinator) {
        coordinator.selectedMeshId = selectedMeshId
        coordinator.selectedIKTarget = selectedIKTarget
        coordinator.onAvatarPlaced = onAvatarPlaced
        
        // Handle avatar placement trigger
        if shouldPlaceAvatar && !coordinator.shouldPlaceAvatar {
            coordinator.placeAvatarAtCenter()
        }
        coordinator.shouldPlaceAvatar = shouldPlaceAvatar
    }
    
    func addCrosshair(to arView: ARView) {
        let crosshairView = UIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        crosshairView.backgroundColor = .clear
        crosshairView.translatesAutoresizingMaskIntoConstraints = false
        
        let horizontalLine = UIView(frame: CGRect(x: 0, y: 9, width: 20, height: 2))
        horizontalLine.backgroundColor = .white
        horizontalLine.layer.shadowColor = UIColor.black.cgColor
        horizontalLine.layer.shadowOpacity = 0.8
        horizontalLine.layer.shadowRadius = 2
        
        let verticalLine = UIView(frame: CGRect(x: 9, y: 0, width: 2, height: 20))
        verticalLine.backgroundColor = .white
        verticalLine.layer.shadowColor = UIColor.black.cgColor
        verticalLine.layer.shadowOpacity = 0.8
        verticalLine.layer.shadowRadius = 2
        
        crosshairView.addSubview(horizontalLine)
        crosshairView.addSubview(verticalLine)
        arView.addSubview(crosshairView)
        
        NSLayoutConstraint.activate([
            crosshairView.centerXAnchor.constraint(equalTo: arView.centerXAnchor),
            crosshairView.centerYAnchor.constraint(equalTo: arView.centerYAnchor),
            crosshairView.widthAnchor.constraint(equalToConstant: 20),
            crosshairView.heightAnchor.constraint(equalToConstant: 20)
        ])
    }
    
    class Coordinator: NSObject, ARSessionDelegate {
        weak var arView: ARView?
        var placedModel: Entity?
        var placedAnchor: AnchorEntity?
        var avatarRigController: AvatarRigController?
        var tapGesture: UITapGestureRecognizer?
        var arConfig: ARWorldTrackingConfiguration?
        var isPaused: Bool = false
        var selectedMeshId: String?
        var selectedIKTarget: String?
        var shouldPlaceAvatar: Bool = false
        var onAvatarPlaced: (() -> Void)?
        var currentMesh: MeshStatus?  // Store the current mesh data
        
        func loadMeshUSDZ(meshId: String) async -> (url: URL?, mesh: MeshStatus?) {
            do {
                // Fetch mesh details
                let mesh = try await MeshGenerationService.shared.fetchMesh(meshId: meshId)
                
                // Check if mesh has USDZ URL
                guard let usdzUrlString = mesh.animationUsdzUrl,
                      let usdzURL = URL(string: usdzUrlString) else {
                    print("⚠️ Mesh \(meshId) does not have a USDZ URL")
                    return (nil, mesh)
                }
                
                // Download and cache the USDZ file
                let filename = FileCacheService.shared.filenameFromURL(usdzURL)
                let cachedURL = try await FileCacheService.shared.downloadAndCache(url: usdzURL, filename: filename)
                
                print("✅ Loaded mesh USDZ from cache: \(cachedURL.path)")
                return (cachedURL, mesh)
            } catch {
                print("❌ Failed to load mesh USDZ: \(error.localizedDescription)")
                return (nil, nil)
            }
        }
        
        @objc func handleTap() {
            guard let arView = arView,
                  tapGesture?.isEnabled == true,
                  arView.session.configuration != nil else {
                return
            }
            
            // Get the center point of the screen
            let centerPoint = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            
            // Perform a raycast from the center of the screen
            let results = arView.raycast(from: centerPoint, allowing: .estimatedPlane, alignment: .any)
            
            var raycastTransform: simd_float4x4?
            
            // If no results from plane detection, try using existing plane anchors
            if results.isEmpty {
                // Try raycasting against existing scene geometry
                if let raycastQuery = arView.makeRaycastQuery(from: centerPoint, allowing: .existingPlaneGeometry, alignment: .any) {
                    let raycastResults = arView.session.raycast(raycastQuery)
                    if let firstResult = raycastResults.first {
                        raycastTransform = firstResult.worldTransform
                    }
                }
            } else if let firstResult = results.first {
                raycastTransform = firstResult.worldTransform
            }
            
            guard let transform = raycastTransform else {
                return
            }
            
            // If avatar is already placed and an IK target is selected, move the target
            if let rigController = avatarRigController,
               let targetName = selectedIKTarget {
                moveIKTarget(targetName: targetName, to: transform, in: arView, rigController: rigController)
            }
            // Otherwise, do nothing (avatar placement is handled by the button)
        }
        
        func placeAvatarAtCenter() {
            guard let arView = arView,
                  arView.session.configuration != nil else {
                return
            }
            
            // Get the center point of the screen
            let centerPoint = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            
            // Perform a raycast from the center of the screen
            let results = arView.raycast(from: centerPoint, allowing: .estimatedPlane, alignment: .any)
            
            var raycastTransform: simd_float4x4?
            
            // If no results from plane detection, try using existing plane anchors
            if results.isEmpty {
                // Try raycasting against existing scene geometry
                if let raycastQuery = arView.makeRaycastQuery(from: centerPoint, allowing: .existingPlaneGeometry, alignment: .any) {
                    let raycastResults = arView.session.raycast(raycastQuery)
                    if let firstResult = raycastResults.first {
                        raycastTransform = firstResult.worldTransform
                    }
                }
            } else if let firstResult = results.first {
                raycastTransform = firstResult.worldTransform
            }
            
            if let transform = raycastTransform {
                placeModel(at: transform, in: arView)
            } else {
                print("⚠️ Could not find a surface to place avatar")
            }
        }
        
        func moveIKTarget(targetName: String, to worldTransform: simd_float4x4, in arView: ARView, rigController: AvatarRigController) {
            guard let anchor = placedAnchor else {
                print("⚠️ No anchor found, cannot move IK target")
                return
            }
            
            // Get the target entity
            let target = rigController.targetController.target(named: targetName)
            
            // Create a temporary entity at the world transform position
            let worldEntity = Entity()
            worldEntity.transform = Transform(matrix: worldTransform)
            
            // Convert world transform to anchor's local space
            // Get the anchor's inverse transform to convert from world to local
            let anchorWorldTransform = anchor.transformMatrix(relativeTo: nil)
            let anchorInverseTransform = anchorWorldTransform.inverse
            
            // Multiply world transform by anchor's inverse to get local transform
            let localTransformMatrix = anchorInverseTransform * worldTransform
            
            // Convert to Transform
            let localTransform = Transform(matrix: localTransformMatrix)
            
            // Keep the current rotation and scale, only update position
            let currentTransform = target.transform
            let newTransform = Transform(
                scale: currentTransform.scale,
                rotation: currentTransform.rotation,
                translation: [localTransform.translation.x * 100.0, -localTransform.translation.z * 100.0, localTransform.translation.y * 100.0]
            )
            
            // Update target transform
            target.transform = newTransform
            
            // Update IK constraint target
            guard var ikComponent = placedModel?.components[IKComponent.self] else {
                print("⚠️ No IKComponent found")
                return
            }
            
            if var constraint = ikComponent.solvers[0].constraints[targetName] {
                constraint.target = newTransform
                ikComponent.solvers[0].constraints[targetName] = constraint
                placedModel?.components.set(ikComponent)
            }
            
            print("✅ Moved IK target \(targetName) to raycast intersection at \(localTransform.translation)")
            
            // Save updated pose to database
            saveCurrentPoseToDatabase(rigController: rigController)
        }
        
        /// Captures the current pose from all IK targets and saves it to the database
        func saveCurrentPoseToDatabase(rigController: AvatarRigController) {
            guard let meshId = self.selectedMeshId else {
                print("⚠️ No mesh ID selected, cannot save pose")
                return
            }
            
            // Get all end targets (these are the ones we care about for the initial pose)
            let endTargetNames = ["head_end", "leftArm_end", "rightArm_end", "leftLeg_end", "rightLeg_end"]
            var changes: [String: [[Double]]] = [:]
            
            // Capture current transforms for each end target
            for targetName in endTargetNames {
                let target = rigController.targetController.target(named: targetName)
                let transform = target.transform
                let matrix = transform.matrix
                
                // Convert simd_float4x4 to 2D array format
                let matrixArray: [[Double]] = [
                    [Double(matrix.columns.0.x), Double(matrix.columns.0.y), Double(matrix.columns.0.z), Double(matrix.columns.0.w)],
                    [Double(matrix.columns.1.x), Double(matrix.columns.1.y), Double(matrix.columns.1.z), Double(matrix.columns.1.w)],
                    [Double(matrix.columns.2.x), Double(matrix.columns.2.y), Double(matrix.columns.2.z), Double(matrix.columns.2.w)],
                    [Double(matrix.columns.3.x), Double(matrix.columns.3.y), Double(matrix.columns.3.z), Double(matrix.columns.3.w)]
                ]
                changes[targetName] = matrixArray
            }
            
            // Create the pose data in the expected format
            let poseData: [[String: Any]] = [
                [
                    "duration": 0.0,
                    "space": "local",
                    "changes": changes
                ]
            ]
            
            // Save to database asynchronously
            Task {
                do {
                    try await MeshGenerationService.shared.updateInitialPose(
                        meshId: meshId,
                        initialPose: poseData
                    )
                    print("✅ Successfully updated initial pose in database for mesh \(meshId)")
                } catch {
                    print("⚠️ Failed to update initial pose in database: \(error.localizedDescription)")
                }
            }
        }
        
        func placeModel(at transform: simd_float4x4, in arView: ARView) {
            // Remove previously placed content (anchor and model)
            if let previousAnchor = placedAnchor {
                avatarRigController?.cleanup()
                avatarRigController = nil
                previousAnchor.removeFromParent()
                placedAnchor = nil
                placedModel = nil
            } else if let previousModel = placedModel {
                avatarRigController?.cleanup()
                avatarRigController = nil
                previousModel.removeFromParent()
                placedModel = nil
            }

            Task {
                do {
                    var modelURL: URL?
                    var fetchedMesh: MeshStatus? = nil
                    
                    // Try to load from selected mesh first
                    if let meshId = self.selectedMeshId {
                        let result = await self.loadMeshUSDZ(meshId: meshId)
                        modelURL = result.url
                        fetchedMesh = result.mesh
                        self.currentMesh = fetchedMesh
                    }
                    
                    // Fallback to bundle file if no mesh selected or loading failed
                    if modelURL == nil {
                        modelURL = Bundle.main.url(forResource: "Animation_FunnyDancing_01", withExtension: "usdz")
                    }
                    
                    guard let modelURL = modelURL else {
                        print("Could not find USDZ file")
                        return
                    }
                    
                    print("Loading USDZ model from: \(modelURL.path)")

                    let rootEntity = try await Entity(contentsOf: modelURL)

                    // Try to use a ModelEntity, even if the root is a generic container
                    let modelEntity: ModelEntity
                    if let asModel = rootEntity as? ModelEntity {
                        modelEntity = asModel
                    } else if let found = findFirstModelEntity(in: rootEntity) {
                        modelEntity = found
                    } else {
                        print("Could not find a ModelEntity in loaded content hierarchy")
                        return
                    }
                    print("✓ Successfully resolved a ModelEntity from loaded content!")
                    
                    // Rotate model 90 degrees around X axis
                    modelEntity.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])

                    // Create an anchor entity
                    let anchorEntity = AnchorEntity(world: transform)
                    anchorEntity.addChild(modelEntity)

                    // Add to the scene
                    arView.scene.addAnchor(anchorEntity)

                    // Store references to the model and its anchor
                    self.placedModel = modelEntity
                    self.placedAnchor = anchorEntity
                    
                    // Debug: Print joint information as JSON-ready 2D arrays
                    var jointData: [String: simd_float4x4] = [:]
                    var jointDataArray: [String: [[Double]]] = [:]

                    for i in modelEntity.jointNames.indices {
                        let matrix = modelEntity.jointTransforms[i].matrix
                        jointData[modelEntity.jointNames[i]] = matrix

                        // Convert simd_float4x4 to 2D array (4x4 matrix)
                        // Convert Float to Double for JSON serialization
                        let matrixArray: [[Double]] = [
                            [Double(matrix.columns.0.x), Double(matrix.columns.0.y), Double(matrix.columns.0.z), Double(matrix.columns.0.w)],
                            [Double(matrix.columns.1.x), Double(matrix.columns.1.y), Double(matrix.columns.1.z), Double(matrix.columns.1.w)],
                            [Double(matrix.columns.2.x), Double(matrix.columns.2.y), Double(matrix.columns.2.z), Double(matrix.columns.2.w)],
                            [Double(matrix.columns.3.x), Double(matrix.columns.3.y), Double(matrix.columns.3.z), Double(matrix.columns.3.w)]
                        ]
                        jointDataArray[modelEntity.jointNames[i]] = matrixArray
                    }
                    
                    // Convert to JSON string
                    if let jsonData = try? JSONSerialization.data(withJSONObject: jointDataArray, options: .prettyPrinted),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        // print(jsonString)
                    } else {
                        // Fallback: print as dictionary
                        // print(jointDataArray)
                    }

                    // Define the left arm limb for IK
                    let leftArmLimb = IKLimb(
                        baseJoint: "Hips/Spine02/Spine01/Spine/LeftShoulder/LeftArm",
                        endJoint: "Hips/Spine02/Spine01/Spine/LeftShoulder/LeftArm/LeftForeArm/LeftHand",
                        baseWeight: [0.0, 0.0, 0.0],
                        endPositionWeight: [1.0, 1.0, 1.0],
                        endOrientationWeight: [0.0, 0.0, 0.0]
                    )
                    
                    // Define the right arm limb for IK
                    let rightArmLimb = IKLimb(
                        baseJoint: "Hips/Spine02/Spine01/Spine/RightShoulder/RightArm",
                        endJoint: "Hips/Spine02/Spine01/Spine/RightShoulder/RightArm/RightForeArm/RightHand",
                        baseWeight: [0.0, 0.0, 0.0],
                        endPositionWeight: [1.0, 1.0, 1.0],
                        endOrientationWeight: [0.0, 0.0, 0.0]
                    )

                    let leftLegLimb = IKLimb(
                        baseJoint: "Hips/LeftUpLeg",
                        endJoint: "Hips/LeftUpLeg/LeftLeg/LeftFoot",
                        baseWeight: [0.0, 0.0, 0.0],
                        endPositionWeight: [1.0, 1.0, 1.0],
                        endOrientationWeight: [0.0, 0.0, 0.0]
                    )
                    
                    let rightLegLimb = IKLimb(
                        baseJoint: "Hips/RightUpLeg",
                        endJoint: "Hips/RightUpLeg/RightLeg/RightFoot",
                        baseWeight: [0.0, 0.0, 0.0],
                        endPositionWeight: [1.0, 1.0, 1.0],
                        endOrientationWeight: [0.0, 0.0, 0.0]
                    )

                    let headLimb = IKLimb(
                        baseJoint: "Hips/Spine02/Spine01/Spine/neck",
                        endJoint: "Hips/Spine02/Spine01/Spine/neck/Head/headfront",
                        baseWeight: [0.0, 0.0, 0.0],
                        endPositionWeight: [0.4, 0.4, 0.4],
                        endOrientationWeight: [1.0, 1.0, 1.0] // orientation matters most
                    )

                    // let hipsLimb = IKLimb(
                    //     baseJoint: "Hips",
                    //     endJoint: "Hips",
                    //     baseWeight: [0.8, 0.8, 0.8],
                    //     endPositionWeight: [1.0, 1.0, 1.0],
                    //     endOrientationWeight: [0.3, 0.3, 0.3]
                    // )
                    
                    // Create avatar rig controller
                    let rigController = try AvatarRigController(
                        entity: modelEntity,
                        anchor: anchorEntity,
                        limbs: [
                            "leftArm": leftArmLimb,
                            "rightArm": rightArmLimb,
                            "leftLeg": leftLegLimb,
                            "rightLeg": rightLegLimb,
                            "head": headLimb,
                            // "hips": hipsLimb
                        ],
                        initialTargetMatrices: jointData,
                        jointRefinements: [
                            "Hips/Spine02/Spine01/Spine/LeftShoulder/LeftArm/LeftForeArm/LeftHand": SIMD3<Float>(0.0, 0.0, 0.0),
                            "Hips/Spine02/Spine01/Spine/RightShoulder/RightArm/RightForeArm/RightHand": SIMD3<Float>(0.0, 0.0, 0.0),
                            "Hips/LeftUpLeg/LeftLeg/LeftFoot": SIMD3<Float>(0.0, 0.0, 0.0),
                            "Hips/RightUpLeg/RightLeg/RightFoot": SIMD3<Float>(0.0, 0.0, 0.0),
                            "Hips/Spine02/Spine01/Spine/neck/Head/headfront": SIMD3<Float>(0.0, 0.0, 0.0),
                            // "Hips": SIMD3<Float>(0.0, 0.0, 0.0)
                        ]
                    )
                    
                    // Store rig controller
                    self.avatarRigController = rigController
                    
                    // Call the callback to reset the placement flag
                    DispatchQueue.main.async {
                        self.onAvatarPlaced?()
                    }

                    // DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    //     rigController.raiseRightHand()
                    // }
                    
                    // Test: Apply hardcoded joint animation from AI response
                    // let testAnimationJSON1 = """
                    // [
                    // {
                    //   "duration": 0.0,
                    //   "space": "local",
                    //   "changes": {
                    //     "leftArm_end": {
                    //       "matrix": [
                    //         [ 1.0,  0.0,  0.0, 0.0 ],
                    //         [ 0.0,  0.0, -1.0, 0.0 ],
                    //         [ 0.0,  1.0,  0.0, 0.0 ],
                    //         [ 80.0,  0.0,  160.0, 1.0 ]
                    //       ]
                    //     },
                    //     "rightArm_end": {
                    //       "matrix": [
                    //         [ 1.0,  0.0,  0.0, 0.0 ],
                    //         [ 0.0,  0.0, -1.0, 0.0 ],
                    //         [ 0.0,  1.0,  0.0, 0.0 ],
                    //         [ -80.0,  0.0,  160.0, 1.0 ]
                    //       ]
                    //     }
                    //   }
                    // },
                    // {
                    //   "duration": 0.5,
                    //   "space": "local",
                    //   "changes": {
                    //     "rightLeg_end": {
                    //       "matrix": [
                    //         [ 1.0,  0.0,  0.0, 0.0 ],
                    //         [ 0.0,  0.0, -1.0, 0.0 ],
                    //         [ 0.0,  1.0,  0.0, 0.0 ],
                    //         [ -20.0,  60.0,  0.0, 1.0 ]
                    //       ]
                    //     },
                    //     "leftLeg_end": {
                    //       "matrix": [
                    //         [ 1.0,  0.0,  0.0, 0.0 ],
                    //         [ 0.0,  0.0, -1.0, 0.0 ],
                    //         [ 0.0,  1.0,  0.0, 0.0 ],
                    //         [ 20.0,  -60.0,  0.0, 1.0 ]
                    //       ]
                    //     }
                    //   }
                    // },
                    // {
                    //   "duration": 0.5,
                    //   "space": "local",
                    //   "changes": {
                    //     "rightLeg_end": {
                    //       "matrix": [
                    //         [ 1.0,  0.0,  0.0, 0.0 ],
                    //         [ 0.0,  0.0, -1.0, 0.0 ],
                    //         [ 0.0,  1.0,  0.0, 0.0 ],
                    //         [ -20.0,  -60.0,  0.0, 1.0 ]
                    //       ]
                    //     },
                    //     "leftLeg_end": {
                    //       "matrix": [
                    //         [ 1.0,  0.0,  0.0, 0.0 ],
                    //         [ 0.0,  0.0, -1.0, 0.0 ],
                    //         [ 0.0,  1.0,  0.0, 0.0 ],
                    //         [ 20.0,  60.0,  0.0, 1.0 ]
                    //       ]
                    //     }
                    //   }
                    // }
                    // ]
                    // """
                    // Determine which initial pose to use: from DB or default
                    var initialPoseData: [[String: Any]]? = nil
                    var shouldSavePose = false
                    
                    // First, try to use saved pose from database
                    if let savedPose = fetchedMesh?.initialPose, !savedPose.isEmpty {
                        print("✅ Found saved initial pose in database, using it")
                        initialPoseData = savedPose
                    } else {
                        // Use default pose and save it
                        print("ℹ️ No saved pose found, using default and saving to database")
                        let defaultPose: [[String: Any]] = [
                            [
                                "duration": 0.0,
                                "space": "local",
                                "changes": [
                                    "head_end": [
                                        [1.0, 0.0, 0.0, 0.0],
                                        [0.0, 1.0, 0.0, 0.0],
                                        [0.0, 0.0, 1.0, 0.0],
                                        [0.0, 0.0, 170.0, 1.0]
                                    ],
                                    "leftArm_end": [
                                        [1.0, 0.0, 0.0, 0.0],
                                        [0.0, 1.0, 0.0, 0.0],
                                        [0.0, 0.0, 1.0, 0.0],
                                        [70.0, 0.0, 140.0, 1.0]
                                    ],
                                    "rightArm_end": [
                                        [1.0, 0.0, 0.0, 0.0],
                                        [0.0, 1.0, 0.0, 0.0],
                                        [0.0, 0.0, 1.0, 0.0],
                                        [-70.0, 0.0, 140.0, 1.0]
                                    ],
                                    "rightLeg_end": [
                                        [1.0, 0.0, 0.0, 0.0],
                                        [0.0, 1.0, 0.0, 0.0],
                                        [0.0, 0.0, 1.0, 0.0],
                                        [-20.0, 0.0, 0.0, 1.0]
                                    ],
                                    "leftLeg_end": [
                                        [1.0, 0.0, 0.0, 0.0],
                                        [0.0, 1.0, 0.0, 0.0],
                                        [0.0, 0.0, 1.0, 0.0],
                                        [20.0, 0.0, 0.0, 1.0]
                                    ]
                                ]
                            ]
                        ]
                        initialPoseData = defaultPose
                        shouldSavePose = true
                    }
                    
                    // Apply the initial pose animation
                    if let initialPose = initialPoseData,
                       let jsonData = try? JSONSerialization.data(withJSONObject: initialPose),
                       let animations: [JointAnimation] = try? JSONDecoder().decode([JointAnimation].self, from: jsonData) {
                        // Apply animation after a brief delay
                        DispatchQueue.main.asyncAfter(deadline: .now()) {
                            rigController.applyJointAnimation(animations)
                        }
                        
                        // Save initial pose to backend if needed
                        if shouldSavePose, let meshId = self.selectedMeshId {
                            Task {
                                do {
                                    try await MeshGenerationService.shared.updateInitialPose(
                                        meshId: meshId,
                                        initialPose: initialPose
                                    )
                                    print("✅ Successfully saved initial pose to backend for mesh \(meshId)")
                                } catch {
                                    print("⚠️ Failed to save initial pose to backend: \(error.localizedDescription)")
                                }
                            }
                        }
                    } else {
                        print("⚠️ Failed to decode initial pose JSON")
                    }

                    // // Test: Apply hardcoded joint animation from AI response
                    let testAnimationJSON = """
                    [
                    {
                        "duration": 0.0,
                        "space": "local",
                        "changes": {
                        "leftArm_end": [
                            [1, 0, 0, 0],
                            [0, 1, 0, 0],
                            [0, 0, 1, 0],
                            [0, 0, 170, 1]
                        ]
                        }
                    }
                    ]
                    """
                    
                    // if let jsonData = testAnimationJSON.data(using: .utf8),
                    //    let animations: [JointAnimation] = try? JSONDecoder().decode([JointAnimation].self, from: jsonData) {
                    //     // Apply animation after a brief delay
                    //     DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    //         rigController.applyJointAnimation(animations)
                    //     }
                    // } else {
                    //     print("⚠️ Failed to decode test animation JSON")
                    //     // DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    //     //     rigController.raiseRightHand()
                    //     // }
                    // }
                }
            }
        }
        
        private func findFirstModelEntity(in entity: Entity) -> ModelEntity? {
            if let model = entity as? ModelEntity { return model }
            for child in entity.children {
                if let found = findFirstModelEntity(in: child) { return found }
            }
            return nil
        }
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // Optionally, you could continuously update cube position here
            // based on depth data from the center of the screen
        }
    }
}

// IK Target Selection Button
struct IKTargetButton: View {
    let title: String
    let targetName: String
    @Binding var selectedTarget: String?
    
    var isSelected: Bool {
        selectedTarget == targetName
    }
    
    var body: some View {
        Button(action: {
            // Toggle selection
            if selectedTarget == targetName {
                selectedTarget = nil
            } else {
                selectedTarget = targetName
            }
        }) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isSelected ? .black : .white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isSelected ? Color.white : Color.black.opacity(0.6))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.white : Color.clear, lineWidth: 2)
                )
        }
    }
}

#Preview {
    ContentView()
}

