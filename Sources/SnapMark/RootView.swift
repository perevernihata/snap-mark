import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            if let session = model.session {
                EditorView(session: session)
            } else {
                WelcomeView()
            }

            if model.isBusy || model.statusMessage != nil {
                VStack {
                    Spacer()
                    StatusPill(
                        text: model.statusMessage ?? "Preparing capture…",
                        showsProgress: model.isBusy,
                        showsCancel: model.isCapturing,
                        onCancel: { model.cancelCapture() }
                    )
                    .padding(.bottom, 24)
                }
            }
        }
        .background(WindowSetupView().frame(width: 0, height: 0))
        .alert(
            "SnapMark",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            if model.errorMessage?.contains("Screen Recording") == true {
                Button("Open System Settings") { model.openScreenRecordingSettings() }
            }
            if model.errorMessage?.contains("moved while it was open") == true {
                Button("Quit SnapMark") { NSApp.terminate(nil) }
            }
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "Something went wrong.")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshHistory()
            model.refreshAuthorization()
        }
    }
}

private struct StatusPill: View {
    let text: String
    let showsProgress: Bool
    let showsCancel: Bool
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Text(text)
                .font(.system(size: 13, weight: .medium))
            if showsCancel {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.borderless)
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.18)))
        .shadow(color: .black.opacity(0.24), radius: 16, y: 7)
    }
}
