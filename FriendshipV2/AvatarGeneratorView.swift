//
//  AvatarGeneratorView.swift
//  FriendshipV2
//
//  Created by Travis Miller on 2025-12-08.
//

import SwiftUI

struct AvatarGeneratorView: View {
    @StateObject private var meshService = MeshGenerationService.shared
    @State private var prompt: String = ""
    @State private var userAvatar: MeshStatus?
    @State private var isLoadingAvatar: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Avatar Generator")
                        .font(.largeTitle)
                        .bold()
                        .foregroundColor(.white)
                    
                    Text("Create your custom 3D avatar with AI")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                
                // Current Avatar Display
                if let userAvatar = userAvatar {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Your Current Avatar")
                            .font(.title2)
                            .bold()
                            .foregroundColor(.white)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                // Avatar icon placeholder
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 64, height: 64)
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .foregroundColor(.gray)
                                    )
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Avatar ID: \(userAvatar.id)")
                                        .font(.subheadline)
                                        .foregroundColor(.white)
                                    
                                    HStack {
                                        Text("Status:")
                                            .foregroundColor(.gray)
                                        Text(statusText(userAvatar.status))
                                            .foregroundColor(statusColor(userAvatar.status))
                                    }
                                    .font(.caption)
                                    
                                    if !userAvatar.prompt.isEmpty {
                                        Text("Prompt: \(userAvatar.prompt)")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                
                // Generation Form
                VStack(alignment: .leading, spacing: 16) {
                    Text("Generate New Avatar")
                        .font(.title2)
                        .bold()
                        .foregroundColor(.white)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Describe your avatar")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        TextEditor(text: $prompt)
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(8)
                            .foregroundColor(.white)
                            .disabled(meshService.isGenerating)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                            )
                        
                        if prompt.isEmpty {
                            Text("e.g., A futuristic robot with blue glowing eyes and silver armor")
                                .font(.caption)
                                .foregroundColor(.gray.opacity(0.6))
                                .padding(.leading, 12)
                                .padding(.top, -24)
                                .allowsHitTesting(false)
                        }
                    }
                    
                    Button(action: {
                        Task {
                            do {
                                try await meshService.generateAvatar(prompt: prompt)
                            } catch {
                                print("Generation error: \(error.localizedDescription)")
                            }
                        }
                    }) {
                        HStack {
                            if meshService.isGenerating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text(meshService.isGenerating ? "Generating Avatar..." : "Generate Avatar")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || meshService.isGenerating
                                ? Color.gray.opacity(0.5)
                                : Color.blue
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || meshService.isGenerating)
                }
                .padding()
                .background(Color.black.opacity(0.3))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Error Display
                if let error = meshService.error {
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.2))
                        .cornerRadius(8)
                        .padding(.horizontal)
                }
                
                // Current Generation Status
                if let currentMesh = meshService.currentMesh {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Generation Status")
                            .font(.title2)
                            .bold()
                            .foregroundColor(.white)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            StatusRow(label: "Mesh ID:", value: currentMesh.id)
                            StatusRow(label: "Prompt:", value: currentMesh.prompt)
                            HStack {
                                Text("Overall Status:")
                                    .foregroundColor(.gray)
                                Spacer()
                                Text(statusText(currentMesh.status))
                                    .foregroundColor(statusColor(currentMesh.status))
                            }
                        }
                        
                        // Stage Progress
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Generation Stages")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            VStack(spacing: 12) {
                                StageProgressView(
                                    stageName: "1. Preview Generation",
                                    status: currentMesh.previewStatus ?? .pending,
                                    progress: currentMesh.previewProgress ?? 0
                                )
                                
                                StageProgressView(
                                    stageName: "2. Model Refinement",
                                    status: currentMesh.refineStatus ?? .pending,
                                    progress: currentMesh.refineProgress ?? 0
                                )
                                
                                StageProgressView(
                                    stageName: "3. Character Rigging",
                                    status: currentMesh.riggingStatus ?? .pending,
                                    progress: currentMesh.riggingProgress ?? 0
                                )
                                
                                StageProgressView(
                                    stageName: "4. Animation Generation",
                                    status: currentMesh.animationStatus ?? .pending,
                                    progress: currentMesh.animationProgress ?? 0
                                )
                            }
                        }
                        .padding(.top, 8)
                        
                        if let errorMessage = currentMesh.errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.2))
                                .cornerRadius(8)
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                
                // Instructions
                VStack(alignment: .leading, spacing: 12) {
                    Text("How it works")
                        .font(.title2)
                        .bold()
                        .foregroundColor(.white)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        InstructionRow(number: "1", text: "Describe your avatar in detail using the prompt field")
                        InstructionRow(number: "2", text: "Click \"Generate Avatar\" to start the AI generation process")
                        InstructionRow(number: "3", text: "Wait for the generation to complete (this may take several minutes)")
                        InstructionRow(number: "4", text: "Your new avatar will automatically become your active avatar")
                    }
                }
                .padding()
                .background(Color.black.opacity(0.3))
                .cornerRadius(12)
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .background(Color.black)
        .onAppear {
            loadUserAvatar()
        }
        .onChange(of: meshService.currentMesh?.status) { oldValue, newValue in
            if newValue == .succeeded {
                loadUserAvatar()
            }
        }
    }
    
    private func loadUserAvatar() {
        guard !isLoadingAvatar else { return }
        isLoadingAvatar = true
        
        Task {
            do {
                userAvatar = try await meshService.fetchUserAvatar()
            } catch {
                print("Failed to load user avatar: \(error.localizedDescription)")
            }
            isLoadingAvatar = false
        }
    }
    
    private func statusText(_ status: GenerationStatus) -> String {
        switch status {
        case .inProgress:
            return "Generating... This will take a few minutes."
        case .succeeded:
            return "Completed"
        case .failed:
            return "Failed"
        }
    }
    
    private func statusColor(_ status: GenerationStatus) -> Color {
        switch status {
        case .inProgress:
            return .yellow
        case .succeeded:
            return .green
        case .failed:
            return .red
        }
    }
}

// MARK: - Supporting Views

struct StatusRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .foregroundColor(.white)
                .font(.system(.body, design: .monospaced))
        }
    }
}

struct StageProgressView: View {
    let stageName: String
    let status: StageStatus
    let progress: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(stageName)
                    .font(.subheadline)
                    .foregroundColor(.white)
                Spacer()
                Text(stageStatusText(status))
                    .font(.caption)
                    .foregroundColor(stageStatusColor(status))
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(stageStatusColor(status))
                        .frame(width: geometry.size.width * CGFloat(progress) / 100, height: 8)
                }
            }
            .frame(height: 8)
            
            if status == .inProgress {
                HStack {
                    Spacer()
                    Text("\(progress)%")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
        }
    }
    
    private func stageStatusText(_ status: StageStatus) -> String {
        switch status {
        case .pending:
            return "Pending"
        case .inProgress:
            return "In Progress"
        case .succeeded:
            return "Completed"
        case .failed:
            return "Failed"
        }
    }
    
    private func stageStatusColor(_ status: StageStatus) -> Color {
        switch status {
        case .pending:
            return .gray
        case .inProgress:
            return .yellow
        case .succeeded:
            return .green
        case .failed:
            return .red
        }
    }
}

struct InstructionRow: View {
    let number: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color.blue)
                .clipShape(Circle())
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.gray)
        }
    }
}

#Preview {
    AvatarGeneratorView()
}
