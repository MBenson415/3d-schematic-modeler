import Foundation
import os.log

private let mcpLog = Logger(subsystem: "SchematicModeler", category: "MCP")

/// A JSON-RPC 2.0 client that communicates with an MCP server over stdio
/// using newline-delimited JSON (NDJSON), per the MCP stdio transport spec.
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

    /// Callback invoked with each stderr line from the MCP server (for progress reporting)
    private var stderrLineHandler: (@Sendable (String) -> Void)?

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

        mcpLog.info("Starting MCP server: \(self.command) \(self.arguments.joined(separator: " "))")
        mcpLog.info("Working directory: \(self.serverDirectory)")

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
        mcpLog.info("MCP server process launched (PID \(proc.processIdentifier))")

        self.process = proc
        self.stdinPipe = stdin
        self.stdoutPipe = stdout
        self.stderrPipe = stderr
        self.readBuffer = Data()

        // Start streaming stderr so server logs appear in the console
        startStderrStreaming(stderr)

        // If the process exits immediately, surface the stderr output.
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        if !proc.isRunning {
            let errData = stderr.fileHandleForReading.availableData
            let errString = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            mcpLog.error("MCP server exited immediately: \(errString)")
            throw MCPError.initializationFailed(
                errString.isEmpty ? "Process exited with code \(proc.terminationStatus)" : errString
            )
        }

        // Initialize handshake
        mcpLog.info("Sending initialize handshake...")
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
            mcpLog.error("Initialize handshake failed: \(initResult.error?.message ?? "unknown")")
            throw MCPError.initializationFailed(initResult.error?.message ?? "Unknown error")
        }

        // Send initialized notification (no response expected)
        try sendNotification(method: "notifications/initialized")

        mcpLog.info("MCP server initialized successfully")
        isInitialized = true
    }

    /// Continuously reads stderr from the server process, logs each line, and forwards to progress handler
    private func startStderrStreaming(_ pipe: Pipe) {
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty,
                  let text = String(data: data, encoding: .utf8)
            else { return }
            for line in text.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    mcpLog.info("[MCP Server] \(trimmed)")
                    // Forward to progress handler on main actor
                    if let self {
                        Task {
                            let handler = await self.stderrLineHandler
                            handler?(trimmed)
                        }
                    }
                }
            }
        }
    }

    /// Terminates the MCP server process.
    func stop() {
        mcpLog.info("Stopping MCP server")
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
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
    /// The optional `onServerLog` callback receives each stderr line from the server process in real time.
    func callTool(
        name: String,
        arguments: [String: Any] = [:],
        timeoutSeconds: UInt64 = 30,
        onServerLog: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        try await ensureStarted()

        // Install progress handler for the duration of this call
        stderrLineHandler = onServerLog

        let argsDesc = arguments.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        mcpLog.info("→ Calling tool '\(name)' (\(argsDesc)) timeout=\(timeoutSeconds)s")
        let startTime = CFAbsoluteTimeGetCurrent()

        defer { stderrLineHandler = nil }

        let response: JSONRPCResponse = try await sendRequest(
            method: "tools/call",
            params: [
                "name": name,
                "arguments": arguments,
            ],
            timeoutSeconds: timeoutSeconds
        )

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        mcpLog.info("← Tool '\(name)' responded in \(String(format: "%.1f", elapsed))s")

        if let error = response.error {
            mcpLog.error("← Tool '\(name)' error: \(error.message)")
            throw MCPError.toolError(name: name, message: error.message)
        }

        guard let result = response.result else {
            mcpLog.error("← Tool '\(name)' returned empty result")
            throw MCPError.emptyResponse
        }

        let text = extractTextContent(from: result)
        mcpLog.info("← Tool '\(name)' returned \(text.count) chars")
        return text
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

    // MARK: - JSON-RPC Transport (NDJSON)

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

    /// Sends a JSON-RPC message as NDJSON (JSON followed by newline).
    private func sendMessage(_ message: [String: Any]) throws {
        guard let stdin = stdinPipe else {
            throw MCPError.notConnected
        }

        let jsonData = try JSONSerialization.data(withJSONObject: message)

        let method = message["method"] as? String ?? "?"
        let id = message["id"] as? Int
        mcpLog.debug("Sending \(method) (id=\(id ?? -1), \(jsonData.count) bytes)")

        let handle = stdin.fileHandleForWriting
        handle.write(jsonData + Data("\n".utf8))
    }

    /// Reads the next JSON-RPC response, skipping notifications.
    private func readResponse(expectedID: Int) async throws -> JSONRPCResponse {
        guard let stdout = stdoutPipe else {
            throw MCPError.notConnected
        }

        let handle = stdout.fileHandleForReading

        while true {
            try Task.checkCancellation()
            let line = try await readLine(from: handle)

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            guard let lineData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else {
                mcpLog.warning("Skipping non-JSON line: \(trimmed.prefix(100))")
                continue
            }

            // Skip notifications (messages without an "id")
            guard let responseID = json["id"] as? Int else {
                let method = json["method"] as? String ?? "?"
                mcpLog.debug("Skipping notification: \(method)")
                continue
            }

            guard responseID == expectedID else {
                mcpLog.debug("Skipping response id=\(responseID) (waiting for \(expectedID))")
                continue
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

    /// Reads one newline-delimited line from the handle (NDJSON transport).
    private func readLine(from handle: FileHandle) async throws -> String {
        let newline = UInt8(ascii: "\n")

        // Check if we already have a complete line in the buffer
        while !readBuffer.contains(newline) {
            try Task.checkCancellation()
            let chunk = try await readChunk(from: handle)
            readBuffer.append(chunk)
        }

        // Extract the first complete line
        guard let newlineIndex = readBuffer.firstIndex(of: newline) else {
            throw MCPError.protocolError("Missing newline")
        }

        let lineData = readBuffer[readBuffer.startIndex..<newlineIndex]
        readBuffer.removeSubrange(readBuffer.startIndex...newlineIndex)

        guard let line = String(data: Data(lineData), encoding: .utf8) else {
            throw MCPError.protocolError("Invalid line encoding")
        }

        return line
    }

    /// Reads available data from the handle using readabilityHandler (non-blocking, cancellation-cooperative).
    private func readChunk(from handle: FileHandle) async throws -> Data {
        try Task.checkCancellation()

        // Thread-safe box ensures the continuation is resumed exactly once,
        // whether from the readabilityHandler callback or from task cancellation.
        final class ContinuationBox: @unchecked Sendable {
            private let lock = NSLock()
            private var continuation: CheckedContinuation<Data, Error>?
            func store(_ c: CheckedContinuation<Data, Error>) {
                lock.lock()
                continuation = c
                lock.unlock()
            }
            func resume(with result: Result<Data, Error>) {
                lock.lock()
                let c = continuation
                continuation = nil
                lock.unlock()
                c?.resume(with: result)
            }
        }

        let box = ContinuationBox()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                box.store(cont)
                handle.readabilityHandler = { fh in
                    fh.readabilityHandler = nil
                    let data = fh.availableData
                    if data.isEmpty {
                        box.resume(with: .failure(MCPError.serverClosed))
                    } else {
                        box.resume(with: .success(data))
                    }
                }
            }
        } onCancel: {
            handle.readabilityHandler = nil
            box.resume(with: .failure(CancellationError()))
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
