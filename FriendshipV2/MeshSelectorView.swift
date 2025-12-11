//
//  MeshSelectorView.swift
//  FriendshipV2
//
//  Created by Travis Miller on 2025-12-08.
//

import SwiftUI

struct MeshSelectorView: View {
    @StateObject private var meshService = MeshGenerationService.shared
    @Binding var selectedMeshId: String?
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            List {
                // Option to use default bundle model
                Button(action: {
                    selectedMeshId = nil
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "cube.box")
                            .foregroundColor(.blue)
                        VStack(alignment: .leading) {
                            Text("Default Model")
                                .font(.headline)
                            Text("Animation_FunnyDancing_01.usdz")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        if selectedMeshId == nil {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                // List of user's meshes
                ForEach(meshService.userAvatars.filter { $0.status == .succeeded }) { mesh in
                    Button(action: {
                        selectedMeshId = mesh.id
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundColor(.green)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mesh.prompt)
                                    .font(.headline)
                                    .lineLimit(2)
                                if let usdzUrl = mesh.animationUsdzUrl {
                                    Text("USDZ Available")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else {
                                    Text("No USDZ")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                            Spacer()
                            if selectedMeshId == mesh.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .navigationTitle("Select Avatar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                }
            }
        }
        .task {
            isLoading = true
            do {
                try await meshService.fetchUserAvatars()
            } catch {
                print("Failed to fetch avatars: \(error.localizedDescription)")
            }
            isLoading = false
        }
    }
}

#Preview {
    MeshSelectorView(selectedMeshId: .constant(nil))
}
