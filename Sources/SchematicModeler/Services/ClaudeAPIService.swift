import Foundation
import AppKit

/// Service for interacting with the Claude API for schematic analysis and circuit explanation
actor ClaudeAPIService {
    private let apiKey: String
    private let model = "claude-sonnet-4-20250514"
    private let baseURL = "https://api.anthropic.com/v1/messages"

    /// Max image dimension before downscaling (keeps tokens reasonable)
    private static let maxImageDimension: CGFloat = 1200
    /// Max bytes per image after JPEG compression
    private static let maxImageBytes = 500_000

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - Image Preprocessing

    /// Downscales and JPEG-compresses an image to fit within token/size limits
    private func preprocessImage(_ data: Data) -> (data: Data, mimeType: String) {
        guard let nsImage = NSImage(data: data) else {
            return (data, "image/png")
        }

        let size = nsImage.size
        let maxDim = Self.maxImageDimension

        // Check if downscaling needed
        if size.width <= maxDim && size.height <= maxDim && data.count <= Self.maxImageBytes {
            return (data, "image/png")
        }

        // Calculate target size
        let scale = min(maxDim / max(size.width, 1), maxDim / max(size.height, 1), 1.0)
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)

        // Render to JPEG
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(newSize.width),
            pixelsHigh: Int(newSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        nsImage.draw(in: NSRect(origin: .zero, size: newSize))
        NSGraphicsContext.restoreGraphicsState()

        // Try quality 75, then 50 if still too large
        for quality: Double in [0.75, 0.50, 0.30] {
            if let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: quality]) {
                if jpeg.count <= Self.maxImageBytes || quality == 0.30 {
                    return (jpeg, "image/jpeg")
                }
            }
        }

        return (data, "image/png")
    }

    // MARK: - Single Image Analysis

    func analyzeSchematic(imageData: Data, mimeType: String = "image/png", context: String = "") async throws -> Circuit {
        let processed = preprocessImage(imageData)

        var userContent: [[String: Any]] = [
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": processed.mimeType,
                    "data": processed.data.base64EncodedString(),
                ] as [String: String],
            ]
        ]

        var promptText = "Analyze this circuit schematic and extract the complete netlist as JSON."
        if !context.isEmpty {
            promptText += " Additional context: \(context)"
        }
        userContent.append(["type": "text", "text": promptText])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 8192,
            "system": netlistSystemPrompt,
            "messages": [
                ["role": "user", "content": userContent]
            ],
        ]

        let responseText = try await sendRequest(body: body, timeout: 120)
        return try parseCircuitJSON(from: responseText)
    }

    // MARK: - Board Assembly Analysis (chunked)

    /// Analyzes a full board assembly by processing schematics and parts lists in stages:
    /// 1. Extract components + connections from each schematic page
    /// 2. Extract component values from parts lists
    /// 3. Merge into a unified netlist
    func analyzeAssembly(
        images: [(data: Data, mimeType: String, label: String)],
        assemblyName: String,
        manualName: String,
        progressHandler: @Sendable (String) -> Void = { _ in }
    ) async throws -> Circuit {
        // Separate schematics from parts lists
        let schematics = images.filter { $0.label.lowercased().contains("schematic") }
        let partsLists = images.filter { $0.label.lowercased().contains("parts") }

        // Step 1: Analyze schematics (may be multiple pages)
        progressHandler("Analyzing \(schematics.count) schematic page(s)...")
        let schematicJSON = try await analyzeSchematicImages(
            schematics.isEmpty ? images : schematics,
            assemblyName: assemblyName,
            manualName: manualName
        )

        // Step 2: If parts lists exist, extract values and merge
        if !partsLists.isEmpty {
            progressHandler("Cross-referencing \(partsLists.count) parts list(s)...")
            let enriched = try await enrichWithPartsLists(
                circuitJSON: schematicJSON,
                partsLists: partsLists,
                assemblyName: assemblyName
            )
            return try parseCircuitJSON(from: enriched)
        }

        return try parseCircuitJSON(from: schematicJSON)
    }

    /// Step 1: Analyze schematic images to extract topology
    private func analyzeSchematicImages(
        _ images: [(data: Data, mimeType: String, label: String)],
        assemblyName: String,
        manualName: String
    ) async throws -> String {
        var userContent: [[String: Any]] = []

        for image in images {
            let processed = preprocessImage(image.data)
            userContent.append([
                "type": "text",
                "text": "--- \(image.label) ---",
            ])
            userContent.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": processed.mimeType,
                    "data": processed.data.base64EncodedString(),
                ] as [String: String],
            ])
        }

        userContent.append([
            "type": "text",
            "text": """
            Above are the schematic pages for \(assemblyName) from \(manualName). \
            Analyze every page and extract a complete, unified netlist as JSON. \
            Trace all connections across pages. Include every component with its \
            designator, type, estimated value (if visible), and pin connections. \
            Return ONLY valid JSON — no text before or after.
            """,
        ])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 32768,
            "system": netlistSystemPrompt,
            "messages": [
                ["role": "user", "content": userContent]
            ],
        ]

        return try await sendRequest(body: body, timeout: 180)
    }

    /// Step 2: Enrich the circuit with accurate values from parts lists
    private func enrichWithPartsLists(
        circuitJSON: String,
        partsLists: [(data: Data, mimeType: String, label: String)],
        assemblyName: String
    ) async throws -> String {
        var userContent: [[String: Any]] = []

        // Include the parts list images
        for image in partsLists {
            let processed = preprocessImage(image.data)
            userContent.append([
                "type": "text",
                "text": "--- \(image.label) ---",
            ])
            userContent.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": processed.mimeType,
                    "data": processed.data.base64EncodedString(),
                ] as [String: String],
            ])
        }

        // Include the existing circuit JSON
        userContent.append([
            "type": "text",
            "text": """
            Above are the parts lists for \(assemblyName). Below is the circuit netlist \
            extracted from the schematics. Update the component values, part numbers, and \
            descriptions using the parts list data. Fix any incorrect component types. \
            Do NOT remove any components or nets — only update values.

            CRITICAL: Return ONLY the updated JSON — no commentary, no markdown fences, \
            no text before or after. Use short net IDs (n1, n2, VCC, GND). \
            Keep descriptions brief. The output must be valid JSON.

            Current netlist:
            \(circuitJSON)
            """,
        ])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 32768,
            "system": """
            You are an expert circuit analyst. You are given parts list images and an existing \
            circuit netlist JSON. Update the netlist with accurate component values, part numbers, \
            and descriptions from the parts lists. Preserve all existing components and net connections. \
            Return ONLY valid JSON in the same schema — no commentary before or after the JSON. \
            Keep net IDs short (e.g. "VCC", "GND", "n1" not long descriptions). \
            Omit the "label" field on nets unless it differs from the id.
            """,
            "messages": [
                ["role": "user", "content": userContent]
            ],
        ]

        return try await sendRequest(body: body, timeout: 180)
    }

    // MARK: - System Prompt

    private var netlistSystemPrompt: String {
        """
        You are an expert circuit analyst. Analyze the schematic image(s) and extract a complete netlist \
        as structured JSON. Identify all components, their values, designators, and pin connections.

        CRITICAL: Return ONLY valid JSON — no text before or after. Do not wrap in markdown fences.

        Schema:
        {
          "id": "string",
          "name": "string",
          "description": "string",
          "components": [
            {
              "designator": "R1",
              "type": "resistor",
              "value": "10kΩ",
              "partNumber": "optional",
              "description": "brief function",
              "pins": [
                { "id": "1", "label": "1", "netID": "n1" },
                { "id": "2", "label": "2", "netID": "n2" }
              ],
              "position": [x, y, z],
              "functionalBlock": "block_id"
            }
          ],
          "nets": [
            {
              "id": "n1",
              "connectedPins": [
                { "componentID": "R1", "pinID": "1" }
              ]
            }
          ],
          "functionalBlocks": [
            {
              "id": "block_id",
              "name": "Input Stage",
              "description": "Functional description",
              "componentIDs": ["R1", "C1"],
              "color": "blue"
            }
          ]
        }

        Component types: resistor, capacitor, capacitor_electrolytic, inductor, diode, diode_zener, \
        transistor_npn, transistor_pnp, transistor_fet, op_amp, ic_dip, ic_soic, transformer, \
        potentiometer, connector, relay, fuse, crystal, led, speaker, unknown

        Block colors: blue, green, orange, purple, red, yellow, cyan, pink

        Keep output compact to avoid truncation:
        - Use short net IDs: "VCC", "GND", "n1", "n2" — not verbose descriptions.
        - Use named nets for power rails (VCC, GND, V+, V-) and signal names from the schematic.
        - Use "n1", "n2", etc. for unnamed internal nets.
        - Omit the "label" field on nets unless it differs meaningfully from the id.
        - Keep component descriptions brief (under 10 words).

        Assign positions as [x, y, z] floats spaced ~0.15 apart, centered around origin. \
        Keep the total layout compact — fit within roughly x ∈ [-0.7, 0.7] and y ∈ [-0.5, 0.5]. \
        Group related components spatially by functional block. \
        Place input on the left (negative x), output on the right (positive x).
        """
    }

    // MARK: - Circuit Explanation

    func explainCircuit(_ circuit: Circuit, question: String? = nil) async throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let circuitJSON = try encoder.encode(circuit)
        let circuitString = String(data: circuitJSON, encoding: .utf8) ?? ""

        var prompt = """
        Here is a circuit netlist in JSON format:

        \(circuitString)

        """

        if let question {
            prompt += "Question: \(question)"
        } else {
            prompt += """
            Please explain:
            1. The overall function of this circuit
            2. Each functional block and its role
            3. Signal flow from input to output
            4. Key components and why their values matter
            5. Common failure modes and troubleshooting tips
            """
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": "You are an expert electronics engineer specializing in audio equipment repair. Explain circuits clearly for troubleshooting. Reference specific component designators and values.",
            "messages": [
                ["role": "user", "content": prompt]
            ],
        ]

        return try await sendRequest(body: body, timeout: 120)
    }

    // MARK: - Troubleshooting

    func troubleshoot(circuit: Circuit, symptom: String) async throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let circuitJSON = try encoder.encode(circuit)
        let circuitString = String(data: circuitJSON, encoding: .utf8) ?? ""

        let prompt = """
        Circuit netlist:
        \(circuitString)

        Symptom: \(symptom)

        Based on this circuit and the reported symptom, provide:
        1. Most likely faulty components (ranked by probability)
        2. Voltage/signal measurements to take at specific test points
        3. Step-by-step troubleshooting procedure
        4. Common causes for this symptom in this type of circuit
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": "You are an expert audio equipment repair technician. Provide practical troubleshooting guidance referencing specific component designators.",
            "messages": [
                ["role": "user", "content": prompt]
            ],
        ]

        return try await sendRequest(body: body, timeout: 120)
    }

    // MARK: - Failure Heat Map

    func assessFailureProbabilities(circuit: Circuit) async throws -> [String: Float] {
        let encoder = JSONEncoder()
        let circuitJSON = try encoder.encode(circuit)
        let circuitString = String(data: circuitJSON, encoding: .utf8) ?? ""

        let prompt = """
        Here is a circuit netlist in JSON format:

        \(circuitString)

        For each component, estimate a failure probability from 0.0 (very unlikely to fail) to 1.0 \
        (very likely to fail) based on: component type, typical stress levels, age susceptibility, \
        and common failure modes in vintage audio equipment.

        Consider: electrolytic capacitors fail most often (aging, drying), followed by power \
        transistors (thermal stress), resistors (rarely), and film capacitors (very rarely).

        Return ONLY a JSON object mapping designator to probability, e.g.:
        {"C101": 0.85, "Q105": 0.45, "R101": 0.05}
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": "You are an expert electronics reliability engineer. Return ONLY valid JSON — no text before or after.",
            "messages": [
                ["role": "user", "content": prompt]
            ],
        ]

        let responseText = try await sendRequest(body: body, timeout: 120)
        let jsonString = extractJSON(from: responseText)
        let data = Data(jsonString.utf8)
        return try JSONDecoder().decode([String: Float].self, from: data)
    }

    // MARK: - Guided Troubleshooting

    func guidedTroubleshoot(
        circuit: Circuit,
        symptom: String,
        previousMeasurements: [(testPoint: String, expected: String, measured: String)] = []
    ) async throws -> TroubleshootStep {
        let encoder = JSONEncoder()
        let circuitJSON = try encoder.encode(circuit)
        let circuitString = String(data: circuitJSON, encoding: .utf8) ?? ""

        var prompt = """
        Circuit netlist:
        \(circuitString)

        Symptom: \(symptom)
        """

        if !previousMeasurements.isEmpty {
            prompt += "\n\nPrevious measurements:"
            for m in previousMeasurements {
                prompt += "\n- \(m.testPoint): expected \(m.expected), measured \(m.measured)"
            }
        }

        prompt += """

        Based on the circuit and symptom\(previousMeasurements.isEmpty ? "" : " plus measurements taken so far"), \
        provide the NEXT single diagnostic step.

        Return ONLY valid JSON matching this schema:
        {
          "description": "What to do and why",
          "testPoint": "component designator or net ID to test",
          "measurementType": "DC voltage" or "resistance" or "AC signal" or "continuity",
          "expectedValue": "what the reading should be",
          "suspectedComponents": ["designator1", "designator2"]
        }
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "system": """
            You are an expert audio equipment repair technician performing guided troubleshooting. \
            Based on the circuit, symptom, and any measurements already taken, provide the SINGLE \
            most informative next diagnostic step. Return ONLY valid JSON.
            """,
            "messages": [
                ["role": "user", "content": prompt]
            ],
        ]

        let responseText = try await sendRequest(body: body, timeout: 120)
        let jsonString = extractJSON(from: responseText)
        let data = Data(jsonString.utf8)
        return try JSONDecoder().decode(TroubleshootStep.self, from: data)
    }

    // MARK: - Voltage Analysis

    func analyzeExpectedVoltages(circuit: Circuit) async throws -> [String: String] {
        let encoder = JSONEncoder()
        let circuitJSON = try encoder.encode(circuit)
        let circuitString = String(data: circuitJSON, encoding: .utf8) ?? ""

        let prompt = """
        Here is a circuit netlist in JSON format:

        \(circuitString)

        Estimate the expected DC operating voltages at key nets/nodes in this circuit. \
        Include power rails, transistor collector/base/emitter voltages, and other \
        significant test points.

        Return ONLY a JSON object mapping net ID to expected voltage string, e.g.:
        {"VCC": "+35V", "Q101_collector": "+18.2V", "GND": "0V"}

        Include 10-20 of the most important test points.
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": "You are an expert circuit analyst. Estimate DC operating points. Return ONLY valid JSON — no text before or after.",
            "messages": [
                ["role": "user", "content": prompt]
            ],
        ]

        let responseText = try await sendRequest(body: body, timeout: 120)
        let jsonString = extractJSON(from: responseText)
        let data = Data(jsonString.utf8)
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    // MARK: - HTTP

    private func sendRequest(body: [String: Any], timeout: TimeInterval = 120) async throws -> String {
        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = timeout
        request.httpBody = jsonData

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout + 30
        let session = URLSession(configuration: config)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClaudeAPIError.httpError(statusCode: httpResponse.statusCode, body: errorBody)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String
        else {
            throw ClaudeAPIError.unexpectedFormat
        }

        let stopReason = json?["stop_reason"] as? String
        if stopReason == "max_tokens" {
            print("[ClaudeAPIService] Warning: response truncated (hit max_tokens limit)")
        }

        // Track token usage
        if let usage = json?["usage"] as? [String: Any] {
            let inputTokens = usage["input_tokens"] as? Int ?? 0
            let outputTokens = usage["output_tokens"] as? Int ?? 0
            await APIUsageTracker.shared.record(inputTokens: inputTokens, outputTokens: outputTokens)
        }

        return text
    }

    // MARK: - JSON Parsing

    private func parseCircuitJSON(from text: String) throws -> Circuit {
        let jsonString = extractJSON(from: text)
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = Data(trimmed.utf8)

        do {
            return try JSONDecoder().decode(Circuit.self, from: data)
        } catch let firstError {
            // Attempt to repair truncated JSON before giving up
            let repaired = repairTruncatedJSON(trimmed)
            if repaired != trimmed {
                let repairedData = Data(repaired.utf8)
                do {
                    let circuit = try JSONDecoder().decode(Circuit.self, from: repairedData)
                    print("[ClaudeAPIService] Repaired truncated JSON — decoded \(circuit.components.count) components")
                    return circuit
                } catch {
                    // Repair didn't help; dump debug info with original error
                    dumpDebugResponse(rawText: text, extractedJSON: trimmed, error: firstError)
                    throw firstError
                }
            }

            dumpDebugResponse(rawText: text, extractedJSON: trimmed, error: firstError)
            throw firstError
        }
    }

    /// Attempts to repair truncated JSON by closing all open structures.
    /// Finds the last position where a complete JSON element ended,
    /// strips trailing incomplete content, and closes open brackets/braces.
    private func repairTruncatedJSON(_ json: String) -> String {
        var inString = false
        var escaped = false
        var depth = 0
        var lastCompleteElement = json.startIndex

        for i in json.indices {
            let char = json[i]
            if escaped { escaped = false; continue }
            if char == "\\" && inString { escaped = true; continue }
            if char == "\"" { inString = !inString; continue }
            if inString { continue }

            switch char {
            case "{", "[": depth += 1
            case "}", "]":
                depth -= 1
                lastCompleteElement = json.index(after: i)
            default: break
            }
        }

        // If nothing is unclosed, no repair needed
        guard depth > 0 || inString else { return json }

        // Truncate to the last complete element
        var repaired = String(json[..<lastCompleteElement])

        // Strip trailing commas
        while let last = repaired.last, last == "," || last == " " || last == "\n" || last == "\r" || last == "\t" {
            repaired.removeLast()
        }

        // Re-scan to find what's still open
        var stack: [Character] = []
        inString = false
        escaped = false
        for char in repaired {
            if escaped { escaped = false; continue }
            if char == "\\" && inString { escaped = true; continue }
            if char == "\"" { inString = !inString; continue }
            if inString { continue }
            switch char {
            case "{": stack.append("}")
            case "[": stack.append("]")
            case "}": if stack.last == "}" { stack.removeLast() }
            case "]": if stack.last == "]" { stack.removeLast() }
            default: break
            }
        }

        // Close remaining open structures
        for closer in stack.reversed() {
            repaired.append(closer)
        }

        return repaired
    }

    /// Extracts JSON from Claude's response, handling markdown fences, prose wrappers, etc.
    private func extractJSON(from text: String) -> String {
        // 1. Try markdown fence extraction
        if let start = text.range(of: "```json") ?? text.range(of: "```") {
            var inner = String(text[start.upperBound...])
            if let end = inner.range(of: "```") {
                inner = String(inner[..<end.lowerBound])
            }
            let trimmed = inner.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("{") { return trimmed }
        }

        // 2. Try to find the outermost JSON object by matching braces
        if let firstBrace = text.firstIndex(of: "{"),
           let lastBrace = text.lastIndex(of: "}") {
            let candidate = String(text[firstBrace...lastBrace])
            // Quick sanity check: does it look like our circuit schema?
            if candidate.contains("\"components\"") || candidate.contains("\"designator\"") || candidate.contains("\"name\"") {
                return candidate
            }
        }

        // 3. Fallback: return as-is and let the decoder report the real error
        return text
    }

    /// Writes debug files when parsing fails so we can inspect the raw API response
    private func dumpDebugResponse(rawText: String, extractedJSON: String, error: Error) {
        let debugDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Claude-Manuals/_debug")
        try? FileManager.default.createDirectory(at: debugDir, withIntermediateDirectories: true)

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let rawFile = debugDir.appendingPathComponent("raw_\(timestamp).txt")
        let jsonFile = debugDir.appendingPathComponent("extracted_\(timestamp).json")
        let errorFile = debugDir.appendingPathComponent("error_\(timestamp).txt")

        try? rawText.write(to: rawFile, atomically: true, encoding: .utf8)
        try? extractedJSON.write(to: jsonFile, atomically: true, encoding: .utf8)
        try? "\(error)".write(to: errorFile, atomically: true, encoding: .utf8)

        print("[ClaudeAPIService] Parse failed — debug files written to \(debugDir.path)")
    }
}

// MARK: - Errors

enum ClaudeAPIError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case unexpectedFormat
    case noAPIKey

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid response from Claude API"
        case .httpError(let code, let body): "HTTP \(code): \(body.prefix(300))"
        case .unexpectedFormat: "Unexpected response format"
        case .noAPIKey: "No API key configured. Set your Anthropic API key in Settings."
        }
    }
}
