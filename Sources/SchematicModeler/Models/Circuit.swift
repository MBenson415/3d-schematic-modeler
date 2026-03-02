import Foundation

// MARK: - Component Types

enum ComponentType: String, Codable, CaseIterable, Sendable {
    case resistor
    case capacitor
    case capacitorElectrolytic = "capacitor_electrolytic"
    case inductor
    case diode
    case diodeZener = "diode_zener"
    case transistorNPN = "transistor_npn"
    case transistorPNP = "transistor_pnp"
    case transistorFET = "transistor_fet"
    case opAmp = "op_amp"
    case icDIP = "ic_dip"
    case icSOIC = "ic_soic"
    case transformer
    case potentiometer
    case connector
    case relay
    case fuse
    case crystal
    case led
    case speaker
    case unknown

    var displayName: String {
        switch self {
        case .resistor: "Resistor"
        case .capacitor: "Capacitor"
        case .capacitorElectrolytic: "Electrolytic Capacitor"
        case .inductor: "Inductor"
        case .diode: "Diode"
        case .diodeZener: "Zener Diode"
        case .transistorNPN: "NPN Transistor"
        case .transistorPNP: "PNP Transistor"
        case .transistorFET: "FET"
        case .opAmp: "Op-Amp"
        case .icDIP: "IC (DIP)"
        case .icSOIC: "IC (SOIC)"
        case .transformer: "Transformer"
        case .potentiometer: "Potentiometer"
        case .connector: "Connector"
        case .relay: "Relay"
        case .fuse: "Fuse"
        case .crystal: "Crystal"
        case .led: "LED"
        case .speaker: "Speaker"
        case .unknown: "Unknown"
        }
    }

    var pinCount: Int {
        switch self {
        case .resistor, .capacitor, .capacitorElectrolytic, .inductor, .fuse, .crystal, .led, .speaker: 2
        case .diode, .diodeZener: 2
        case .transistorNPN, .transistorPNP, .transistorFET, .potentiometer: 3
        case .opAmp: 5 // inv, noninv, out, vcc, vee
        case .transformer: 4 // pri1, pri2, sec1, sec2
        case .icDIP, .icSOIC: 8 // default, overridden per component
        case .connector: 2 // default
        case .relay: 4 // coil+, coil-, NO, COM
        case .unknown: 2
        }
    }

    /// Prefix used in designator (R for resistor, C for capacitor, etc.)
    static func fromDesignator(_ designator: String) -> ComponentType {
        let prefix = String(designator.prefix(while: { $0.isLetter })).uppercased()
        switch prefix {
        case "R": return .resistor
        case "C": return .capacitor
        case "L": return .inductor
        case "D": return .diode
        case "Q": return .transistorNPN
        case "U", "IC": return .icDIP
        case "T": return .transformer
        case "VR", "RV": return .potentiometer
        case "J", "P", "CN": return .connector
        case "K", "RY": return .relay
        case "F": return .fuse
        case "Y", "X": return .crystal
        case "LED": return .led
        case "SP": return .speaker
        default: return .unknown
        }
    }
}

// MARK: - Pin

struct Pin: Codable, Identifiable, Sendable {
    let id: String
    var label: String
    var netID: String?

    init(id: String, label: String, netID: String? = nil) {
        self.id = id
        self.label = label
        self.netID = netID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.label = (try? container.decode(String.self, forKey: .label)) ?? ""
        self.netID = try? container.decode(String.self, forKey: .netID)
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, netID
    }
}

// MARK: - Component

struct Component: Codable, Identifiable, Sendable {
    let id: String
    var designator: String
    var type: ComponentType
    var value: String
    var partNumber: String?
    var description: String?
    var manufacturer: String?
    var package: String?
    var tolerance: String?
    var pins: [Pin]
    var position: SIMD3<Float>
    var functionalBlock: String?
    var annotations: [String]?
    var failureProbability: Float?

