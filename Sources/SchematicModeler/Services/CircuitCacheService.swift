import Foundation

/// Saves and loads analyzed Circuit JSON alongside manual directories.
/// Cache path: ~/Claude-Manuals/<manual-dir>/_circuits/<assembly-id>.json
enum CircuitCacheService {

    private static let circuitsDirName = "_circuits"

    /// Converts an assembly ID to a filesystem-safe filename.
    /// IDs like "HT3035:B / 25C335B" contain `:` and `/` which break file paths.
    static func safeFilename(for assemblyID: String) -> String {
        var safe = assemblyID
        for ch: Character in ["/", ":", "\\", " "] {
            safe = safe.split(separator: ch, omittingEmptySubsequences: false).joined(separator: "-")
        }
        // Collapse multiple dashes and trim
        while safe.contains("--") {
            safe = safe.replacingOccurrences(of: "--", with: "-")
        }
        safe = safe.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return safe.isEmpty ? "unknown" : safe
    }

    /// Returns the cache file URL for a given assembly within a manual directory
    static func cacheURL(manualDirectory: URL, assemblyID: String) -> URL {
        let filename = safeFilename(for: assemblyID)
        return manualDirectory
            .appendingPathComponent(circuitsDirName)
            .appendingPathComponent("\(filename).json")
    }

    /// Check if a cached circuit exists
    static func hasCachedCircuit(manualDirectory: URL, assemblyID: String) -> Bool {
        let url = cacheURL(manualDirectory: manualDirectory, assemblyID: assemblyID)
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Load a cached circuit from disk
    static func loadCircuit(manualDirectory: URL, assemblyID: String) throws -> Circuit {
        let url = cacheURL(manualDirectory: manualDirectory, assemblyID: assemblyID)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Circuit.self, from: data)
    }

    /// Save a circuit to the cache
    static func saveCircuit(_ circuit: Circuit, manualDirectory: URL, assemblyID: String) throws {
        let dir = manualDirectory.appendingPathComponent(circuitsDirName)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let url = dir.appendingPathComponent("\(assemblyID).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(circuit)
        try data.write(to: url, options: .atomic)
    }

    /// Delete a cached circuit
    static func deleteCircuit(manualDirectory: URL, assemblyID: String) throws {
        let url = cacheURL(manualDirectory: manualDirectory, assemblyID: assemblyID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// List all cached assembly IDs for a manual
    static func cachedAssemblyIDs(manualDirectory: URL) -> Set<String> {
        let dir = manualDirectory.appendingPathComponent(circuitsDirName)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        return Set(files.compactMap { url -> String? in
            guard url.pathExtension == "json" else { return nil }
            return url.deletingPathExtension().lastPathComponent
        })
    }
}
