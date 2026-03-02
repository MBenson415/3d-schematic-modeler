import Foundation

/// A JSON-RPC 2.0 client that communicates with an MCP server over stdio
/// using newline-delimited JSON (one JSON object per line).
actor MCPClient {

    private let serverDirectory: String
    private let command: String
    private let arguments: [String]

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var nextID: Int = 1
    private var isInitialized = false

    /// Buffer for accumulating raw bytes from stdout
    private var readBuffer = Data()

    init(
        serverDirectory: String,
        command: String = "/usr/bin/env",
        arguments: [String] = ["uv", "run", "python", "main.py"]
    ) {
        self.serverDirectory = serverDirectory
        self.command = command
        self.arguments = arguments
    }

    deinit {
        process?.terminate()
    }

    // MARK: - Lifecycle

    private var stderrPipe: Pipe?

    /// Spawns the MCP server process and performs the initialize handshake.
    func start() async throws {
        guard process == nil else { return }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: command)
        proc.arguments = arguments
        proc.currentDirectoryURL = URL(fileURLWithPath: serverDirectory)

        // GUI apps have a minimal PATH — ensure common tool locations are included.
        var env = ProcessInfo.processInfo.environment
        let extraPaths = [
            "\(NSHomeDirectory())/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
        proc.environment = env

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        try proc.run()

        self.process = proc
        self.stdinPipe = stdin
        self.stdoutPipe = stdout
        self.stderrPipe = stderr
        self.readBuffer = Data()

        // If the process exits immediately, surface the stderr output.
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        if !proc.isRunning {
            let errData = stderr.fileHandleForReading.availableData
            let errString = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw MCPError.initializationFailed(
                errString.isEmpty ? "Process exited with code \(proc.terminationStatus)" : errString
            )
        }

        // Initialize handshake
        let initResult: JSONRPCResponse = try await sendRequest(
            method: "initialize",
            params: [
                "protocolVersion": "2024-11-05",
                "capabilities": [:] as [String: String],
                "clientInfo": [
                    "name": "SchematicModeler",
                    "version": "1.0",
                ],
            ] as [String: Any]
        )

        guard initResult.error == nil else {
            throw MCPError.initializationFailed(initResult.error?.message ?? "Unknown error")
        }

        // Send initialized notification (no response expected)
        try sendNotification(method: "notifications/initialized")

        isInitialized = true
    }

    /// Terminates the MCP server process.
    func stop() {
        process?.terminate()
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        isInitialized = false
        readBuffer = Data()
    }

    // MARK: - Tool Calls

    /// Calls an MCP tool by name with the given arguments and returns text content.
    func callTool(name: String, arguments: [String: Any] = [:]) async throws -> String {
        try await ensureStarted()

        let response: JSONRPCResponse = try await sendRequest(
            method: "tools/call",
            params: [
                "name": name,
                "arguments": arguments,
            ]
        )

        if let error = response.error {
            throw MCPError.toolError(name: name, message: error.message)
        }

        guard let result = response.result else {
            throw MCPError.emptyResponse
        }

        return extractTextContent(from: result)
    }

    /// Lists available tools on the MCP server.
    func listTools() async throws -> [[String: Any]] {
        try await ensureStarted()

        let response: JSONRPCResponse = try await sendRequest(
            method: "tools/list",
            params: [:] as [String: Any]
        )

        if let error = response.error {
            throw MCPError.toolError(name: "tools/list", message: error.message)
        }

        guard let result = response.result,
              let tools = result["tools"] as? [[String: Any]]
        else {
            return []
        }

        return tools
    }

    // MARK: - Health Check

    /// Pings the server by sending a `tools/list` request with a short timeout.
    /// Returns `true` if the server responds in time.
    func ping() async -> Bool {
        do {
            try await ensureStarted()
            let _: JSONRPCResponse = try await sendRequest(
                method: "tools/list",
                params: [:] as [String: Any],
                timeoutSeconds: 5
            )
            return true
        } catch {
            return false
        }
    }

    // MARK: - JSON-RPC Transport

    private func ensureStarted() async throws {
        if !isInitialized {
            try await start()
        }
    }

    private func sendRequest(
        method: String,
        params: [String: Any],
        timeoutSeconds: UInt64 = 30
    ) async throws -> JSONRPCResponse {
        let id = nextID
        nextID += 1

        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        ]

        try sendMessage(message)
        return try await withThrowingTaskGroup(of: JSONRPCResponse.self) { group in
            group.addTask {
                try await self.readResponse(expectedID: id)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                throw MCPError.timeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func sendNotification(method: String, params: [String: Any] = [:]) throws {
        var message: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
        ]
        if !params.isEmpty {
            message["params"] = params
        }
        try sendMessage(message)
    }

    private func sendMessage(_ message: [String: Any]) throws {
        guard let stdin = stdinPipe else {
            throw MCPError.notConnected
        }

        var jsonData = try JSONSerialization.data(withJSONObject: message)
        jsonData.append(0x0A) // newline delimiter

        let handle = stdin.fileHandleForWriting
        handle.write(jsonData)
    }

    /// Reads the next JSON-RPC response, skipping notifications.
    private func readResponse(expectedID: Int) async throws -> JSONRPCResponse {
        guard let stdout = stdoutPipe else {
            throw MCPError.notConnected
        }

        let handle = stdout.fileHandleForReading

        while true {
            let line = try await readLine(from: handle)

            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else {
                continue // Skip malformed lines
            }

            // Skip notifications (messages without an "id")
            guard let responseID = json["id"] as? Int else {
                continue
            }

            guard responseID == expectedID else {
                continue // Skip mismatched IDs
            }

            var error: JSONRPCError?
            if let errObj = json["error"] as? [String: Any] {
                error = JSONRPCError(
                    code: errObj["code"] as? Int ?? -1,
                    message: errObj["message"] as? String ?? "Unknown error"
                )
            }

            let result = json["result"] as? [String: Any]
            return JSONRPCResponse(id: responseID, result: result, error: error)
        }
    }

    /// Reads one newline-delimited line from the handle.
    /// Runs the blocking read on a non-cooperative thread.
    private func readLine(from handle: FileHandle) async throws -> String {
        while true {
            // Check buffer for a complete line
            if let newlineIndex = readBuffer.firstIndex(of: 0x0A) {
                let lineData = readBuffer[readBuffer.startIndex..<newlineIndex]
                readBuffer.removeSubrange(readBuffer.startIndex...newlineIndex)
                let line = String(data: Data(lineData), encoding: .utf8) ?? ""
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
                continue // Skip empty lines
            }

            // Read more data off the cooperative thread pool
            let chunk: Data = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let data = handle.availableData
                    if data.isEmpty {
                        continuation.resume(throwing: MCPError.serverClosed)
                    } else {
                        continuation.resume(returning: data)
                    }
                }
            }
            readBuffer.append(chunk)
        }
    }

    // MARK: - Content Extraction

    /// Extracts text from the MCP tools/call result, which contains a `content` array.
    private func extractTextContent(from result: [String: Any]) -> String {
        guard let contentArray = result["content"] as? [[String: Any]] else {
            // Fallback: try to serialize the whole result
            if let data = try? JSONSerialization.data(withJSONObject: result),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
            return ""
        }

        return contentArray
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
    }
}

// MARK: - Types

struct JSONRPCResponse: @unchecked Sendable {
    let id: Int
    let result: [String: Any]?
    let error: JSONRPCError?
}

struct JSONRPCError {
    let code: Int
    let message: String
}

enum MCPError: LocalizedError {
    case notConnected
    case initializationFailed(String)
    case toolError(name: String, message: String)
    case emptyResponse
    case encodingError
    case protocolError(String)
    case serverClosed
    case timeout

    var errorDescription: String? {
        switch self {
        case .notConnected:
            "MCP server not connected"
        case .initializationFailed(let msg):
            "MCP initialization failed: \(msg)"
        case .toolError(let name, let msg):
            "MCP tool '\(name)' error: \(msg)"
        case .emptyResponse:
            "MCP server returned empty response"
        case .encodingError:
            "Failed to encode MCP message"
        case .protocolError(let msg):
            "MCP protocol error: \(msg)"
        case .serverClosed:
            "MCP server closed unexpectedly"
        case .timeout:
            "MCP request timed out"
        }
    }
}
