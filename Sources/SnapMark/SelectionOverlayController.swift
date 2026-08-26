import AppKit

struct SelectionOverlaySlice: Equatable {
    let windowFrame: CGRect
    let sourceRect: CGRect
}

struct SelectionDesktop: Equatable {
    let globalFrame: CGRect
    let displayFrames: [CGRect]

    init?(displayFrames: [CGRect]) {
        let usableFrames = displayFrames.map(\.standardized).filter { $0.width > 0 && $0.height > 0 }
        guard let first = usableFrames.first else { return nil }
        self.displayFrames = usableFrames
        globalFrame = usableFrames.dropFirst().reduce(first) { $0.union($1) }
    }

    var canvasSize: CGSize { globalFrame.size }

    func screenRect(for selection: CGRect) -> CGRect {
        selection.offsetBy(
            dx: globalFrame.minX,
            dy: globalFrame.minY
        )
    }
}

enum SelectionOverlayLayout {
    static func slices(globalFrame: CGRect, displayFrames: [CGRect]) -> [SelectionOverlaySlice] {
        displayFrames.compactMap { displayFrame in
            let windowFrame = displayFrame.standardized.intersection(globalFrame.standardized)
            guard !windowFrame.isNull, windowFrame.width > 0, windowFrame.height > 0 else {
                return nil
            }
            return SelectionOverlaySlice(
                windowFrame: windowFrame,
                sourceRect: CGRect(
                    x: windowFrame.minX - globalFrame.minX,
                    y: windowFrame.minY - globalFrame.minY,
                    width: windowFrame.width,
                    height: windowFrame.height
                )
            )
        }
    }
}

enum SelectionOverlayHealth {
    static func shouldAbort(expectedWindowCount: Int, visibleWindowCount: Int, appIsHidden: Bool) -> Bool {
        expectedWindowCount <= 0 || visibleWindowCount < expectedWindowCount || appIsHidden
    }
}

struct SelectionOverlaySessionState {
    private(set) var activeID: UUID?

    mutating func activate(_ sessionID: UUID) {
        activeID = sessionID
    }

    mutating func finish(_ sessionID: UUID) -> Bool {
        guard activeID == sessionID else { return false }
        activeID = nil
        return true
    }
}

@MainActor
enum SelectionOverlayRetirement {
    typealias Cleanup = @MainActor @Sendable () -> Void

    static func prepare(_ windowControllers: [NSWindowController]) -> Cleanup {
        let retiredContent = windowControllers.compactMap { controller -> (NSWindow, NSView)? in
            guard let window = controller.window, let contentView = window.contentView else { return nil }
            return (window, contentView)
        }
        retiredContent.forEach { window, _ in
            window.delegate = nil
            window.orderOut(nil)
        }
        return {
            retiredContent.forEach { window, contentView in
                if window.contentView === contentView {
                    window.contentView = nil
                }
            }
        }
    }
}

@MainActor
enum SelectionOverlayWindowPolicy {
    static func makeWindow() -> CaptureOverlayWindow {
        let window = CaptureOverlayWindow(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configure(window)
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return window
    }

    static func configure(_ window: NSWindow) {
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
    }
}

@MainActor
final class SelectionOverlayWindowPool {
    private var windowControllers: [NSWindowController] = []

    var allocatedCount: Int { windowControllers.count }

    func acquire(
        count: Int,
        makeWindowController: () -> NSWindowController
    ) -> [NSWindowController] {
        while windowControllers.count < count {
            windowControllers.append(makeWindowController())
        }
        return Array(windowControllers.prefix(count))
    }
}

@MainActor
final class SelectionOverlayController: NSObject, NSWindowDelegate {
    private let windowPool = SelectionOverlayWindowPool()
    private var activeWindowControllers: [NSWindowController] = []
    private var views: [SelectionOverlayView] = []
    private var interaction: SelectionInteraction?
    private var continuation: CheckedContinuation<CGRect?, Never>?
    private var visibilityTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var sessionState = SelectionOverlaySessionState()

    private var windows: [CaptureOverlayWindow] {
        activeWindowControllers.compactMap { $0.window as? CaptureOverlayWindow }
    }

