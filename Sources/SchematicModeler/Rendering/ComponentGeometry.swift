import SceneKit

/// Generates parametric 3D geometry for circuit components
enum ComponentGeometry {

    static let componentScale: Float = 0.1

    // MARK: - Public Factory

    static func createNode(for component: Component) -> SCNNode {
        let node: SCNNode
        switch component.type {
        case .resistor:
            node = makeResistor(value: component.value)
        case .capacitor:
            node = makeCapacitor()
        case .capacitorElectrolytic:
            node = makeElectrolyticCapacitor()
        case .diode, .diodeZener, .led:
            node = makeDiode(type: component.type)
        case .transistorNPN, .transistorPNP, .transistorFET:
            node = makeTransistor()
        case .opAmp:
            node = makeIC(pinCount: 8, label: component.value)
        case .icDIP, .icSOIC:
            node = makeIC(pinCount: component.pins.count > 0 ? component.pins.count : 8, label: component.value)
        case .transformer:
            node = makeTransformer()
        case .potentiometer:
            node = makePotentiometer()
        case .connector:
            node = makeConnector(pinCount: max(component.pins.count, 2))
        case .inductor:
            node = makeInductor()
        case .relay:
            node = makeRelay()
        case .fuse:
            node = makeFuse()
        case .crystal:
            node = makeCrystal()
        case .speaker:
            node = makeSpeaker()
        case .unknown:
            node = makeGenericComponent()
        }

        node.name = component.designator
        node.position = SCNVector3(component.position.x, component.position.y, component.position.z)

        // Add designator label above the component
        let label = makeLabel(text: component.designator, size: 0.04)
        label.position = SCNVector3(0, Float(node.boundingBox.max.y) + 0.06, 0)
        node.addChildNode(label)

        // Add value label below designator
        if !component.value.isEmpty {
            let valueLabel = makeLabel(text: component.value, size: 0.03, color: .lightGray)
            valueLabel.position = SCNVector3(0, Float(node.boundingBox.max.y) + 0.03, 0)
            node.addChildNode(valueLabel)
        }

        // Add pin anchor nodes
        addPinAnchors(to: node, component: component)

        return node
    }

    // MARK: - Resistor

    private static func makeResistor(value: String) -> SCNNode {
        let node = SCNNode()

        // Body — small cylinder
        let body = SCNCylinder(radius: 0.03, height: 0.1)
        body.firstMaterial = makeMaterial(color: .init(red: 0.36, green: 0.25, blue: 0.2, alpha: 1)) // brown
        let bodyNode = SCNNode(geometry: body)
        bodyNode.eulerAngles.z = .pi / 2
        node.addChildNode(bodyNode)

        // Color bands (simplified — 3 bands)
        let bandColors = resistorBandColors(value: value)
        for (i, color) in bandColors.prefix(3).enumerated() {
            let band = SCNCylinder(radius: 0.031, height: 0.008)
            band.firstMaterial = makeMaterial(color: color)
            let bandNode = SCNNode(geometry: band)
            bandNode.eulerAngles.z = .pi / 2
            bandNode.position = SCNVector3(Float(i - 1) * 0.025, 0, 0)
            node.addChildNode(bandNode)
        }

        // Leads
        let lead = SCNCylinder(radius: 0.004, height: 0.08)
        lead.firstMaterial = makeMaterial(color: .gray)

        let leftLead = SCNNode(geometry: lead)
        leftLead.eulerAngles.z = .pi / 2
        leftLead.position = SCNVector3(-0.09, 0, 0)
        node.addChildNode(leftLead)

        let rightLead = SCNNode(geometry: lead)
        rightLead.eulerAngles.z = .pi / 2
        rightLead.position = SCNVector3(0.09, 0, 0)
        node.addChildNode(rightLead)

        return node
    }

    // MARK: - Capacitor (ceramic disc)

    private static func makeCapacitor() -> SCNNode {
        let node = SCNNode()

        let body = SCNCylinder(radius: 0.035, height: 0.015)
        body.firstMaterial = makeMaterial(color: .init(red: 0.9, green: 0.8, blue: 0.4, alpha: 1)) // tan ceramic
        let bodyNode = SCNNode(geometry: body)
        node.addChildNode(bodyNode)

        // Leads
        let lead = SCNCylinder(radius: 0.003, height: 0.08)
        lead.firstMaterial = makeMaterial(color: .gray)

        let leftLead = SCNNode(geometry: lead)
        leftLead.position = SCNVector3(-0.015, -0.04, 0)
        node.addChildNode(leftLead)

        let rightLead = SCNNode(geometry: lead)
        rightLead.position = SCNVector3(0.015, -0.04, 0)
        node.addChildNode(rightLead)

        return node
    }

