import SwiftUI

/// Interactive step-by-step troubleshooting with measurement entry
struct GuidedTroubleshootView: View {
    let circuit: Circuit?
    var onHighlightComponent: ((String) -> Void)?
    var onDismiss: (() -> Void)?
    @State private var symptom = ""
    @State private var measurements: [(testPoint: String, expected: String, measured: String)] = []
    @State private var currentStep: TroubleshootStep?
    @State private var measuredValue = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var apiKey = UserDefaults.standard.string(forKey: "anthropic_api_key") ?? ""

    var body: some View {
        VStack(spacing: 0) {
            // Title
            HStack {
                Text("Guided Troubleshooting")
                    .font(.title2.bold())
                Spacer()
                Button { onDismiss?() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            HSplitView {
                // Left: measurement history
                VStack(alignment: .leading, spacing: 8) {
                    Text("Measurement Log")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 8)

                    if measurements.isEmpty {
                        Text("No measurements yet.\nEnter a symptom to begin.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(spacing: 6) {
                                ForEach(Array(measurements.enumerated()), id: \.offset) { index, m in
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text("Step \(index + 1)")
                                                .font(.caption2.bold())
                                            Spacer()
                                            Text(m.testPoint)
                                                .font(.system(.caption2, design: .monospaced))
                                                .foregroundStyle(.blue)
                                        }
                                        HStack {
                                            Text("Expected: \(m.expected)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text("Measured: \(m.measured)")
                                                .font(.caption2)
                                                .foregroundStyle(m.measured == m.expected ? .green : .orange)
                                        }
                                    }
                                    .padding(8)
                                    .background(.quaternary.opacity(0.5))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    // Suspected components
                    if let step = currentStep, !step.suspectedComponents.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Suspected Components")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            ForEach(step.suspectedComponents, id: \.self) { designator in
                                Button {
                                    onHighlightComponent?(designator)
                                } label: {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.orange)
                                        Text(designator)
                                            .font(.system(.caption, design: .monospaced, weight: .bold))
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)

                // Right: current step + input
                VStack(spacing: 16) {
                    if currentStep == nil && measurements.isEmpty {
                        // Initial symptom entry
                        VStack(spacing: 12) {
                            Image(systemName: "wrench.and.screwdriver")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)

                            Text("Describe the symptom")
                                .font(.headline)

                            TextField("e.g. 'DC offset on output', 'no audio left channel', 'distortion at high volume'", text: $symptom, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(3)

                            if apiKey.isEmpty {
                                SecureField("Anthropic API Key", text: $apiKey)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Button {
                                startDiagnosis()
                            } label: {
                                Label("Begin Diagnosis", systemImage: "stethoscope")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(symptom.isEmpty || apiKey.isEmpty || isLoading || circuit == nil)
                        }
                        .padding(32)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let step = currentStep {
                        // Current diagnostic step
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                // Instruction
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("Diagnostic Step \(measurements.count + 1)", systemImage: "stethoscope")
                                        .font(.headline)

                                    Text(step.description)
                                        .font(.body)
                                        .textSelection(.enabled)
                                }

                                Divider()

                                // Test details
                                HStack(spacing: 24) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Test Point")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Button {
                                            onHighlightComponent?(step.testPoint)
                                        } label: {
                                            Text(step.testPoint)
                                                .font(.system(.title3, design: .monospaced, weight: .bold))
                                                .foregroundStyle(.blue)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Click to highlight in 3D view")
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Measurement")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(step.measurementType)
                                            .font(.body)
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Expected")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(step.expectedValue)
                                            .font(.system(.body, design: .monospaced, weight: .bold))
                                            .foregroundStyle(.green)
                                    }
                                }

                                Divider()

                                // Measurement entry
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Enter your measured value:")
                                        .font(.callout.bold())

                                    HStack {
                                        TextField("e.g. +18.5V, 4.7kΩ, 0V", text: $measuredValue)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(.body, design: .monospaced))
                                            .onSubmit { submitMeasurement() }

                                        Button {
                                            submitMeasurement()
                                        } label: {
                                            Label("Next Step", systemImage: "arrow.right.circle.fill")
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .disabled(measuredValue.isEmpty || isLoading)
                                    }
                                }
                            }
                            .padding(24)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    if isLoading {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Claude is analyzing...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.bottom, 8)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func startDiagnosis() {
        guard let circuit, !symptom.isEmpty else { return }
        UserDefaults.standard.set(apiKey, forKey: "anthropic_api_key")
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let service = ClaudeAPIService(apiKey: apiKey)
                let step = try await service.guidedTroubleshoot(
                    circuit: circuit,
                    symptom: symptom
                )
                currentStep = step
                onHighlightComponent?(step.testPoint)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func submitMeasurement() {
        guard let step = currentStep, !measuredValue.isEmpty, let circuit else { return }

        measurements.append((
            testPoint: step.testPoint,
            expected: step.expectedValue,
            measured: measuredValue
        ))

        measuredValue = ""
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let service = ClaudeAPIService(apiKey: apiKey)
                let nextStep = try await service.guidedTroubleshoot(
                    circuit: circuit,
                    symptom: symptom,
                    previousMeasurements: measurements
                )
                currentStep = nextStep
                onHighlightComponent?(nextStep.testPoint)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
