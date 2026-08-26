import SwiftUI
import Darwin

@main
struct SnapMarkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel

    init() {
        if CommandLine.arguments.contains("--self-test") {
            exit(SelfTestRunner.run())
        }
        _model = StateObject(wrappedValue: AppModel.shared)
    }

    var body: some Scene {
        Window("SnapMark", id: "main") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 940, minHeight: 620)
        }
        .defaultSize(width: 1080, height: 700)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Capture area") { model.beginCapture(.area) }
                    .keyboardShortcut("2", modifiers: [.command, .shift])
                Button("Capture window") { model.beginCapture(.window) }
                    .keyboardShortcut("5", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { model.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(model.session?.canUndo != true)
                Button("Redo") { model.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(model.session?.canRedo != true)
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save screenshot…") { model.save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(model.session == nil)
            }
        }

        MenuBarExtra("SnapMark", systemImage: "viewfinder") {
            Button("Capture area") { model.beginCapture(.area) }
            Button("Capture window") { model.beginCapture(.window) }
            Divider()
            Button("Show SnapMark") { model.showMainWindow() }
            Button("Open captures folder") { model.history.revealInFinder() }
                .disabled(model.history.items.isEmpty)
            SettingsLink { Text("Settings…") }
            Divider()
            Button("Quit SnapMark") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}
