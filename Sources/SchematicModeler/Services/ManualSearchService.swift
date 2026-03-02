import Foundation

/// Communicates with the service-manual-reader MCP server for search and extraction
actor ManualSearchService {

    private let mcpServerDir = "/Users/marshallbenson/Desktop/Code/service-manual-reader/mcp-server"
    private let mcpClient: MCPClient

    init() {
        mcpClient = MCPClient(
            serverDirectory: "/Users/marshallbenson/Desktop/Code/service-manual-reader/mcp-server"
        )
    }

    struct SearchResult: Identifiable, Sendable {
        let id = UUID()
        let title: String
        let url: String
    }

    // MARK: - Health Check

    func pingServer() async -> Bool {
        await mcpClient.ping()
    }

    // MARK: - Search

    func searchManual(brand: String, model: String) async throws -> [SearchResult] {
        let output = try await mcpClient.callTool(
            name: "search_service_manual",
            arguments: ["brand": brand, "model": model]
        )
        return parseSearchResults(output)
    }

    // MARK: - Download PDF

    func downloadPDF(from url: URL, title: String) async throws -> URL {
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode)
        else {
            throw ManualSearchError.downloadFailed
        }

        let safeName = title
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .prefix(80)
        let filename = safeName.isEmpty ? UUID().uuidString : String(safeName)

        let manualsDir = ManualLibraryService.manualsDirectory
        let fm = FileManager.default
        if !fm.fileExists(atPath: manualsDir.path) {
            try fm.createDirectory(at: manualsDir, withIntermediateDirectories: true)
        }

        let dest = manualsDir
            .appendingPathComponent(filename)
            .appendingPathExtension("pdf")
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.moveItem(at: tempURL, to: dest)
        return dest
    }

    // MARK: - Extract PDF

    func extractPDF(at path: URL) async throws -> String {
        try await mcpClient.callTool(
            name: "extract_manual",
            arguments: ["pdf_path": path.path]
        )
    }

    // MARK: - MCP Tools: Manual Browsing

    /// Returns list of available manual names from the MCP server
    func listMCPManuals() async throws -> [String] {
        let output = try await mcpClient.callTool(name: "list_manuals")
        return output.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Returns board assembly index (IDs and structure) for a manual
    func readIndex(manualName: String) async throws -> String {
        try await mcpClient.callTool(
            name: "read_index",
            arguments: ["manual_name": manualName]
        )
    }

    /// Returns section content from a manual
    func readSection(manualName: String, section: String) async throws -> String {
        try await mcpClient.callTool(
            name: "read_section",
            arguments: ["manual_name": manualName, "section": section]
        )
    }

    /// Returns schematic image paths for an assembly
    func getSchematic(manualName: String, boardID: String) async throws -> String {
        try await mcpClient.callTool(
            name: "get_schematic",
            arguments: ["manual_name": manualName, "board_id": boardID]
        )
    }

    // MARK: - MCP Tools: Analysis Pipeline

    /// Analyzes schematic images for an assembly (intermediate step)
    func analyzeSchematic(manualName: String, boardID: String) async throws -> String {
        try await mcpClient.callTool(
            name: "analyze_schematic",
            arguments: ["manual_name": manualName, "board_id": boardID],
            timeoutSeconds: 300
        )
    }

    /// Cross-checks schematic analysis against parts lists
    func crossCheckSchematic(manualName: String, boardID: String) async throws -> String {
        try await mcpClient.callTool(
            name: "cross_check_schematic",
            arguments: ["manual_name": manualName, "board_id": boardID],
            timeoutSeconds: 300
        )
    }

    /// Runs the full analysis pipeline: analyze schematics → generate netlist → write _circuits/<board_id>.json.
    /// Long-running (2-5 min) — the MCP server handles all Claude API interaction internally.
    /// The `onProgress` callback receives stderr lines from the server process in real time.
    func generateNetlist(
        manualName: String,
        boardID: String,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        try await mcpClient.callTool(
            name: "generate_netlist",
            arguments: ["manual_name": manualName, "board_id": boardID],
            timeoutSeconds: 300,
            onServerLog: onProgress
        )
    }

    // MARK: - Shutdown

    func shutdown() async {
        await mcpClient.stop()
    }

    // MARK: - Parse Search Results

    private func parseSearchResults(_ text: String) -> [SearchResult] {
        var results: [SearchResult] = []
        let lines = text.components(separatedBy: "\n")

        var currentTitle: String?
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Numbered result: "1. Title..."
            if let dotIndex = trimmed.firstIndex(of: "."),
               let num = Int(trimmed[..<dotIndex]),
               num > 0
            {
                currentTitle = String(trimmed[trimmed.index(after: dotIndex)...]).trimmingCharacters(in: .whitespaces)
            }
            // URL line
            else if trimmed.hasPrefix("http"), let title = currentTitle {
                results.append(SearchResult(title: title, url: trimmed))
                currentTitle = nil
            }
        }

        return results
    }
}

enum ManualSearchError: LocalizedError {
    case processError(exitCode: Int32, stderr: String)
    case timeout
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .processError(let code, let stderr):
            "Process exited with code \(code): \(stderr.prefix(500))"
        case .timeout:
            "Process timed out"
        case .downloadFailed:
            "Failed to download PDF"
        }
    }
}
