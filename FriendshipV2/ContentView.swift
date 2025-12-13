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

struct ContentView: View {
    @StateObject private var auth = AuthService.shared
    @StateObject private var meshService = MeshGenerationService.shared
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
                            selectedMeshId: selectedMeshId
                        )
                        .edgesIgnoringSafeArea(.all)
                        
                        // Mesh selector button
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
        return coordinator
    }
    
    func updateCoordinator(_ coordinator: Coordinator) {
        coordinator.selectedMeshId = selectedMeshId
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
        var tapGesture: UITapGestureRecognizer?
        var arConfig: ARWorldTrackingConfiguration?
        var isPaused: Bool = false
        var selectedMeshId: String?
        
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
                previousAnchor.removeFromParent()
                placedAnchor = nil
                placedModel = nil
            } else if let previousModel = placedModel {
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
                    
                    // Rotate model 90 degrees around Y axis
                    modelEntity.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])

                    // Create an anchor entity
                    let anchorEntity = AnchorEntity(world: transform)
                    anchorEntity.addChild(modelEntity)

                    // Add to the scene
                    arView.scene.addAnchor(anchorEntity)

                    // Store references to the model and its anchor
                    self.placedModel = modelEntity
                    self.placedAnchor = anchorEntity

                    // Play any animations in the model
