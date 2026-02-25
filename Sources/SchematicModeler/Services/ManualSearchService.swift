import Foundation

/// Shells out to the service-manual-reader Python tools for search and extraction
actor ManualSearchService {

    private let uvPath = "/Users/marshallbenson/.local/bin/uv"
    private let mcpServerDir = "/Users/marshallbenson/Desktop/Code/service-manual-reader/mcp-server"
    private let convertScript = "/Users/marshallbenson/Desktop/Code/service-manual-reader/convert.py"

    struct SearchResult: Identifiable, Sendable {
        let id = UUID()
        let title: String
        let url: String
    }

    // MARK: - Search

    func searchManual(brand: String, model: String) async throws -> [SearchResult] {
        let escapedBrand = brand.replacingOccurrences(of: "'", with: "\\'")
        let escapedModel = model.replacingOccurrences(of: "'", with: "\\'")

        let script = """
        import asyncio, sys
        sys.path.insert(0, '.')
        from main import search_service_manual
        result = asyncio.run(search_service_manual('\(escapedBrand)', '\(escapedModel)'))
        print(result)
        """

        let output = try await runProcess(
            executable: uvPath,
            arguments: ["--directory", mcpServerDir, "run", "python", "-c", script],
            timeout: 20
        )

        return parseSearchResults(output)
    }

    // MARK: - Extract PDF

    func extractPDF(at path: URL) async throws -> String {
        let output = try await runProcess(
            executable: uvPath,
            arguments: [
                "--directory", mcpServerDir,
                "run", "python", convertScript, path.path,
            ],
            timeout: 300
        )

        return output
    }

    // MARK: - Process Execution

    private func runProcess(executable: String, arguments: [String], timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            process.terminationHandler = { _ in
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let outString = String(data: outData, encoding: .utf8) ?? ""
                let errString = String(data: errData, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: outString)
                } else {
                    continuation.resume(throwing: ManualSearchError.processError(
                        exitCode: process.terminationStatus,
                        stderr: errString.isEmpty ? outString : errString
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }

            // Timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    process.terminate()
                }
            }
        }
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

    var errorDescription: String? {
        switch self {
        case .processError(let code, let stderr):
            "Process exited with code \(code): \(stderr.prefix(500))"
        case .timeout:
            "Process timed out"
        }
    }
}
