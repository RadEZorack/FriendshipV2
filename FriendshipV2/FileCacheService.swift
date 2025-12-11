//
//  FileCacheService.swift
//  FriendshipV2
//
//  Created by Travis Miller on 2025-12-08.
//

import Foundation

/// Service for downloading and caching files locally
@MainActor
final class FileCacheService {
    static let shared = FileCacheService()
    
    private let cacheDirectory: URL
    
    private init() {
        // Use app's cache directory
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cacheDir.appendingPathComponent("MeshCache", isDirectory: true)
        
        // Create cache directory if it doesn't exist
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    /// Downloads a file from URL and caches it locally
    /// Returns the local file URL if successful
    func downloadAndCache(url: URL, filename: String) async throws -> URL {
        // Check if file already exists in cache
        let localURL = cacheDirectory.appendingPathComponent(filename)
        
        if FileManager.default.fileExists(atPath: localURL.path) {
            print("📦 File already cached: \(filename)")
            return localURL
        }
        
        print("📥 Downloading file: \(url.absoluteString)")
        
        // Download file
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw FileCacheError.downloadFailed
        }
        
        // Save to cache
        try data.write(to: localURL)
        print("✅ File cached: \(filename)")
        
        return localURL
    }
    
    /// Gets the local cached URL for a file if it exists
    func getCachedURL(filename: String) -> URL? {
        let localURL = cacheDirectory.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: localURL.path) ? localURL : nil
    }
    
    /// Clears all cached files
    func clearCache() throws {
        let files = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
        for file in files {
            try FileManager.default.removeItem(at: file)
        }
        print("🗑️ Cache cleared")
    }
    
    /// Generates a filename from a URL
    func filenameFromURL(_ url: URL) -> String {
        // Use the last path component, or generate from URL hash
        if let lastComponent = url.pathComponents.last, !lastComponent.isEmpty {
            return lastComponent
        }
        // Fallback: use URL hash
        return "\(url.absoluteString.hash).usdz"
    }
}

enum FileCacheError: LocalizedError {
    case downloadFailed
    case invalidURL
    
    var errorDescription: String? {
        switch self {
        case .downloadFailed:
            return "Failed to download file"
        case .invalidURL:
            return "Invalid file URL"
        }
    }
}
