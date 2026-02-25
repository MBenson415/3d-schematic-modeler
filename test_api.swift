#!/usr/bin/env swift

import Foundation

// MARK: - Inline model types (mirrors Circuit.swift for standalone testing)

enum ComponentType: String, Codable {
    case resistor, capacitor, inductor, diode, led, fuse, crystal, speaker
    case capacitorElectrolytic = "capacitor_electrolytic"
    case diodeZener = "diode_zener"
    case transistorNPN = "transistor_npn"
    case transistorPNP = "transistor_pnp"
    case transistorFET = "transistor_fet"
    case opAmp = "op_amp"
    case icDIP = "ic_dip"
    case icSOIC = "ic_soic"
    case transformer, potentiometer, connector, relay, unknown
}

struct Pin: Codable {
    let id: String
    var label: String
    var netID: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.label = (try? c.decode(String.self, forKey: .label)) ?? ""
        self.netID = try? c.decode(String.self, forKey: .netID)
    }
    private enum CodingKeys: String, CodingKey { case id, label, netID }
}

struct Component: Codable {
    let id: String
    var designator: String
    var type: ComponentType
    var value: String
    var partNumber: String?
    var description: String?
    var pins: [Pin]
    var position: [Float]?
    var functionalBlock: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let designator = try c.decode(String.self, forKey: .designator)
        self.id = (try? c.decode(String.self, forKey: .id)) ?? designator
        self.designator = designator
        if let rawType = try? c.decode(String.self, forKey: .type) {
            self.type = ComponentType(rawValue: rawType) ?? .unknown
        } else {
            self.type = .unknown
        }
        self.value = (try? c.decode(String.self, forKey: .value)) ?? ""
        self.partNumber = try? c.decode(String.self, forKey: .partNumber)
        self.description = try? c.decode(String.self, forKey: .description)
        self.pins = (try? c.decode([Pin].self, forKey: .pins)) ?? []
        self.position = try? c.decode([Float].self, forKey: .position)
        self.functionalBlock = try? c.decode(String.self, forKey: .functionalBlock)
    }
    private enum CodingKeys: String, CodingKey {
        case id, designator, type, value, partNumber, description, pins, position, functionalBlock
    }
}

struct Net: Codable {
    let id: String
    var label: String?
    var connectedPins: [PinRef]

    struct PinRef: Codable {
        let componentID: String
        let pinID: String
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.label = try? c.decode(String.self, forKey: .label)
        self.connectedPins = (try? c.decode([PinRef].self, forKey: .connectedPins)) ?? []
    }
    private enum CodingKeys: String, CodingKey { case id, label, connectedPins }
}

struct FunctionalBlock: Codable {
    let id: String
    var name: String
    var description: String?
    var componentIDs: [String]
    var color: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = (try? c.decode(String.self, forKey: .name)) ?? ""
        self.description = try? c.decode(String.self, forKey: .description)
        self.componentIDs = (try? c.decode([String].self, forKey: .componentIDs)) ?? []
        self.color = try? c.decode(String.self, forKey: .color)
    }
    private enum CodingKeys: String, CodingKey { case id, name, description, componentIDs, color }
}

struct Circuit: Codable {
    let id: String
    var name: String
    var description: String?
    var components: [Component]
    var nets: [Net]
    var functionalBlocks: [FunctionalBlock]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        self.name = (try? c.decode(String.self, forKey: .name)) ?? "Untitled"
        self.description = try? c.decode(String.self, forKey: .description)
        self.components = (try? c.decode([Component].self, forKey: .components)) ?? []
        self.nets = (try? c.decode([Net].self, forKey: .nets)) ?? []
        self.functionalBlocks = (try? c.decode([FunctionalBlock].self, forKey: .functionalBlocks)) ?? []
    }
    private enum CodingKeys: String, CodingKey {
        case id, name, description, components, nets, functionalBlocks
    }
}

// MARK: - Test

// Read API key from UserDefaults or environment
let apiKey: String = {
    // Try the app's UserDefaults domain
    if let defaults = UserDefaults(suiteName: "SchematicModeler"),
       let key = defaults.string(forKey: "anthropic_api_key"), !key.isEmpty {
        return key
    }
    // Try standard defaults
    if let key = UserDefaults.standard.string(forKey: "anthropic_api_key"), !key.isEmpty {
        return key
    }
    // Fallback to environment variable
    if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty {
        return key
    }
    return ""
}()

guard !apiKey.isEmpty else {
    print("ERROR: No API key found.")
    print("Set it via: defaults write com.apple.dt.Xcode anthropic_api_key 'sk-ant-...'")
    print("Or export ANTHROPIC_API_KEY='sk-ant-...'")
    exit(1)
}

print("API key found: \(apiKey.prefix(12))...")

// Minimal prompt — ask Claude to return a tiny circuit JSON
let systemPrompt = """
You are an expert circuit analyst. Return ONLY valid JSON matching this schema:
{
  "id": "string",
  "name": "string",
  "description": "string",
  "components": [
    {
      "designator": "R1",
      "type": "resistor",
      "value": "10kΩ",
      "pins": [
        { "id": "1", "label": "1", "netID": "net_name" }
      ],
      "position": [0.0, 0.0, 0.0],
      "functionalBlock": "block_id"
    }
  ],
  "nets": [
    {
      "id": "net_name",
      "label": "optional display name",
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

Return ONLY the JSON, no markdown fences, no explanation.
"""

