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
import Combine

// Import our new IK and Avatar modules
// Note: In Xcode, these will be automatically available if they're in the same target

// Shared state for orb controls
class OrbControlState: ObservableObject {
    weak var coordinator: ARViewContainer.Coordinator?
    @Published var isReady: Bool = false
    
    func updateTargetPosition(orbName: String, axis: OrbAxis, translation: CGSize) {
        guard let coordinator = coordinator,
              let rigController = coordinator.avatarRigController else {
            return
        }
        
        let target = rigController.targetController.target(named: orbName)
        let currentTransform = target.transform
        
        let sensitivity: Float = 0.5
        var newTranslation = currentTransform.translation
        
        switch axis {
        case .x:
            newTranslation.x += Float(translation.width) * sensitivity
        case .y:
            newTranslation.y += Float(translation.height) * sensitivity
        case .z:
            newTranslation.z += Float(-translation.height) * sensitivity
        }
        
        var newTransform = currentTransform
        newTransform.translation = newTranslation
        target.transform = newTransform
    }
    
    func updateTargetPositionInPlane(orbName: String, screenPoint: CGPoint) {
        guard let coordinator = coordinator,
              let rigController = coordinator.avatarRigController,
              let arView = coordinator.arView else {
            return
        }
        
        // Raycast from screen point to find 3D position
        let results = arView.raycast(from: screenPoint, allowing: .estimatedPlane, alignment: .any)
        
        if let firstResult = results.first {
            // Use the raycast result's world position
            let worldTransform = firstResult.worldTransform
            let worldPosition = SIMD3<Float>(
                worldTransform.columns.3.x,
                worldTransform.columns.3.y,
                worldTransform.columns.3.z
            )
            
            let target = rigController.targetController.target(named: orbName)
            var newTransform = target.transform
            newTransform.translation = worldPosition
            target.transform = newTransform
        } else {
            // Fallback: try existing plane geometry
            if let raycastQuery = arView.makeRaycastQuery(from: screenPoint, allowing: .existingPlaneGeometry, alignment: .any) {
                let raycastResults = arView.session.raycast(raycastQuery)
                if let firstResult = raycastResults.first {
                    let worldTransform = firstResult.worldTransform
                    let worldPosition = SIMD3<Float>(
                        worldTransform.columns.3.x,
                        worldTransform.columns.3.y,
                        worldTransform.columns.3.z
                    )
                    
                    let target = rigController.targetController.target(named: orbName)
                    var newTransform = target.transform
                    newTransform.translation = worldPosition
                    target.transform = newTransform
                } else {
                    // If no raycast hit, project to a plane at the current target's depth
                    guard let frame = arView.session.currentFrame else { return }
                    let cameraTransform = frame.camera.transform
                    let cameraPosition = SIMD3<Float>(
                        cameraTransform.columns.3.x,
                        cameraTransform.columns.3.y,
                        cameraTransform.columns.3.z
                    )
                    
                    let target = rigController.targetController.target(named: orbName)
                    let currentPos = target.transform.translation
                    
                    // Project screen point to a plane at the target's depth
                    let depth = simd_length(currentPos - cameraPosition)
                    if depth > 0 {
                        let normalizedPoint = CGPoint(
                            x: (screenPoint.x / arView.bounds.width - 0.5) * 2.0,
                            y: (0.5 - screenPoint.y / arView.bounds.height) * 2.0
                        )
                        
                        // Get FOV from camera intrinsics or use default
                        let fov: Float
                        if let frame = arView.session.currentFrame {
                            let intrinsics = frame.camera.intrinsics
                            // Calculate horizontal FOV from intrinsics
                            let fx = intrinsics[0][0]
                            let imageWidth = Float(frame.camera.imageResolution.width)
                            fov = 2.0 * atan(imageWidth / (2.0 * fx))
                        } else {
                            fov = 60.0 * .pi / 180.0 // Default 60 degrees
                        }
                        let aspect = Float(arView.bounds.width / arView.bounds.height)
                        
                        let rightVector = SIMD3<Float>(cameraTransform.columns.0.x, cameraTransform.columns.0.y, cameraTransform.columns.0.z)
                        let upVector = SIMD3<Float>(cameraTransform.columns.1.x, cameraTransform.columns.1.y, cameraTransform.columns.1.z)
                        let forwardVector = SIMD3<Float>(-cameraTransform.columns.2.x, -cameraTransform.columns.2.y, -cameraTransform.columns.2.z)
                        
                        let horizontalOffset = rightVector * Float(normalizedPoint.x) * depth * tan(fov / 2.0) * aspect
                        let verticalOffset = upVector * Float(normalizedPoint.y) * depth * tan(fov / 2.0)
                        
                        let newPosition = cameraPosition + forwardVector * depth + horizontalOffset + verticalOffset
                        
                        var newTransform = target.transform
                        newTransform.translation = newPosition
                        target.transform = newTransform
                    }
                }
            }
        }
    }
    
