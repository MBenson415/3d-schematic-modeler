import SwiftUI

/// Bottom panel showing circuit explanation and functional block legend
struct CircuitExplanationView: View {
    let circuit: Circuit?
    let explanation: String
    var selectedBlockID: String?
    var onBlockSelected: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let circuit {
                // Circuit title
                HStack {
                    Text(circuit.name)
                        .font(.headline)
                    Spacer()
                    Text("\(circuit.components.count) components")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(circuit.nets.count) nets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Functional block legend
                if !circuit.functionalBlocks.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(circuit.functionalBlocks) { block in
                                let isSelected = selectedBlockID == block.id
                                Button {
                                    onBlockSelected?(block.id)
                                } label: {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(color(for: block.color))
                                            .frame(width: 8, height: 8)
                                        Text(block.name)
                                            .font(.caption)
                                            .fontWeight(isSelected ? .semibold : .regular)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(isSelected ? color(for: block.color).opacity(0.2) : Color.clear)
                                    .background(.quaternary)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(isSelected ? color(for: block.color) : .clear, lineWidth: 1.5)
                                    )
                                }
                                .buttonStyle(.plain)
                                .help("Click to highlight \u{2022} Double-click to zoom")
                            }
                        }
                    }
                }

                // Explanation text
                if !explanation.isEmpty {
                    Divider()
                    ScrollView {
                        Text(explanation)
                            .font(.system(.caption, design: .default))
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 120)
                }
            } else {
                ContentUnavailableView(
                    "No Circuit Loaded",
                    systemImage: "cpu",
                    description: Text("Load a schematic image or open a circuit file to begin.")
                )
            }
        }
        .padding()
        .background(.ultraThinMaterial)
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