    func select(on desktop: SelectionDesktop) async -> CGRect? {
        if let activeSessionID = sessionState.activeID {
            finish(with: nil, matching: activeSessionID)
        }
        let sessionID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }
                sessionState.activate(sessionID)
                self.continuation = continuation
                present(desktop, sessionID: sessionID)
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.finish(with: nil, matching: sessionID)
            }
        }
    }

    func cancelSelection() {
        guard let sessionID = sessionState.activeID else { return }
        finish(with: nil, matching: sessionID)
    }

    private func present(_ desktop: SelectionDesktop, sessionID: UUID) {
        let slices = SelectionOverlayLayout.slices(
            globalFrame: desktop.globalFrame,
            displayFrames: desktop.displayFrames
        )
        guard !slices.isEmpty else {
            finish(with: nil, matching: sessionID)
            return
        }

        let interaction = SelectionInteraction(
            canvasBounds: CGRect(origin: .zero, size: desktop.canvasSize)
        )
        interaction.onChange = { [weak self] in
            guard let self, self.sessionState.activeID == sessionID else { return }
            self.views.forEach { $0.needsDisplay = true }
        }
        interaction.onComplete = { [weak self] rect in
            self?.finish(with: rect, matching: sessionID)
        }
        interaction.onCancel = { [weak self] in
            self?.finish(with: nil, matching: sessionID)
        }
        self.interaction = interaction

        activeWindowControllers = windowPool.acquire(count: slices.count) {
            let overlay = SelectionOverlayWindowPolicy.makeWindow()
            return NSWindowController(window: overlay)
        }

        for (controller, slice) in zip(activeWindowControllers, slices) {
            guard let overlay = controller.window as? CaptureOverlayWindow else { continue }
            overlay.setFrame(slice.windowFrame, display: true)
            overlay.level = .screenSaver
            overlay.hasShadow = false
            overlay.acceptsMouseMovedEvents = true
            overlay.animationBehavior = .none
            overlay.delegate = self

            let view = SelectionOverlayView(
                frame: CGRect(origin: .zero, size: slice.windowFrame.size),
                sourceRect: slice.sourceRect,
                interaction: interaction
            )
            overlay.contentView = view
            views.append(view)
        }

        installObservers(sessionID: sessionID)
        windows.forEach { $0.orderFrontRegardless() }
        let keyWindow = zip(windows, slices)
            .first(where: { NSScreen.main?.frame.intersects($0.1.windowFrame) == true })?.0
            ?? windows.first
        keyWindow?.makeKeyAndOrderFront(nil)
        startVisibilityGuard(expectedWindowCount: slices.count, sessionID: sessionID)
    }

    private func finish(with selection: CGRect?, matching sessionID: UUID) {
        guard sessionState.finish(sessionID) else { return }
        visibilityTask?.cancel()
        visibilityTask = nil
        removeObservers()
        let pending = continuation
        continuation = nil
        let retiringWindowControllers = activeWindowControllers
        activeWindowControllers = []
        views = []
        interaction = nil
        let releaseRetiredContent = SelectionOverlayRetirement.prepare(retiringWindowControllers)
        Task { @MainActor in
            await Task.yield()
            releaseRetiredContent()
        }
        pending?.resume(returning: selection)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              windows.contains(where: { $0 === closingWindow }),
              let sessionID = sessionState.activeID else { return }
        finish(with: nil, matching: sessionID)
    }

    private func installObservers(sessionID: UUID) {
        removeObservers()
        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: NSApplication.didHideNotification,
                object: NSApp,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.finish(with: nil, matching: sessionID)
                }
            },
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: NSApp,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.finish(with: nil, matching: sessionID)
                }
            }
        ]
    }

    private func removeObservers() {
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        observers = []
    }

    private func startVisibilityGuard(expectedWindowCount: Int, sessionID: UUID) {
        visibilityTask?.cancel()
        visibilityTask = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: .milliseconds(250))
                    guard let self,
                          self.sessionState.activeID == sessionID,
                          self.continuation != nil else { return }
                    let visibleWindowCount = self.windows.lazy.filter(\.isVisible).count
                    if SelectionOverlayHealth.shouldAbort(
                        expectedWindowCount: expectedWindowCount,
                        visibleWindowCount: visibleWindowCount,
                        appIsHidden: NSApp.isHidden
                    ) {
                        self.finish(with: nil, matching: sessionID)
                        return
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                self?.finish(with: nil, matching: sessionID)
            }
        }
    }
}

final class CaptureOverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class SelectionInteraction {
    let canvasBounds: CGRect
    private(set) var dragStart: CGPoint?
    private(set) var pointer: CGPoint?
    private(set) var selection: CGRect?
    var onChange: (() -> Void)?
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    init(canvasBounds: CGRect) {
        self.canvasBounds = canvasBounds
    }

    func move(to point: CGPoint) {
        pointer = clamped(point)
        onChange?()
    }