    func initializeOrbPositions() {
        guard let coordinator = coordinator,
              let rigController = coordinator.avatarRigController,
              let anchor = coordinator.placedAnchor else {
            return
        }
        
        // Initialize orbs at their default positions from the starting animation
        // These positions are in centimeters, convert to meters (divide by 100)
        // Coordinate system: X=left/right, Y=up/down, Z=forward/back
        // Since feet look good at z=0, and head/arms are too close with positive z,
        // we should use Y for vertical and keep Z closer to 0 or negative
        let scaleFactor: Float = 0.01 // 1cm = 0.01m
        let defaultPositions: [String: SIMD3<Float>] = [
            "head_end": SIMD3<Float>(0.0, 0.0, 170.0 * scaleFactor),      // 1.7m up (use Y axis)
            "leftArm_end": SIMD3<Float>(70.0 * scaleFactor, 0.0, 140.0 * scaleFactor),  // 0.7m left, 1.4m up
            "rightArm_end": SIMD3<Float>(-70.0 * scaleFactor, 0.0, 140.0 * scaleFactor), // 0.7m right, 1.4m up
            "rightLeg_end": SIMD3<Float>(-20.0 * scaleFactor, 0.0, 0.0),  // 0.2m right
            "leftLeg_end": SIMD3<Float>(20.0 * scaleFactor, 0.0, 0.0)     // 0.2m left
        ]
        
        print("🎯 Initializing orb positions with scale factor: \(scaleFactor)")
        for (name, pos) in defaultPositions {
            print("   \(name): \(pos)")
        }
        
        for (orbName, position) in defaultPositions {
            let target = rigController.targetController.target(named: orbName)
            
            // Get the current transform to preserve any coordinate system setup
            var transform = target.transform
            
            // Only update the translation, keeping rotation and scale as-is
            // This preserves the coordinate system the IK system expects
            transform.translation = position
            
            target.transform = transform
            
            print("🎯 Set target \(orbName) translation to: \(position)")
            print("   Full transform: \(transform)")
            print("   Target position relative to anchor: \(target.position(relativeTo: anchor))")
        }
    }
    
    func project3DToScreen(_ worldPosition: SIMD3<Float>) -> CGPoint? {
        guard let coordinator = coordinator,
              let arView = coordinator.arView,
              let frame = arView.session.currentFrame else {
            return nil
        }
        
        // Convert world position to camera space
        let cameraTransform = frame.camera.transform
        let cameraPosition = SIMD3<Float>(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )
        
        let worldToCamera = worldPosition - cameraPosition
        
        // Get camera basis vectors
        let right = SIMD3<Float>(cameraTransform.columns.0.x, cameraTransform.columns.0.y, cameraTransform.columns.0.z)
        let up = SIMD3<Float>(cameraTransform.columns.1.x, cameraTransform.columns.1.y, cameraTransform.columns.1.z)
        let forward = SIMD3<Float>(-cameraTransform.columns.2.x, -cameraTransform.columns.2.y, -cameraTransform.columns.2.z)
        
        // Project to camera space
        let depth = simd_dot(worldToCamera, forward)
        guard depth > 0 else { return nil } // Behind camera
        
        let horizontal = simd_dot(worldToCamera, right)
        let vertical = simd_dot(worldToCamera, up)
        
        // Get FOV and aspect ratio
        let fov: Float
        if let frame = arView.session.currentFrame {
            let intrinsics = frame.camera.intrinsics
            // Calculate horizontal FOV from intrinsics
            let fx = intrinsics[0][0]
            let imageWidth = Float(frame.camera.imageResolution.width)
            fov = 2.0 * atan(imageWidth / (2.0 * fx))
        } else {
            fov = 60.0 * .pi / 180.0 // Default 60 degrees
        }
        let aspect = Float(arView.bounds.width / arView.bounds.height)
        
        // Normalize to screen coordinates
        let normalizedX = horizontal / (depth * tan(fov / 2.0) * aspect)
        let normalizedY = vertical / (depth * tan(fov / 2.0))
        
        // Convert to screen coordinates
        let screenX = (normalizedX + 1.0) * 0.5 * Float(arView.bounds.width)
        let screenY = (1.0 - normalizedY) * 0.5 * Float(arView.bounds.height)
        
        return CGPoint(x: CGFloat(screenX), y: CGFloat(screenY))
    }
    
    func placeCharacter() {
        coordinator?.placeCharacterAtCenter()
    }
}

struct ContentView: View {
    @StateObject private var auth = AuthService.shared
    @StateObject private var meshService = MeshGenerationService.shared
    @StateObject private var orbControlState = OrbControlState()
    @State private var selectedTab: TabSelection = .ar
    @State private var selectedMeshId: String?
    @State private var showingMeshSelector = false

