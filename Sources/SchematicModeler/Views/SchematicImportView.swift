import SwiftUI
import UniformTypeIdentifiers

/// Sheet for importing and analyzing schematic images
struct SchematicImportView: View {
    @Environment(\.dismiss) private var dismiss
    var onCircuitLoaded: (Circuit) -> Void

    @State private var selectedImageURL: URL?
    @State private var imageData: Data?
    @State private var contextText: String = ""
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var apiKey: String = UserDefaults.standard.string(forKey: "anthropic_api_key") ?? ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Import Schematic")
                .font(.title2.bold())

            // API Key
            if apiKey.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Anthropic API Key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("sk-ant-...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                    Text("Required for schematic analysis. Your key is stored locally.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Image selection
            GroupBox("Schematic Image") {
                VStack(spacing: 12) {
                    if let imageData, let nsImage = NSImage(data: imageData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        ContentUnavailableView(
                            "Drop or Select Image",
                            systemImage: "photo.on.rectangle",
                            description: Text("PNG, JPG, or PDF schematic image")
                        )
                        .frame(height: 200)
                    }

                    Button("Choose Image...") {
                        selectImage()
                    }
                }
                .padding()
            }

            // Context
            GroupBox("Context (optional)") {
                TextField("e.g. Pioneer SX-750 power amplifier assembly AWH-046", text: $contextText)
                    .textFieldStyle(.roundedBorder)
            }

            // Error
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            // Actions
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                if isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                    Text("Analyzing schematic...")
                        .foregroundStyle(.secondary)
                }

                Button("Analyze") {
                    analyzeSchematic()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(imageData == nil || apiKey.isEmpty || isAnalyzing)
            }

            // Manual file path input for ~/Claude-Manuals images
            GroupBox("Or Load from Claude-Manuals") {
                HStack {
                    Button("Browse Claude-Manuals...") {
                        browseClaudeManuals()
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 600)
    }

    private func selectImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .pdf]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            selectedImageURL = url
            imageData = try? Data(contentsOf: url)
        }
    }

    private func browseClaudeManuals() {
        let manualsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Claude-Manuals")

        let panel = NSOpenPanel()
        panel.directoryURL = manualsPath
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            selectedImageURL = url
            imageData = try? Data(contentsOf: url)

            // Auto-fill context from file path
            if contextText.isEmpty {
                let pathComponents = url.deletingLastPathComponent().lastPathComponent
                contextText = pathComponents.replacingOccurrences(of: "-", with: " ").capitalized
            }
        }
    }

    private func analyzeSchematic() {
        guard let imageData else { return }

        // Save API key
        UserDefaults.standard.set(apiKey, forKey: "anthropic_api_key")

        isAnalyzing = true
        errorMessage = nil

        let service = ClaudeAPIService(apiKey: apiKey)
        let mimeType = selectedImageURL?.pathExtension == "png" ? "image/png" : "image/jpeg"

        Task {
            do {
                let circuit = try await service.analyzeSchematic(
                    imageData: imageData,
                    mimeType: mimeType,
                    context: contextText
                )
                await MainActor.run {
                    isAnalyzing = false
                    onCircuitLoaded(circuit)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isAnalyzing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
