import SwiftUI

/// Left column: brand/model search + list of extracted manuals
struct ManualListSidebar: View {
    @Bindable var viewModel: ManualBrowserViewModel

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
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title)
                                    .font(.caption)
                                    .lineLimit(2)
                                Text(result.url)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .padding(.vertical, 2)
                            .contextMenu {
                                Button("Copy URL") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(result.url, forType: .string)
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .frame(maxHeight: 200)
            }

            Divider()

            // Extracted manuals
            List(viewModel.manuals, selection: Binding(
                get: { viewModel.selectedManual },
                set: { viewModel.selectManual($0) }
            )) { manual in
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
                .tag(manual)
            }
            .listStyle(.sidebar)

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
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
            }
        }
    }
}
