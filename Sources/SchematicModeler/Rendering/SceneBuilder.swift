import SceneKit

/// Builds and manages the 3D SceneKit scene from a Circuit model
@MainActor
final class SceneBuilder {

    let scene: SCNScene
    private(set) var currentLayoutMode: LayoutMode = .pictorial
    /// Circuit with both pictorial (.position) and schematic (.schematicPosition) coordinates
    private var processedCircuit: Circuit?

    init() {
        scene = SCNScene()
        setupEnvironment()
    }

    // MARK: - Environment

    private func setupEnvironment() {
        // Background
        scene.background.contents = NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1)

        // Ambient light
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = NSColor(white: 0.3, alpha: 1)
        ambient.name = "ambientLight"
        scene.rootNode.addChildNode(ambient)

        // Key light
        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light?.type = .directional
        keyLight.light?.color = NSColor(white: 0.8, alpha: 1)
        keyLight.light?.castsShadow = true
        keyLight.light?.shadowMode = .deferred
        keyLight.light?.shadowSampleCount = 8
        keyLight.position = SCNVector3(2, 5, 3)
        keyLight.look(at: SCNVector3Zero)
        keyLight.name = "keyLight"
        scene.rootNode.addChildNode(keyLight)

        // Fill light
        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .directional
        fill.light?.color = NSColor(white: 0.3, alpha: 1)
        fill.position = SCNVector3(-3, 2, -1)
        fill.look(at: SCNVector3Zero)
        fill.name = "fillLight"
        scene.rootNode.addChildNode(fill)

        // PCB ground plane
        let pcb = SCNBox(width: 2.0, height: 0.02, length: 1.5, chamferRadius: 0.005)
        let pcbMaterial = SCNMaterial()
        pcbMaterial.diffuse.contents = NSColor(red: 0.05, green: 0.35, blue: 0.15, alpha: 1) // PCB green
        pcbMaterial.lightingModel = .physicallyBased
        pcbMaterial.roughness.contents = 0.8
        pcbMaterial.metalness.contents = 0.0
        pcb.firstMaterial = pcbMaterial

