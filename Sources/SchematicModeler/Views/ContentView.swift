import SwiftUI
import SceneKit

/// Main application content view with 3-column layout
struct ContentView: View {
    @State private var viewModel = CircuitViewModel()
    @State private var manualBrowserVM = ManualBrowserViewModel()
    @AppStorage("showInspector") private var showInspector = true
    @AppStorage("showAssemblyBrowser") private var showAssemblyBrowser = true
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
                // 3D View — ZStack so overlays render above the Metal-backed SCNView
                ZStack {
                    SceneKitView(
                        scene: viewModel.scene,
                        onComponentSelected: { designator in
                            viewModel.selectComponent(designator)
                        }
                    )

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
                .frame(maxWidth: .infinity, maxHeight: .infinity)

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
                    viewModel.toggleLayoutMode()
                } label: {
                    Label(
                        viewModel.layoutMode == .schematic ? "Pictorial" : "Schematic",
                        systemImage: viewModel.layoutMode == .schematic
                            ? "rectangle.3.group.fill" : "rectangle.3.group"
                    )
                }
                .help(viewModel.layoutMode == .schematic
                    ? "Switch to PCB (pictorial) layout"
                    : "Switch to schematic layout")
                .disabled(viewModel.circuit == nil)

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
    @State private var logLines: [String] = []

    var body: some View {
        VStack(spacing: 12) {
            // Determinate progress bar if we can parse a fraction, else indeterminate
            if let fraction = parsedFraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .frame(width: 220)
                Text("\(Int(fraction * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.regular)
            }

            // Current step
            Text(currentStep)
                .font(.callout.bold())
                .multilineTextAlignment(.center)
                .lineLimit(3)

            // Scrolling log of server output
            if !logLines.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(logLines.suffix(8).enumerated()), id: \.offset) { i, line in
                                Text(line)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .id(i)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 80)
                    .onChange(of: logLines.count) {
                        withAnimation {
                            proxy.scrollTo(logLines.suffix(8).count - 1, anchor: .bottom)
                        }
                    }
                }
            }

            Text(timeString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(24)
        .frame(minWidth: 320)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            elapsedSeconds = 0
            logLines = []
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
        .onChange(of: progress) {
            if !progress.isEmpty {
                logLines.append(progress)
            }
        }
    }

    /// The latest meaningful progress line to show as the main status
    private var currentStep: String {
        if progress.isEmpty { return "Starting analysis..." }
        return progress
    }

    /// Attempt to parse a progress fraction from the server output.
    /// Recognizes patterns like "Step 2/5", "3 of 7", "50%", "[2/4]"
    private var parsedFraction: Double? {
        let text = progress

        // Match "N%" pattern
        if let range = text.range(of: #"(\d+)%"#, options: .regularExpression) {
            let numStr = text[range].dropLast() // remove %
            if let n = Double(numStr), n > 0, n <= 100 {
                return n / 100.0
            }
        }

        // Match "N/M" or "N of M" pattern (step-style)
        let stepPatterns = [
            #"(\d+)\s*/\s*(\d+)"#,
            #"(\d+)\s+of\s+(\d+)"#,
            #"\[(\d+)/(\d+)\]"#,
        ]
        for pattern in stepPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               match.numberOfRanges >= 3,
               let r1 = Range(match.range(at: 1), in: text),
               let r2 = Range(match.range(at: 2), in: text),
               let current = Double(text[r1]),
               let total = Double(text[r2]),
               total > 0
            {
                return min(current / total, 1.0)
            }
        }

        return nil
    }

    private var timeString: String {
        let mins = elapsedSeconds / 60
        let secs = elapsedSeconds % 60
        return String(format: "Elapsed: %d:%02d", mins, secs)
    }
}
