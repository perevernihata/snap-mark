import AppKit
import CoreGraphics

enum CaptureServiceError: LocalizedError {
    case permissionDenied
    case noDisplays
    case areaCaptureFailed
    case authorizationRefreshRequired
    case systemCaptureFailed
    case timedOut(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen Recording access is off. Allow SnapMark in System Settings, then reopen the app."
        case .noDisplays:
            return "SnapMark could not find a display to capture."
        case .areaCaptureFailed:
            return "macOS could not capture the selected area. Try the selection again."
        case .authorizationRefreshRequired:
            return "SnapMark's Screen Recording switch belongs to an older build. Switch SnapMark off and back on once in System Settings, then reopen it."
        case .systemCaptureFailed:
            return "Screen Recording is still linked to an older SnapMark build. In System Settings, switch SnapMark off and on once, then try again."
        case let .timedOut(stage):
            return "\(stage) did not respond. Quit and reopen SnapMark, then try again."
        }
    }
}

@MainActor
final class CaptureService {
    private let displayTimeout: TimeInterval

    init(displayTimeout: TimeInterval = 8) {
        self.displayTimeout = displayTimeout
    }

    var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    func captureArea(in screenRect: CGRect) async throws -> CGImage {
        guard CGPreflightScreenCaptureAccess() else {
            throw CaptureServiceError.permissionDenied
        }
        let rect = screenRect.standardized
        guard rect.width > 0, rect.height > 0 else {
            throw CaptureServiceError.areaCaptureFailed
        }
        guard let primaryDisplayFrame = NSScreen.screens.first(where: {
            abs($0.frame.minX) < 0.5 && abs($0.frame.minY) < 0.5
        })?.frame else {
            throw CaptureServiceError.noDisplays
        }

        let captureRect = ScreenCaptureCoordinateSpace.quartzRect(
            fromAppKit: rect,
            primaryDisplayFrame: primaryDisplayFrame
        ).integral
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapMarkArea-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("area.png")
        let region = [
            Int(captureRect.minX),
            Int(captureRect.minY),
            Int(captureRect.width),
            Int(captureRect.height)
        ].map(String.init).joined(separator: ",")
        let status = try await AsyncTimeout.run(
            seconds: displayTimeout,
            timeoutError: CaptureServiceError.timedOut("Area capture")
        ) {
            try await SystemScreenshotProcess().run(
                arguments: ["-x", "-R\(region)", "-tpng", url.path]
            )
        }
        try Task.checkCancellation()

        guard status == 0, let image = HistoryStore.loadImage(at: url) else {
            throw CaptureServiceError.areaCaptureFailed
        }
        return image
    }

    /// Starts directly in macOS window-selection mode. One click captures the highlighted
    /// window; Escape returns nil without showing an error.
    func captureWindowUsingSystemTool() async throws -> CGImage? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapMarkWindow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("window.png")
        let status = try await SystemScreenshotProcess().run(
            arguments: ["-x", "-i", "-w", "-W", url.path]
        )
        try Task.checkCancellation()

        if status != 0 || !FileManager.default.fileExists(atPath: url.path) {
            return nil
        }
        guard let image = HistoryStore.loadImage(at: url) else {
            throw CaptureServiceError.systemCaptureFailed
        }
        return image
    }

}

enum ScreenCaptureCoordinateSpace {
    static func quartzRect(fromAppKit rect: CGRect, primaryDisplayFrame: CGRect) -> CGRect {
        let rect = rect.standardized
        return CGRect(
            x: rect.minX - primaryDisplayFrame.minX,
            y: primaryDisplayFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}

private final class SystemScreenshotProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var continuation: CheckedContinuation<Int32, Error>?
    private var terminalResult: Result<Int32, Error>?

    func run(arguments: [String]) async throws -> Int32 {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                start(arguments: arguments, continuation: continuation)
            }
        } onCancel: {
            cancel()
        }
    }

    private func start(arguments: [String], continuation: CheckedContinuation<Int32, Error>) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = arguments
        process.terminationHandler = { [weak self] process in
            self?.finish(.success(process.terminationStatus))
        }

        lock.lock()
        if let terminalResult {
            lock.unlock()
            continuation.resume(with: terminalResult)
            return
        }
        self.process = process
        self.continuation = continuation
        lock.unlock()

        lock.lock()
        let shouldRun = terminalResult == nil
        lock.unlock()
        guard shouldRun else { return }

        do {
            try process.run()
            lock.lock()
            let cancelledAfterLaunch = terminalResult != nil
            lock.unlock()
            if cancelledAfterLaunch, process.isRunning {
                process.terminate()
            }
        } catch {
            finish(.failure(error))
        }
    }

    private func cancel() {
        lock.lock()
        let process = self.process
        lock.unlock()
        if process?.isRunning == true {
            process?.terminate()
        }
        finish(.failure(CancellationError()))
    }

    private func finish(_ result: Result<Int32, Error>) {
        lock.lock()
        guard terminalResult == nil else {
            lock.unlock()
            return
        }
        terminalResult = result
        let continuation = self.continuation
        self.continuation = nil
        process = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
