import SwiftUI

/// Far-left sidebar for browsing manuals and board assemblies inline
struct AssemblyListSidebar: View {
    @Bindable var viewModel: ManualBrowserViewModel
    var onCircuitLoaded: (Circuit) -> Void
    /// Called when an uncached assembly is selected (shows empty board + analyze prompt)
    var onAssemblySelected: ((ServiceManual, BoardAssemblyRef) -> Void)?

    // Image viewer sheet state
    @State private var showImageViewer = false
    @State private var viewerImages: [SchematicImage] = []
    @State private var viewerAssemblyName = ""

    // Rename state
    @State private var renamingManualID: String?
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding(
                get: { viewModel.selectedAssembly },
                set: { assembly in
                    viewModel.selectAssembly(assembly)
                    guard let assembly else { return }
                    handleAssemblyTap(assembly)
                }
            )) {
                ForEach(viewModel.manuals) { manual in
                    DisclosureGroup {
                        ForEach(manual.boardAssemblies) { assembly in
                            assemblyRow(assembly, manual: manual)
                                .tag(assembly)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if viewModel.isCached(manual: manual, assembly: assembly) {
                                        Button(role: .destructive) {
                                            viewModel.deleteCachedCircuit(manual: manual, assembly: assembly)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            if renamingManualID == manual.id {
                                TextField("Manual name", text: $renameText, onCommit: {
                                    viewModel.renameManual(manual, to: renameText)
                                    renamingManualID = nil
                                })
                                .font(.caption.bold())
                                .textFieldStyle(.roundedBorder)
                            } else {
                                Text(manual.name)
                                    .font(.caption.bold())
                                    .foregroundStyle(.primary)
                            }
                            Text("\(manual.boardAssemblies.count) assemblies")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .contextMenu {
                            Button {
                                renameText = manual.name
                                renamingManualID = manual.id
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                viewModel.deleteManual(manual)
                            } label: {
                                Label("Delete Manual", systemImage: "trash")
                            }
                        }
                    }
                }
                .onMove { viewModel.moveManuals(from: $0, to: $1) }
            }
            .listStyle(.sidebar)

            // Analysis progress
            if viewModel.isAnalyzing {
                VStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(viewModel.analysisProgress)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
            }

            if let error = viewModel.analysisError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(6)
                    .lineLimit(3)
            }
        }
        .task {
            if viewModel.manuals.isEmpty {
                await viewModel.loadManuals()
            }
        }
        .sheet(isPresented: $showImageViewer) {
            SchematicImageViewer(
                images: viewerImages,
                assemblyName: viewerAssemblyName
            )
        }
    }

    private func assemblyRow(_ assembly: BoardAssemblyRef, manual: ServiceManual) -> some View {
        let cached = viewModel.isCached(manual: manual, assembly: assembly)
        return HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(assembly.id)
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                    if cached {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
                Text(assembly.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if !assembly.schematicImages.isEmpty {
                        Label("\(assembly.schematicImages.count)", systemImage: "doc.richtext")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                    if !assembly.partsListImages.isEmpty {
                        Label("\(assembly.partsListImages.count)", systemImage: "list.bullet.rectangle")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            if !cached {
                Button {
                    analyzeAssembly(assembly, manual: manual)
                } label: {
                    Image(systemName: "sparkles")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isAnalyzing)
                .help("Analyze \(assembly.id) with Claude")
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            if !assembly.schematicImages.isEmpty {
                Button {
                    openViewer(images: assembly.schematicImages, assemblyName: "\(assembly.id) — \(assembly.name)")
                } label: {
                    Label("View Schematics (\(assembly.schematicImages.count))", systemImage: "doc.richtext")
                }
            }

            if !assembly.partsListImages.isEmpty {
                Button {
                    openViewer(images: assembly.partsListImages, assemblyName: "\(assembly.id) — \(assembly.name)")
                } label: {
                    Label("View Parts Lists (\(assembly.partsListImages.count))", systemImage: "list.bullet.rectangle")
                }
            }

            if !assembly.allImages.isEmpty {
                Button {
                    openViewer(images: assembly.allImages, assemblyName: "\(assembly.id) — \(assembly.name)")
                } label: {
                    Label("View All Images (\(assembly.allImages.count))", systemImage: "photo.on.rectangle.angled")
                }
            }

            Divider()

            if let firstImage = assembly.allImages.first {
                Button {
                    let folderURL = firstImage.fileURL.deletingLastPathComponent()
                    NSWorkspace.shared.open(folderURL)
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
            }

            Divider()

            Button {
                analyzeAssembly(assembly, manual: manual)
            } label: {
                Label("Analyze with Claude", systemImage: "sparkles")
            }
            .disabled(viewModel.isAnalyzing)

            if cached {
                Button(role: .destructive) {
                    viewModel.deleteCachedCircuit(manual: manual, assembly: assembly)
                } label: {
                    Label("Delete Cache", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Actions

    private func openViewer(images: [SchematicImage], assemblyName: String) {
        viewerImages = images
        viewerAssemblyName = assemblyName
        showImageViewer = true
    }

    private func handleAssemblyTap(_ assembly: BoardAssemblyRef) {
        // Find the manual this assembly belongs to
        guard let manual = viewModel.manuals.first(where: { m in
            m.boardAssemblies.contains(where: { $0.id == assembly.id })
        }) else { return }

        viewModel.selectManual(manual)
        viewModel.selectedAssembly = assembly

        if viewModel.isCached(manual: manual, assembly: assembly),
           let circuit = viewModel.loadCachedCircuit(manual: manual, assembly: assembly) {
            onCircuitLoaded(circuit)
        } else {
            onAssemblySelected?(manual, assembly)
        }
    }

    private func analyzeAssembly(_ assembly: BoardAssemblyRef, manual: ServiceManual) {
        viewModel.selectManual(manual)
        viewModel.selectAssembly(assembly)
        Task {
            do {
                let circuit = try await viewModel.analyzeSelectedAssembly()
                onCircuitLoaded(circuit)
            } catch {
                // Error shown in viewModel.analysisError
            }
        }
    }
}
