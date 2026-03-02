import SwiftUI
import AppKit
import os.log

private let browserLog = Logger(subsystem: "SchematicModeler", category: "ManualBrowser")

@MainActor
@Observable
final class ManualBrowserViewModel {

    // Manual library
    var manuals: [ServiceManual] = []
    var selectedManual: ServiceManual?
    var selectedAssembly: BoardAssemblyRef?
    var selectedImage: SchematicImage?
    var loadedImageData: Data?

    // MCP server status
    enum MCPStatus { case unknown, checking, connected, unreachable }
    var mcpStatus: MCPStatus = .unknown

    // Search
    var searchBrand = ""
    var searchModel = ""
    var searchResults: [ManualSearchService.SearchResult] = []
    var isSearching = false
    var searchError: String?

    // Extraction
    var isExtracting = false
    var extractionStatus = ""

    // Analysis
    var isAnalyzing = false
    var analysisError: String?
    var analysisProgress = ""

    // Cache: tracks which assemblies have saved circuits (keyed by "manualID/assemblyID")
    var cachedAssemblies: Set<String> = []

    // Services
    private let libraryService = ManualLibraryService()
    private let searchService = ManualSearchService()

    // MARK: - Load Manuals

    func loadManuals() async {
        do {
            manuals = try await libraryService.listManuals()
            refreshCacheIndex()
        } catch {
            // Don't wipe existing manuals on reload failure
            print("[ManualBrowser] Failed to load manuals: \(error)")
        }
    }

    /// Scans all manual directories for cached circuit files
    func refreshCacheIndex() {
        var cached: Set<String> = []
        for manual in manuals {
            for assembly in manual.boardAssemblies {
                if CircuitCacheService.hasCachedCircuit(manualDirectory: manual.directoryURL, assemblyID: assembly.id) {
                    cached.insert("\(manual.id)/\(assembly.id)")
                }
            }
        }
        cachedAssemblies = cached
    }

    func isCached(manual: ServiceManual, assembly: BoardAssemblyRef) -> Bool {
        cachedAssemblies.contains("\(manual.id)/\(assembly.id)")
    }

    /// Load a cached circuit for an assembly
    func loadCachedCircuit(manual: ServiceManual, assembly: BoardAssemblyRef) -> Circuit? {
        try? CircuitCacheService.loadCircuit(manualDirectory: manual.directoryURL, assemblyID: assembly.id)
    }

    // MARK: - Selection

    func selectManual(_ manual: ServiceManual?) {
        selectedManual = manual
        selectedAssembly = nil
        selectedImage = nil
        loadedImageData = nil
    }

    func selectAssembly(_ assembly: BoardAssemblyRef?) {
        selectedAssembly = assembly
        selectedImage = nil
        loadedImageData = nil
    }

    func selectImage(_ image: SchematicImage?) {
        selectedImage = image
        loadedImageData = nil

        guard let image else { return }

        Task {
            do {
                let data = try await libraryService.loadImage(at: image.fileURL)
                self.loadedImageData = data
            } catch {
                self.loadedImageData = nil
            }
        }
    }

    // MARK: - MCP Status

    func checkMCPServer() async {
        mcpStatus = .checking
        let ok = await searchService.pingServer()
        mcpStatus = ok ? .connected : .unreachable
    }

    // MARK: - Search

    func searchForManual() async {
        guard !searchBrand.isEmpty || !searchModel.isEmpty else { return }

        isSearching = true
        searchError = nil
        searchResults = []

        do {
            searchResults = try await searchService.searchManual(brand: searchBrand, model: searchModel)
            if searchResults.isEmpty {
                searchError = "No results found."
            }
        } catch {
            searchError = error.localizedDescription
        }

        isSearching = false
    }

    // MARK: - PDF Import & Extraction

