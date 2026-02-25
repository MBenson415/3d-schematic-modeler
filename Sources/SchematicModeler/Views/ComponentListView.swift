import SwiftUI

/// Sidebar listing all components in the circuit, grouped by functional block
struct ComponentListView: View {
    let circuit: Circuit?
    let selectedComponentID: String?
    var onSelect: ((String?) -> Void)?

    var body: some View {
        Group {
            if let circuit {
                List(selection: Binding(
                    get: { selectedComponentID },
                    set: { onSelect?($0) }
                )) {
                    // Grouped by functional block
                    ForEach(circuit.functionalBlocks) { block in
                        Section(block.name) {
                            let blockComponents = circuit.components.filter { $0.functionalBlock == block.id }
                            ForEach(blockComponents) { component in
                                componentRow(component, blockColor: block.color)
                                    .tag(component.designator)
                            }
                        }
                    }

                    // Ungrouped components
                    let ungrouped = circuit.components.filter { $0.functionalBlock == nil }
                    if !ungrouped.isEmpty {
                        Section("Other") {
                            ForEach(ungrouped) { component in
                                componentRow(component, blockColor: nil)
                                    .tag(component.designator)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            } else {
                ContentUnavailableView(
                    "No Circuit",
                    systemImage: "cpu",
                    description: Text("Load a circuit to see components.")
                )
            }
        }
    }

    private func componentRow(_ component: Component, blockColor: FunctionalBlock.BlockColor?) -> some View {
        HStack {
            if let blockColor {
                Circle()
                    .fill(color(for: blockColor))
                    .frame(width: 6, height: 6)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(component.designator)
                        .font(.system(.body, design: .monospaced, weight: .medium))
                    Spacer()
                    Text(component.value)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(component.type.displayName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func color(for blockColor: FunctionalBlock.BlockColor) -> Color {
        switch blockColor {
        case .blue: .blue
        case .green: .green
        case .orange: .orange
        case .purple: .purple
        case .red: .red
        case .yellow: .yellow
        case .cyan: .cyan
        case .pink: .pink
        }
    }
}
