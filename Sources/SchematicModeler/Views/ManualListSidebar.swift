import SwiftUI

/// Left column: brand/model search + list of extracted manuals
struct ManualListSidebar: View {
    @Bindable var viewModel: ManualBrowserViewModel
    @State private var manualToDelete: ServiceManual?

    var body: some View {
        VStack(spacing: 0) {
            // Search form
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Search Service Manual")
                        .font(.headline)

                    TextField("Brand (e.g. Pioneer)", text: $viewModel.searchBrand)
                        .textFieldStyle(.roundedBorder)

                    TextField("Model (e.g. SX-750)", text: $viewModel.searchModel)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button("Search") {
                            Task { await viewModel.searchForManual() }
                        }
                        .disabled(viewModel.searchBrand.isEmpty && viewModel.searchModel.isEmpty)
                        .disabled(viewModel.isSearching)

                        if viewModel.isSearching {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if let error = viewModel.searchError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(8)

            // Search results
            if !viewModel.searchResults.isEmpty {
                List {
                    Section("Search Results") {
                        ForEach(viewModel.searchResults) { result in
                            Button {
                                Task { await viewModel.downloadAndExtract(url: result.url, title: result.title) }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title)
                                        .font(.caption)
                                        .lineLimit(2)
                                    Text(result.url)
                                        .font(.caption2)
                                        .foregroundStyle(.link)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .padding(.vertical, 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isExtracting)
                            .contextMenu {
                                Button("Download & Extract") {
                                    Task { await viewModel.downloadAndExtract(url: result.url, title: result.title) }
                                }
                                .disabled(viewModel.isExtracting)
                                Button("Copy URL") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(result.url, forType: .string)
                                }
                                Button("Open in Browser") {
                                    if let url = URL(string: result.url) {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .frame(maxHeight: 200)
            }

            Divider()

            // Extracted manuals with collapsible assemblies
            List(selection: Binding(
                get: { viewModel.selectedAssembly },
                set: { assembly in
                    if let assembly {
                        // Find the parent manual for this assembly
                        if let manual = viewModel.manuals.first(where: {
                            $0.boardAssemblies.contains(where: { $0.id == assembly.id })
                        }) {
                            viewModel.selectManual(manual)
                        }
                        viewModel.selectAssembly(assembly)
                    } else {
                        viewModel.selectAssembly(nil)
                    }
                }
            )) {
                ForEach(viewModel.manuals) { manual in
                    DisclosureGroup {
                        ForEach(manual.boardAssemblies) { assembly in
                            HStack(spacing: 4) {
                                Image(systemName: viewModel.isCached(manual: manual, assembly: assembly)
                                      ? "checkmark.circle.fill" : "cpu")
                                    .foregroundStyle(viewModel.isCached(manual: manual, assembly: assembly)
                                                     ? .green : .secondary)
                                    .font(.caption)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(assembly.id)
                                        .font(.caption.monospaced())
                                    if assembly.name != assembly.id {
                                        Text(assembly.name)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .tag(assembly)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(manual.name)
                                .font(.body.bold())
                            HStack {
                                Text("\(manual.boardAssemblies.count) assemblies")
                                Text("\(manual.totalPages) pages")
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .contextMenu {
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([manual.directoryURL])
                            }
                            Divider()
                            Button("Delete...", role: .destructive) {
                                manualToDelete = manual
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .confirmationDialog(
                "Delete \(manualToDelete?.name ?? "")?",
                isPresented: Binding(
                    get: { manualToDelete != nil },
                    set: { if !$0 { manualToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let manual = manualToDelete {
                        viewModel.deleteManual(manual)
                    }
                    manualToDelete = nil
                }
            } message: {
                Text("This will permanently remove the extracted manual and all cached circuits from disk.")
            }

            Divider()

            // Import PDF button
            HStack {
                Button {
                    viewModel.importPDF()
                } label: {
                    Label("Import PDF...", systemImage: "doc.badge.plus")
                }
                .disabled(viewModel.isExtracting)

                if viewModel.isExtracting {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()
            }
            .padding(8)

            if !viewModel.extractionStatus.isEmpty {
                Text(viewModel.extractionStatus)
                    .font(.caption2)
                    .foregroundStyle(
                        viewModel.extractionStatus.hasPrefix("Error")
                            || viewModel.extractionStatus.contains("not found")
                            ? .red : .secondary
                    )
                    .lineLimit(4)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
            }
        }
    }
}
