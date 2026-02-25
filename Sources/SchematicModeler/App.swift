import SwiftUI
import AppKit

@main
struct SchematicModelerApp: App {
    init() {
        // Required for SPM-based macOS apps to appear as a foreground GUI app
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        // Set app icon from bundled resource
        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1400, height: 900)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Circuit JSON...") {
                    NotificationCenter.default.post(name: .openCircuitJSON, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command])

                Divider()

                Button("Load Demo Circuit") {
                    NotificationCenter.default.post(name: .loadDemoCircuit, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("Import Schematic Image...") {
                    NotificationCenter.default.post(name: .importSchematic, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Button("Browse Service Manuals...") {
                    NotificationCenter.default.post(name: .browseManuals, object: nil)
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @AppStorage("anthropic_api_key") private var apiKey = ""
    private var usage: APIUsageTracker { APIUsageTracker.shared }

    var body: some View {
        Form {
            Section("Claude API") {
                SecureField("Anthropic API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                Text("Used for schematic analysis and circuit explanation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Session Usage") {
                LabeledContent("Requests") {
                    Text("\(usage.requestCount)")
                        .monospacedDigit()
                }
                LabeledContent("Input Tokens") {
                    Text("\(usage.totalInputTokens.formatted())")
                        .monospacedDigit()
                }
                LabeledContent("Output Tokens") {
                    Text("\(usage.totalOutputTokens.formatted())")
                        .monospacedDigit()
                }
                LabeledContent("Estimated Cost") {
                    Text(usage.formattedCost)
                        .monospacedDigit()
                        .foregroundStyle(usage.estimatedCost > 1.0 ? .orange : .secondary)
                }

                Button("Reset Usage Counter") {
                    usage.reset()
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 320)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let loadDemoCircuit = Notification.Name("loadDemoCircuit")
    static let importSchematic = Notification.Name("importSchematic")
    static let openCircuitJSON = Notification.Name("openCircuitJSON")
    static let browseManuals = Notification.Name("browseManuals")
}
