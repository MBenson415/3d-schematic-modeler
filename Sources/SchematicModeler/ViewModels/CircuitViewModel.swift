import SwiftUI
import SceneKit

/// Main view model managing circuit state and 3D scene
@MainActor
@Observable
final class CircuitViewModel {

    // MARK: - State

    var circuit: Circuit?
    var selectedComponentID: String?
    var selectedBlockID: String?
    /// Assembly selected but not yet analyzed — shows empty board
    var pendingAssemblyName: String?
    var selectedComponent: Component? {
        guard let id = selectedComponentID else { return nil }
        return circuit?.component(for: id)
    }
    var connectedNets: [Net] = []
    var circuitExplanation: String = ""
    var isAnalyzing: Bool = false
    var errorMessage: String?

    // MARK: - Scene

    let sceneBuilder = SceneBuilder()
    var scene: SCNScene { sceneBuilder.scene }

    // MARK: - Load Circuit

    func loadCircuit(_ circuit: Circuit) {
        self.circuit = circuit
        self.pendingAssemblyName = nil
        self.selectedComponentID = nil
        self.connectedNets = []
        sceneBuilder.buildCircuit(circuit)
    }

    /// Show an empty board for an assembly that hasn't been analyzed yet
    func showEmptyBoard(assemblyName: String) {
        self.circuit = nil
        self.pendingAssemblyName = assemblyName
        self.selectedComponentID = nil
        self.connectedNets = []
        self.circuitExplanation = ""
        sceneBuilder.buildEmptyBoard()
    }

    func loadDemoCircuit() {
        let demo = DemoCircuits.pioneerSX750PowerAmp()
        loadCircuit(demo)
        circuitExplanation = """
        Pioneer SX-750 Power Amplifier Assembly (AWH-046)

        This is a complementary-symmetry push-pull power amplifier capable of \
        delivering 50W per channel. The circuit uses a differential pair input \
        stage (Q101/Q102) for low noise and high common-mode rejection, followed \
        by a voltage amplifier stage (Q103) and complementary output transistors \
        (Q105/Q106) in a quasi-complementary configuration.

        Key functional blocks:
        • Input Stage — Differential pair with constant current source
        • Voltage Amplifier — Class A driver with bootstrap capacitor
        • Output Stage — Complementary push-pull with bias network
        • Feedback Network — Sets closed-loop gain via R107/R108
        • Protection — Output coupling capacitor and DC offset detection
        """
    }

    // MARK: - Selection

    func selectComponent(_ designator: String?) {
        selectedComponentID = designator
        selectedBlockID = nil

        if let designator {
            sceneBuilder.highlightComponent(named: designator)
            if let circuit {
                connectedNets = circuit.netsConnectedTo(designator)
                sceneBuilder.highlightNets(for: designator, in: circuit)
            }
        } else {
            sceneBuilder.clearSelection()
            connectedNets = []
        }
    }

    func selectBlock(_ blockID: String?) {
        guard let circuit else { return }

        if let blockID,
           let block = circuit.functionalBlocks.first(where: { $0.id == blockID }) {
            // Toggle off if already selected
            if selectedBlockID == blockID {
                selectedBlockID = nil
                selectedComponentID = nil
                connectedNets = []
                sceneBuilder.clearSelection()
                sceneBuilder.resetCamera()
                return
            }

            selectedBlockID = blockID
            selectedComponentID = nil

            let componentIDs = Set(block.componentIDs)
            sceneBuilder.highlightComponents(named: componentIDs)
            sceneBuilder.highlightNets(for: componentIDs, in: circuit)
            sceneBuilder.focusOnBlock(block, in: circuit)

            // Collect all connected nets for the inspector
            connectedNets = componentIDs.flatMap { circuit.netsConnectedTo($0) }
                .reduce(into: [Net]()) { result, net in
                    if !result.contains(where: { $0.id == net.id }) {
                        result.append(net)
                    }
                }
        } else {
            selectedBlockID = nil
            selectedComponentID = nil
            connectedNets = []
            sceneBuilder.clearSelection()
        }
    }

    func handleHitTest(at point: CGPoint, in view: SCNView) {
        let hits = view.hitTest(point, options: [
            .searchMode: SCNHitTestSearchMode.closest.rawValue,
            .ignoreHiddenNodes: true,
        ])

        // Walk up hierarchy to find the component node
        for hit in hits {
            var node: SCNNode? = hit.node
            while let current = node {
                if let name = current.name,
                   current.parent?.name == "components"
                {
                    selectComponent(name)
                    return
                }
                node = current.parent
            }
        }

        // Clicked empty space
        selectComponent(nil)
    }

    // MARK: - Annotations

    func addAnnotation(to designator: String, note: String) {
        guard let index = circuit?.components.firstIndex(where: { $0.designator == designator }) else { return }
        if circuit?.components[index].annotations == nil {
            circuit?.components[index].annotations = []
        }
        circuit?.components[index].annotations?.append(note)
    }

    func removeAnnotation(from designator: String, at noteIndex: Int) {
        guard let index = circuit?.components.firstIndex(where: { $0.designator == designator }) else { return }
        circuit?.components[index].annotations?.remove(at: noteIndex)
        if circuit?.components[index].annotations?.isEmpty == true {
            circuit?.components[index].annotations = nil
        }
    }

    // MARK: - Heat Map

    var heatMapActive: Bool = false
    var failureProbabilities: [String: Float] = [:]

    func applyHeatMap() {
        guard let circuit else { return }
        heatMapActive = true
        sceneBuilder.applyHeatMap(probabilities: failureProbabilities, for: circuit)
    }

    func clearHeatMap() {
        guard let circuit else { return }
        heatMapActive = false
        sceneBuilder.clearHeatMap(for: circuit)
    }

    // MARK: - Voltage Overlay

    var showVoltages: Bool = false
    var expectedVoltages: [String: String] = [:]

    func toggleVoltageOverlay() {
        if showVoltages {
            sceneBuilder.hideVoltageOverlay()
            showVoltages = false
        } else if let circuit {
            sceneBuilder.showVoltageOverlay(voltages: expectedVoltages, circuit: circuit)
            showVoltages = true
        }
    }

    // MARK: - Export

    func exportCircuitJSON() -> String? {
        guard let circuit else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(circuit) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func importCircuitJSON(_ json: String) throws {
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        let circuit = try decoder.decode(Circuit.self, from: data)
        loadCircuit(circuit)
    }
}
