import SwiftUI

/// Side panel showing details of a selected component
struct ComponentDetailView: View {
    let component: Component
    let connectedNets: [Net]
    let circuit: Circuit?
    var onAddAnnotation: ((String, String) -> Void)?
    var onRemoveAnnotation: ((String, Int) -> Void)?

    @State private var newNote = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Text(component.designator)
                        .font(.system(.title, design: .monospaced, weight: .bold))
                    Spacer()
                    Text(component.type.displayName)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }

                // Failure probability badge
                if let prob = component.failureProbability, prob > 0 {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(heatMapColor(for: prob))
                            .frame(width: 8, height: 8)
                        Text("Failure Risk: \(Int(prob * 100))%")
                            .font(.caption)
                            .foregroundStyle(prob > 0.6 ? .red : prob > 0.3 ? .orange : .green)
                    }
                }

                Divider()

                // Value
                LabeledContent("Value") {
                    Text(component.value)
                        .font(.system(.body, design: .monospaced))
                }

                if let partNumber = component.partNumber {
                    LabeledContent("Part Number") {
                        Text(partNumber)
                            .font(.system(.body, design: .monospaced))
                    }
                }

                if let desc = component.description {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(desc)
                            .font(.body)
                    }
                }

                // Functional block
                if let blockID = component.functionalBlock,
                   let block = circuit?.functionalBlocks.first(where: { $0.id == blockID })
                {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Functional Block")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Circle()
                                .fill(color(for: block.color))
                                .frame(width: 10, height: 10)
                            Text(block.name)
                                .font(.body.bold())
                        }
                        if let desc = block.description {
                            Text(desc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                // Connected nets
                if !connectedNets.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connected Nets")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(connectedNets) { net in
                            HStack {
                                Circle()
                                    .fill(WireRenderer.colorForNet(index: circuit?.nets.firstIndex(where: { $0.id == net.id }) ?? 0).swiftUIColor)
                                    .frame(width: 8, height: 8)
                                Text(net.label ?? net.id)
                                    .font(.system(.caption, design: .monospaced))
                                Spacer()
                                Text("\(net.connectedPins.count) pins")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                Divider()

                // Pins
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pins")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(component.pins) { pin in
                        HStack {
                            Text(pin.label)
                                .font(.system(.caption, design: .monospaced))
                            Spacer()
                            if let netID = pin.netID {
                                Text(netID)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Divider()

                // Annotations / Repair Notes
                VStack(alignment: .leading, spacing: 8) {
                    Text("Repair Notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let annotations = component.annotations, !annotations.isEmpty {
                        ForEach(Array(annotations.enumerated()), id: \.offset) { index, note in
                            HStack(alignment: .top) {
                                Image(systemName: "note.text")
                                    .font(.caption2)
                                    .foregroundStyle(.yellow)
                                Text(note)
                                    .font(.caption)
                                    .textSelection(.enabled)
                                Spacer()
                                if onRemoveAnnotation != nil {
                                    Button {
                                        onRemoveAnnotation?(component.designator, index)
                                    } label: {
                                        Image(systemName: "xmark.circle")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(6)
                            .background(.yellow.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }

                    if onAddAnnotation != nil {
                        HStack(spacing: 4) {
                            TextField("Add note...", text: $newNote)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                                .onSubmit { submitNote() }

                            Button {
                                submitNote()
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.yellow)
                            }
                            .buttonStyle(.plain)
                            .disabled(newNote.isEmpty)
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func submitNote() {
        guard !newNote.isEmpty else { return }
        onAddAnnotation?(component.designator, newNote)
        newNote = ""
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

    private func heatMapColor(for probability: Float) -> Color {
        if probability > 0.6 { return .red }
        if probability > 0.3 { return .orange }
        return .green
    }
}

// MARK: - NSColor to SwiftUI Color

extension NSColor {
    var swiftUIColor: Color {
        Color(self)
    }
}
