import SceneKit

/// Renders wire connections between component pins as PCB-style traces
enum WireRenderer {

    // MARK: - Net Colors

    private static let netColors: [NSColor] = [
        .systemRed, .systemBlue, .systemGreen, .systemOrange,
        .systemPurple, .systemYellow, .systemTeal, .systemPink,
        .systemIndigo, .systemMint,
    ]

    static func colorForNet(index: Int) -> NSColor {
        netColors[index % netColors.count]
    }

    // MARK: - Special net colors

    private static func colorForNetID(_ id: String, fallback: NSColor) -> NSColor {
        let lower = id.lowercased()
        if lower == "vcc" || lower.hasPrefix("+") { return .systemRed }
        if lower == "vee" || lower.hasPrefix("-") { return .systemBlue }
        if lower == "gnd" || lower == "ground" { return .black }
        return fallback
    }

    // MARK: - Trace dimensions

    private static let traceRadius: CGFloat = 0.003
    /// Routing starts just above the PCB top surface (PCB top = 0.0)
    private static let traceBaseY: CGFloat = 0.003
    /// Each net gets its own routing layer, stacking upward
    private static let traceLayerSpacing: CGFloat = 0.004
    /// PCB bottom surface Y coordinate (PCB center = -0.01, half-height = 0.01)
    private static let pcbBottomY: CGFloat = -0.02
    /// How far through-hole pins extend below the PCB bottom
    private static let pinProtrusion: CGFloat = 0.012

    // MARK: - Wire Generation

    /// Creates all wire traces for a circuit, routed as PCB-like connections
    static func createWires(for circuit: Circuit, in scene: SCNScene) -> SCNNode {
        let wiresRoot = SCNNode()
        wiresRoot.name = "wires"

        // Through-hole pins container (rendered once, shared across nets)
        let throughHoleNode = SCNNode()
        throughHoleNode.name = "throughHoles"
        var processedPins: Set<String> = []  // track "compID_pinID" to avoid duplicates

        for (index, net) in circuit.nets.enumerated() {
            let defaultColor = colorForNet(index: index)
            let color = colorForNetID(net.id, fallback: defaultColor)
            let netNode = SCNNode()
            netNode.name = "net_\(net.id)"

            let pinData = resolvePinPositions(for: net, in: scene)

            guard pinData.count >= 2 else { continue }

            // Assign this net a routing layer on top of the PCB, stacking upward
            let routeY = traceBaseY + CGFloat(index) * traceLayerSpacing

            // Build a minimum spanning chain connecting all pins
            let chain = buildChain(from: pinData.map(\.position))

            for (i, j) in chain {
                let from = pinData[i].position
                let to = pinData[j].position

                let traceNode = createRoutedTrace(
                    from: from,
                    to: to,
                    routeY: routeY,
                    color: color,
                    netID: net.id
                )
                netNode.addChildNode(traceNode)
            }

            // Top-side pads at each pin connection point
            for pin in pinData {
                let pad = makeTopPad(at: pin.position, routeY: routeY, color: color)
                netNode.addChildNode(pad)

                // Through-hole pin: poke through PCB to bottom with solder pad
                let key = "\(pin.componentID)_\(pin.pinID)"
                if !processedPins.contains(key) {
                    processedPins.insert(key)
                    let throughHole = makeThroughHolePin(at: pin.position, color: color)
                    throughHoleNode.addChildNode(throughHole)
                }
            }

            wiresRoot.addChildNode(netNode)
        }

        wiresRoot.addChildNode(throughHoleNode)
        return wiresRoot
    }

    // MARK: - Routed Trace (L-route on PCB top surface)

    /// Creates a routed trace on the top surface: pin stub down to trace layer → L-route → stub up to pin
    private static func createRoutedTrace(
        from start: SCNVector3,
        to end: SCNVector3,
        routeY: CGFloat,
        color: NSColor,
        netID: String
    ) -> SCNNode {
        let node = SCNNode()
        node.name = "wire_\(netID)"

        // Drop from pin position down to the routing layer on the PCB top
        let p1 = SCNVector3(CGFloat(start.x), routeY, CGFloat(start.z))
        let p2 = SCNVector3(CGFloat(end.x), routeY, CGFloat(end.z))

        // Vertical stub from start pin to routing layer
        if abs(CGFloat(start.y) - routeY) > 0.001 {
            node.addChildNode(makeTubeSegment(from: start, to: p1, color: color))
        }

        // Horizontal trace on routing layer — L-shaped for PCB realism
        let dx = abs(CGFloat(end.x) - CGFloat(start.x))
        let dz = abs(CGFloat(end.z) - CGFloat(start.z))

        if dx > 0.01 && dz > 0.01 {
            let corner = SCNVector3(CGFloat(end.x), routeY, CGFloat(start.z))
            node.addChildNode(makeTubeSegment(from: p1, to: corner, color: color))
            node.addChildNode(makeTubeSegment(from: corner, to: p2, color: color))
            node.addChildNode(makeJointSphere(at: corner, color: color))
        } else {
            node.addChildNode(makeTubeSegment(from: p1, to: p2, color: color))
        }

        // Vertical stub from routing layer up to end pin
        if abs(CGFloat(end.y) - routeY) > 0.001 {
            node.addChildNode(makeTubeSegment(from: p2, to: end, color: color))
        }

        return node
    }