    var body: some View {
        Group {
            if auth.isAuthenticated {
                TabView(selection: $selectedTab) {
                    ZStack {
                        ARViewContainer(
                            isActive: selectedTab == .ar,
                            selectedMeshId: selectedMeshId,
                            orbControlState: orbControlState
                        )
                        .edgesIgnoringSafeArea(.all)
                        
                        // Control buttons
                        VStack {
                            HStack {
                                // Place character button
                                Button(action: {
                                    orbControlState.placeCharacter()
                                }) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                        .padding()
                                        .background(Color.blue.opacity(0.8))
                                        .clipShape(Circle())
                                }
                                .padding()
                                
                                Spacer()
                                
                                // Mesh selector button
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
    @ObservedObject var orbControlState: OrbControlState
    
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
            // Allow hit testing
            uiView.isUserInteractionEnabled = true
        } else {
            // Pause AR session to save resources
            if !context.coordinator.isPaused {
                uiView.session.pause()
                context.coordinator.isPaused = true
            }
            // Disable hit testing to prevent interference
            uiView.isUserInteractionEnabled = false
        }
    }
    
    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.selectedMeshId = selectedMeshId
        coordinator.orbControlState = orbControlState
        orbControlState.coordinator = coordinator
        return coordinator
    }
    
    func updateCoordinator(_ coordinator: Coordinator) {
        coordinator.selectedMeshId = selectedMeshId
        coordinator.orbControlState = orbControlState
        orbControlState.coordinator = coordinator
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
        var arConfig: ARWorldTrackingConfiguration?
        var isPaused: Bool = false
        var selectedMeshId: String?
        var orbControlState: OrbControlState?
        var orbEntities: [String: ModelEntity] = [:]
        var draggingOrb: String?
        var dragStartPosition: SIMD3<Float>?
        
        func loadMeshUSDZ(meshId: String) async -> URL? {
            do {
                // Fetch mesh details
                let mesh = try await MeshGenerationService.shared.fetchMesh(meshId: meshId)
                
                // Check if mesh has USDZ URL
                guard let usdzUrlString = mesh.animationUsdzUrl,
                      let usdzURL = URL(string: usdzUrlString) else {
                    print("⚠️ Mesh \(meshId) does not have a USDZ URL")
                    return nil
                }
                
                // Download and cache the USDZ file
                let filename = FileCacheService.shared.filenameFromURL(usdzURL)
                let cachedURL = try await FileCacheService.shared.downloadAndCache(url: usdzURL, filename: filename)
                
                print("✅ Loaded mesh USDZ from cache: \(cachedURL.path)")
                return cachedURL
            } catch {
                print("❌ Failed to load mesh USDZ: \(error.localizedDescription)")
                return nil
            }
        }
        
        func placeCharacterAtCenter() {
            guard let arView = arView,
                  arView.session.configuration != nil else {
                return
            }
            
            // Get the center point of the screen
            let centerPoint = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            
            // Perform a raycast from the center of the screen
            let results = arView.raycast(from: centerPoint, allowing: .estimatedPlane, alignment: .any)
            
            // If no results from plane detection, try using existing plane anchors
            if results.isEmpty {
                // Try raycasting against existing scene geometry
                if let raycastQuery = arView.makeRaycastQuery(from: centerPoint, allowing: .existingPlaneGeometry, alignment: .any) {
                    let raycastResults = arView.session.raycast(raycastQuery)
                    if let firstResult = raycastResults.first {
                        placeModel(at: firstResult.worldTransform, in: arView)
                        return
                    }
                }
            } else if let firstResult = results.first {
                placeModel(at: firstResult.worldTransform, in: arView)
            }
        }
        
        func placeModel(at transform: simd_float4x4, in arView: ARView) {
            // Remove previously placed content (anchor and model)
            if let previousAnchor = placedAnchor {
                // Clean up orbs
                stopOrbPositionSync()
                for (_, orbEntity) in orbEntities {
                    orbEntity.removeFromParent()
                }
                orbEntities.removeAll()
                
                avatarRigController?.cleanup()
                avatarRigController = nil
                previousAnchor.removeFromParent()
                placedAnchor = nil
                placedModel = nil
            } else if let previousModel = placedModel {
                // Clean up orbs
                stopOrbPositionSync()
                for (_, orbEntity) in orbEntities {
                    orbEntity.removeFromParent()
                }
                orbEntities.removeAll()
                
                avatarRigController?.cleanup()
                avatarRigController = nil
                previousModel.removeFromParent()
                placedModel = nil
            }

            Task {
                do {
                    var modelURL: URL?
                    
                    // Try to load from selected mesh first
                    if let meshId = self.selectedMeshId {
                        modelURL = await self.loadMeshUSDZ(meshId: meshId)
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
                        baseWeight: [0.8, 0.8, 0.8],
                        endPositionWeight: [1.0, 1.0, 1.0],
                        endOrientationWeight: [0.4, 0.4, 0.4]
                    )
                    
                    // Define the right arm limb for IK
                    let rightArmLimb = IKLimb(
                        baseJoint: "Hips/Spine02/Spine01/Spine/RightShoulder/RightArm",
                        endJoint: "Hips/Spine02/Spine01/Spine/RightShoulder/RightArm/RightForeArm/RightHand",
                        baseWeight: [0.8, 0.8, 0.8],
                        endPositionWeight: [1.0, 1.0, 1.0],
                        endOrientationWeight: [0.4, 0.4, 0.4]
                    )

                    let leftLegLimb = IKLimb(
                        baseJoint: "Hips/LeftUpLeg",
                        endJoint: "Hips/LeftUpLeg/LeftLeg/LeftFoot",
                        baseWeight: [0.8, 0.8, 0.8],
                        endPositionWeight: [1.0, 1.0, 1.0],
                        endOrientationWeight: [0.3, 0.3, 0.3]
                    )
                    
                    let rightLegLimb = IKLimb(
                        baseJoint: "Hips/RightUpLeg",
                        endJoint: "Hips/RightUpLeg/RightLeg/RightFoot",
                        baseWeight: [0.8, 0.8, 0.8],
                        endPositionWeight: [1.0, 1.0, 1.0],
                        endOrientationWeight: [0.3, 0.3, 0.3]
                    )

                    let headLimb = IKLimb(
                        baseJoint: "Hips/Spine02/Spine01/Spine/neck",
                        endJoint: "Hips/Spine02/Spine01/Spine/neck/Head/headfront",
                        baseWeight: [0.6, 0.6, 0.6],
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
                    
                    // Initialize orb positions in 3D space and create 3D orb entities
                    // DispatchQueue.main.async {
                    //     // Don't initialize positions - let the animation set them
                    //     // Wait for animation to apply, then create orbs at the actual positions
                    //     // The animation duration is 1.0 second, wait a bit longer for it to settle
                    //     DispatchQueue.main.asyncAfter(deadline: .now()) {
                    //         // orbControlState!.initializeOrbPositions()
                    //         self.create3DOrbs(in: arView, anchor: anchorEntity, rigController: rigController)
                    //     }
                    // }

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
                    // Build starting animation from current joint positions
                    // let targetJointPaths: [String: String] = [
                    //     "head_end": "Hips/Spine02/Spine01/Spine/neck/Head/headfront",
                    //     "leftArm_end": "Hips/Spine02/Spine01/Spine/LeftShoulder/LeftArm/LeftForeArm/LeftHand",
                    //     "rightArm_end": "Hips/Spine02/Spine01/Spine/RightShoulder/RightArm/RightForeArm/RightHand",
                    //     "rightLeg_end": "Hips/LeftUpLeg/LeftLeg/LeftFoot",
                    //     "leftLeg_end": "Hips/RightUpLeg/RightLeg/RightFoot"
                    // ]
                    
                    // var changes: [String: [[Double]]] = [:]
                    // for (targetName, jointPath) in targetJointPaths {
                    //     if let matrix = jointDataArray[jointPath] {
                    //         changes[targetName] = matrix
                    //     }
                    // }
                    // print(changes)
                    
                    // let startingAnimation = JointAnimation(
                    //     duration: 1.0,
                    //     space: "local",
                    //     changes: changes
                    // )
                    
                    // Apply starting animation
                    // DispatchQueue.main.asyncAfter(deadline: .now()) {
                    //     rigController.applyJointAnimation([startingAnimation])
                    // }

                    let startingAnimationJSON = """
                    [
                    {
                      "duration": 1.0,
                      "space": "local",
                      "changes": {
                        "head_end": [
                          [ 1.0,  0.0,  0.0, 0.0 ],
                          [ 0.0,  1.0,  0.0, 0.0 ],
                          [ 0.0,  0.0,  1.0, 0.0 ],
                          [ 0.0,  0.0,  170.0, 1.0 ]
                        ],
                        "leftArm_end": [
                          [ 1.0,  0.0,  0.0, 0.0 ],
                          [ 0.0,  1.0,  0.0, 0.0 ],
                          [ 0.0,  0.0,  1.0, 0.0 ],
                          [ 70.0,  0.0,  140.0, 1.0 ]
                        ],
                        "rightArm_end": [
                          [ 1.0,  0.0,  0.0, 0.0 ],
                          [ 0.0,  1.0,  0.0, 0.0 ],
                          [ 0.0,  0.0,  1.0, 0.0 ],
                          [ -70.0,  0.0,  140.0, 1.0 ]
                        ],
                        "rightLeg_end": [
                          [ 1.0,  0.0,  0.0, 0.0 ],
                          [ 0.0,  1.0,  0.0, 0.0 ],
                          [ 0.0,  0.0,  1.0, 0.0 ],
                          [ -20.0, 0.0,  0.0, 1.0 ]
                        ],
                        "leftLeg_end": [
                          [ 1.0,  0.0,  0.0, 0.0 ],
                          [ 0.0,  1.0,  0.0, 0.0 ],
                          [ 0.0,  0.0,  1.0, 0.0 ],
                          [ 20.0, 0.0,  0.0, 1.0 ]
                        ]
                      }
                    }
                    ]
                    """

                    if let jsonData = startingAnimationJSON.data(using: .utf8),
                       let animations: [JointAnimation] = try? JSONDecoder().decode([JointAnimation].self, from: jsonData) {
                        // Apply animation after a brief delay
                        DispatchQueue.main.asyncAfter(deadline: .now()) {
                            rigController.applyJointAnimation(animations)
                            self.create3DOrbs(in: arView, anchor: anchorEntity, rigController: rigController)
                        }
                    } else {
                        print("⚠️ Failed to decode test animation JSON")
                        // DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        //     rigController.raiseRightHand()
                        // }
                    }

                    // // Test: Apply hardcoded joint animation from AI response
                    // let testAnimationJSON = """
                    // [
                    // {
                    //     "duration": 0.0,
                    //     "space": "local",
                    //     "changes": {
                    //     "leftArm_end": [
                    //         [1, 0, 0, 0],
                    //         [0, 1, 0, 0],
                    //         [0, 0, 1, 0],
                    //         [0, 0, 170, 1]
                    //     ]
                    //     }
                    // }
                    // ]
                    // """
                    
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
        
        func create3DOrbs(in arView: ARView, anchor: AnchorEntity, rigController: AvatarRigController) {
            print("🎯 Creating 3D orbs...")
            print("   Anchor exists: \(anchor != nil)")
            print("   Rig controller exists: \(rigController != nil)")
            
            // Remove existing orbs
            for (_, orbEntity) in orbEntities {
                orbEntity.removeFromParent()
            }
            orbEntities.removeAll()
            
            let orbNames = ["head_end", "leftArm_end", "rightArm_end", "rightLeg_end", "leftLeg_end"]
            let orbColors: [String: UIColor] = [
                "head_end": .yellow,
                "leftArm_end": .blue,
                "rightArm_end": .red,
                "rightLeg_end": .green,
                "leftLeg_end": .purple
            ]
            
            for orbName in orbNames {
                // Create a sphere mesh - make it much larger and more visible
                let sphereMesh = MeshResource.generateSphere(radius: 0.1) // 10cm radius - much more visible
                
                // Create a more visible material - use UnlitMaterial for better visibility
                let color = orbColors[orbName] ?? .white
                let material = UnlitMaterial(color: color)
                
                let orbEntity = ModelEntity(mesh: sphereMesh, materials: [material])
                orbEntity.name = orbName
                
                // Get the IK target
                let target = rigController.targetController.target(named: orbName)
                
                // Use the target's actual position relative to anchor
                // The animation sets positions in centimeters, convert to meters
                // Also swap Y and Z to match RealityKit's coordinate system
                let targetPositionRaw = target.position(relativeTo: anchor)
                let converted = targetPositionRaw * 0.01 // Convert cm to meters
                // Swap Y and Z: (x, y, z) -> (x, z, y)
                let targetPosition = SIMD3<Float>(converted.x, converted.z, converted.y)
                
                // Set orb position to match the target's actual position (in meters)
                orbEntity.position = targetPosition
                
                // Reset rotation and scale to identity to avoid coordinate system issues
                orbEntity.orientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
                orbEntity.scale = SIMD3<Float>(1, 1, 1)
                
                print("✅ Created orb \(orbName)")
                print("   Target transform translation (cm): \(target.transform.translation)")
                print("   Target position raw (cm): \(targetPositionRaw)")
                print("   Target position converted (m): \(targetPosition)")
                print("   Orb position: \(orbEntity.position)")
                print("   Distance from anchor: \(simd_length(targetPosition))m")
                
                // Add collision component for hit testing (larger radius for easier interaction)
                let collisionShape = ShapeResource.generateSphere(radius: 0.15) // 15cm for easier touch
                orbEntity.components.set(CollisionComponent(shapes: [collisionShape]))
                
                // Add input target component for gestures
                orbEntity.components.set(InputTargetComponent())
                
                // Add to anchor
                anchor.addChild(orbEntity)
                orbEntities[orbName] = orbEntity
                
                print("✅ Added orb \(orbName) to scene, total orbs: \(orbEntities.count)")
            }
            
            print("✅ Created \(orbEntities.count) orbs in 3D space")
            
            // Add gesture recognizer for dragging orbs (only if not already added)
            if arView.gestureRecognizers?.contains(where: { $0 is UIPanGestureRecognizer }) == false {
                let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleOrbDrag(_:)))
                arView.addGestureRecognizer(panGesture)
            }
            
            // Start updating orb positions to sync with IK targets
            startOrbPositionSync(rigController: rigController, anchor: anchor)
        }
        
        private var orbSyncTimer: Timer?
        
        func startOrbPositionSync(rigController: AvatarRigController, anchor: AnchorEntity) {
            orbSyncTimer?.invalidate()
            // Sync orbs to IK targets when not dragging
            // This keeps the orbs connected to the avatar's limbs
            orbSyncTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
                guard let self = self,
                      self.draggingOrb == nil else { return } // Don't sync while dragging
                
                for (orbName, orbEntity) in self.orbEntities {
                    let target = rigController.targetController.target(named: orbName)
                    // Get target position in animation coordinates (cm), convert to RealityKit (m)
                    let targetTransform = target.transform
                    let targetPosCm = targetTransform.translation
                    
                    // Convert from animation coordinates to RealityKit coordinates
                    // When dragging, we convert: RealityKit (x, y, z) -> Animation (y, x, z) * 100
                    // So reverse: Animation (x, y, z) -> RealityKit (y, x, z) / 100
                    // Animation X (left/right) -> RealityKit Y (up/down)
                    // Animation Y (up/down) -> RealityKit X (left/right)
                    // Animation Z (in/out) -> RealityKit Z (in/out)
                    let targetPosM = SIMD3<Float>(
                        targetPosCm.x * 0.01,  // Animation Y (up/down) -> RealityKit X (left/right)
                        targetPosCm.z * 0.01,  // Animation X (left/right) -> RealityKit Y (up/down)
                        targetPosCm.y * 0.01   // Animation Z (in/out) -> RealityKit Z (in/out)
                    )
                    
                    // Only update if position changed significantly to avoid jitter
                    let distance = simd_length(orbEntity.position - targetPosM)
                    if distance > 0.001 { // 1mm threshold
                        orbEntity.position = targetPosM
                    }
                }
            }
        }
        
        func stopOrbPositionSync() {
            orbSyncTimer?.invalidate()
            orbSyncTimer = nil
        }
        
        @objc func handleOrbDrag(_ gesture: UIPanGestureRecognizer) {
            guard let arView = arView,
                  let rigController = avatarRigController,
                  let anchor = placedAnchor else { return }
            
            let location = gesture.location(in: arView)
            
            switch gesture.state {
            case .began:
                // Hit test to find which orb was touched
                // Use ARKit raycasting to find the closest orb
                var closestOrb: (name: String, entity: ModelEntity, distance: Float)?
                var minDistance: Float = Float.greatestFiniteMagnitude
                
                // Raycast from touch location
                let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any)
                guard let firstResult = results.first else { return }
                
                let raycastWorldPosition = SIMD3<Float>(
                    firstResult.worldTransform.columns.3.x,
                    firstResult.worldTransform.columns.3.y,
                    firstResult.worldTransform.columns.3.z
                )
                
                // Convert raycast position to anchor's local space for comparison
                let anchorTransform = anchor.transformMatrix(relativeTo: nil)
                let anchorPosition = SIMD3<Float>(
                    anchorTransform.columns.3.x,
                    anchorTransform.columns.3.y,
                    anchorTransform.columns.3.z
                )
                let raycastLocalPosition = raycastWorldPosition - anchorPosition
                
                // Find closest orb to raycast position
                for (orbName, orbEntity) in orbEntities {
                    let orbLocalPos = orbEntity.position(relativeTo: anchor)
                    let distance = simd_length(raycastLocalPosition - orbLocalPos)
                    // Increase threshold to 0.5m (50cm) to make it easier to grab orbs
                    if distance < minDistance && distance < 0.5 {
                        minDistance = distance
                        closestOrb = (orbName, orbEntity, distance)
                    }
                }
                
                if let closest = closestOrb {
                    draggingOrb = closest.name
                    dragStartPosition = closest.entity.position(relativeTo: anchor)
                    
                    // Cancel any running animations to prevent resetting positions
                    if let animationTask = rigController.currentAnimationTask {
                        animationTask.cancel()
                        rigController.currentAnimationTask = nil
                        print("🛑 Cancelled animation to preserve orb position")
                    }
                    
                    print("🎯 Started dragging orb: \(closest.name) at distance: \(minDistance)m")
                } else {
                    print("⚠️ No orb found near touch location")
                }
                
            case .changed:
                guard let orbName = draggingOrb,
                      let orbEntity = orbEntities[orbName] else { return }
                
                // Project touch location to a plane parallel to the phone screen
                // Use the orb's current depth to maintain distance from camera
                guard let frame = arView.session.currentFrame else { return }
                let cameraTransform = frame.camera.transform
                let cameraPosition = SIMD3<Float>(
                    cameraTransform.columns.3.x,
                    cameraTransform.columns.3.y,
                    cameraTransform.columns.3.z
                )
                
                // Get current orb position in world space
                let currentOrbWorldPos = orbEntity.position(relativeTo: nil)
                
                // Calculate depth from camera to orb (distance along camera's forward vector)
                let forwardVector = SIMD3<Float>(-cameraTransform.columns.2.x, -cameraTransform.columns.2.y, -cameraTransform.columns.2.z)
                let toOrb = currentOrbWorldPos - cameraPosition
                var depth = simd_dot(toOrb, forwardVector)
                
                // If depth is invalid, use the drag start position depth
                if depth <= 0 {
                    if let startPos = dragStartPosition {
                        let anchorWorldPos = anchor.position(relativeTo: nil)
                        let startWorldPos = anchorWorldPos + startPos
                        let toStart = startWorldPos - cameraPosition
                        depth = simd_dot(toStart, forwardVector)
                    }
                    if depth <= 0 {
                        depth = 1.0 // Default 1 meter if still invalid
                    }
                }
                
                // Normalize screen coordinates (-1 to 1)
                let normalizedPoint = CGPoint(
                    x: (location.x / arView.bounds.width - 0.5) * 2.0,
                    y: (0.5 - location.y / arView.bounds.height) * 2.0
                )
                
                // Get FOV from camera intrinsics
                let intrinsics = frame.camera.intrinsics
                let fx = intrinsics[0][0]
                let imageWidth = Float(frame.camera.imageResolution.width)
                let fov = 2.0 * atan(imageWidth / (2.0 * fx))
                let aspect = Float(arView.bounds.width / arView.bounds.height)
                
                // Calculate camera basis vectors
                let rightVector = SIMD3<Float>(cameraTransform.columns.0.x, cameraTransform.columns.0.y, cameraTransform.columns.0.z)
                let upVector = SIMD3<Float>(cameraTransform.columns.1.x, cameraTransform.columns.1.y, cameraTransform.columns.1.z)
                
                // Project to plane at current depth, parallel to screen
                let horizontalOffset = rightVector * Float(normalizedPoint.x) * depth * tan(fov / 2.0) * aspect
                let verticalOffset = upVector * Float(normalizedPoint.y) * depth * tan(fov / 2.0)
                
                // Calculate new world position
                let newWorldPosition = cameraPosition + forwardVector * depth + horizontalOffset + verticalOffset
                
                // Convert to anchor's local space
                let anchorTransform = anchor.transformMatrix(relativeTo: nil)
                let anchorPosition = SIMD3<Float>(
                    anchorTransform.columns.3.x,
                    anchorTransform.columns.3.y,
                    anchorTransform.columns.3.z
                )
                let localPosition = newWorldPosition - anchorPosition
                
                // Update orb position (in RealityKit coordinate system: Y up, Z forward)
                orbEntity.position = localPosition
                
                // Update IK target
                // Convert from RealityKit coordinates (Y up, Z forward) to animation coordinates
                // Also convert from meters to centimeters
                // Mapping: left/right screen (X) -> up/down animation (Y), up/down screen (Y) -> left/right animation (X)
                let target = rigController.targetController.target(named: orbName)
                var newTransform = target.transform
                // Remap axes: (x, y, z) -> (y, x, z) * 100
                // X (left/right screen) -> Y (up/down animation)
                // Y (up/down screen) -> X (left/right animation)
                // Z (in/out) -> Z (in/out animation)
                let targetTranslation = SIMD3<Float>(
                    localPosition.x * 100.0,   // Y (up/down screen) becomes X (left/right animation)
                    localPosition.y * 100.0,   // X (left/right screen) becomes Y (up/down animation)
                    localPosition.z * 100.0    // Z (in/out) stays Z (in/out animation)
                )
                newTransform.translation = targetTranslation
                target.transform = newTransform
                
            case .ended, .cancelled:
                draggingOrb = nil
                dragStartPosition = nil
                
            case .failed:
                draggingOrb = nil
                dragStartPosition = nil
                
            @unknown default:
                break
            }
        }
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // Optionally, you could continuously update cube position here
            // based on depth data from the center of the screen
        }
    }
}

// MARK: - Orb Controls

enum OrbAxis {
    case x, y, z
}

struct OrbControlsOverlay: View {
    @ObservedObject var orbControlState: OrbControlState
    
    @State private var orbPositions: [String: CGPoint] = [
        "head_end": CGPoint(x: 100, y: 150),
        "leftArm_end": CGPoint(x: 50, y: 300),
        "rightArm_end": CGPoint(x: 350, y: 300),
        "rightLeg_end": CGPoint(x: 200, y: 600),
        "leftLeg_end": CGPoint(x: 100, y: 600)
    ]
    
    @State private var selectedOrb: String?
    @State private var draggingAxis: (String, OrbAxis)? // (orbName, axis)
    @State private var initialOrbPositions: [String: CGPoint] = [:]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(Array(orbPositions.keys), id: \.self) { orbName in
                    OrbView(
                        name: orbName,
                        position: orbPositions[orbName] ?? .zero,
                        isSelected: selectedOrb == orbName,
                        onAxisDrag: { axis, translation in
                            handleAxisDrag(orbName: orbName, axis: axis, translation: translation)
                        },
                        onCenterDrag: { translation, isStart in
                            handleCenterDrag(orbName: orbName, translation: translation, screenSize: geometry.size, isStart: isStart)
                        },
                        onTap: {
                            selectedOrb = (selectedOrb == orbName) ? nil : orbName
                        }
                    )
                }
            }
        }
    }
    
    private func handleAxisDrag(orbName: String, axis: OrbAxis, translation: CGSize) {
        orbControlState.updateTargetPosition(orbName: orbName, axis: axis, translation: translation)
    }
    
    private func handleCenterDrag(orbName: String, translation: CGSize, screenSize: CGSize, isStart: Bool = false) {
        // Store initial position on drag start
        if isStart {
            initialOrbPositions[orbName] = orbPositions[orbName]
        }
        
        // Update screen position based on initial position + translation
        if let initialPos = initialOrbPositions[orbName] ?? orbPositions[orbName] {
            var newPos = CGPoint(
                x: initialPos.x + translation.width,
                y: initialPos.y + translation.height
            )
            
            // Clamp to screen bounds
            newPos.x = max(50, min(screenSize.width - 50, newPos.x))
            newPos.y = max(50, min(screenSize.height - 50, newPos.y))
            
            orbPositions[orbName] = newPos
            
            // Update 3D position using raycasting from screen point
            orbControlState.updateTargetPositionInPlane(orbName: orbName, screenPoint: newPos)
        }
    }
}

