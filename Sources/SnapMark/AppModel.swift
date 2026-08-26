import AppKit
import Combine

enum CaptureMode: CaseIterable, Equatable {
    case area
    case window
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var session: EditorSession?
    @Published var isCapturing = false
    @Published var isOpeningHistory = false
    @Published private(set) var hasScreenRecordingPermission = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    let preferences: AppPreferences
    let history: HistoryStore

    private let captureService = CaptureService()
    private let selectionController = SelectionOverlayController()
    private let launchLocation: RunningBundleLocation
    private var statusTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var historyLoadTask: Task<Void, Never>?
    private var activeCaptureID: UUID?
    private var activeHistoryLoadID: UUID?
    private var concealedWindows: [NSWindow] = []

    private init() {
        preferences = AppPreferences()
        history = HistoryStore()
        launchLocation = RunningBundleLocation()
        hasScreenRecordingPermission = captureService.hasScreenRecordingPermission

        if ProcessInfo.processInfo.environment["SNAPMARK_DEMO"] == "1",
           let image = DemoImageFactory.make() {
            session = EditorSession(image: image)
        }
    }

    var isBusy: Bool {
        isCapturing || isOpeningHistory
    }

    func beginCapture(_ mode: CaptureMode) {
        guard !isBusy else { return }
        guard launchLocation.isAvailable() else {
            refreshHistory()
            errorMessage = "SnapMark was moved while it was open. Quit this copy and reopen SnapMark from Applications."
            return
        }

        statusTask?.cancel()
        let captureID = UUID()
        activeCaptureID = captureID
        isCapturing = true
        statusMessage = preferences.delaySeconds > 0 ? "Starting timer…" : "Preparing capture…"
        captureTask = Task { [weak self] in
            await self?.performCapture(mode, captureID: captureID)
        }
    }

    func open(_ item: HistoryItem) {
        guard !isBusy else { return }
        statusTask?.cancel()
        historyLoadTask?.cancel()
        let loadID = UUID()
        activeHistoryLoadID = loadID
        isOpeningHistory = true
        statusMessage = "Opening capture…"
        historyLoadTask = Task { [weak self] in
            let image = await Task.detached(priority: .userInitiated) {
                HistoryStore.loadImage(at: item.url)
            }.value
            guard let self else { return }
            defer { self.finishHistoryLoad(loadID) }
            guard !Task.isCancelled, self.activeHistoryLoadID == loadID else { return }
            guard let image else {
                self.history.reload()
                self.errorMessage = "That capture could not be opened. It may have been moved or deleted."
                return
            }
            self.session = EditorSession(image: image)
            self.bringMainWindowForward()
        }
    }

    func closeEditor() {
        session = nil
        refreshHistory()
    }

    func refreshHistory() {
        history.reload()
    }

    func refreshAuthorization() {
        hasScreenRecordingPermission = captureService.hasScreenRecordingPermission
    }

    func cancelCapture() {
        guard let captureID = activeCaptureID else { return }
        captureTask?.cancel()
        selectionController.cancelSelection()
        revealAfterCapture()
        finishCapture(captureID)
        bringMainWindowForward()
    }

