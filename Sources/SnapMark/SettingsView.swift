import SwiftUI

struct SettingsView: View {
    @ObservedObject private var preferences = AppModel.shared.preferences
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Capture") {
                Picker("Delay", selection: $preferences.delaySeconds) {
                    Text("None").tag(0)
                    Text("3 seconds").tag(3)
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                }
                Toggle("Copy immediately after capture", isOn: $preferences.copyAfterCapture)
            }

            Section("Privacy") {
                Toggle("Keep the latest 30 captures on this Mac", isOn: $preferences.keepHistory)
                LabeledContent("Capture access") {
                    Label("Managed by macOS", systemImage: "checkmark.shield")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Shortcut") {
                LabeledContent("Capture area") {
                    Text("⌃⇧⌘4")
                        .font(.system(.body, design: .monospaced, weight: .medium))
                }
                LabeledContent("Capture window") {
                    Text("⇧⌘5")
                        .font(.system(.body, design: .monospaced, weight: .medium))
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 380)
    }
}
