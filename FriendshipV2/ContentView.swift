//
//  ContentView.swift
//  FriendshipV2
//
//  Created by Travis Miller on 2025-12-08.
//

import SwiftUI
import RealityKit
import ARKit

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
        
        // Run the AR session
        arView.session.run(config)
        
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
        var placedCube: ModelEntity?
        
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
                        placeCube(at: firstResult.worldTransform, in: arView)
                        return
                    }
                }
            } else if let firstResult = results.first {
                placeCube(at: firstResult.worldTransform, in: arView)
            }
        }
        
        func placeCube(at transform: simd_float4x4, in arView: ARView) {
            // Remove previously placed cube
            if let previousCube = placedCube {
                previousCube.removeFromParent()
            }
            
            // Create a cube mesh
            let mesh = MeshResource.generateBox(size: 0.1) // 10cm cube
            
            // Create a material with a color
            var material = SimpleMaterial()
            material.color = .init(tint: .systemBlue.withAlphaComponent(0.8))
            material.metallic = .init(floatLiteral: 0.5)
            material.roughness = .init(floatLiteral: 0.3)
            
            // Create the model entity
            let cubeEntity = ModelEntity(mesh: mesh, materials: [material])
            
            // Create an anchor entity
            let anchorEntity = AnchorEntity(world: transform)
            anchorEntity.addChild(cubeEntity)
            
            // Add to the scene
            arView.scene.addAnchor(anchorEntity)
            
            // Store reference to the cube
            placedCube = cubeEntity
            
            // Add a subtle animation
            var transform = cubeEntity.transform
            transform.translation.y += 0.05
            cubeEntity.move(to: transform, relativeTo: anchorEntity, duration: 0.3, timingFunction: .easeOut)
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
