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