    func copy() {
        guard let image = renderedImage() else { return }
        do {
            try ExportService.copyToClipboard(image)
            showStatus("Copied to clipboard")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() {
        guard let image = renderedImage() else { return }
        do {
            if let url = try ExportService.showSavePanel(for: image, suggestedName: suggestedFilename()) {
                showStatus("Saved \(url.lastPathComponent)")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func share() {
        guard let image = renderedImage() else { return }
        ExportService.showSharePicker(for: image)
    }

    func undo() { session?.undo() }
    func redo() { session?.redo() }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func showMainWindow() {
        refreshHistory()
        bringMainWindowForward()
    }

    private func performCapture(_ mode: CaptureMode, captureID: UUID) async {
        defer { finishCapture(captureID) }

        do {
            if preferences.delaySeconds > 0 {
                for remaining in stride(from: preferences.delaySeconds, through: 1, by: -1) {
                    statusMessage = "Capturing in \(remaining)…"
                    try await Task.sleep(for: .seconds(1))
                }
            }

            let route = try CaptureRoute.resolve(
                mode: mode,
                hasFullScreenRecordingAccess: captureService.hasScreenRecordingPermission
            )

            if route == .authorizationRequired {
                throw CaptureServiceError.authorizationRefreshRequired
            }

            concealForCapture()
            try await Task.sleep(for: .milliseconds(160))
            try Task.checkCancellation()

            switch route {
            case .systemWindowCapture:
                statusMessage = "Click a window to capture • Esc to cancel"
                let image = try await captureService.captureWindowUsingSystemTool()
                revealAfterCapture()
                guard let image else { return }
                try Task.checkCancellation()
                guard activeCaptureID == captureID else { return }
                openCapturedImage(image)
                return

            case .systemAreaCapture:
                guard let desktop = SelectionDesktop(displayFrames: NSScreen.screens.map(\.frame)) else {
                    throw CaptureServiceError.noDisplays
                }
                statusMessage = nil
                guard let selection = await selectionController.select(on: desktop) else {
                    bringMainWindowForward()
                    return
                }
                try Task.checkCancellation()
                guard activeCaptureID == captureID else { return }

                statusMessage = "Capturing selection…"
                try await Task.sleep(for: .milliseconds(80))
                let image = try await captureService.captureArea(
                    in: desktop.screenRect(for: selection)
                )
                try Task.checkCancellation()
                guard activeCaptureID == captureID else { return }
                openCapturedImage(image)
                return

            case .authorizationRequired:
                preconditionFailure("Authorization-required capture should stop before capture begins")
            }
        } catch is CancellationError {
            statusMessage = nil
            revealAfterCapture()
        } catch {
            statusMessage = nil
            errorMessage = error.localizedDescription
            bringMainWindowForward()
        }
        refreshAuthorization()
    }

    private func finishCapture(_ captureID: UUID) {
        guard activeCaptureID == captureID else { return }
        activeCaptureID = nil
        captureTask = nil
        isCapturing = false
        statusMessage = nil
    }

    private func finishHistoryLoad(_ loadID: UUID) {
        guard activeHistoryLoadID == loadID else { return }
        activeHistoryLoadID = nil
        historyLoadTask = nil
        isOpeningHistory = false
        statusMessage = nil
    }

    private func openCapturedImage(_ image: CGImage) {
        session = EditorSession(image: image)

        if preferences.keepHistory {
            do {
                _ = try history.save(image)
            } catch {
                errorMessage = "The screenshot opened, but its history copy could not be saved."
            }
        }
        if preferences.copyAfterCapture {
            try? ExportService.copyToClipboard(image)
        }
        bringMainWindowForward()
    }

    private func renderedImage() -> CGImage? {
        guard let session else { return nil }
        do {
            return try session.renderedImage()
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func suggestedFilename() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "SnapMark \(formatter.string(from: Date())).png"
    }

    private func showStatus(_ message: String) {
        statusTask?.cancel()
        statusMessage = message
        statusTask = Task {
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            statusMessage = nil
        }
    }

    private func bringMainWindowForward() {
        revealAfterCapture()
        NSApp.unhide(nil)
        let mainWindows = NSApp.windows.filter { window in
            window.level == .normal && !(window is NSPanel)
        }
        let window = mainWindows.first(where: \.isKeyWindow) ?? mainWindows.first
        mainWindows.filter { $0 !== window }.forEach { $0.close() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    private func concealForCapture() {
        guard concealedWindows.isEmpty else { return }
        concealedWindows = NSApp.windows.filter { window in
            window.isVisible && window.level == .normal && !(window is NSPanel)
        }
        concealedWindows.forEach { $0.orderOut(nil) }
    }

    private func revealAfterCapture() {
        NSApp.unhide(nil)
        let windows = concealedWindows
        concealedWindows = []
        windows.forEach { window in
            if !window.isVisible {
                window.orderFront(nil)
            }
        }
    }
}