    func importPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.message = "Select a service manual PDF to extract"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            await extractPDF(at: url)
        }
    }

    func downloadAndExtract(url: String, title: String) async {
        guard let remoteURL = URL(string: url) else { return }

        isExtracting = true
        extractionStatus = "Downloading PDF..."

        do {
            let localFile = try await searchService.downloadPDF(from: remoteURL, title: title)
            extractionStatus = "Extracting \(localFile.lastPathComponent)..."
            let result = try await searchService.extractPDF(at: localFile)

            extractionStatus = "Reloading manuals..."
            let previousIDs = Set(manuals.map(\.id))
            await loadManuals()

            if let newManual = manuals.first(where: { !previousIDs.contains($0.id) }) {
                // Auto-name from search brand/model if available
                let autoName = [searchBrand, searchModel]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                if !autoName.isEmpty {
                    renameManual(newManual, to: "\(autoName) Service Manual")
                }

                selectManual(manuals.first(where: { $0.id == newManual.id }) ?? newManual)
                let displayName = manuals.first(where: { $0.id == newManual.id })?.name ?? newManual.name
                extractionStatus = "Loaded: \(displayName) (\(newManual.boardAssemblies.count) assemblies)"
            } else {
                // No new manual directory found — show convert.py output for debugging
                extractionStatus = "Extraction finished but no new manual found. Output: \(result.prefix(300))"
            }
        } catch {
            extractionStatus = "Error: \(error.localizedDescription)"
        }

        isExtracting = false
    }

    func extractPDF(at url: URL) async {
        isExtracting = true
        extractionStatus = "Extracting \(url.lastPathComponent)..."

        do {
            let result = try await searchService.extractPDF(at: url)

            extractionStatus = "Reloading manuals..."
            let previousIDs = Set(manuals.map(\.id))
            await loadManuals()

            if let newManual = manuals.first(where: { !previousIDs.contains($0.id) }) {
                selectManual(newManual)
                extractionStatus = "Loaded: \(newManual.name) (\(newManual.boardAssemblies.count) assemblies)"
            } else {
                extractionStatus = "Extraction finished but no new manual found. Output: \(result.prefix(300))"
            }
        } catch {
            extractionStatus = "Error: \(error.localizedDescription)"
        }

        isExtracting = false
    }

    // MARK: - Analyze Assembly (via MCP server)

    /// Generates a circuit netlist for the selected assembly.
    /// Tries the MCP server first; falls back to direct Claude API if MCP doesn't produce a file.
    func analyzeSelectedAssembly() async throws -> Circuit {
        guard let manual = selectedManual,
              let assembly = selectedAssembly else {
            throw ClaudeAPIError.invalidResponse
        }

        isAnalyzing = true
        analysisError = nil
        analysisProgress = "Generating netlist for \(assembly.id)..."
        browserLog.info("Starting netlist generation: manual='\(manual.name)' board='\(assembly.id)'")
        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            // --- Attempt 1: MCP server ---
            let mcpResult = try? await searchService.generateNetlist(
                manualName: manual.name,
                boardID: assembly.id,
                onProgress: { @Sendable [weak self] line in
                    Task { @MainActor in
                        self?.analysisProgress = line
                    }
                }
            )

            if CircuitCacheService.hasCachedCircuit(manualDirectory: manual.directoryURL, assemblyID: assembly.id) {
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                browserLog.info("MCP netlist complete in \(String(format: "%.1f", elapsed))s")
                return try loadAndFinish(manual: manual, assembly: assembly)
            }

            browserLog.info("MCP did not produce file — falling back to direct Claude API. MCP output: \(mcpResult?.prefix(200) ?? "nil")")

            // --- Attempt 2: Direct Claude API ---
            let circuit = try await analyzeWithClaudeAPI(manual: manual, assembly: assembly)

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            browserLog.info("Claude API analysis complete in \(String(format: "%.1f", elapsed))s — \(circuit.components.count) components")

            // Cache the result
            try? CircuitCacheService.saveCircuit(circuit, manualDirectory: manual.directoryURL, assemblyID: assembly.id)
            cachedAssemblies.insert("\(manual.id)/\(assembly.id)")
            isAnalyzing = false
            analysisProgress = ""
            return circuit
        } catch {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            browserLog.error("Analysis failed after \(String(format: "%.1f", elapsed))s: \(error.localizedDescription)")
            isAnalyzing = false
            analysisProgress = ""
            analysisError = error.localizedDescription
            throw error
        }
    }

    /// Loads a cached circuit and marks it in the index
    private func loadAndFinish(manual: ServiceManual, assembly: BoardAssemblyRef) throws -> Circuit {
        analysisProgress = "Loading circuit..."
        let circuit = try CircuitCacheService.loadCircuit(
            manualDirectory: manual.directoryURL,
            assemblyID: assembly.id
        )
        browserLog.info("Loaded circuit: \(circuit.name) — \(circuit.components.count) components, \(circuit.nets.count) nets")
        cachedAssemblies.insert("\(manual.id)/\(assembly.id)")
        isAnalyzing = false
        analysisProgress = ""
        return circuit
    }

    /// Fallback: analyze assembly images directly via Claude Vision API
    private func analyzeWithClaudeAPI(manual: ServiceManual, assembly: BoardAssemblyRef) async throws -> Circuit {
        let apiKey = UserDefaults.standard.string(forKey: "anthropic_api_key") ?? ""
        guard !apiKey.isEmpty else {
            throw MCPAnalysisError.noAPIKeyForFallback(boardID: assembly.id)
        }

        let allImages = assembly.allImages
        guard !allImages.isEmpty else {
            throw MCPAnalysisError.noImagesAvailable(boardID: assembly.id)
        }

        analysisProgress = "Falling back to Claude Vision API (\(allImages.count) images)..."
        browserLog.info("Claude API fallback: \(allImages.count) images for \(assembly.id)")

        // Load image data from disk
        var imageEntries: [(data: Data, mimeType: String, label: String)] = []
        for image in allImages {
            guard let data = try? Data(contentsOf: image.fileURL) else { continue }
            let ext = image.fileURL.pathExtension.lowercased()
            let mimeType = ext == "jpg" || ext == "jpeg" ? "image/jpeg" : "image/png"
            imageEntries.append((data: data, mimeType: mimeType, label: "\(image.category.displayName) — \(image.filename)"))
        }

        guard !imageEntries.isEmpty else {
            throw MCPAnalysisError.noImagesAvailable(boardID: assembly.id)
        }

        let service = ClaudeAPIService(apiKey: apiKey)
        return try await service.analyzeAssembly(
            images: imageEntries,
            assemblyName: "\(assembly.id) — \(assembly.name)",
            manualName: manual.name,
            progressHandler: { @Sendable [weak self] line in
                Task { @MainActor in
                    self?.analysisProgress = line
                }
            }
        )
    }

    /// Single-image analysis via MCP server — analyzes the schematic for a specific board assembly
    func analyzeSelectedImage() async throws -> Circuit {
        guard let image = selectedImage,
              let manual = selectedManual else {
            throw ClaudeAPIError.invalidResponse
        }

        isAnalyzing = true
        analysisError = nil
        analysisProgress = "Analyzing schematic for \(image.boardID)..."

        do {
            // Use MCP server to analyze this board's schematics
            let _ = try await searchService.analyzeSchematic(
                manualName: manual.name,
                boardID: image.boardID
            )

            analysisProgress = "Loading circuit..."

            // Load the result from disk
            let circuit = try CircuitCacheService.loadCircuit(
                manualDirectory: manual.directoryURL,
                assemblyID: image.boardID
            )

            cachedAssemblies.insert("\(manual.id)/\(image.boardID)")
            isAnalyzing = false
            analysisProgress = ""
            return circuit
        } catch {
            isAnalyzing = false
            analysisProgress = ""
            analysisError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Cache Management

    func deleteCachedCircuit(manual: ServiceManual, assembly: BoardAssemblyRef) {
        try? CircuitCacheService.deleteCircuit(manualDirectory: manual.directoryURL, assemblyID: assembly.id)
        cachedAssemblies.remove("\(manual.id)/\(assembly.id)")
    }

    /// Delete an entire manual directory from disk and refresh the list
    func deleteManual(_ manual: ServiceManual) {
        if selectedManual == manual {
            selectManual(nil)
        }

        let fm = FileManager.default
        if fm.fileExists(atPath: manual.directoryURL.path) {
            try? fm.removeItem(at: manual.directoryURL)
        }

        manuals.removeAll { $0.id == manual.id }
        cachedAssemblies = cachedAssemblies.filter { !$0.hasPrefix("\(manual.id)/") }
    }

    // MARK: - Reorder

    func moveManuals(from source: IndexSet, to destination: Int) {
        manuals.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Rename

    func renameManual(_ manual: ServiceManual, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let indexURL = manual.directoryURL.appendingPathComponent("_index.md")
        guard var content = try? String(contentsOf: indexURL, encoding: .utf8) else { return }

        // Replace the first `# Title` line
        let lines = content.components(separatedBy: "\n")
        if let titleIndex = lines.firstIndex(where: { $0.hasPrefix("# ") && !$0.hasPrefix("## ") }) {
            var mutableLines = lines
            mutableLines[titleIndex] = "# \(trimmed)"
            content = mutableLines.joined(separator: "\n")
        } else {
            // No title line — prepend one
            content = "# \(trimmed)\n\n" + content
        }

        try? content.write(to: indexURL, atomically: true, encoding: .utf8)

        // Update in-memory list
        if let idx = manuals.firstIndex(where: { $0.id == manual.id }) {
            let old = manuals[idx]
            manuals[idx] = ServiceManual(
                id: old.id,
                name: trimmed,
                directoryURL: old.directoryURL,
                totalPages: old.totalPages,
                boardAssemblies: old.boardAssemblies,
                sections: old.sections
            )
        }
    }

    // MARK: - Finder

    func openInFinder(_ image: SchematicImage) {
        NSWorkspace.shared.activateFileViewerSelecting([image.fileURL])
    }
}

// MARK: - MCP Analysis Errors

enum MCPAnalysisError: LocalizedError {
    case noCircuitGenerated(boardID: String, serverOutput: String)
    case noAPIKeyForFallback(boardID: String)
    case noImagesAvailable(boardID: String)

    var errorDescription: String? {
        switch self {
        case .noCircuitGenerated(let boardID, let serverOutput):
            "No circuit generated for \(boardID). Server: \(serverOutput)"
        case .noAPIKeyForFallback(let boardID):
            "MCP failed for \(boardID) and no API key set for fallback. Add your Anthropic API key in settings."
        case .noImagesAvailable(let boardID):
            "No schematic images found for \(boardID)."
        }
    }
}