    // MARK: - Electrolytic Capacitor

    private static func makeElectrolyticCapacitor() -> SCNNode {
        let node = SCNNode()

        let body = SCNCylinder(radius: 0.04, height: 0.1)
        body.firstMaterial = makeMaterial(color: .init(red: 0.1, green: 0.1, blue: 0.5, alpha: 1)) // dark blue
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, 0.02, 0)
        node.addChildNode(bodyNode)

        // Top cap with - stripe
        let cap = SCNCylinder(radius: 0.041, height: 0.01)
        cap.firstMaterial = makeMaterial(color: .init(red: 0.7, green: 0.7, blue: 0.7, alpha: 1))
        let capNode = SCNNode(geometry: cap)
        capNode.position = SCNVector3(0, 0.075, 0)
        node.addChildNode(capNode)

        // Leads
        let lead = SCNCylinder(radius: 0.004, height: 0.06)
        lead.firstMaterial = makeMaterial(color: .gray)

        let leftLead = SCNNode(geometry: lead)
        leftLead.position = SCNVector3(-0.015, -0.06, 0)
        node.addChildNode(leftLead)

        let rightLead = SCNNode(geometry: lead)
        rightLead.position = SCNVector3(0.015, -0.06, 0)
        node.addChildNode(rightLead)