let userPrompt = """
Create a simple test circuit with 3 components: a resistor R1 (10k), capacitor C1 (100nF), \
and transistor Q1 (2SC1815 NPN). Connect R1 pin 1 to VCC net, R1 pin 2 to Q1 base, \
C1 pin 1 to input net, C1 pin 2 to Q1 base. Q1 collector to output net, Q1 emitter to GND. \
One functional block "Input Stage" containing all three.
"""

let body: [String: Any] = [
    "model": "claude-sonnet-4-20250514",
    "max_tokens": 4096,
    "system": systemPrompt,
    "messages": [
        ["role": "user", "content": userPrompt]
    ],
]

let jsonData = try! JSONSerialization.data(withJSONObject: body)

var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
request.httpMethod = "POST"
request.setValue("application/json", forHTTPHeaderField: "content-type")
request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
request.timeoutInterval = 60
request.httpBody = jsonData

print("\n--- Sending request to Claude API ---\n")

let semaphore = DispatchSemaphore(value: 0)

let task = URLSession.shared.dataTask(with: request) { data, response, error in
    defer { semaphore.signal() }

    if let error = error {
        print("NETWORK ERROR: \(error.localizedDescription)")
        return
    }

    guard let httpResponse = response as? HTTPURLResponse else {
        print("ERROR: Not an HTTP response")
        return
    }

    print("HTTP Status: \(httpResponse.statusCode)")

    guard let data = data else {
        print("ERROR: No data in response")
        return
    }

    // Print raw response
    let rawResponse = String(data: data, encoding: .utf8) ?? "<binary>"
    print("\n--- RAW API RESPONSE (\(data.count) bytes) ---")
    print(rawResponse.prefix(2000))
    if rawResponse.count > 2000 {
        print("\n... [truncated, \(rawResponse.count) total chars] ...")
    }

    // Parse the API envelope
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        print("\nERROR: Could not parse API response as JSON")
        return
    }

    // Extract text content
    guard let content = json["content"] as? [[String: Any]],
          let firstBlock = content.first,
          let text = firstBlock["text"] as? String
    else {
        print("\nERROR: Could not extract text from content blocks")
        print("Keys in response: \(json.keys.sorted())")
        if let content = json["content"] {
            print("Content value: \(content)")
        }
        if let error = json["error"] {
            print("Error value: \(error)")
        }
        return
    }

    print("\n--- EXTRACTED TEXT (\(text.count) chars) ---")
    print(text.prefix(3000))

    // Try to parse as circuit JSON (same logic as the app)
    print("\n--- PARSING ATTEMPT ---")

    var jsonString = text

    // Check if wrapped in markdown fences
    if let fenceStart = text.range(of: "```json") ?? text.range(of: "```") {
        print("Found markdown fence at offset \(text.distance(from: text.startIndex, to: fenceStart.lowerBound))")
        jsonString = String(text[fenceStart.upperBound...])
        if let fenceEnd = jsonString.range(of: "```") {
            jsonString = String(jsonString[..<fenceEnd.lowerBound])
            print("Stripped markdown fences, extracted \(jsonString.count) chars")
        }
    } else {
        print("No markdown fences found — using raw text")
    }

    let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
    print("First 100 chars of JSON to decode: \(trimmed.prefix(100))")
    print("Last 100 chars of JSON to decode: \(trimmed.suffix(100))")

    let circuitData = Data(trimmed.utf8)

    do {
        let decoder = JSONDecoder()
        let circuit = try decoder.decode(Circuit.self, from: circuitData)
        print("\nSUCCESS! Decoded circuit:")
        print("  Name: \(circuit.name)")
        print("  Components: \(circuit.components.count)")
        for comp in circuit.components {
            print("    \(comp.designator) (\(comp.type.rawValue)) = \(comp.value), pins: \(comp.pins.count)")
        }
        print("  Nets: \(circuit.nets.count)")
        for net in circuit.nets {
            print("    \(net.id): \(net.connectedPins.count) pins")
        }
        print("  Functional blocks: \(circuit.functionalBlocks.count)")
    } catch let decodingError as DecodingError {
        print("\nDECODING ERROR: \(decodingError)")
        switch decodingError {
        case .dataCorrupted(let ctx):
            print("  Data corrupted: \(ctx.debugDescription)")
            print("  Coding path: \(ctx.codingPath.map(\.stringValue))")
        case .keyNotFound(let key, let ctx):
            print("  Key not found: \(key.stringValue)")
            print("  Coding path: \(ctx.codingPath.map(\.stringValue))")
        case .typeMismatch(let type, let ctx):
            print("  Type mismatch: expected \(type)")
            print("  Coding path: \(ctx.codingPath.map(\.stringValue))")
            print("  Debug: \(ctx.debugDescription)")
        case .valueNotFound(let type, let ctx):
            print("  Value not found: \(type)")
            print("  Coding path: \(ctx.codingPath.map(\.stringValue))")
        @unknown default:
            print("  Unknown decoding error")
        }
    } catch {
        print("\nGENERAL ERROR: \(error)")
        print("  Localized: \(error.localizedDescription)")
    }
}

task.resume()
semaphore.wait()