struct OrbView: View {
    let name: String
    let position: CGPoint
    let isSelected: Bool
    let onAxisDrag: (OrbAxis, CGSize) -> Void
    let onCenterDrag: (CGSize, Bool) -> Void
    let onTap: () -> Void
    
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var draggingAxis: OrbAxis?
    
    private let orbSize: CGFloat = 30
    private let arrowLength: CGFloat = 40
    
    var body: some View {
        ZStack {
            // X axis arrow (red, horizontal)
            ZStack {
                // Hit area
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: arrowLength + 20, height: 30)
                
                ArrowView(
                    color: .red,
                    axis: .x,
                    length: arrowLength,
                    position: position,
                    offset: CGSize(width: orbSize/2 + arrowLength/2, height: 0)
                )
            }
            .position(CGPoint(
                x: position.x + orbSize/2 + arrowLength/2,
                y: position.y
            ))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if draggingAxis == nil {
                            draggingAxis = .x
                        }
                        if draggingAxis == .x {
                            onAxisDrag(.x, value.translation)
                        }
                    }
                    .onEnded { _ in
                        draggingAxis = nil
                    }
            )
            
            // Y axis arrow (green, vertical forward)
            ZStack {
                // Hit area
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 30, height: arrowLength + 20)
                
                ArrowView(
                    color: .green,
                    axis: .y,
                    length: arrowLength,
                    position: position,
                    offset: CGSize(width: 0, height: -orbSize/2 - arrowLength/2)
                )
            }
            .position(CGPoint(
                x: position.x,
                y: position.y - orbSize/2 - arrowLength/2
            ))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if draggingAxis == nil {
                            draggingAxis = .y
                        }
                        if draggingAxis == .y {
                            onAxisDrag(.y, value.translation)
                        }
                    }
                    .onEnded { _ in
                        draggingAxis = nil
                    }
            )
            
            // Z axis arrow (blue, diagonal)
            ZStack {
                // Hit area
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 30, height: arrowLength + 20)
                
                ArrowView(
                    color: .blue,
                    axis: .z,
                    length: arrowLength,
                    position: position,
                    offset: CGSize(width: orbSize/2 + 10, height: -orbSize/2 - arrowLength/2)
                )
            }
            .position(CGPoint(
                x: position.x + orbSize/2 + 10,
                y: position.y - orbSize/2 - arrowLength/2
            ))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if draggingAxis == nil {
                            draggingAxis = .z
                        }
                        if draggingAxis == .z {
                            onAxisDrag(.z, value.translation)
                        }
                    }
                    .onEnded { _ in
                        draggingAxis = nil
                    }
            )
            
            // Center orb
            Circle()
                .fill(isSelected ? Color.white : Color.white.opacity(0.7))
                .frame(width: orbSize, height: orbSize)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.yellow : Color.white, lineWidth: 2)
                )
                .shadow(radius: 5)
                .position(position)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if draggingAxis == nil {
                                if !isDragging {
                                    isDragging = true
                                    dragOffset = .zero
                                    onCenterDrag(.zero, true)
                                }
                                onCenterDrag(value.translation, false)
                            }
                        }
                        .onEnded { _ in
                            isDragging = false
                            dragOffset = .zero
                        }
                        .simultaneously(with: TapGesture()
                            .onEnded { _ in
                                if !isDragging && draggingAxis == nil {
                                    onTap()
                                }
                            })
                )
        }
    }
}

