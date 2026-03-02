import SwiftUI
import SceneKit

/// Main application content view with 3-column layout
struct ContentView: View {
    @State private var viewModel = CircuitViewModel()
    @State private var manualBrowserVM = ManualBrowserViewModel()
    @State private var showInspector = true
    @State private var showAssemblyBrowser = true
    @State private var showImportSheet = false
    @State private var showExportSheet = false
    @State private var showTroubleshootSheet = false
    @State private var showManualBrowser = false
    @State private var isLoadingHeatMap = false
    @State private var isLoadingVoltages = false

    var body: some View {
        HSplitView {
            // Far-left — assembly browser
            if showAssemblyBrowser {
                AssemblyListSidebar(
                    viewModel: manualBrowserVM,
                    onCircuitLoaded: { circuit in
                        viewModel.loadCircuit(circuit)
                    },
                    onAssemblySelected: { manual, assembly in
                        viewModel.showEmptyBoard(assemblyName: "\(assembly.id) — \(assembly.name)")
                    }
                )
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)
            }

            // Left sidebar — component list (hidden when no circuit loaded)
            if viewModel.circuit != nil {
                ComponentListView(
                    circuit: viewModel.circuit,
                    selectedComponentID: viewModel.selectedComponentID,
                    onSelect: { viewModel.selectComponent($0) }
                )
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
            }

            // Center — 3D scene + bottom explanation
            VStack(spacing: 0) {
                // 3D View
                SceneKitView(
                    scene: viewModel.scene,
                    onComponentSelected: { designator in
                        viewModel.selectComponent(designator)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    // Verbose analysis progress bar
                    if manualBrowserVM.isAnalyzing {
                        AnalysisProgressOverlay(progress: manualBrowserVM.analysisProgress)
                    }
                    // Empty board — assembly selected but not yet analyzed
                    else if viewModel.pendingAssemblyName != nil && viewModel.circuit == nil {
                        EmptyBoardOverlay(
                            assemblyName: viewModel.pendingAssemblyName ?? "",
                            isAnalyzing: manualBrowserVM.isAnalyzing,
                            onAnalyze: { analyzeCurrentAssembly() }
                        )
                    }
                }

                Divider()

                // Bottom — troubleshoot panel or circuit explanation
                if showTroubleshootSheet {
                    GuidedTroubleshootView(
                        circuit: viewModel.circuit,
                        onHighlightComponent: { designator in
                            viewModel.selectComponent(designator)
                        },
                        onDismiss: { showTroubleshootSheet = false }
                    )
                    .frame(minHeight: 280, idealHeight: 320)
                } else {
                    CircuitExplanationView(
                        circuit: viewModel.circuit,
                        explanation: viewModel.circuitExplanation,
                        selectedBlockID: viewModel.selectedBlockID,
                        onBlockSelected: { blockID in
                            viewModel.selectBlock(blockID)
                        }
                    )
                    .frame(height: 180)
                }
            }
            .frame(minWidth: 400)

            // Right sidebar — component detail
            if showInspector, let component = viewModel.selectedComponent {
                ComponentDetailView(
                    component: component,
                    connectedNets: viewModel.connectedNets,
                    circuit: viewModel.circuit,
                    onAddAnnotation: { designator, note in
                        viewModel.addAnnotation(to: designator, note: note)
                    },
                    onRemoveAnnotation: { designator, index in
                        viewModel.removeAnnotation(from: designator, at: index)
                    }
                )
                .frame(minWidth: 250, idealWidth: 280, maxWidth: 350)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showManualBrowser = true
                } label: {
                    Label("Browse Manuals", systemImage: "books.vertical")
                }
                .help("Browse service manuals for schematics")

                Button {
                    showImportSheet = true
                } label: {
                    Label("Import Schematic", systemImage: "photo.badge.plus")
                }
                .help("Analyze a schematic image with Claude Vision")

                Button {
                    viewModel.loadDemoCircuit()
                } label: {
                    Label("Load Demo", systemImage: "cpu")
                }
                .help("Load Pioneer SX-750 Power Amp demo circuit")

                Button {
                    showTroubleshootSheet.toggle()
                } label: {
                    Label("Troubleshoot", systemImage: showTroubleshootSheet ? "wrench.and.screwdriver.fill" : "wrench.and.screwdriver")
                }
                .help(showTroubleshootSheet ? "Close troubleshooting panel" : "Guided step-by-step troubleshooting")
                .disabled(viewModel.circuit == nil)

                Button {
                    toggleHeatMap()
                } label: {
                    Label("Heat Map", systemImage: viewModel.heatMapActive ? "flame.fill" : "flame")
                }
                .help(viewModel.heatMapActive ? "Hide failure heat map" : "Show failure probability heat map")
                .disabled(viewModel.circuit == nil || isLoadingHeatMap)

                Button {
                    toggleVoltages()
                } label: {
                    Label("Voltages", systemImage: viewModel.showVoltages ? "bolt.fill" : "bolt")
                }
                .help(viewModel.showVoltages ? "Hide voltage overlay" : "Show expected DC voltages")
                .disabled(viewModel.circuit == nil || isLoadingVoltages)

                Button {
                    exportCircuit()
                } label: {
                    Label("Export JSON", systemImage: "square.and.arrow.up")
                }
                .help("Export circuit as JSON")
                .disabled(viewModel.circuit == nil)

                Button {
                    showAssemblyBrowser.toggle()
                } label: {
                    Label("Assemblies", systemImage: "sidebar.left")
                }
                .help("Toggle assembly browser")

                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .help("Toggle component inspector")

                // API usage indicator
                if APIUsageTracker.shared.requestCount > 0 {
                    Text(APIUsageTracker.shared.formattedCost)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .help("\(APIUsageTracker.shared.formattedTokens) across \(APIUsageTracker.shared.requestCount) requests")
                }
            }
        }
        .sheet(isPresented: $showImportSheet) {
            SchematicImportView { circuit in
                viewModel.loadCircuit(circuit)
            }
        }
        .sheet(isPresented: $showManualBrowser, onDismiss: {
            Task { await manualBrowserVM.loadManuals() }
        }) {
            ManualBrowserView(viewModel: manualBrowserVM) { circuit in
                viewModel.loadCircuit(circuit)
                showManualBrowser = false
            }
        }
        .onAppear {
            viewModel.loadDemoCircuit()
        }
    }

    private func analyzeCurrentAssembly() {
        guard manualBrowserVM.selectedAssembly != nil else { return }
        Task {
            do {
                let circuit = try await manualBrowserVM.analyzeSelectedAssembly()
                viewModel.loadCircuit(circuit)
            } catch {
                // Error shown in manualBrowserVM.analysisError
            }
        }
    }

    private func toggleHeatMap() {
        if viewModel.heatMapActive {
            viewModel.clearHeatMap()
            return
        }
        guard let circuit = viewModel.circuit else { return }
        let apiKey = UserDefaults.standard.string(forKey: "anthropic_api_key") ?? ""
        guard !apiKey.isEmpty else { return }
        isLoadingHeatMap = true
        Task {
            do {
                let service = ClaudeAPIService(apiKey: apiKey)
                let probs = try await service.assessFailureProbabilities(circuit: circuit)
                viewModel.failureProbabilities = probs
                viewModel.applyHeatMap()
            } catch {
                // Silently fail — could add error display later
            }
            isLoadingHeatMap = false
        }
    }

    private func toggleVoltages() {
        if viewModel.showVoltages {
            viewModel.toggleVoltageOverlay()
            return
        }
        guard let circuit = viewModel.circuit else { return }
        let apiKey = UserDefaults.standard.string(forKey: "anthropic_api_key") ?? ""
        guard !apiKey.isEmpty else { return }
        isLoadingVoltages = true
        Task {
            do {
                let service = ClaudeAPIService(apiKey: apiKey)
                let voltages = try await service.analyzeExpectedVoltages(circuit: circuit)
                viewModel.expectedVoltages = voltages
                viewModel.toggleVoltageOverlay()
            } catch {
                // Silently fail
            }
            isLoadingVoltages = false
        }
    }

    private func exportCircuit() {
        guard let json = viewModel.exportCircuitJSON() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(viewModel.circuit?.name ?? "circuit").json"

        if panel.runModal() == .OK, let url = panel.url {
            try? json.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Empty Board Overlay

struct EmptyBoardOverlay: View {
    let assemblyName: String
    let isAnalyzing: Bool
    var onAnalyze: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cpu")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(assemblyName)
                .font(.title3.bold())
            Text("This assembly has not been analyzed yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                onAnalyze()
            } label: {
                Label("Analyze with Claude", systemImage: "sparkles")
                    .font(.body.bold())
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isAnalyzing)
        }
        .padding(32)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Analysis Progress Overlay

struct AnalysisProgressOverlay: View {
    let progress: String

    @State private var elapsedSeconds = 0
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)

            Text(progress.isEmpty ? "Starting analysis..." : progress)
                .font(.callout.bold())
                .multilineTextAlignment(.center)

            Text(timeString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Text("Claude is analyzing schematic images.\nThis typically takes 30–90 seconds.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(minWidth: 280)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            elapsedSeconds = 0
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [self] _ in
                Task { @MainActor in
                    self.elapsedSeconds += 1
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private var timeString: String {
        let mins = elapsedSeconds / 60
        let secs = elapsedSeconds % 60
        return String(format: "Elapsed: %d:%02d", mins, secs)
    }
}