        return node
    }

    // MARK: - Diode

    private static func makeDiode(type: ComponentType) -> SCNNode {
        let node = SCNNode()

        let bodyColor: NSColor = type == .led
            ? .init(red: 1.0, green: 0.2, blue: 0.2, alpha: 0.8)
            : .init(red: 0.15, green: 0.15, blue: 0.15, alpha: 1)

        let body = SCNCylinder(radius: 0.02, height: 0.06)
        body.firstMaterial = makeMaterial(color: bodyColor)
        let bodyNode = SCNNode(geometry: body)
        bodyNode.eulerAngles.z = .pi / 2
        node.addChildNode(bodyNode)

        // Cathode band
        let band = SCNCylinder(radius: 0.021, height: 0.008)
        band.firstMaterial = makeMaterial(color: .white)
        let bandNode = SCNNode(geometry: band)
        bandNode.eulerAngles.z = .pi / 2
        bandNode.position = SCNVector3(0.022, 0, 0)
        node.addChildNode(bandNode)

        // Leads
        let lead = SCNCylinder(radius: 0.003, height: 0.06)
        lead.firstMaterial = makeMaterial(color: .gray)

        let leftLead = SCNNode(geometry: lead)
        leftLead.eulerAngles.z = .pi / 2
        leftLead.position = SCNVector3(-0.06, 0, 0)
        node.addChildNode(leftLead)

        let rightLead = SCNNode(geometry: lead)
        rightLead.eulerAngles.z = .pi / 2
        rightLead.position = SCNVector3(0.06, 0, 0)
        node.addChildNode(rightLead)

        return node
    }

    // MARK: - Transistor (TO-92 package)

    private static func makeTransistor() -> SCNNode {
        let node = SCNNode()

        // Flat-sided body (approximate with sphere + box subtraction → use hemisphere)
        let body = SCNCapsule(capRadius: 0.025, height: 0.05)
        body.firstMaterial = makeMaterial(color: .init(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        let bodyNode = SCNNode(geometry: body)
        node.addChildNode(bodyNode)

        // 3 pins
        let lead = SCNCylinder(radius: 0.003, height: 0.06)
        lead.firstMaterial = makeMaterial(color: .gray)

        for i in 0..<3 {
            let pin = SCNNode(geometry: lead)
            pin.position = SCNVector3(Float(i - 1) * 0.015, -0.055, 0)
            node.addChildNode(pin)
        }

        return node
    }

    // MARK: - IC (DIP package)

    private static func makeIC(pinCount: Int, label: String) -> SCNNode {
        let node = SCNNode()
        let pinsPerSide = max(pinCount / 2, 2)
        let bodyWidth: CGFloat = 0.08
        let bodyLength = CGFloat(pinsPerSide) * 0.02 + 0.02
        let bodyHeight: CGFloat = 0.03

        let body = SCNBox(width: bodyWidth, height: bodyHeight, length: bodyLength, chamferRadius: 0.003)
        body.firstMaterial = makeMaterial(color: .init(red: 0.12, green: 0.12, blue: 0.12, alpha: 1))
        let bodyNode = SCNNode(geometry: body)
        node.addChildNode(bodyNode)

        // Pin 1 dot
        let dot = SCNCylinder(radius: 0.005, height: 0.001)
        dot.firstMaterial = makeMaterial(color: .white)
        let dotNode = SCNNode(geometry: dot)
        dotNode.position = SCNVector3(-Float(bodyWidth / 2) + 0.015, Float(bodyHeight / 2) + 0.001, -Float(bodyLength / 2) + 0.015)
        dotNode.eulerAngles.x = 0
        node.addChildNode(dotNode)

        // Pins on each side
        let pin = SCNBox(width: 0.01, height: 0.004, length: 0.02, chamferRadius: 0.001)
        pin.firstMaterial = makeMaterial(color: .init(red: 0.7, green: 0.7, blue: 0.7, alpha: 1))

        for i in 0..<pinsPerSide {
            let z = -Float(bodyLength / 2) + 0.02 + Float(i) * 0.02

            let leftPin = SCNNode(geometry: pin)
            leftPin.position = SCNVector3(-Float(bodyWidth / 2) - 0.01, -0.01, z)
            node.addChildNode(leftPin)

            let rightPin = SCNNode(geometry: pin)
            rightPin.position = SCNVector3(Float(bodyWidth / 2) + 0.01, -0.01, z)
            node.addChildNode(rightPin)
        }

        // Part label on top
        let partLabel = makeLabel(text: label, size: 0.015, color: .white)
        partLabel.position = SCNVector3(0, Float(bodyHeight / 2) + 0.002, 0)
        partLabel.eulerAngles.x = -.pi / 2
        node.addChildNode(partLabel)

        return node
    }

    // MARK: - Transformer

    private static func makeTransformer() -> SCNNode {
        let node = SCNNode()

        // Core (E-I shape simplified as box)
        let core = SCNBox(width: 0.12, height: 0.1, length: 0.08, chamferRadius: 0.005)
        core.firstMaterial = makeMaterial(color: .init(red: 0.3, green: 0.3, blue: 0.3, alpha: 1))
        let coreNode = SCNNode(geometry: core)
        node.addChildNode(coreNode)

        // Primary winding (left coil)
        let coil1 = SCNTorus(ringRadius: 0.03, pipeRadius: 0.015)
        coil1.firstMaterial = makeMaterial(color: .init(red: 0.7, green: 0.4, blue: 0.1, alpha: 1)) // copper
        let coil1Node = SCNNode(geometry: coil1)
        coil1Node.position = SCNVector3(-0.025, 0, 0)
        coil1Node.eulerAngles.z = .pi / 2
        node.addChildNode(coil1Node)

        // Secondary winding (right coil)
        let coil2 = SCNTorus(ringRadius: 0.03, pipeRadius: 0.015)
        coil2.firstMaterial = makeMaterial(color: .init(red: 0.7, green: 0.1, blue: 0.1, alpha: 1)) // red
        let coil2Node = SCNNode(geometry: coil2)
        coil2Node.position = SCNVector3(0.025, 0, 0)
        coil2Node.eulerAngles.z = .pi / 2
        node.addChildNode(coil2Node)

        return node
    }

    // MARK: - Potentiometer

    private static func makePotentiometer() -> SCNNode {
        let node = SCNNode()

        let body = SCNCylinder(radius: 0.04, height: 0.02)
        body.firstMaterial = makeMaterial(color: .init(red: 0.2, green: 0.3, blue: 0.6, alpha: 1))
        let bodyNode = SCNNode(geometry: body)
        node.addChildNode(bodyNode)

        // Shaft
        let shaft = SCNCylinder(radius: 0.008, height: 0.04)
        shaft.firstMaterial = makeMaterial(color: .init(red: 0.7, green: 0.7, blue: 0.7, alpha: 1))
        let shaftNode = SCNNode(geometry: shaft)
        shaftNode.position = SCNVector3(0, 0.03, 0)
        node.addChildNode(shaftNode)

        // 3 pins
        let lead = SCNCylinder(radius: 0.003, height: 0.04)
        lead.firstMaterial = makeMaterial(color: .gray)
        for i in 0..<3 {
            let pin = SCNNode(geometry: lead)
            pin.position = SCNVector3(Float(i - 1) * 0.02, -0.03, 0)
            node.addChildNode(pin)
        }

        return node
    }

    // MARK: - Connector

    private static func makeConnector(pinCount: Int) -> SCNNode {
        let node = SCNNode()
        let width = CGFloat(pinCount) * 0.02 + 0.02

        let body = SCNBox(width: width, height: 0.03, length: 0.03, chamferRadius: 0.002)
        body.firstMaterial = makeMaterial(color: .init(red: 0.9, green: 0.9, blue: 0.85, alpha: 1))
        let bodyNode = SCNNode(geometry: body)
        node.addChildNode(bodyNode)

        let pin = SCNCylinder(radius: 0.003, height: 0.03)
        pin.firstMaterial = makeMaterial(color: .init(red: 0.8, green: 0.7, blue: 0.2, alpha: 1)) // gold
        for i in 0..<pinCount {
            let pinNode = SCNNode(geometry: pin)
            pinNode.position = SCNVector3(-Float(width / 2) + 0.02 + Float(i) * 0.02, -0.03, 0)
            node.addChildNode(pinNode)
        }

        return node
    }

    // MARK: - Simple component shapes

    private static func makeInductor() -> SCNNode {
        let node = SCNNode()
        let body = SCNTorus(ringRadius: 0.03, pipeRadius: 0.015)
        body.firstMaterial = makeMaterial(color: .init(red: 0.5, green: 0.35, blue: 0.2, alpha: 1))
        node.addChildNode(SCNNode(geometry: body))

        let lead = SCNCylinder(radius: 0.003, height: 0.06)
        lead.firstMaterial = makeMaterial(color: .gray)
        let l1 = SCNNode(geometry: lead)
        l1.position = SCNVector3(-0.03, -0.03, 0)
        node.addChildNode(l1)
        let l2 = SCNNode(geometry: lead)
        l2.position = SCNVector3(0.03, -0.03, 0)
        node.addChildNode(l2)

        return node
    }

    private static func makeRelay() -> SCNNode {
        let node = SCNNode()
        let body = SCNBox(width: 0.08, height: 0.06, length: 0.05, chamferRadius: 0.003)
        body.firstMaterial = makeMaterial(color: .init(red: 0.1, green: 0.1, blue: 0.4, alpha: 1))
        node.addChildNode(SCNNode(geometry: body))
        return node
    }

    private static func makeFuse() -> SCNNode {
        let node = SCNNode()
        let body = SCNCylinder(radius: 0.01, height: 0.06)
        body.firstMaterial = makeMaterial(color: .init(red: 0.9, green: 0.9, blue: 0.9, alpha: 0.7))
        let bodyNode = SCNNode(geometry: body)
        bodyNode.eulerAngles.z = .pi / 2
        node.addChildNode(bodyNode)

        // End caps
        let cap = SCNCylinder(radius: 0.011, height: 0.01)
        cap.firstMaterial = makeMaterial(color: .init(red: 0.7, green: 0.7, blue: 0.7, alpha: 1))
        let c1 = SCNNode(geometry: cap)
        c1.eulerAngles.z = .pi / 2
        c1.position = SCNVector3(-0.03, 0, 0)
        node.addChildNode(c1)
        let c2 = SCNNode(geometry: cap)
        c2.eulerAngles.z = .pi / 2
        c2.position = SCNVector3(0.03, 0, 0)
        node.addChildNode(c2)

        return node
    }

    private static func makeCrystal() -> SCNNode {
        let node = SCNNode()
        let body = SCNBox(width: 0.04, height: 0.02, length: 0.015, chamferRadius: 0.002)
        body.firstMaterial = makeMaterial(color: .init(red: 0.7, green: 0.7, blue: 0.7, alpha: 1))
        node.addChildNode(SCNNode(geometry: body))

        let lead = SCNCylinder(radius: 0.003, height: 0.04)
        lead.firstMaterial = makeMaterial(color: .gray)
        let l1 = SCNNode(geometry: lead)
        l1.position = SCNVector3(-0.01, -0.03, 0)
        node.addChildNode(l1)
        let l2 = SCNNode(geometry: lead)
        l2.position = SCNVector3(0.01, -0.03, 0)
        node.addChildNode(l2)

        return node
    }

    private static func makeSpeaker() -> SCNNode {
        let node = SCNNode()
        let cone = SCNCone(topRadius: 0.02, bottomRadius: 0.05, height: 0.03)
        cone.firstMaterial = makeMaterial(color: .init(red: 0.15, green: 0.15, blue: 0.15, alpha: 1))
        node.addChildNode(SCNNode(geometry: cone))
        return node
    }

    private static func makeGenericComponent() -> SCNNode {
        let node = SCNNode()
        let body = SCNBox(width: 0.05, height: 0.03, length: 0.03, chamferRadius: 0.005)
        body.firstMaterial = makeMaterial(color: .init(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        node.addChildNode(SCNNode(geometry: body))
        return node
    }

    // MARK: - Pin Anchors

    private static func addPinAnchors(to node: SCNNode, component: Component) {
        let pins = component.pins.isEmpty ? defaultPins(for: component.type) : component.pins
        let count = pins.count

        for (i, pin) in pins.enumerated() {
            let anchor = SCNNode()
            anchor.name = "pin_\(pin.id)"

            // Distribute pins along the bottom edge
            let spread = Float(count - 1) * 0.025
            let x = -spread / 2 + Float(i) * 0.025
            anchor.position = SCNVector3(x, Float(node.boundingBox.min.y) - 0.02, 0)

            // Small sphere for visual debugging (hidden by default)
            let sphere = SCNSphere(radius: 0.005)
            sphere.firstMaterial = makeMaterial(color: .init(red: 1, green: 0.8, blue: 0, alpha: 0.6))
            let sphereNode = SCNNode(geometry: sphere)
            sphereNode.isHidden = true
            anchor.addChildNode(sphereNode)

            node.addChildNode(anchor)
        }
    }

    private static func defaultPins(for type: ComponentType) -> [Pin] {
        (0..<type.pinCount).map { Pin(id: "p\($0)", label: "Pin \($0)") }
    }

    // MARK: - Labels

    /// Creates a 2D text label rendered as a texture on a flat plane.
    /// This produces crisp, readable labels instead of polygonal 3D text meshes.
    static func makeLabel(text: String, size: CGFloat, color: NSColor = .white) -> SCNNode {
        // Render text to an image at high resolution for crispness
        let scale: CGFloat = 4.0 // retina multiplier
        let font = NSFont.systemFont(ofSize: 64 * scale, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)

        let padding: CGFloat = 16 * scale
        let imgWidth = ceil(textSize.width + padding * 2)
        let imgHeight = ceil(textSize.height + padding * 2)

        let image = NSImage(size: NSSize(width: imgWidth, height: imgHeight))
        image.lockFocus()

        // Semi-transparent dark background pill
        let bgRect = NSRect(x: 0, y: 0, width: imgWidth, height: imgHeight)
        let cornerRadius = imgHeight * 0.3
        let path = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor(white: 0.0, alpha: 0.55).setFill()
        path.fill()

        // Draw text centered
        let textRect = NSRect(
            x: (imgWidth - textSize.width) / 2,
            y: (imgHeight - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        (text as NSString).draw(in: textRect, withAttributes: attrs)

        image.unlockFocus()

        // Map image size to scene units (size parameter controls height)
        let aspect = imgWidth / imgHeight
        let planeHeight = size
        let planeWidth = planeHeight * aspect

        let plane = SCNPlane(width: planeWidth, height: planeHeight)
        let mat = SCNMaterial()
        mat.diffuse.contents = image
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        mat.writesToDepthBuffer = false
        plane.firstMaterial = mat

        let node = SCNNode(geometry: plane)
        node.renderingOrder = 100 // render on top

        // Billboard constraint so labels always face camera
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = [.X, .Y]
        node.constraints = [billboard]

        return node
    }

    // MARK: - Materials

    static func makeMaterial(color: NSColor) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.lightingModel = .physicallyBased
        mat.roughness.contents = 0.6
        mat.metalness.contents = 0.1
        return mat
    }

    // MARK: - Resistor Color Bands

    private static func resistorBandColors(value: String) -> [NSColor] {
        let colorMap: [Character: NSColor] = [
            "0": .black,
            "1": .brown,
            "2": .red,
            "3": .orange,
            "4": .yellow,
            "5": .green,
            "6": .blue,
            "7": .purple,
            "8": .gray,
            "9": .white,
        ]

        // Extract numeric value from string like "10kΩ", "4.7kΩ", "100Ω"
        let cleaned = value
            .replacingOccurrences(of: "Ω", with: "")
            .replacingOccurrences(of: "ohm", with: "")
            .trimmingCharacters(in: .whitespaces)

        var numericValue: Double = 0
        if cleaned.lowercased().hasSuffix("m") {
            numericValue = (Double(cleaned.dropLast()) ?? 0) * 1_000_000
        } else if cleaned.lowercased().hasSuffix("k") {
            numericValue = (Double(cleaned.dropLast()) ?? 0) * 1000
        } else {
            numericValue = Double(cleaned) ?? 0
        }

        guard numericValue > 0 else { return [.brown, .black, .brown] }

        let digits = String(Int(numericValue))
        var colors: [NSColor] = []
        for char in digits.prefix(2) {
            colors.append(colorMap[char] ?? .black)
        }
        // Multiplier band = number of trailing zeros
        let zeros = max(0, digits.count - 2)
        colors.append(colorMap[Character(String(zeros))] ?? .black)

        return colors
    }
}
