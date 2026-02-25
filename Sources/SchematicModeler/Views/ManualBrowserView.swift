import SwiftUI

/// Main manual browser window — 3-column NavigationSplitView
struct ManualBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ManualBrowserViewModel()
    var onCircuitLoaded: (Circuit) -> Void

    var body: some View {
        NavigationSplitView {
            ManualListSidebar(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 350)
        } content: {
            AssemblyBrowserView(viewModel: viewModel, onCircuitLoaded: onCircuitLoaded)
                .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
        } detail: {
            SchematicPreviewView(viewModel: viewModel) { circuit in
                onCircuitLoaded(circuit)
            }
        }
        .navigationTitle("Service Manual Browser")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .frame(minWidth: 1000, minHeight: 600)
        .task {
            await viewModel.loadManuals()
        }
    }
}