struct ArrowView: View {
    let color: Color
    let axis: OrbAxis
    let length: CGFloat
    let position: CGPoint
    let offset: CGSize
    
    var body: some View {
        Path { path in
            let start = CGPoint(
                x: position.x + offset.width,
                y: position.y + offset.height
            )
            
            switch axis {
            case .x:
                // Horizontal arrow pointing right
                path.move(to: start)
                path.addLine(to: CGPoint(x: start.x + length, y: start.y))
                // Arrowhead
                path.addLine(to: CGPoint(x: start.x + length - 8, y: start.y - 5))
                path.move(to: CGPoint(x: start.x + length, y: start.y))
                path.addLine(to: CGPoint(x: start.x + length - 8, y: start.y + 5))
            case .y:
                // Vertical arrow pointing up
                path.move(to: start)
                path.addLine(to: CGPoint(x: start.x, y: start.y - length))
                // Arrowhead
                path.addLine(to: CGPoint(x: start.x - 5, y: start.y - length + 8))
                path.move(to: CGPoint(x: start.x, y: start.y - length))
                path.addLine(to: CGPoint(x: start.x + 5, y: start.y - length + 8))
            case .z:
                // Diagonal arrow (representing Z axis)
                path.move(to: start)
                path.addLine(to: CGPoint(x: start.x + length * 0.7, y: start.y - length * 0.7))
                // Arrowhead
                let end = CGPoint(x: start.x + length * 0.7, y: start.y - length * 0.7)
                path.addLine(to: CGPoint(x: end.x - 6, y: end.y + 4))
                path.move(to: end)
                path.addLine(to: CGPoint(x: end.x - 4, y: end.y + 6))
            }
        }
        .stroke(color, lineWidth: 3)
        .shadow(color: color.opacity(0.5), radius: 2)
    }
}

#Preview {
    ContentView()
}

