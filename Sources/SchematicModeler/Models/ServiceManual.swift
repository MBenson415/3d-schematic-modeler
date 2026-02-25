import Foundation

/// Represents an extracted service manual on disk at ~/Claude-Manuals/
struct ServiceManual: Identifiable, Hashable, Sendable {
    let id: String                    // directory name, e.g. "sx-750-service-manual"
    let name: String                  // display name from _index.md
    let directoryURL: URL
    let totalPages: Int
    let boardAssemblies: [BoardAssemblyRef]
    let sections: [ManualSection]

    static func == (lhs: ServiceManual, rhs: ServiceManual) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Board assembly cross-reference entry from _index.md
struct BoardAssemblyRef: Identifiable, Hashable, Sendable {
    let id: String                    // e.g. "AWH-046"
    let name: String                  // e.g. "Power Amplifier Assembly"
    let schematicImages: [SchematicImage]
    let partsListImages: [SchematicImage]

    var allImages: [SchematicImage] { schematicImages + partsListImages }

    static func == (lhs: BoardAssemblyRef, rhs: BoardAssemblyRef) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A section from the table of contents
struct ManualSection: Identifiable, Sendable {
    let id: String                    // filename
    let title: String
    let pageRange: String
    let assemblyCode: String?
}

/// A schematic image file that can be previewed and analyzed
struct SchematicImage: Identifiable, Hashable, Sendable {
    let id: String                    // filename
    let filename: String
    let fileURL: URL
    let category: SchematicImageCategory
    let boardID: String

    static func == (lhs: SchematicImage, rhs: SchematicImage) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum SchematicImageCategory: String, Sendable {
    case schematic
    case partsList = "parts-list"

    var displayName: String {
        switch self {
        case .schematic: "Schematic"
        case .partsList: "Parts List"
        }
    }

    var systemImage: String {
        switch self {
        case .schematic: "doc.richtext"
        case .partsList: "list.bullet.rectangle"
        }
    }
}
