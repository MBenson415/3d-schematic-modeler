import Foundation

/// A JSON-RPC 2.0 client that communicates with an MCP server over stdio
/// using Content-Length framing (LSP-style).
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

    /// Spawns the MCP server process and performs the initialize handshake.
    func start() async throws {
        guard process == nil else { return }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: command)
        proc.arguments = arguments
        proc.currentDirectoryURL = URL(fileURLWithPath: serverDirectory)

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
        self.readBuffer = Data()

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

    // MARK: - JSON-RPC Transport

    private func ensureStarted() async throws {
        if !isInitialized {
            try await start()
        }
    }

    private func sendRequest(method: String, params: [String: Any]) async throws -> JSONRPCResponse {
        let id = nextID
        nextID += 1

        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        ]

        try sendMessage(message)
        return try await readResponse(expectedID: id)
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

        let jsonData = try JSONSerialization.data(withJSONObject: message)
        let header = "Content-Length: \(jsonData.count)\r\n\r\n"
        guard let headerData = header.data(using: .utf8) else {
            throw MCPError.encodingError
        }

        let handle = stdin.fileHandleForWriting
        handle.write(headerData)
        handle.write(jsonData)
    }

    /// Reads the next JSON-RPC response, skipping any notifications.
    private func readResponse(expectedID: Int) async throws -> JSONRPCResponse {
        guard let stdout = stdoutPipe else {
            throw MCPError.notConnected
        }

        let handle = stdout.fileHandleForReading

        while true {
            // Read Content-Length header
            let contentLength = try await readContentLength(from: handle)

            // Read exactly contentLength bytes of JSON body
            let body = try await readExactly(contentLength, from: handle)

            guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                continue // Skip malformed messages
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

    /// Parses the `Content-Length: N\r\n\r\n` header from the byte stream.
    private func readContentLength(from handle: FileHandle) async throws -> Int {
        // Accumulate bytes until we find \r\n\r\n
        while true {
            if let range = readBuffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = readBuffer.subdata(in: readBuffer.startIndex..<range.lowerBound)
                readBuffer.removeSubrange(readBuffer.startIndex..<range.upperBound)

                guard let headerString = String(data: headerData, encoding: .utf8),
                      let lengthLine = headerString.split(separator: "\r\n").first(where: { $0.hasPrefix("Content-Length:") }),
                      let length = Int(lengthLine.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "")
                else {
                    throw MCPError.protocolError("Invalid Content-Length header")
                }
                return length
            }

            let chunk = try readChunk(from: handle)
            guard !chunk.isEmpty else {
                throw MCPError.serverClosed
            }
            readBuffer.append(chunk)
        }
    }

    /// Reads exactly `count` bytes from the buffer + handle.
    private func readExactly(_ count: Int, from handle: FileHandle) async throws -> Data {
        while readBuffer.count < count {
            let chunk = try readChunk(from: handle)
            guard !chunk.isEmpty else {
                throw MCPError.serverClosed
            }
            readBuffer.append(chunk)
        }

        let result = readBuffer.prefix(count)
        readBuffer.removeFirst(count)
        return Data(result)
    }

    private func readChunk(from handle: FileHandle) throws -> Data {
        let data = handle.availableData
        if data.isEmpty {
            throw MCPError.serverClosed
        }
        return data
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

struct JSONRPCResponse {
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
