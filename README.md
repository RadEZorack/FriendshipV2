# FriendshipV2 - AR Cube Placement App

An iOS AR app that uses LiDAR depth sensing to place a 3D cube at the center of the screen where it intersects with real-world surfaces.

## Features

- **ARKit Integration**: Uses ARKit with RealityKit for immersive AR experiences
- **LiDAR Support**: Leverages LiDAR sensors for accurate depth sensing and scene reconstruction
- **Center-Screen Placement**: Places a cube where the center crosshair intersects with real-world surfaces
- **Visual Feedback**: White crosshair indicates the center point for cube placement
- **Tap to Place**: Simply tap anywhere on the screen to place a cube at the center raycast hit point

## Requirements

- iOS device with LiDAR sensor (iPhone 12 Pro or later, iPad Pro 2020 or later)
- iOS 14.0 or later
- ARKit compatible device

## How It Works

1. **AR Session Setup**: The app initializes an AR session with:
   - Scene reconstruction using LiDAR mesh data
   - Horizontal and vertical plane detection
   - World tracking configuration

2. **Raycasting**: When you tap the screen:
   - A raycast is performed from the center of the screen
   - The raycast detects intersections with estimated or existing planes
   - If a surface is detected, a cube is placed at that location

3. **Cube Placement**:
   - A 10cm blue cube is created using RealityKit
   - The cube has metallic and roughness properties for realistic rendering
   - A subtle animation moves the cube slightly upward when placed
   - Each new placement replaces the previous cube

## Technical Details

### ARKit Configuration
- **Scene Reconstruction**: Uses LiDAR mesh reconstruction when available
- **Plane Detection**: Detects both horizontal and vertical planes
- **Raycasting**: Supports both estimated and existing plane geometry

### Visual Elements
- **Cube**: 10cm metallic blue cube with transparency
- **Crosshair**: White crosshair at screen center for aiming
- **Lighting**: Enhanced environment lighting for better rendering

## Usage

1. Launch the app on a LiDAR-enabled device
2. Grant camera permissions when prompted
3. Point the camera at surfaces in your environment
4. Tap anywhere on the screen to place a cube at the center point
5. The cube will appear where the center crosshair intersects with a detected surface

## Code Structure

- **ContentView.swift**: Main AR view implementation
  - `ContentView`: SwiftUI view hosting the AR experience
  - `ARViewContainer`: UIViewRepresentable wrapper for ARView
  - `Coordinator`: Handles AR session events and cube placement logic

- **Info.plist**: Contains required camera usage permissions

## Future Enhancements

Potential improvements could include:
- Multiple cube placement without removing previous ones
- Different shapes and colors
- Distance measurement from camera
- Persistent cube placement using AR anchors
- Continuous depth visualization

