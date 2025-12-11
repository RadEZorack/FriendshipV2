//
//  FriendshipV2App.swift
//  FriendshipV2
//
//  Created by Travis Miller on 2025-12-08.
//

import SwiftUI

@main
struct FriendshipV2App: App {
    @StateObject private var auth = AuthService.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .task {
                    // Attempt silent sign-in on app launch
                    _ = await auth.attemptSilentSignIn()
                }
        }
    }
}