    // MARK: - Tube Segment

    private static func makeTubeSegment(from start: SCNVector3, to end: SCNVector3, color: NSColor) -> SCNNode {
        let dx = CGFloat(end.x) - CGFloat(start.x)
        let dy = CGFloat(end.y) - CGFloat(start.y)
        let dz = CGFloat(end.z) - CGFloat(start.z)
        let distance = sqrt(dx * dx + dy * dy + dz * dz)

        guard distance > 0.0005 else { return SCNNode() }

        let tube = SCNCylinder(radius: traceRadius, height: distance)
        tube.radialSegmentCount = 8
        tube.firstMaterial = makeTraceMaterial(color: color)

        let node = SCNNode(geometry: tube)

        // Position at midpoint
        node.position = SCNVector3(
            (CGFloat(start.x) + CGFloat(end.x)) / 2,
            (CGFloat(start.y) + CGFloat(end.y)) / 2,
            (CGFloat(start.z) + CGFloat(end.z)) / 2
        )

        // Align cylinder axis to direction vector
        let up = SIMD3<Double>(0, 1, 0)
        let dir = SIMD3<Double>(Double(dx), Double(dy), Double(dz))
        let dirNorm = simd_normalize(dir)
        let dot = simd_dot(up, dirNorm)
        let cross = simd_cross(up, dirNorm)
        let crossLen = simd_length(cross)

        if crossLen > 0.0001 {
            let angle = acos(min(max(dot, -1), 1))
            let axis = cross / crossLen
            node.rotation = SCNVector4(axis.x, axis.y, axis.z, angle)
        } else if dot < 0 {
            node.rotation = SCNVector4(1, 0, 0, Double.pi)
        }

        return node
    }

    // MARK: - Joint / Solder Point

    private static func makeJointSphere(at position: SCNVector3, color: NSColor) -> SCNNode {
        let sphere = SCNSphere(radius: traceRadius * 1.5)
        sphere.segmentCount = 8
        sphere.firstMaterial = makeTraceMaterial(color: color)
        let node = SCNNode(geometry: sphere)
        node.position = position
        return node
    }

    /// Copper pad on the top surface where a trace meets a pin
    private static func makeTopPad(at pinPos: SCNVector3, routeY: CGFloat, color: NSColor) -> SCNNode {
        let pad = SCNCylinder(radius: traceRadius * 2.5, height: 0.001)
        pad.radialSegmentCount = 12
        let mat = makeTraceMaterial(color: color)
        mat.emission.contents = color.withAlphaComponent(0.15)
        pad.firstMaterial = mat
        let node = SCNNode(geometry: pad)
        node.position = SCNVector3(CGFloat(pinPos.x), routeY, CGFloat(pinPos.z))
        return node
    }

    /// Through-hole pin: extends from pin position down through PCB with a solder pad on the bottom
    private static func makeThroughHolePin(at pinPos: SCNVector3, color: NSColor) -> SCNNode {
        let node = SCNNode()

        let bottomY = pcbBottomY - pinProtrusion

        // Pin wire going through the PCB
        let pinStub = makeTubeSegment(
            from: SCNVector3(CGFloat(pinPos.x), 0.0, CGFloat(pinPos.z)),
            to: SCNVector3(CGFloat(pinPos.x), bottomY, CGFloat(pinPos.z)),
            color: .gray
        )
        node.addChildNode(pinStub)

        // Solder pad on the bottom of the PCB
        let pad = SCNCylinder(radius: traceRadius * 3.0, height: 0.0015)
        pad.radialSegmentCount = 12
        let solderMat = SCNMaterial()
        solderMat.diffuse.contents = NSColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1)
        solderMat.lightingModel = .physicallyBased
        solderMat.roughness.contents = 0.2
        solderMat.metalness.contents = 0.8
        pad.firstMaterial = solderMat
        let padNode = SCNNode(geometry: pad)
        padNode.position = SCNVector3(CGFloat(pinPos.x), pcbBottomY - 0.001, CGFloat(pinPos.z))
        node.addChildNode(padNode)

