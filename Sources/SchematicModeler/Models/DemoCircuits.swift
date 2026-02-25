import Foundation

/// Pre-built demo circuits for testing and demonstration
enum DemoCircuits {

    /// Pioneer SX-750 Power Amplifier Assembly (AWH-046)
    /// Simplified representation of the complementary push-pull output stage
    static func pioneerSX750PowerAmp() -> Circuit {
        // Define components with approximate board positions
        var components: [Component] = []

        // Input stage — differential pair
        components.append(Component(
            designator: "Q101",
            type: .transistorNPN,
            value: "2SC1345",
            description: "Differential pair input (non-inverting)",
            pins: [Pin(id: "b", label: "Base", netID: "input"),
                   Pin(id: "c", label: "Collector", netID: "n1"),
                   Pin(id: "e", label: "Emitter", netID: "n_tail")],
            position: SIMD3(-0.4, 0.05, -0.2),
            functionalBlock: "input_stage"
        ))

        components.append(Component(
            designator: "Q102",
            type: .transistorNPN,
            value: "2SC1345",
            description: "Differential pair input (inverting)",
            pins: [Pin(id: "b", label: "Base", netID: "feedback"),
                   Pin(id: "c", label: "Collector", netID: "n2"),
                   Pin(id: "e", label: "Emitter", netID: "n_tail")],
            position: SIMD3(-0.2, 0.05, -0.2),
            functionalBlock: "input_stage"
        ))

        // Current source for diff pair
        components.append(Component(
            designator: "R101",
            type: .resistor,
            value: "10kΩ",
            description: "Tail current setting resistor",
            pins: [Pin(id: "1", label: "1", netID: "n_tail"),
                   Pin(id: "2", label: "2", netID: "vee")],
            position: SIMD3(-0.3, 0.05, -0.35),
            functionalBlock: "input_stage"
        ))

        components.append(Component(
            designator: "R102",
            type: .resistor,
            value: "22kΩ",
            description: "Collector load resistor",
            pins: [Pin(id: "1", label: "1", netID: "vcc"),
                   Pin(id: "2", label: "2", netID: "n1")],
            position: SIMD3(-0.4, 0.05, -0.05),
            functionalBlock: "input_stage"
        ))

        components.append(Component(
            designator: "R103",
            type: .resistor,
            value: "22kΩ",
            description: "Collector load resistor",
            pins: [Pin(id: "1", label: "1", netID: "vcc"),
                   Pin(id: "2", label: "2", netID: "n2")],
            position: SIMD3(-0.2, 0.05, -0.05),
            functionalBlock: "input_stage"
        ))

        // Voltage amplifier stage
        components.append(Component(
            designator: "Q103",
            type: .transistorNPN,
            value: "2SC1845",
            description: "Voltage amplifier / driver",
            pins: [Pin(id: "b", label: "Base", netID: "n2"),
                   Pin(id: "c", label: "Collector", netID: "n3"),
                   Pin(id: "e", label: "Emitter", netID: "n4")],
            position: SIMD3(0.0, 0.05, -0.1),
            functionalBlock: "vas"
        ))

        components.append(Component(
            designator: "R104",
            type: .resistor,
            value: "4.7kΩ",
            description: "VAS collector load",
            pins: [Pin(id: "1", label: "1", netID: "vcc"),
                   Pin(id: "2", label: "2", netID: "n3")],
            position: SIMD3(0.0, 0.05, 0.05),
            functionalBlock: "vas"
        ))

        components.append(Component(
            designator: "R105",
            type: .resistor,
            value: "100Ω",
            description: "VAS emitter degeneration",
            pins: [Pin(id: "1", label: "1", netID: "n4"),
                   Pin(id: "2", label: "2", netID: "vee")],
            position: SIMD3(0.0, 0.05, -0.25),
            functionalBlock: "vas"
        ))

        // Bootstrap capacitor
        components.append(Component(
            designator: "C101",
            type: .capacitorElectrolytic,
            value: "100µF",
            description: "Bootstrap capacitor — maintains VAS headroom",
            pins: [Pin(id: "1", label: "+", netID: "n3"),
                   Pin(id: "2", label: "-", netID: "output")],
            position: SIMD3(0.1, 0.05, 0.0),
            functionalBlock: "vas"
        ))

        // Bias network
        components.append(Component(
            designator: "Q104",
            type: .transistorNPN,
            value: "2SC1345",
            description: "Bias multiplier (Vbe multiplier)",
            pins: [Pin(id: "b", label: "Base", netID: "n_bias"),
                   Pin(id: "c", label: "Collector", netID: "n3"),
                   Pin(id: "e", label: "Emitter", netID: "n5")],
            position: SIMD3(0.2, 0.05, -0.05),
            functionalBlock: "bias"
        ))

        components.append(Component(
            designator: "R106",
            type: .resistor,
            value: "470Ω",
            description: "Bias adjust resistor",
            pins: [Pin(id: "1", label: "1", netID: "n_bias"),
                   Pin(id: "2", label: "2", netID: "n5")],
            position: SIMD3(0.2, 0.05, -0.2),
            functionalBlock: "bias"
        ))

        components.append(Component(
            designator: "VR101",
            type: .potentiometer,
            value: "500Ω",
            description: "Idle current / bias adjustment",
            pins: [Pin(id: "1", label: "1", netID: "n_bias"),
                   Pin(id: "w", label: "Wiper", netID: "n_bias"),
                   Pin(id: "2", label: "2", netID: "n3")],
            position: SIMD3(0.3, 0.05, -0.05),
            functionalBlock: "bias"
        ))

        // Output stage — complementary pair
        components.append(Component(
            designator: "Q105",
            type: .transistorNPN,
            value: "2SD388",
            description: "Output NPN power transistor",
            pins: [Pin(id: "b", label: "Base", netID: "n3"),
                   Pin(id: "c", label: "Collector", netID: "vcc"),
                   Pin(id: "e", label: "Emitter", netID: "output")],
            position: SIMD3(0.4, 0.05, 0.1),
            functionalBlock: "output_stage"
        ))

        components.append(Component(
            designator: "Q106",
            type: .transistorPNP,
            value: "2SB541",
            description: "Output PNP power transistor",
            pins: [Pin(id: "b", label: "Base", netID: "n5"),
                   Pin(id: "c", label: "Collector", netID: "vee"),
                   Pin(id: "e", label: "Emitter", netID: "output")],
            position: SIMD3(0.4, 0.05, -0.2),
            functionalBlock: "output_stage"
        ))

        // Emitter resistors (ballast)
        components.append(Component(
            designator: "R109",
            type: .resistor,
            value: "0.33Ω",
            description: "Output emitter ballast resistor (NPN)",
            pins: [Pin(id: "1", label: "1", netID: "output"),
                   Pin(id: "2", label: "2", netID: "n_spk")],
            position: SIMD3(0.5, 0.05, 0.1),
            functionalBlock: "output_stage"
        ))

        components.append(Component(
            designator: "R110",
            type: .resistor,
            value: "0.33Ω",
            description: "Output emitter ballast resistor (PNP)",
            pins: [Pin(id: "1", label: "1", netID: "output"),
                   Pin(id: "2", label: "2", netID: "n_spk")],
            position: SIMD3(0.5, 0.05, -0.2),
            functionalBlock: "output_stage"
        ))

        // Feedback network
        components.append(Component(
            designator: "R107",
            type: .resistor,
            value: "27kΩ",
            description: "Feedback resistor (sets gain)",
            pins: [Pin(id: "1", label: "1", netID: "feedback"),
                   Pin(id: "2", label: "2", netID: "n_spk")],
            position: SIMD3(-0.1, 0.05, 0.2),
            functionalBlock: "feedback"
        ))

        components.append(Component(
            designator: "R108",
            type: .resistor,
            value: "1kΩ",
            description: "Feedback ground reference",
            pins: [Pin(id: "1", label: "1", netID: "feedback"),
                   Pin(id: "2", label: "2", netID: "gnd")],
            position: SIMD3(-0.2, 0.05, 0.2),
            functionalBlock: "feedback"
        ))

        // Input coupling capacitor
        components.append(Component(
            designator: "C102",
            type: .capacitorElectrolytic,
            value: "10µF",
            description: "Input DC blocking capacitor",
            pins: [Pin(id: "1", label: "+", netID: "input_ac"),
                   Pin(id: "2", label: "-", netID: "input")],
            position: SIMD3(-0.55, 0.05, -0.2),
            functionalBlock: "input_stage"
        ))

        // Output coupling capacitor
        components.append(Component(
            designator: "C103",
            type: .capacitorElectrolytic,
            value: "2200µF",
            description: "Output coupling capacitor",
            pins: [Pin(id: "1", label: "+", netID: "n_spk"),
                   Pin(id: "2", label: "-", netID: "speaker_out")],
            position: SIMD3(0.6, 0.05, -0.05),
            functionalBlock: "output_stage"
        ))

        // Speaker connector
        components.append(Component(
            designator: "J101",
            type: .connector,
            value: "Speaker Out",
            description: "Speaker output terminal",
            pins: [Pin(id: "1", label: "+", netID: "speaker_out"),
                   Pin(id: "2", label: "-", netID: "gnd")],
            position: SIMD3(0.75, 0.05, -0.05),
            functionalBlock: "output_stage"
        ))

        // Input connector
        components.append(Component(
            designator: "J102",
            type: .connector,
            value: "Audio In",
            description: "Audio input terminal",
            pins: [Pin(id: "1", label: "Signal", netID: "input_ac"),
                   Pin(id: "2", label: "GND", netID: "gnd")],
            position: SIMD3(-0.75, 0.05, -0.2),
            functionalBlock: "input_stage"
        ))

        // Define nets
        let nets: [Net] = [
            Net(id: "input_ac", label: "INPUT AC", connectedPins: [
                .init(componentID: "J102", pinID: "1"),
                .init(componentID: "C102", pinID: "1"),
            ]),
            Net(id: "input", label: "INPUT", connectedPins: [
                .init(componentID: "C102", pinID: "2"),
                .init(componentID: "Q101", pinID: "b"),
            ]),
            Net(id: "feedback", label: "FEEDBACK", connectedPins: [
                .init(componentID: "Q102", pinID: "b"),
                .init(componentID: "R107", pinID: "1"),
                .init(componentID: "R108", pinID: "1"),
            ]),
            Net(id: "n_tail", label: nil, connectedPins: [
                .init(componentID: "Q101", pinID: "e"),
                .init(componentID: "Q102", pinID: "e"),
                .init(componentID: "R101", pinID: "1"),
            ]),
            Net(id: "n1", label: nil, connectedPins: [
                .init(componentID: "Q101", pinID: "c"),
                .init(componentID: "R102", pinID: "2"),
            ]),
            Net(id: "n2", label: nil, connectedPins: [
                .init(componentID: "Q102", pinID: "c"),
                .init(componentID: "R103", pinID: "2"),
                .init(componentID: "Q103", pinID: "b"),
            ]),
            Net(id: "n3", label: nil, connectedPins: [
                .init(componentID: "Q103", pinID: "c"),
                .init(componentID: "R104", pinID: "2"),
                .init(componentID: "C101", pinID: "1"),
                .init(componentID: "Q104", pinID: "c"),
                .init(componentID: "VR101", pinID: "2"),
                .init(componentID: "Q105", pinID: "b"),
            ]),
            Net(id: "n4", label: nil, connectedPins: [
                .init(componentID: "Q103", pinID: "e"),
                .init(componentID: "R105", pinID: "1"),
            ]),
            Net(id: "n5", label: nil, connectedPins: [
                .init(componentID: "Q104", pinID: "e"),
                .init(componentID: "R106", pinID: "2"),
                .init(componentID: "Q106", pinID: "b"),
            ]),
            Net(id: "n_bias", label: "BIAS", connectedPins: [
                .init(componentID: "Q104", pinID: "b"),
                .init(componentID: "R106", pinID: "1"),
                .init(componentID: "VR101", pinID: "1"),
                .init(componentID: "VR101", pinID: "w"),
            ]),
            Net(id: "output", label: "OUTPUT", connectedPins: [
                .init(componentID: "Q105", pinID: "e"),
                .init(componentID: "Q106", pinID: "e"),
                .init(componentID: "R109", pinID: "1"),
                .init(componentID: "R110", pinID: "1"),
                .init(componentID: "C101", pinID: "2"),
            ]),
            Net(id: "n_spk", label: "SPEAKER", connectedPins: [
                .init(componentID: "R109", pinID: "2"),
                .init(componentID: "R110", pinID: "2"),
                .init(componentID: "R107", pinID: "2"),
                .init(componentID: "C103", pinID: "1"),
            ]),
            Net(id: "speaker_out", label: "SPEAKER OUT", connectedPins: [
                .init(componentID: "C103", pinID: "2"),
                .init(componentID: "J101", pinID: "1"),
            ]),
            Net(id: "vcc", label: "+45V", connectedPins: [
                .init(componentID: "R102", pinID: "1"),
                .init(componentID: "R103", pinID: "1"),
                .init(componentID: "R104", pinID: "1"),
                .init(componentID: "Q105", pinID: "c"),
            ]),
            Net(id: "vee", label: "-45V", connectedPins: [
                .init(componentID: "R101", pinID: "2"),
                .init(componentID: "R105", pinID: "2"),
                .init(componentID: "Q106", pinID: "c"),
            ]),
            Net(id: "gnd", label: "GND", connectedPins: [
                .init(componentID: "R108", pinID: "2"),
                .init(componentID: "J101", pinID: "2"),
                .init(componentID: "J102", pinID: "2"),
            ]),
        ]

        // Define functional blocks
        let blocks: [FunctionalBlock] = [
            FunctionalBlock(
                id: "input_stage",
                name: "Input Stage",
                description: "Differential pair input with constant current source. Provides high input impedance, low noise, and common-mode rejection.",
                componentIDs: ["Q101", "Q102", "R101", "R102", "R103", "C102", "J102"],
                color: .blue
            ),
            FunctionalBlock(
                id: "vas",
                name: "Voltage Amplifier Stage",
                description: "Single-ended class A voltage amplifier. Converts the differential pair current output to a voltage swing sufficient to drive the output stage. Bootstrap capacitor C101 extends voltage swing.",
                componentIDs: ["Q103", "R104", "R105", "C101"],
                color: .green
            ),
            FunctionalBlock(
                id: "bias",
                name: "Bias Network",
                description: "Vbe multiplier (Q104) sets the quiescent current for the output transistors. VR101 allows idle current adjustment to minimize crossover distortion.",
                componentIDs: ["Q104", "R106", "VR101"],
                color: .orange
            ),
            FunctionalBlock(
                id: "output_stage",
                name: "Output Stage",
                description: "Complementary push-pull output with emitter ballast resistors. Q105 (NPN) handles positive swing, Q106 (PNP) handles negative swing. C103 blocks DC from reaching the speaker.",
                componentIDs: ["Q105", "Q106", "R109", "R110", "C103", "J101"],
                color: .red
            ),
            FunctionalBlock(
                id: "feedback",
                name: "Feedback Network",
                description: "Negative feedback from output to inverting input. R107/R108 set closed-loop gain to approximately 28 (29 dB). Stabilizes gain and reduces distortion.",
                componentIDs: ["R107", "R108"],
                color: .purple
            ),
        ]

        return Circuit(
            id: "pioneer-sx750-power-amp",
            name: "Pioneer SX-750 Power Amplifier (AWH-046)",
            description: "50W complementary push-pull power amplifier",
            components: components,
            nets: nets,
            functionalBlocks: blocks
        )
    }
}
