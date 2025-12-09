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

struct ContentView: View {
    var body: some View {
        ARViewContainer()
            .edgesIgnoringSafeArea(.all)
    }
}

struct ARViewContainer: UIViewRepresentable {
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
        
        // Run the AR session
        arView.session.run(config)
        
        // Enable occlusion from people and scene depth
        arView.environment.sceneUnderstanding.options.insert(.occlusion)
        
        // Add coordinator as delegate
        context.coordinator.arView = arView
        arView.session.delegate = context.coordinator
        
        // Add a tap gesture recognizer to place cube at center
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        arView.addGestureRecognizer(tapGesture)
        
        // Add lighting
        arView.environment.lighting.intensityExponent = 1.5
        
        // Add a crosshair at the center of the screen
        addCrosshair(to: arView)
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
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
        
        @objc func handleTap() {
            guard let arView = arView else { return }
            
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
                    // Load USDZ file from bundle
                    guard let modelURL = Bundle.main.url(forResource: "Animation_FunnyDancing_01", withExtension: "usdz") else {
                        print("Could not find USDZ file in bundle")
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
                    if let animation = modelEntity.availableAnimations.first {
                        modelEntity.playAnimation(animation.repeat())
                    }

                    // Add a subtle placement animation
                    var entityTransform = modelEntity.transform
                    entityTransform.translation.y -= 0.1
                    modelEntity.transform = entityTransform

                    entityTransform.translation.y += 0.1
                    modelEntity.move(to: entityTransform, relativeTo: anchorEntity, duration: 0.3, timingFunction: .easeOut)

                } catch {
                    print("Failed to load model: \(error)")
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
