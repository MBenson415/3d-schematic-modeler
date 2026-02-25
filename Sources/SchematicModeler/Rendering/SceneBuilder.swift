import SceneKit

/// Builds and manages the 3D SceneKit scene from a Circuit model
@MainActor
final class SceneBuilder {

    let scene: SCNScene

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
    /// Fraction of board area usable for component placement (leaves margin)
    private static let usableFraction: Float = 0.80

    func buildCircuit(_ circuit: Circuit) {
        // Remove existing components and wires
        scene.rootNode.childNodes
            .filter { $0.name != "ambientLight" && $0.name != "keyLight" && $0.name != "fillLight" && $0.name != "pcb" }
            .forEach { $0.removeFromParentNode() }

        // Remap positions so components lie flat on the x-z board plane,
        // then scale to fit within the PCB bounds.
        let remapped = Self.remapAndFitToBoard(circuit)

        // Resize the PCB to fit the layout if needed
        resizePCB(for: remapped)

        // Components container
        let componentsNode = SCNNode()
        componentsNode.name = "components"

        for component in remapped.components {
            let node = ComponentGeometry.createNode(for: component)
            componentsNode.addChildNode(node)
        }

        scene.rootNode.addChildNode(componentsNode)

        // Wires
        let wiresNode = WireRenderer.createWires(for: remapped, in: scene)
        scene.rootNode.addChildNode(wiresNode)
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
