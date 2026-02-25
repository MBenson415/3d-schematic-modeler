import Foundation

/// Reads ~/Claude-Manuals/ directory and parses _index.md files
actor ManualLibraryService {

    static let manualsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Claude-Manuals")

    // MARK: - List Manuals

    func listManuals() throws -> [ServiceManual] {
        let fm = FileManager.default
        let baseDir = Self.manualsDirectory

        guard fm.fileExists(atPath: baseDir.path) else { return [] }

        let contents = try fm.contentsOfDirectory(
            at: baseDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var manuals: [ServiceManual] = []
        for dir in contents {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }

            let indexFile = dir.appendingPathComponent("_index.md")
            guard fm.fileExists(atPath: indexFile.path) else { continue }

            if let manual = try? parseIndex(at: dir) {
                manuals.append(manual)
            }
        }

        return manuals.sorted { $0.name < $1.name }
    }

    // MARK: - Parse _index.md

    func parseIndex(at directoryURL: URL) throws -> ServiceManual {
        let indexURL = directoryURL.appendingPathComponent("_index.md")
        let content = try String(contentsOf: indexURL, encoding: .utf8)
        let lines = content.components(separatedBy: "\n")
        let dirName = directoryURL.lastPathComponent

        var name = dirName
        var totalPages = 0
        var sections: [ManualSection] = []
        var assemblies: [String: BoardAssemblyBuilder] = [:]

        enum ParseState {
            case header, metadata, toc, crossRef(String)
        }
        var state: ParseState = .header

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Title
            if trimmed.hasPrefix("# ") && !trimmed.hasPrefix("## ") {
                name = String(trimmed.dropFirst(2))
                continue
            }

            // Section headers
            if trimmed == "## Metadata" { state = .metadata; continue }
            if trimmed == "## Table of Contents" { state = .toc; continue }
            if trimmed == "## Assembly Cross-Reference" { state = .crossRef(""); continue }

            // Cross-reference assembly header: ### `AWH-046`
            if trimmed.hasPrefix("### `") {
                let code = extractBacktickContent(trimmed)
                if let code {
                    state = .crossRef(code)
                    if assemblies[code] == nil {
                        assemblies[code] = BoardAssemblyBuilder(id: code)
                    }
                }
                continue
            }

            switch state {
            case .metadata:
                // Total pages
                if trimmed.contains("**Total pages:**") {
                    if let match = trimmed.range(of: #"\d+"#, options: .regularExpression) {
                        totalPages = Int(trimmed[match]) ?? 0
                    }
                }
                // Board assembly list entries
                if trimmed.hasPrefix("- `") {
                    if let code = extractBacktickContent(trimmed) {
                        let dashIndex = trimmed.range(of: "— ")
                        let assemblyName = dashIndex.map { String(trimmed[$0.upperBound...]) } ?? code
                        if assemblies[code] == nil {
                            assemblies[code] = BoardAssemblyBuilder(id: code, name: assemblyName)
                        } else {
                            assemblies[code]?.name = assemblyName
                        }
                    }
                }

            case .toc:
                // TOC entry: - [Title](filename.md) (pages N-M) `AWH-046`
                if let section = parseTOCEntry(trimmed) {
                    sections.append(section)
                }

            case .crossRef(let currentAssemblyID):
                guard !currentAssemblyID.isEmpty else { continue }

                // Section line: - [Title](filename.md) (schematic|parts-list)
                if trimmed.hasPrefix("- [") {
                    let isPartsList = trimmed.contains("(parts-list)")
                    if isPartsList {
                        assemblies[currentAssemblyID]?.currentCategory = .partsList
                    } else {
                        assemblies[currentAssemblyID]?.currentCategory = .schematic
                    }
                }

                // Image line:   - Image: `filename.png`
                if trimmed.hasPrefix("- Image: `") {
                    if let filename = extractBacktickContent(trimmed) {
                        let fileURL = directoryURL.appendingPathComponent(filename)
                        let category = assemblies[currentAssemblyID]?.currentCategory ?? .schematic
                        let image = SchematicImage(
                            id: filename,
                            filename: filename,
                            fileURL: fileURL,
                            category: category,
                            boardID: currentAssemblyID
                        )
                        if category == .partsList {
                            assemblies[currentAssemblyID]?.partsListImages.append(image)
                        } else {
                            assemblies[currentAssemblyID]?.schematicImages.append(image)
                        }
                    }
                }

            case .header:
                break
            }
        }

        // Build final assembly refs
        let assemblyRefs = assemblies.values
            .sorted { $0.id < $1.id }
            .map { builder in
                BoardAssemblyRef(
                    id: builder.id,
                    name: builder.name,
                    schematicImages: builder.schematicImages,
                    partsListImages: builder.partsListImages
                )
            }

        return ServiceManual(
            id: dirName,
            name: name,
            directoryURL: directoryURL,
            totalPages: totalPages,
            boardAssemblies: assemblyRefs,
            sections: sections
        )
    }

    // MARK: - Image Loading

    func loadImage(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    // MARK: - Parsing Helpers

    private func extractBacktickContent(_ text: String) -> String? {
        guard let start = text.firstIndex(of: "`") else { return nil }
        let afterStart = text.index(after: start)
        guard let end = text[afterStart...].firstIndex(of: "`") else { return nil }
        return String(text[afterStart..<end])
    }

    private func parseTOCEntry(_ line: String) -> ManualSection? {
        // Format: - [Title](filename.md) (pages N-M) `CODE`
        guard line.hasPrefix("- [") else { return nil }

        // Extract title
        guard let titleEnd = line.firstIndex(of: "]") else { return nil }
        let titleStart = line.index(line.startIndex, offsetBy: 3) // skip "- ["
        let title = String(line[titleStart..<titleEnd])

        // Extract filename
        guard let parenStart = line[titleEnd...].firstIndex(of: "("),
              let parenEnd = line[parenStart...].firstIndex(of: ")")
        else { return nil }
        let filename = String(line[line.index(after: parenStart)..<parenEnd])

        // Extract page range
        var pageRange = ""
        let afterFileParen = line.index(after: parenEnd)
        if let pagesStart = line[afterFileParen...].range(of: "(pages") ?? line[afterFileParen...].range(of: "(page") {
            if let pagesEnd = line[pagesStart.upperBound...].firstIndex(of: ")") {
                pageRange = line[pagesStart.upperBound..<pagesEnd].trimmingCharacters(in: .whitespaces)
            }
        }

        // Extract assembly code (optional backtick at end)
        var assemblyCode: String? = nil
        if let lastBacktick = line.lastIndex(of: "`") {
            let beforeLast = line[..<lastBacktick]
            if let secondToLast = beforeLast.lastIndex(of: "`") {
                assemblyCode = String(line[line.index(after: secondToLast)..<lastBacktick])
            }
        }

        return ManualSection(
            id: filename,
            title: title,
            pageRange: pageRange,
            assemblyCode: assemblyCode
        )
    }
}

// MARK: - Builder Helper

private struct BoardAssemblyBuilder {
    let id: String
    var name: String
    var schematicImages: [SchematicImage] = []
    var partsListImages: [SchematicImage] = []
    var currentCategory: SchematicImageCategory = .schematic

    init(id: String, name: String = "") {
        self.id = id
        self.name = name.isEmpty ? id : name
    }
}
