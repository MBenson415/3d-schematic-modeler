import SwiftUI

/// Right column: full-size schematic image preview with analyze/action buttons
struct SchematicPreviewView: View {
    @Bindable var viewModel: ManualBrowserViewModel
    var onAnalyzed: (Circuit) -> Void
    @AppStorage("anthropic_api_key") private var apiKey = ""

    var body: some View {
        Group {
            if let image = viewModel.selectedImage {
                VStack(spacing: 0) {
                    // Image preview
                    if let data = viewModel.loadedImageData, let nsImage = NSImage(data: data) {
                        ScrollView([.horizontal, .vertical]) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        ProgressView("Loading image...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    Divider()

                    // Metadata + actions
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(image.filename)
                                    .font(.system(.body, design: .monospaced, weight: .medium))
                                HStack(spacing: 12) {
                                    Label(image.boardID, systemImage: "cpu")
                                    Label(image.category.displayName, systemImage: image.category.systemImage)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }

                        if apiKey.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle")
                                Text("Set your Anthropic API key in Settings to enable analysis.")
                            }
                            .font(.caption)
                            .foregroundStyle(.orange)
                        }

                        if let error = viewModel.analysisError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        HStack {
                            Button {
                                viewModel.openInFinder(image)
                            } label: {
                                Label("Open in Finder", systemImage: "folder")
                            }

                            Spacer()

                            if viewModel.isAnalyzing {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Analyzing with Claude...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Button {
                                analyzeWithClaude()
                            } label: {
                                Label("Analyze with Claude", systemImage: "sparkles")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.loadedImageData == nil || apiKey.isEmpty || viewModel.isAnalyzing)
                        }
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "Select a Schematic",
                    systemImage: "photo",
                    description: Text("Choose a schematic image from the assembly browser to preview it.")
                )
            }
        }
    }

    private func analyzeWithClaude() {
        Task {
            do {
                let circuit = try await viewModel.analyzeSelectedImage()
                onAnalyzed(circuit)
            } catch {
                // Error is already set in viewModel
            }
        }
    }
}