        return node
    }

    // MARK: - Material

    private static func makeTraceMaterial(color: NSColor) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.lightingModel = .physicallyBased
        mat.roughness.contents = 0.3
        mat.metalness.contents = 0.6
        return mat
    }

    // MARK: - Minimum Spanning Chain

    /// Builds a minimum spanning tree (Prim's) to connect all pin positions efficiently
    private static func buildChain(from positions: [SCNVector3]) -> [(Int, Int)] {
        let n = positions.count
        guard n >= 2 else { return [] }

        var inTree = [Bool](repeating: false, count: n)
        var minDist = [CGFloat](repeating: .infinity, count: n)
        var minEdge = [Int](repeating: 0, count: n)
        var edges: [(Int, Int)] = []

        // Start from node 0
        inTree[0] = true
        for i in 1..<n {
            minDist[i] = distance(positions[0], positions[i])
            minEdge[i] = 0
        }

        for _ in 1..<n {
            // Find closest node not in tree
            var closest = -1
            var closestDist: CGFloat = .infinity
            for i in 0..<n where !inTree[i] {
                if minDist[i] < closestDist {
                    closestDist = minDist[i]
                    closest = i
                }
            }

            guard closest >= 0 else { break }

            inTree[closest] = true
            edges.append((minEdge[closest], closest))

            // Update distances
            for i in 0..<n where !inTree[i] {
                let d = distance(positions[closest], positions[i])
                if d < minDist[i] {
                    minDist[i] = d
                    minEdge[i] = closest
                }
            }
        }

        return edges
    }

    private static func distance(_ a: SCNVector3, _ b: SCNVector3) -> CGFloat {
        let dx = CGFloat(b.x) - CGFloat(a.x)
        let dy = CGFloat(b.y) - CGFloat(a.y)
        let dz = CGFloat(b.z) - CGFloat(a.z)
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    // MARK: - Position Resolution

    struct PinPosition {
        let componentID: String
        let pinID: String
        let position: SCNVector3
    }

    private static func resolvePinPositions(for net: Net, in scene: SCNScene) -> [PinPosition] {
        var results: [PinPosition] = []

        for pinRef in net.connectedPins {
            if let componentNode = scene.rootNode.childNode(withName: pinRef.componentID, recursively: true) {
                // Try to find the specific pin anchor
                if let pinNode = componentNode.childNode(withName: "pin_\(pinRef.pinID)", recursively: true) {
                    let worldPos = pinNode.convertPosition(SCNVector3Zero, to: scene.rootNode)
                    results.append(PinPosition(componentID: pinRef.componentID, pinID: pinRef.pinID, position: worldPos))
                } else {
                    // Fallback: offset slightly from component center based on pin index
                    let pos = componentNode.position
                    let pinIndex = net.connectedPins.firstIndex(where: { $0.componentID == pinRef.componentID && $0.pinID == pinRef.pinID }) ?? 0
                    let offset = CGFloat(pinIndex) * 0.02 - 0.01
                    let fallbackPos = SCNVector3(CGFloat(pos.x) + offset, CGFloat(pos.y), CGFloat(pos.z))
                    results.append(PinPosition(componentID: pinRef.componentID, pinID: pinRef.pinID, position: fallbackPos))
                }
            }
        }

        return results
    }

    // MARK: - Highlighting

    static func highlightNet(named netID: String, in scene: SCNScene, color: NSColor = .systemYellow) {
        guard let netNode = scene.rootNode.childNode(withName: "net_\(netID)", recursively: true) else { return }

        netNode.enumerateChildNodes { child, _ in
            if let geometry = child.geometry {
                let highlight = SCNMaterial()
                highlight.diffuse.contents = color
                highlight.emission.contents = color.withAlphaComponent(0.5)
                highlight.lightingModel = .physicallyBased
                highlight.roughness.contents = 0.2
                highlight.metalness.contents = 0.8
                geometry.firstMaterial = highlight
            }
        }
    }

    /// Dims all individual net nodes (not the parent) so highlighted nets can stay bright
    static func dimAllWires(in scene: SCNScene) {
        guard let wires = scene.rootNode.childNode(withName: "wires", recursively: false) else { return }
        wires.opacity = 1.0 // ensure parent is fully opaque
        for child in wires.childNodes {
            child.opacity = 0.12
        }
    }

    static func restoreAllWires(in scene: SCNScene) {
        guard let wires = scene.rootNode.childNode(withName: "wires", recursively: false) else { return }
        wires.opacity = 1.0
        for child in wires.childNodes {
            child.opacity = 1.0
        }
    }
}
