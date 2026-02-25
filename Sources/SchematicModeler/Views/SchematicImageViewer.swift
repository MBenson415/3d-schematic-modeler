import SwiftUI
import AppKit

/// In-app gallery sheet for viewing schematic and parts-list images
struct SchematicImageViewer: View {
    let images: [SchematicImage]
    let assemblyName: String
    var initialIndex: Int = 0

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex: Int = 0
    @State private var loadedImages: [String: NSImage] = [:]
    @State private var zoomScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text(assemblyName)
                    .font(.headline)
                Spacer()
                Text("\(selectedIndex + 1) of \(images.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            HSplitView {
                // Left: thumbnail strip
                thumbnailSidebar
                    .frame(minWidth: 160, idealWidth: 200, maxWidth: 260)

                // Right: main image
                mainImageView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            // Bottom bar
            bottomBar
        }
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            selectedIndex = min(initialIndex, images.count - 1)
        }
        .onKeyPress(.leftArrow) {
            navigatePrevious()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            navigateNext()
            return .handled
        }
    }

    // MARK: - Thumbnail Sidebar

    private var thumbnailSidebar: some View {
        ScrollViewReader { proxy in
            List(selection: Binding(
                get: { selectedIndex },
                set: { selectedIndex = $0; zoomScale = 1.0 }
            )) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                    thumbnailRow(image, index: index)
                        .tag(index)
                        .id(index)
                }
            }
            .listStyle(.sidebar)
            .onChange(of: selectedIndex) { _, newValue in
                withAnimation {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private func thumbnailRow(_ image: SchematicImage, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Thumbnail
            Group {
                if let nsImage = loadedImages[image.id] {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .overlay {
                            ProgressView()
                                .controlSize(.small)
                        }
                }
            }
            .frame(height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // Label
            Text(image.filename)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)

            // Category badge
            Label(image.category.displayName, systemImage: image.category.systemImage)
                .font(.caption2)
                .foregroundStyle(image.category == .schematic ? .blue : .orange)
        }
        .padding(.vertical, 4)
        .task {
            await loadThumbnail(for: image)
        }
    }

    // MARK: - Main Image

    private var mainImageView: some View {
        Group {
            if images.indices.contains(selectedIndex) {
                let image = images[selectedIndex]
                if let nsImage = loadedImages[image.id] {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(zoomScale)
                            .frame(
                                width: nsImage.size.width * zoomScale,
                                height: nsImage.size.height * zoomScale
                            )
                    }
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                let newScale = max(0.25, min(zoomScale * value.magnification, 5.0))
                                zoomScale = newScale
                            }
                    )
                    .background(Color.black.opacity(0.03))
                } else {
                    ProgressView("Loading image...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .task(id: selectedIndex) {
                            await loadFullImage(for: image)
                        }
                }
            } else {
                ContentUnavailableView("No Images", systemImage: "photo.on.rectangle.angled")
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            if images.indices.contains(selectedIndex) {
                let image = images[selectedIndex]

                Label(image.category.displayName, systemImage: image.category.systemImage)
                    .font(.caption)
                    .foregroundStyle(image.category == .schematic ? .blue : .orange)

                Text(image.filename)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Zoom controls
            HStack(spacing: 8) {
                Button {
                    zoomScale = max(0.25, zoomScale - 0.25)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)

                Text("\(Int(zoomScale * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 40)

                Button {
                    zoomScale = min(5.0, zoomScale + 0.25)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)

                Button {
                    zoomScale = 1.0
                } label: {
                    Text("Fit")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            Divider()
                .frame(height: 16)

            // Navigation
            HStack(spacing: 4) {
                Button {
                    navigatePrevious()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .disabled(selectedIndex == 0)

                Button {
                    navigateNext()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
                .disabled(selectedIndex >= images.count - 1)
            }

            Divider()
                .frame(height: 16)

            if images.indices.contains(selectedIndex) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([images[selectedIndex].fileURL])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Navigation

    private func navigatePrevious() {
        if selectedIndex > 0 {
            selectedIndex -= 1
            zoomScale = 1.0
        }
    }

    private func navigateNext() {
        if selectedIndex < images.count - 1 {
            selectedIndex += 1
            zoomScale = 1.0
        }
    }

    // MARK: - Image Loading

    private func loadThumbnail(for image: SchematicImage) async {
        guard loadedImages[image.id] == nil else { return }
        await loadFullImage(for: image)
    }

    private func loadFullImage(for image: SchematicImage) async {
        guard loadedImages[image.id] == nil else { return }
        do {
            let data = try Data(contentsOf: image.fileURL)
            if let nsImage = NSImage(data: data) {
                loadedImages[image.id] = nsImage
            }
        } catch {
            // Image failed to load — leave nil
        }
    }
}