    init(
        designator: String,
        type: ComponentType,
        value: String,
        partNumber: String? = nil,
        description: String? = nil,
        manufacturer: String? = nil,
        package: String? = nil,
        tolerance: String? = nil,
        pins: [Pin] = [],
        position: SIMD3<Float> = .zero,
        functionalBlock: String? = nil,
        annotations: [String]? = nil,
        failureProbability: Float? = nil
    ) {
        self.id = designator
        self.designator = designator
        self.type = type
        self.value = value
        self.partNumber = partNumber
        self.description = description
        self.manufacturer = manufacturer
        self.package = package
        self.tolerance = tolerance
        self.pins = pins
        self.position = position
        self.functionalBlock = functionalBlock
        self.annotations = annotations
        self.failureProbability = failureProbability
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let designator = try container.decode(String.self, forKey: .designator)
        self.id = (try? container.decode(String.self, forKey: .id)) ?? designator
        self.designator = designator
        if let rawType = try? container.decode(String.self, forKey: .type) {
            self.type = ComponentType(rawValue: rawType) ?? .unknown
        } else {
            self.type = .unknown
        }
        self.value = (try? container.decode(String.self, forKey: .value)) ?? ""
        self.partNumber = try? container.decode(String.self, forKey: .partNumber)
        self.description = try? container.decode(String.self, forKey: .description)
        self.manufacturer = try? container.decode(String.self, forKey: .manufacturer)
        self.package = try? container.decode(String.self, forKey: .package)
        self.tolerance = try? container.decode(String.self, forKey: .tolerance)
        self.pins = (try? container.decode([Pin].self, forKey: .pins)) ?? []
        self.functionalBlock = try? container.decode(String.self, forKey: .functionalBlock)
        self.annotations = try? container.decode([String].self, forKey: .annotations)
        self.failureProbability = try? container.decode(Float.self, forKey: .failureProbability)

        // Position can come as SIMD3 array [x,y,z] or might be missing
        if let pos = try? container.decode(SIMD3<Float>.self, forKey: .position) {
            self.position = pos
        } else if let arr = try? container.decode([Float].self, forKey: .position), arr.count >= 3 {
            self.position = SIMD3<Float>(arr[0], arr[1], arr[2])
        } else {
            self.position = .zero
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, designator, type, value, partNumber, description, manufacturer, package, tolerance
        case pins, position, functionalBlock, annotations, failureProbability
    }
}

// MARK: - Net

struct Net: Codable, Identifiable, Sendable {
    let id: String
    var label: String?
    var connectedPins: [PinReference]

    struct PinReference: Codable, Sendable {
        let componentID: String
        let pinID: String
    }

    init(id: String, label: String? = nil, connectedPins: [PinReference] = []) {
        self.id = id
        self.label = label
        self.connectedPins = connectedPins
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.label = try? container.decode(String.self, forKey: .label)
        self.connectedPins = (try? container.decode([PinReference].self, forKey: .connectedPins)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, connectedPins
    }
}

// MARK: - Circuit

struct Circuit: Codable, Identifiable, Sendable {
    let id: String
    var name: String
    var description: String?
    var components: [Component]
    var nets: [Net]
    var functionalBlocks: [FunctionalBlock]

    init(
        id: String = UUID().uuidString,
        name: String,
        description: String? = nil,
        components: [Component] = [],
        nets: [Net] = [],
        functionalBlocks: [FunctionalBlock] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.components = components
        self.nets = nets
        self.functionalBlocks = functionalBlocks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        self.name = (try? container.decode(String.self, forKey: .name)) ?? "Untitled Circuit"
        self.description = try? container.decode(String.self, forKey: .description)
        self.components = (try? container.decode([Component].self, forKey: .components)) ?? []
        self.nets = (try? container.decode([Net].self, forKey: .nets)) ?? []
        self.functionalBlocks = (try? container.decode([FunctionalBlock].self, forKey: .functionalBlocks)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, components, nets, functionalBlocks
    }

    func component(for designator: String) -> Component? {
        components.first { $0.designator == designator }
    }

    func netsConnectedTo(_ componentID: String) -> [Net] {
        nets.filter { net in
            net.connectedPins.contains { $0.componentID == componentID }
        }
    }
}

// MARK: - Functional Block

struct FunctionalBlock: Codable, Identifiable, Sendable {
    let id: String
    var name: String
    var description: String?
    var componentIDs: [String]
    var color: BlockColor

    enum BlockColor: String, Codable, Sendable {
        case blue, green, orange, purple, red, yellow, cyan, pink
    }

    init(id: String, name: String, description: String? = nil, componentIDs: [String] = [], color: BlockColor = .blue) {
        self.id = id
        self.name = name
        self.description = description
        self.componentIDs = componentIDs
        self.color = color
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = (try? container.decode(String.self, forKey: .name)) ?? ""
        self.description = try? container.decode(String.self, forKey: .description)
        self.componentIDs = (try? container.decode([String].self, forKey: .componentIDs)) ?? []
        if let rawColor = try? container.decode(String.self, forKey: .color) {
            self.color = BlockColor(rawValue: rawColor.lowercased()) ?? .blue
        } else {
            self.color = .blue
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, componentIDs, color
    }
}

// MARK: - Troubleshoot Step

struct TroubleshootStep: Codable, Sendable {
    var description: String
    var testPoint: String
    var measurementType: String
    var expectedValue: String
    var suspectedComponents: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.description = (try? container.decode(String.self, forKey: .description)) ?? ""
        self.testPoint = (try? container.decode(String.self, forKey: .testPoint)) ?? ""
        self.measurementType = (try? container.decode(String.self, forKey: .measurementType)) ?? "DC voltage"
        self.expectedValue = (try? container.decode(String.self, forKey: .expectedValue)) ?? ""
        self.suspectedComponents = (try? container.decode([String].self, forKey: .suspectedComponents)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case description, testPoint, measurementType, expectedValue, suspectedComponents
    }
}

// MARK: - Board Assembly

struct BoardAssembly: Codable, Identifiable, Sendable {
    let id: String
    var name: String
    var assemblyCode: String
    var circuit: Circuit?
    var schematicImagePaths: [String]
    var partsListImagePaths: [String]
}
