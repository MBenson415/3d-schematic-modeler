import SwiftUI
import AppKit

@MainActor
@Observable
final class ManualBrowserViewModel {

    // Manual library
    var manuals: [ServiceManual] = []
    var selectedManual: ServiceManual?
    var selectedAssembly: BoardAssemblyRef?
    var selectedImage: SchematicImage?
    var loadedImageData: Data?

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
            let ids = CircuitCacheService.cachedAssemblyIDs(manualDirectory: manual.directoryURL)
            for id in ids {
                cached.insert("\(manual.id)/\(id)")
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
                selectManual(newManual)
                extractionStatus = "Loaded: \(newManual.name) (\(newManual.boardAssemblies.count) assemblies)"
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

    // MARK: - Analyze Assembly (all images)

    /// Loads all schematic + parts list images for the selected assembly and sends them to Claude
    func analyzeSelectedAssembly() async throws -> Circuit {
        guard let assembly = selectedAssembly else {
            throw ClaudeAPIError.invalidResponse
        }

        let apiKey = UserDefaults.standard.string(forKey: "anthropic_api_key") ?? ""
        guard !apiKey.isEmpty else {
            throw ClaudeAPIError.noAPIKey
        }

        isAnalyzing = true
        analysisError = nil
        analysisProgress = "Loading images for \(assembly.id)..."

        do {
            // Load all images for this assembly
            var images: [(data: Data, mimeType: String, label: String)] = []

            for (i, schematic) in assembly.schematicImages.enumerated() {
                analysisProgress = "Loading schematic \(i + 1)/\(assembly.schematicImages.count)..."
                let data = try await libraryService.loadImage(at: schematic.fileURL)
                images.append((data: data, mimeType: "image/png", label: "Schematic page \(i + 1): \(schematic.filename)"))
            }

            for (i, partsList) in assembly.partsListImages.enumerated() {
                analysisProgress = "Loading parts list \(i + 1)/\(assembly.partsListImages.count)..."
                let data = try await libraryService.loadImage(at: partsList.fileURL)
                images.append((data: data, mimeType: "image/png", label: "Parts list page \(i + 1): \(partsList.filename)"))
            }

            guard !images.isEmpty else {
                throw ClaudeAPIError.invalidResponse
            }

            analysisProgress = "Analyzing \(images.count) images with Claude..."

            let service = ClaudeAPIService(apiKey: apiKey)
            let circuit = try await service.analyzeAssembly(
                images: images,
                assemblyName: "\(assembly.id) — \(assembly.name)",
                manualName: selectedManual?.name ?? "service manual",
                progressHandler: { [weak self] status in
                    Task { @MainActor in
                        self?.analysisProgress = status
                    }
                }
            )

            // Cache the result
            if let manual = selectedManual {
                try? CircuitCacheService.saveCircuit(circuit, manualDirectory: manual.directoryURL, assemblyID: assembly.id)
                cachedAssemblies.insert("\(manual.id)/\(assembly.id)")
            }

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

    /// Single-image analysis (for previewing individual schematics)
    func analyzeSelectedImage() async throws -> Circuit {
        guard let imageData = loadedImageData, let image = selectedImage else {
            throw ClaudeAPIError.invalidResponse
        }

        let apiKey = UserDefaults.standard.string(forKey: "anthropic_api_key") ?? ""
        guard !apiKey.isEmpty else {
            throw ClaudeAPIError.noAPIKey
        }

        isAnalyzing = true
        analysisError = nil
        analysisProgress = "Analyzing single image..."

        do {
            let service = ClaudeAPIService(apiKey: apiKey)
            let context = "Board assembly \(image.boardID) from \(selectedManual?.name ?? "service manual"). This is a \(image.category.displayName.lowercased()) image."
            let circuit = try await service.analyzeSchematic(
                imageData: imageData,
                mimeType: "image/png",
                context: context
            )
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

    // MARK: - Finder

    func openInFinder(_ image: SchematicImage) {
        NSWorkspace.shared.activateFileViewerSelecting([image.fileURL])
    }
}
