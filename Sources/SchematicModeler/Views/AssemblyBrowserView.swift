import SwiftUI

/// Middle column: board assembly tree with expandable schematic/parts images
struct AssemblyBrowserView: View {
    @Bindable var viewModel: ManualBrowserViewModel
    var onCircuitLoaded: ((Circuit) -> Void)?

    var body: some View {
        Group {
            if let manual = viewModel.selectedManual {
                VStack(spacing: 0) {
                    List(selection: Binding(
                        get: { viewModel.selectedImage },
                        set: { viewModel.selectImage($0) }
                    )) {
                        ForEach(manual.boardAssemblies) { assembly in
                            Section {
                                // Analyze full board button
                                Button {
                                    viewModel.selectAssembly(assembly)
                                    analyzeAssembly(assembly)
                                } label: {
                                    Label {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Analyze Full Board")
                                                .font(.caption.bold())
                                            Text("\(assembly.allImages.count) images → 3D model")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    } icon: {
                                        Image(systemName: "sparkles")
                                    }
                                }
                                .buttonStyle(.borderless)
                                .tint(.accentColor)
                                .disabled(viewModel.isAnalyzing)

                                // Schematics
                                if !assembly.schematicImages.isEmpty {
                                    DisclosureGroup("Schematics (\(assembly.schematicImages.count))") {
                                        ForEach(assembly.schematicImages) { image in
                                            imageRow(image)
                                                .tag(image)
                                        }
                                    }
                                }

                                // Parts Lists
                                if !assembly.partsListImages.isEmpty {
                                    DisclosureGroup("Parts Lists (\(assembly.partsListImages.count))") {
                                        ForEach(assembly.partsListImages) { image in
                                            imageRow(image)
                                                .tag(image)
                                        }
                                    }
                                }
                            } header: {
                                HStack {
                                    Text(assembly.id)
                                        .font(.system(.caption, design: .monospaced, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.blue.opacity(0.15))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                    Text(assembly.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)

                    // Analysis progress bar
                    if viewModel.isAnalyzing {
                        VStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text(viewModel.analysisProgress)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial)
                    }

                    if let error = viewModel.analysisError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(8)
                    }
                }
            } else {
                ContentUnavailableView(
                    "Select a Manual",
                    systemImage: "book",
                    description: Text("Choose a manual from the list to browse its board assemblies.")
                )
            }
        }
    }

    private func imageRow(_ image: SchematicImage) -> some View {
        Label {
            Text(image.filename)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
        } icon: {
            Image(systemName: image.category.systemImage)
                .foregroundStyle(image.category == .schematic ? .blue : .orange)
        }
    }

    private func analyzeAssembly(_ assembly: BoardAssemblyRef) {
        Task {
            do {
                let circuit = try await viewModel.analyzeSelectedAssembly()
                onCircuitLoaded?(circuit)
            } catch {
                // Error is shown in viewModel.analysisError
            }
        }
    }
}