//                    if let animation = modelEntity.availableAnimations.first {
//                        modelEntity.playAnimation(animation.repeat())
//                    }
//
//                    // Add a subtle placement animation
//                    var entityTransform = modelEntity.transform
//                    entityTransform.translation.y -= 0.1
//                    modelEntity.transform = entityTransform
//
//                    entityTransform.translation.y += 0.1
//                    modelEntity.move(to: entityTransform, relativeTo: anchorEntity, duration: 0.3, timingFunction: .easeOut)
                    
                    // Load a model containing a skeletal mesh.
                    let armEntity = modelEntity


                    // Fetch the skeleton from the model's MeshResource.
                    guard let meshResource = modelEntity.components[ModelComponent.self]?.mesh else {
                        fatalError("No mesh found")
                    }


                    let modelSkeleton = meshResource.contents.skeletons[0]


                    // Start with the default rig instance for the skeleton without any constraints.
                    var rig = try IKRig(for: modelSkeleton)


                    // This is a good place to change default rig level settings. For example, reducing
                    // the maximum solver iterations reduces the performance cost of the solve but can
                    // increase error in reaching the demands.
                    rig.maxIterations = 30


                    // Refine joint settings.
                    rig.joints["Hips/Spine02/Spine01/Spine/LeftShoulder/LeftArm/LeftForeArm"]?.fkWeightPerAxis = .zero


                    // Define the joint constraints for the rig.
                    // Weight values should be between 0.0 (no influence) and 1.0 (full influence)
                    // Higher values don't mean "stronger" - they should stay in 0.0-1.0 range
                    rig.constraints = [
                        // A point constraint is a standard term for a position demand.
                        // See ``IKRig/Constraint/point(named:on:positionWeight:)``
                        // Using 0.8 for strong but not absolute influence on the elbow/upper arm
                        .point(named: "base_constraint", on: "Hips/Spine02/Spine01/Spine/LeftShoulder/LeftArm", positionWeight: [0.8, 0.8, 0.8]),
                        // A parent constraint is a standard term for both position and orientation demands as
                        // a single transformation. See ``IKRig/Constraint/parent(named:on:positionWeight:orientationWeight:)``
                        // Using 1.0 for full position influence on the hand (end effector)
                        .parent(named: "end_constraint", on: "Hips/Spine02/Spine01/Spine/LeftShoulder/LeftArm/LeftForeArm/LeftHand",
                                positionWeight: [1.0, 1.0, 1.0],
                                orientationWeight: [0.4, 0.4, 0.4]), // Moderate orientation influence
                    ]


                    // Make a resource containing the rig.
                    let resource = try IKResource(rig: rig)

                    // Add the component to the entity using the new resource.
                    armEntity.components.set(IKComponent(resource: resource))
                    
                    // Get the IKComponent to configure constraints
                    guard var ikComponent = armEntity.components[IKComponent.self] else {
                        print("Failed to get IKComponent")
                        return
                    }
                    
                    // Create target entities for the constraints
                    // These entities define where the IK joints should move to
                    // Positions are relative to the anchor entity (world space)
                    // Note: Model is rotated -90° around X axis, and skeleton origin is at feet
                    // Coordinate system: X=left/right, Y=forward/back, Z=up/down (after rotation)
                    let baseTargetEntity = Entity()
                    baseTargetEntity.name = "base_target"
                    anchorEntity.addChild(baseTargetEntity)
                    
                    let endTargetEntity = Entity()
                    endTargetEntity.name = "end_target"
                    anchorEntity.addChild(endTargetEntity)

                    // Set initial positions for targets
                    // Since skeleton origin is at feet and model is rotated:
                    // - X: left/right (positive = right)
                    // - Y: forward/back (positive = forward) 
                    // - Z: up/down (positive = up)
                    // Adjust these values based on your model's scale and natural arm position
                    endTargetEntity.position = SIMD3<Float>(0.0, -25.0, 140.0)  // Elbow: right, at shoulder height
                    baseTargetEntity.position = SIMD3<Float>(0.0, -15.0, 130.0)   // Hand: slightly right, at hand height
                    
                    // Set target values for the constraints
                    // This tells the IK solver where to move the joints
                    // Note: The exact API for setting targets may vary. Try setting directly to entity.
                    // If this doesn't work, the constraints may need targets set during IKRig creation,
                    // or targets may be automatically created and need to be found and positioned.
                    if var baseConstraint = ikComponent.solvers[0].constraints["base_constraint"] {
                        // Try setting target directly - the exact type may need to be determined at runtime
                        // For now, we'll add the target entities to the scene and they should be tracked
                        // You may need to animate these entities to see IK movement
                        baseConstraint.target = baseTargetEntity.transform
                        ikComponent.solvers[0].constraints["base_constraint"] = baseConstraint
                    }
                    
                    if var endConstraint = ikComponent.solvers[0].constraints["end_constraint"] {
                        endConstraint.target = endTargetEntity.transform
                        endConstraint.animationOverrideWeight.position = 1.0
                        ikComponent.solvers[0].constraints["end_constraint"] = endConstraint
                    }
                    
                    // Update the component with the modified constraints before starting animation
                    armEntity.components.set(ikComponent)
                    
                    // Create a waving motion loop for the hand
                    // Account for model rotation (-90° around X axis) and skeleton origin at feet
                    let waveDuration: TimeInterval = 1.0 // Duration for each complete wave cycle
                    let stepDuration = waveDuration / 3
                    let startPosition = endTargetEntity.position

                    // Start a timer to continuously update constraint targets
                    // This ensures IK follows the moving target entities
                    let updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { _ in
                        guard var ikComponent = armEntity.components[IKComponent.self] else { return }
                        
                        // Update end constraint target to follow the moving entity
                        if var endConstraint = ikComponent.solvers[0].constraints["end_constraint"] {
                            endConstraint.target = endTargetEntity.transform
                            ikComponent.solvers[0].constraints["end_constraint"] = endConstraint
                        }
                        
                        // Update base constraint target
                        if var baseConstraint = ikComponent.solvers[0].constraints["base_constraint"] {
                            baseConstraint.target = baseTargetEntity.transform
                            ikComponent.solvers[0].constraints["base_constraint"] = baseConstraint
                        }
                        
                        armEntity.components.set(ikComponent)
                    }
                    
                    // Store timer reference to prevent it from being deallocated
                    // Note: In a real app, you'd want to invalidate this when the model is removed
                    
                    // Use a recursive function with DispatchQueue for reliable timing
                    // This avoids nested Task issues
                    func performWave() {
                        // print("Waving motion loop - starting wave")
                        
                        // Calculate wave positions relative to start
                        // Coordinate system: X=left/right, Y=forward/back, Z=up/down (after -90° X rotation)
                        let rightPos = startPosition + SIMD3<Float>(15.0, 0.0, 0.0)   // To the right
                        let leftPos = startPosition + SIMD3<Float>(-15.0, 0.0, 0.0)  // To the left
                        
                        // Step 1: Animate to the right
                        endTargetEntity.move(
                            to: Transform(translation: rightPos),
                            relativeTo: anchorEntity,
                            duration: stepDuration,
                            timingFunction: .easeOut
                        )
                        
                        // Step 2: After step 1, move to the left
                        DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration) {
                            endTargetEntity.move(
                                to: Transform(translation: leftPos),
                                relativeTo: anchorEntity,
                                duration: stepDuration,
                                timingFunction: .easeInOut
                            )
                            
                            // Step 3: After step 2, return to start
                            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration) {
                                endTargetEntity.move(
                                    to: Transform(translation: startPosition),
                                    relativeTo: anchorEntity,
                                    duration: stepDuration,
                                    timingFunction: .easeIn
                                )
                                
                                // Step 4: After step 3, pause then loop
                                DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration + 0.2) {
                                    performWave()
                                }
                            }
                        }
                    }
                    
                    // Start the waving motion after a brief delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        performWave()
                    }
                    
                    
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

#Preview {
    ContentView()
}