    func begin(at point: CGPoint) {
        let point = clamped(point)
        dragStart = point
        pointer = point
        selection = CGRect(origin: point, size: .zero)
        onChange?()
    }

    func drag(to point: CGPoint) {
        guard let dragStart else { return }
        let point = clamped(point)
        pointer = point
        selection = CaptureGeometry.normalizedRect(from: dragStart, to: point)
        onChange?()
    }

    func end(at point: CGPoint) {
        guard let dragStart else { return }
        let completed = CaptureGeometry.normalizedRect(from: dragStart, to: clamped(point))
        self.dragStart = nil
        if completed.width >= 8, completed.height >= 8 {
            onComplete?(completed)
        } else {
            selection = nil
            onChange?()
        }
    }

    func cancel() {
        onCancel?()
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(canvasBounds.minX, point.x), canvasBounds.maxX),
            y: min(max(canvasBounds.minY, point.y), canvasBounds.maxY)
        )
    }
}

final class SelectionOverlayView: NSView {
    private let sourceRect: CGRect
    private let interaction: SelectionInteraction

    init(
        frame frameRect: NSRect,
        sourceRect: CGRect,
        interaction: SelectionInteraction
    ) {
        self.sourceRect = sourceRect
        self.interaction = interaction
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseMoved(with event: NSEvent) {
        interaction.move(to: canvasPoint(for: event))
    }

    override func mouseDown(with event: NSEvent) {
        interaction.begin(at: canvasPoint(for: event))
    }

    override func mouseDragged(with event: NSEvent) {
        interaction.drag(to: canvasPoint(for: event))
    }

    override func mouseUp(with event: NSEvent) {
        interaction.end(at: canvasPoint(for: event))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            interaction.cancel()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(rect: dirtyRect).fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.black.withAlphaComponent(0.22).setFill()
        bounds.fill()

        if let selection = interaction.selection, selection.width > 0, selection.height > 0 {
            let localSelection = selection.offsetBy(dx: -sourceRect.minX, dy: -sourceRect.minY)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(rect: localSelection).fill()
            NSGraphicsContext.restoreGraphicsState()

            let border = NSBezierPath(rect: localSelection.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1.5
            NSColor.white.setStroke()
            border.stroke()

            if sourceRect.insetBy(dx: -1, dy: -1).contains(
                CGPoint(x: selection.minX, y: selection.maxY)
            ) {
                drawSizeLabel(for: selection, localRect: localSelection)
            }
        } else if let pointer = interaction.pointer, sourceRect.contains(pointer) {
            let localPointer = CGPoint(
                x: pointer.x - sourceRect.minX,
                y: pointer.y - sourceRect.minY
            )
            drawGuide(at: localPointer)
            drawInstruction(near: localPointer)
        }
    }

    private func drawGuide(at point: CGPoint) {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: bounds.minX, y: point.y))
        path.line(to: CGPoint(x: bounds.maxX, y: point.y))
        path.move(to: CGPoint(x: point.x, y: bounds.minY))
        path.line(to: CGPoint(x: point.x, y: bounds.maxY))
        path.lineWidth = 0.5
        NSColor.white.withAlphaComponent(0.52).setStroke()
        path.stroke()
    }

    private func drawInstruction(near point: CGPoint) {
        let text = "Drag to capture across any display  •  Esc to cancel"
        drawPill(text, origin: CGPoint(x: point.x + 18, y: point.y + 18), keepInside: bounds)
    }

    private func drawSizeLabel(for selection: CGRect, localRect: CGRect) {
        let text = "\(Int(selection.width)) × \(Int(selection.height))"
        drawPill(text, origin: CGPoint(x: localRect.minX, y: localRect.maxY + 9), keepInside: bounds)
    }

    private func drawPill(_ text: String, origin: CGPoint, keepInside container: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let size = CGSize(width: textSize.width + 18, height: textSize.height + 10)
        let x = min(max(container.minX + 8, origin.x), container.maxX - size.width - 8)
        let y = min(max(container.minY + 8, origin.y), container.maxY - size.height - 8)
        let pill = CGRect(origin: CGPoint(x: x, y: y), size: size)
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 7, yRadius: 7).fill()
        (text as NSString).draw(at: CGPoint(x: pill.minX + 9, y: pill.minY + 5), withAttributes: attributes)
    }

    private func canvasPoint(for event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return CGPoint(
            x: sourceRect.minX + local.x,
            y: sourceRect.minY + local.y
        )
    }
}