        let pcbNode = SCNNode(geometry: pcb)
        pcbNode.name = "pcb"
        pcbNode.position = SCNVector3(0, -0.01, 0)
        scene.rootNode.addChildNode(pcbNode)
    }

    // MARK: - Build

    /// Clears everything except the environment (lights + PCB)
    func buildEmptyBoard() {
        scene.rootNode.childNodes
            .filter { $0.name != "ambientLight" && $0.name != "keyLight" && $0.name != "fillLight" && $0.name != "pcb" }
            .forEach { $0.removeFromParentNode() }
    }

    // MARK: - Board dimensions

    /// Default PCB size; may be enlarged for big circuits
    private static let defaultBoardWidth: Float = 2.0
    private static let defaultBoardLength: Float = 1.5
    private static let boardSurfaceY: Float = 0.05
    /// Elevation for schematic view (components float above board plane)
    private static let schematicElevation: Float = 0.15
    /// Fraction of board area usable for component placement (leaves margin)
    private static let usableFraction: Float = 0.80

    func buildCircuit(_ circuit: Circuit) {
        // Remove existing components and wires
        scene.rootNode.childNodes
            .filter { $0.name != "ambientLight" && $0.name != "keyLight" && $0.name != "fillLight" && $0.name != "pcb" }
            .forEach { $0.removeFromParentNode() }

        // Auto-layout if positions are missing (MCP-generated circuits have all-zero positions)
        let layoutCircuit = Self.needsAutoLayout(circuit)
            ? Self.autoLayoutCircuit(circuit)
            : circuit

        // Compute both position sets:
        // 1. Pictorial (board) positions in .position
        // 2. Schematic positions in .schematicPosition
        var pictorial = Self.remapAndFitToBoard(layoutCircuit)
        let schematic = Self.remapAndFitSchematic(layoutCircuit)

        for i in pictorial.components.indices {
            pictorial.components[i].schematicPosition = schematic.components[i].position
        }

        processedCircuit = pictorial
        currentLayoutMode = .pictorial

        // Resize the PCB to fit the layout if needed
        resizePCB(for: pictorial)

        // Components container
        let componentsNode = SCNNode()
        componentsNode.name = "components"

        for component in pictorial.components {
            let node = ComponentGeometry.createNode(for: component)
            componentsNode.addChildNode(node)
        }

        scene.rootNode.addChildNode(componentsNode)

        // Functional block tinting — subtly color components by block
        applyFunctionalBlockTinting(for: pictorial)

        // Wires
        let wiresNode = WireRenderer.createWires(for: pictorial, in: scene)
        scene.rootNode.addChildNode(wiresNode)

        // Net labels
        WireRenderer.addNetLabels(for: pictorial, in: scene)
    }

    /// Resizes the PCB board to fit the component layout with margins
    private func resizePCB(for circuit: Circuit) {
        guard !circuit.components.isEmpty,
              let pcbNode = scene.rootNode.childNode(withName: "pcb", recursively: false)
        else { return }

        let positions = circuit.components.map(\.position)
        let xs = positions.map(\.x)
        let zs = positions.map(\.z)
        let layoutW = (xs.max()! - xs.min()!) + 0.4 // margin on each side
        let layoutD = (zs.max()! - zs.min()!) + 0.3

        let boardW = max(Self.defaultBoardWidth, layoutW)
        let boardD = max(Self.defaultBoardLength, layoutD)

        let pcb = SCNBox(width: CGFloat(boardW), height: 0.02, length: CGFloat(boardD), chamferRadius: 0.005)
        pcb.firstMaterial = pcbNode.geometry?.firstMaterial
        pcbNode.geometry = pcb
    }

    // MARK: - Position Remapping + Scale-to-Fit

    /// Remaps 2D x-y positions to the x-z board plane, then scales the layout
    /// to fit within the PCB bounds with margins.
    private static func remapAndFitToBoard(_ circuit: Circuit) -> Circuit {
        guard !circuit.components.isEmpty else { return circuit }

        var remapped = circuit

        // Step 1: Detect and remap 2D x-y layout → x-z board plane
        let positions = remapped.components.map(\.position)
        let zRange = (positions.map(\.z).max()!) - (positions.map(\.z).min()!)
        let yRange = (positions.map(\.y).max()!) - (positions.map(\.y).min()!)
        let needsAxisRemap = zRange < 0.01 && yRange > 0.01

        if needsAxisRemap {
            for i in remapped.components.indices {
                let pos = remapped.components[i].position
                remapped.components[i].position = SIMD3(pos.x, boardSurfaceY, pos.y)
            }
        } else {
            // Ensure y is at board surface height
            for i in remapped.components.indices {
                remapped.components[i].position.y = boardSurfaceY
            }
        }

        // Step 2: Scale-to-fit within the usable board area
        let xs = remapped.components.map(\.position.x)
        let zs = remapped.components.map(\.position.z)
        let minX = xs.min()!, maxX = xs.max()!
        let minZ = zs.min()!, maxZ = zs.max()!
        let layoutW = maxX - minX
        let layoutD = maxZ - minZ
        let midX = (minX + maxX) / 2
        let midZ = (minZ + maxZ) / 2

        // Usable area on the default board
        let usableW = defaultBoardWidth * usableFraction
        let usableD = defaultBoardLength * usableFraction

        // Compute uniform scale factor
        var scale: Float = 1.0
        if layoutW > 0.001 || layoutD > 0.001 {
            let scaleX = layoutW > 0.001 ? usableW / layoutW : 10.0
            let scaleZ = layoutD > 0.001 ? usableD / layoutD : 10.0
            scale = min(scaleX, scaleZ)
            // Clamp: don't blow up tiny circuits too much, don't shrink below readable
            scale = min(scale, 2.0)
            scale = max(scale, 0.25)
        }

        // Step 3: Center and scale all positions
        for i in remapped.components.indices {
            let pos = remapped.components[i].position
            remapped.components[i].position = SIMD3(
                (pos.x - midX) * scale,
                pos.y,
                (pos.z - midZ) * scale
            )
        }

        return remapped
    }

    /// Remaps positions for schematic view: components float above board, spread for clarity
    private static func remapAndFitSchematic(_ circuit: Circuit) -> Circuit {
        guard !circuit.components.isEmpty else { return circuit }

        var remapped = circuit

        // Step 1: Detect and remap 2D x-y layout → x-z plane at schematic elevation
        let positions = remapped.components.map(\.position)
        let zRange = (positions.map(\.z).max()!) - (positions.map(\.z).min()!)
        let yRange = (positions.map(\.y).max()!) - (positions.map(\.y).min()!)
        let needsAxisRemap = zRange < 0.01 && yRange > 0.01

        if needsAxisRemap {
            for i in remapped.components.indices {
                let pos = remapped.components[i].position
                remapped.components[i].position = SIMD3(pos.x, schematicElevation, pos.y)
            }
        } else {
            for i in remapped.components.indices {
                remapped.components[i].position.y = schematicElevation
            }
        }

        // Step 2: Scale-to-fit (slightly wider spread than board layout)
        let xs = remapped.components.map(\.position.x)
        let zs = remapped.components.map(\.position.z)
        let minX = xs.min()!, maxX = xs.max()!
        let minZ = zs.min()!, maxZ = zs.max()!
        let layoutW = maxX - minX
        let layoutD = maxZ - minZ
        let midX = (minX + maxX) / 2
        let midZ = (minZ + maxZ) / 2

        let usableW = defaultBoardWidth * usableFraction
        let usableD = defaultBoardLength * usableFraction

        var scale: Float = 1.0
        if layoutW > 0.001 || layoutD > 0.001 {
            let scaleX = layoutW > 0.001 ? usableW / layoutW : 10.0
            let scaleZ = layoutD > 0.001 ? usableD / layoutD : 10.0
            scale = min(scaleX, scaleZ)
            scale = min(scale, 2.0)
            scale = max(scale, 0.25)
        }

        // Step 3: Center and scale
        for i in remapped.components.indices {
            let pos = remapped.components[i].position
            remapped.components[i].position = SIMD3(
                (pos.x - midX) * scale,
                pos.y,
                (pos.z - midZ) * scale
            )
        }

        return remapped
    }

    // MARK: - Layout Mode Switching

    func switchLayoutMode(to mode: LayoutMode) {
        guard mode != currentLayoutMode, let processedCircuit else { return }
        currentLayoutMode = mode

        guard let componentsNode = scene.rootNode.childNode(withName: "components", recursively: false) else { return }

        // Remove wires immediately (they'll be rebuilt after animation)
        scene.rootNode.childNode(withName: "wires", recursively: false)?.removeFromParentNode()

        // Animate component positions and PCB fade
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.6
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        for component in processedCircuit.components {
            guard let node = componentsNode.childNode(withName: component.designator, recursively: false) else { continue }

            let targetPos: SIMD3<Float>
            switch mode {
            case .schematic:
                targetPos = component.schematicPosition ?? component.position
            case .pictorial:
                targetPos = component.position
            }

            node.position = SCNVector3(targetPos.x, targetPos.y, targetPos.z)
        }

        // Fade PCB
        if let pcbNode = scene.rootNode.childNode(withName: "pcb", recursively: false) {
            pcbNode.opacity = mode == .schematic ? 0.08 : 1.0
        }

        SCNTransaction.completionBlock = { [weak self] in
            self?.rebuildWires(mode: mode)
        }
        SCNTransaction.commit()
    }

    /// Rebuilds wires for the given layout mode using current scene node positions
    private func rebuildWires(mode: LayoutMode) {
        guard let processedCircuit else { return }

        // Build a circuit snapshot using the target positions for wire routing
        var wireCircuit = processedCircuit
        for i in wireCircuit.components.indices {
            switch mode {
            case .schematic:
                wireCircuit.components[i].position = wireCircuit.components[i].schematicPosition ?? wireCircuit.components[i].position
            case .pictorial:
                break // .position is already the pictorial position
            }
        }

        let wiresNode: SCNNode
        switch mode {
        case .schematic:
            wiresNode = WireRenderer.createSchematicWires(for: wireCircuit, in: scene)
        case .pictorial:
            wiresNode = WireRenderer.createWires(for: wireCircuit, in: scene)
        }

        // Net labels
        WireRenderer.addNetLabels(for: wireCircuit, in: scene)

        // Fade wires in
        wiresNode.opacity = 0
        scene.rootNode.addChildNode(wiresNode)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.3
        wiresNode.opacity = 1.0
        SCNTransaction.commit()
    }

    // MARK: - Selection

    func highlightComponent(named designator: String) {
        highlightComponents(named: [designator])
    }

    func highlightComponents(named designators: Set<String>) {
        guard let components = scene.rootNode.childNode(withName: "components", recursively: false) else { return }

        // Reset all
        components.enumerateChildNodes { node, _ in
            node.opacity = 1.0
        }

        WireRenderer.dimAllWires(in: scene)

        // Dim non-selected, glow selected
        components.enumerateChildNodes { node, _ in
            guard node.parent?.name == "components" else { return }
            if let name = node.name, designators.contains(name) {
                node.opacity = 1.0
                node.enumerateChildNodes { child, _ in
                    if let material = child.geometry?.firstMaterial {
                        material.emission.contents = NSColor.systemYellow.withAlphaComponent(0.2)
                    }
                }
            } else {
                node.opacity = 0.3
            }
        }
    }

    func clearSelection() {
        if let components = scene.rootNode.childNode(withName: "components", recursively: false) {
            components.enumerateChildNodes { node, _ in
                node.opacity = 1.0
                if let material = node.geometry?.firstMaterial {
                    material.emission.contents = NSColor.black
                }
                node.enumerateChildNodes { child, _ in
                    if let material = child.geometry?.firstMaterial {
                        material.emission.contents = NSColor.black
                    }
                }
            }
        }
        WireRenderer.restoreAllWires(in: scene)
    }

    func highlightNets(for componentID: String, in circuit: Circuit) {
        highlightNets(for: [componentID], in: circuit)
    }

    func highlightNets(for componentIDs: Set<String>, in circuit: Circuit) {
        // Collect all nets connected to any of the given components
        var connectedNets: [Net] = []
        for id in componentIDs {
            for net in circuit.netsConnectedTo(id) {
                if !connectedNets.contains(where: { $0.id == net.id }) {
                    connectedNets.append(net)
                }
            }
        }

        // Dim all nets, then restore + highlight connected ones
        WireRenderer.dimAllWires(in: scene)

        for net in connectedNets {
            let netIndex = circuit.nets.firstIndex(where: { $0.id == net.id }) ?? 0
            let color = WireRenderer.colorForNet(index: netIndex)

            if let netNode = scene.rootNode.childNode(withName: "net_\(net.id)", recursively: true) {
                netNode.opacity = 1.0
            }
            WireRenderer.highlightNet(named: net.id, in: scene, color: color)
        }
    }

    // MARK: - Functional Block Tinting

    /// Applies subtle emission tint to components based on their functional block color
    private func applyFunctionalBlockTinting(for circuit: Circuit) {
        guard let componentsNode = scene.rootNode.childNode(withName: "components", recursively: false) else { return }

        // Build designator → block color map
        var designatorToColor: [String: NSColor] = [:]
        for block in circuit.functionalBlocks {
            let color = Self.blockTintColor(block.color)
            for compID in block.componentIDs {
                designatorToColor[compID] = color
            }
        }

        componentsNode.enumerateChildNodes { node, _ in
            guard node.parent?.name == "components",
                  let name = node.name,
                  let tint = designatorToColor[name]
            else { return }

            node.enumerateChildNodes { child, _ in
                if let material = child.geometry?.firstMaterial {
                    material.emission.contents = tint.withAlphaComponent(0.15)
                }
            }
        }
    }

    private static func blockTintColor(_ color: FunctionalBlock.BlockColor) -> NSColor {
        switch color {
        case .blue: return .systemBlue
        case .green: return .systemGreen
        case .orange: return .systemOrange
        case .purple: return .systemPurple
        case .red: return .systemRed
        case .yellow: return .systemYellow
        case .cyan: return .systemCyan
        case .pink: return .systemPink
        }
    }

    // MARK: - Auto-Layout (for circuits without position data)

    /// Returns true if all component positions are clustered at the same point (e.g. all zero)
    private static func needsAutoLayout(_ circuit: Circuit) -> Bool {
        guard circuit.components.count > 1 else { return false }
        let positions = circuit.components.map(\.position)
        let xs = positions.map(\.x)
        let zs = positions.map(\.z)
        let ys = positions.map(\.y)
        let xRange = (xs.max()! - xs.min()!)
        let yRange = (ys.max()! - ys.min()!)
        let zRange = (zs.max()! - zs.min()!)
        return xRange < 0.01 && yRange < 0.01 && zRange < 0.01
    }

    /// Builds an adjacency list from nets, skipping power/ground nets that connect everything
    private static func buildAdjacency(from circuit: Circuit) -> [String: Set<String>] {
        let powerNets: Set<String> = ["GND", "VCC", "VEE", "V+", "V-", "VDD", "VSS", "VGND", "GND_out", "VCC_out", "VEE_out"]
        var adj: [String: Set<String>] = [:]
        for comp in circuit.components {
            adj[comp.designator] = []
        }
        for net in circuit.nets {
            // Skip power/ground nets
            let netUpper = net.id.uppercased()
            if powerNets.contains(net.id) || netUpper == "GND" || netUpper.hasPrefix("VCC") || netUpper.hasPrefix("VEE") || netUpper.hasPrefix("VDD") || netUpper.hasPrefix("VSS") {
                continue
            }
            let components = net.connectedPins.map(\.componentID)
            for i in components.indices {
                for j in (i + 1)..<components.count {
                    adj[components[i], default: []].insert(components[j])
                    adj[components[j], default: []].insert(components[i])
                }
            }
        }
        return adj
    }

    /// Finds source components (signal inputs) to use as BFS roots
    private static func findSources(in circuit: Circuit) -> [String] {
        let inputPatterns = ["ac_in", "input", "in", "audio_in", "sig_in", "line_in"]
        var sources: [String] = []

        for net in circuit.nets {
            let netLower = net.id.lowercased()
            if inputPatterns.contains(where: { netLower.contains($0) }) {
                for pin in net.connectedPins {
                    if !sources.contains(pin.componentID) {
                        sources.append(pin.componentID)
                    }
                }
            }
        }

        // Fallback: components with fewest signal connections (typically input stage)
        if sources.isEmpty {
            let adj = buildAdjacency(from: circuit)
            let sorted = circuit.components
                .sorted { (adj[$0.designator]?.count ?? 0) < (adj[$1.designator]?.count ?? 0) }
            if let first = sorted.first {
                sources.append(first.designator)
            }
        }

        return sources
    }

    /// BFS from sources to assign depth (column index) to each component
    private static func bfsDepths(
        sources: [String],
        adjacency: [String: Set<String>],
        allDesignators: [String]
    ) -> [String: Int] {
        var depths: [String: Int] = [:]
        var queue: [String] = []

        // Seed sources at depth 0
        for src in sources {
            if depths[src] == nil {
                depths[src] = 0
                queue.append(src)
            }
        }

        // BFS
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            let currentDepth = depths[current]!

            for neighbor in adjacency[current] ?? [] {
                if depths[neighbor] == nil {
                    depths[neighbor] = currentDepth + 1
                    queue.append(neighbor)
                }
            }
        }

        // Assign unvisited components (power-only or disconnected) to max depth + 1
        let maxDepth = (depths.values.max() ?? 0) + 1
        for d in allDesignators {
            if depths[d] == nil {
                depths[d] = maxDepth
            }
        }

        return depths
    }

    /// Assigns x-y positions based on BFS depth (signal flow left-to-right)
    private static func autoLayoutCircuit(_ circuit: Circuit) -> Circuit {
        var result = circuit
        let adjacency = buildAdjacency(from: circuit)
        let sources = findSources(in: circuit)
        let allDesignators = circuit.components.map(\.designator)
        let depths = bfsDepths(sources: sources, adjacency: adjacency, allDesignators: allDesignators)

        // Group designators by depth
        var columns: [Int: [String]] = [:]
        for (designator, depth) in depths {
            columns[depth, default: []].append(designator)
        }

        // Sort within each column for consistent ordering
        for key in columns.keys {
            columns[key]?.sort()
        }

        let xSpacing: Float = 0.3
        let zSpacing: Float = 0.25

        // Assign positions: x from depth, y (used as z after remap) spread per column
        for i in result.components.indices {
            let designator = result.components[i].designator
            let depth = depths[designator] ?? 0
            let column = columns[depth] ?? [designator]
            let indexInColumn = column.firstIndex(of: designator) ?? 0
            let columnCount = column.count

            let x = Float(depth) * xSpacing
            // Center the column vertically
            let y = (Float(indexInColumn) - Float(columnCount - 1) / 2.0) * zSpacing

            // Position in x-y plane (z=0); remapAndFitToBoard will remap y→z
            result.components[i].position = SIMD3(x, y, 0)
        }

        return result
    }

    // MARK: - Heat Map

    func applyHeatMap(probabilities: [String: Float], for circuit: Circuit) {
        guard let components = scene.rootNode.childNode(withName: "components", recursively: false) else { return }

        components.enumerateChildNodes { node, _ in
            guard node.parent?.name == "components", let name = node.name else { return }
            let prob = probabilities[name] ?? 0
            let tintColor = Self.heatMapColor(for: prob)

            node.enumerateChildNodes { child, _ in
                if let material = child.geometry?.firstMaterial {
                    material.emission.contents = tintColor.withAlphaComponent(CGFloat(prob * 0.4))
                }
            }
        }
    }

    func clearHeatMap(for circuit: Circuit) {
        guard let components = scene.rootNode.childNode(withName: "components", recursively: false) else { return }

        components.enumerateChildNodes { node, _ in
            node.enumerateChildNodes { child, _ in
                if let material = child.geometry?.firstMaterial {
                    material.emission.contents = NSColor.black
                }
            }
        }
    }

    private static func heatMapColor(for probability: Float) -> NSColor {
        // Green (0.0) → Yellow (0.5) → Red (1.0)
        let p = max(0, min(1, probability))
        let r: CGFloat = p < 0.5 ? CGFloat(p * 2) : 1.0
        let g: CGFloat = p < 0.5 ? 1.0 : CGFloat(1.0 - (p - 0.5) * 2)
        return NSColor(red: r, green: g, blue: 0, alpha: 1)
    }

    // MARK: - Functional Block Camera

    private var defaultCameraPosition = SCNVector3(0, 0.8, 1.2)

    func focusOnBlock(_ block: FunctionalBlock, in circuit: Circuit) {
        let blockComponents = circuit.components.filter { block.componentIDs.contains($0.designator) }
        guard !blockComponents.isEmpty else { return }

        // Compute bounding box center
        let positions = blockComponents.map(\.position)
        let minX = positions.map(\.x).min()!
        let maxX = positions.map(\.x).max()!
        let minZ = positions.map(\.z).min()!
        let maxZ = positions.map(\.z).max()!
        let centerX = (minX + maxX) / 2
        let centerZ = (minZ + maxZ) / 2
        let spanX = maxX - minX + 0.3
        let spanZ = maxZ - minZ + 0.3
        let span = max(spanX, spanZ, 0.3)

        // Camera at 45° looking at the center, distance proportional to span
        let cameraY = Float(0.3 + span * 0.6)
        let cameraZ = centerZ + Float(span * 0.7)
        let targetPos = SCNVector3(centerX, cameraY, cameraZ)
        let lookAt = SCNVector3(centerX, Self.boardSurfaceY, centerZ)

        guard let cameraNode = scene.rootNode.childNodes.first(where: { $0.camera != nil }) else { return }

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.5
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cameraNode.position = targetPos
        cameraNode.look(at: lookAt)
        SCNTransaction.commit()
    }

    func resetCamera() {
        guard let cameraNode = scene.rootNode.childNodes.first(where: { $0.camera != nil }) else { return }

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.5
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cameraNode.position = defaultCameraPosition
        cameraNode.look(at: SCNVector3Zero)
        SCNTransaction.commit()
    }

    // MARK: - Voltage Overlay

    func showVoltageOverlay(voltages: [String: String], circuit: Circuit) {
        hideVoltageOverlay()

        let voltagesNode = SCNNode()
        voltagesNode.name = "voltages"

        for (netID, voltage) in voltages {
            guard let net = circuit.nets.first(where: { $0.id == netID }),
                  let firstPin = net.connectedPins.first,
                  let component = circuit.component(for: firstPin.componentID)
            else { continue }

            let label = ComponentGeometry.makeLabel(
                text: "\(netID): \(voltage)",
                size: 0.03,
                color: .cyan
            )
            label.position = SCNVector3(
                component.position.x,
                component.position.y + 0.12,
                component.position.z
            )
            voltagesNode.addChildNode(label)
        }

        scene.rootNode.addChildNode(voltagesNode)
    }

    func hideVoltageOverlay() {
        scene.rootNode.childNode(withName: "voltages", recursively: false)?
            .removeFromParentNode()
    }
}
