import AppKit
import Combine
import SwiftUI

struct AnnotationCanvas: NSViewRepresentable {
    @ObservedObject var session: EditorSession

    func makeNSView(context: Context) -> AnnotationCanvasNSView {
        AnnotationCanvasNSView(session: session)
    }

    func updateNSView(_ nsView: AnnotationCanvasNSView, context: Context) {
        nsView.setSession(session)
    }
}

@MainActor
final class AnnotationCanvasNSView: NSView, NSTextViewDelegate {
    private(set) var session: EditorSession
    private var observation: AnyCancellable?
    private var colorObservation: AnyCancellable?
    private var cachedImage: CGImage?
    private var startPoint: CGPoint?
    private var livePoints: [CGPoint] = []
    private var currentPoint: CGPoint?
    private var textView: NSTextView?
    private var textOrigin: CGPoint?
    private var textColor: RGBAColor?
    private var textFontSize: CGFloat?

    init(session: EditorSession) {
        self.session = session
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Screenshot editing canvas, \(Int(session.imageSize.width)) by \(Int(session.imageSize.height)) pixels")
        setAccessibilityHelp("Use the tool buttons to choose an edit, then interact with the screenshot. Escape cancels a live edit.")
        observeSession()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        resizeTextEntry()
    }

    func setSession(_ newSession: EditorSession) {
        guard session !== newSession else { return }
        session = newSession
        setAccessibilityLabel("Screenshot editing canvas, \(Int(newSession.imageSize.width)) by \(Int(newSession.imageSize.height)) pixels")
        cachedImage = nil
        observeSession()
        needsDisplay = true
    }

    private func observeSession() {
        observation = session.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.cachedImage = nil
                self.needsDisplay = true
                self.window?.invalidateCursorRects(for: self)
            }
        }
        colorObservation = session.$selectedColor.sink { [weak self] color in
            self?.syncActiveTextColor(to: color)
        }
    }

    override func resetCursorRects() {
        let cursor: NSCursor = session.selectedTool == .text ? .iBeam : .crosshair
        addCursorRect(bounds, cursor: cursor)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let imageRect = fittedImageRect
        guard imageRect.width > 0, imageRect.height > 0 else { return }

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = CGSize(width: 0, height: -5)
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: imageRect, xRadius: 3, yRadius: 3).fill()
        NSGraphicsContext.restoreGraphicsState()

        if cachedImage == nil {
            cachedImage = try? session.renderedImage()
        }
        if let cachedImage {
            NSImage(cgImage: cachedImage, size: session.imageSize).draw(
                in: imageRect,
                from: .zero,
                operation: .copy,
                fraction: 1,
                respectFlipped: false,
                hints: [.interpolation: NSImageInterpolation.high]
            )
        }

        drawLiveEdit(in: imageRect)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let imagePoint = imagePoint(from: viewPoint) else { return }

        if session.selectedTool == .text {
            beginTextEntry(atViewPoint: viewPoint, imagePoint: imagePoint)
            return
        }

        startPoint = imagePoint
        currentPoint = imagePoint
        livePoints = [imagePoint]
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard startPoint != nil else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let imagePoint = clampedImagePoint(from: viewPoint)
        currentPoint = imagePoint

        if session.selectedTool == .pen || session.selectedTool == .highlight {
            if let last = livePoints.last,
               hypot(last.x - imagePoint.x, last.y - imagePoint.y) > 1.5 {
                livePoints.append(imagePoint)
            }
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = startPoint else { return }
        let end = clampedImagePoint(from: convert(event.locationInWindow, from: nil))
        currentPoint = end

        switch session.selectedTool {
        case .pen:
            if livePoints.count > 1 {
                session.add(.pen(points: livePoints, color: session.selectedColor, width: session.lineWidth))
            }
        case .highlight:
            if livePoints.count > 1 {
                session.add(.highlight(
                    points: livePoints,
                    color: session.selectedColor,
                    width: max(14, session.lineWidth * 4)
                ))
            }
        case .arrow:
            if distance(from: start, to: end) > 5 {
                session.add(.arrow(start: start, end: end, color: session.selectedColor, width: session.lineWidth))
            }
        case .rectangle:
            let rect = CaptureGeometry.normalizedRect(from: start, to: end)
            if rect.width > 4, rect.height > 4 {
                session.add(.rectangle(rect: rect, color: session.selectedColor, width: session.lineWidth))
            }
        case .pixelate:
            let rect = CaptureGeometry.normalizedRect(from: start, to: end)
            if rect.width > 8, rect.height > 8 {
                session.add(.pixelate(rect: rect))
            }
        case .blackout:
            let rect = CaptureGeometry.normalizedRect(from: start, to: end)
            if rect.width > 8, rect.height > 8 {
                session.add(.blackout(rect: rect))
            }
        case .crop:
            session.crop(to: CaptureGeometry.normalizedRect(from: start, to: end))
        case .text:
            break
        }

        clearLiveEdit()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            clearLiveEdit()
            cancelTextEntry()
            return
        }

        if let character = event.charactersIgnoringModifiers?.lowercased(),
           let tool = EditorTool.allCases.first(where: { $0.shortcut.lowercased() == character }) {
            session.selectedTool = tool
            return
        }
        super.keyDown(with: event)
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitTextEntry()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelTextEntry()
            return true
        }
        return false
    }

    func textDidChange(_ notification: Notification) {
        guard let changedView = notification.object as? NSTextView,
              changedView === textView else { return }
        resizeTextEntry()
    }

    private var fittedImageRect: CGRect {
        CaptureGeometry.aspectFit(imageSize: session.imageSize, in: bounds, padding: 30)
    }

    private func imagePoint(from viewPoint: CGPoint) -> CGPoint? {
        CaptureGeometry.imagePoint(fromViewPoint: viewPoint, imageRect: fittedImageRect, imageSize: session.imageSize)
    }

    private func clampedImagePoint(from viewPoint: CGPoint) -> CGPoint {
        let rect = fittedImageRect
        let clamped = CGPoint(
            x: min(max(rect.minX, viewPoint.x), rect.maxX),
            y: min(max(rect.minY, viewPoint.y), rect.maxY)
        )
        return CaptureGeometry.imagePoint(fromViewPoint: clamped, imageRect: rect, imageSize: session.imageSize) ?? .zero
    }

    private func viewPoint(from imagePoint: CGPoint, imageRect: CGRect) -> CGPoint {
        CaptureGeometry.viewPoint(fromImagePoint: imagePoint, imageRect: imageRect, imageSize: session.imageSize)
    }

    private func drawLiveEdit(in imageRect: CGRect) {
        guard let start = startPoint, let end = currentPoint else { return }
        let scale = imageRect.width / session.imageSize.width
        let color = session.selectedColor.nsColor
        let width = max(1, session.lineWidth * scale)

        switch session.selectedTool {
        case .pen, .highlight:
            guard let first = livePoints.first else { return }
            let path = NSBezierPath()
            path.move(to: viewPoint(from: first, imageRect: imageRect))
            for point in livePoints.dropFirst() {
                path.line(to: viewPoint(from: point, imageRect: imageRect))
            }
            path.lineWidth = session.selectedTool == .highlight ? max(8, width * 4) : width
            path.lineCapStyle = session.selectedTool == .highlight ? .square : .round
            path.lineJoinStyle = .round
            (session.selectedTool == .highlight ? color.withAlphaComponent(0.34) : color).setStroke()
            path.stroke()

        case .arrow:
            let a = viewPoint(from: start, imageRect: imageRect)
            let b = viewPoint(from: end, imageRect: imageRect)
            let path = NSBezierPath()
            path.move(to: a)
            path.line(to: b)
            path.lineWidth = width
            path.lineCapStyle = .round
            color.setStroke()
            path.stroke()
            drawArrowHead(from: a, to: b, width: width, color: color)

        case .rectangle:
            let a = viewPoint(from: start, imageRect: imageRect)
            let b = viewPoint(from: end, imageRect: imageRect)
            let path = NSBezierPath(roundedRect: CaptureGeometry.normalizedRect(from: a, to: b), xRadius: 4, yRadius: 4)
            path.lineWidth = width
            color.setStroke()
            path.stroke()

        case .pixelate:
            let a = viewPoint(from: start, imageRect: imageRect)
            let b = viewPoint(from: end, imageRect: imageRect)
            let rect = CaptureGeometry.normalizedRect(from: a, to: b)
            NSColor.systemGray.withAlphaComponent(0.5).setFill()
            rect.fill()
            let path = NSBezierPath(rect: rect)
            path.setLineDash([5, 4], count: 2, phase: 0)
            path.lineWidth = 1.5
            NSColor.white.setStroke()
            path.stroke()

        case .blackout:
            let a = viewPoint(from: start, imageRect: imageRect)
            let b = viewPoint(from: end, imageRect: imageRect)
            let rect = CaptureGeometry.normalizedRect(from: a, to: b)
            NSColor.black.setFill()
            rect.fill()
            let path = NSBezierPath(rect: rect)
            path.setLineDash([5, 4], count: 2, phase: 0)
            path.lineWidth = 1.5
            NSColor.white.setStroke()
            path.stroke()

        case .crop:
            let a = viewPoint(from: start, imageRect: imageRect)
            let b = viewPoint(from: end, imageRect: imageRect)
            let cropRect = CaptureGeometry.normalizedRect(from: a, to: b)
            NSGraphicsContext.saveGraphicsState()
            let outside = NSBezierPath(rect: imageRect)
            outside.appendRect(cropRect)
            outside.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.58).setFill()
            outside.fill()
            NSGraphicsContext.restoreGraphicsState()
            let border = NSBezierPath(rect: cropRect)
            border.lineWidth = 1.5
            NSColor.white.setStroke()
            border.stroke()

        case .text:
            break
        }
    }

    private func drawArrowHead(from start: CGPoint, to end: CGPoint, width: CGFloat, color: NSColor) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = max(10, width * 4.5)
        let head = NSBezierPath()
        head.move(to: CGPoint(x: end.x - length * cos(angle - .pi / 6), y: end.y - length * sin(angle - .pi / 6)))
        head.line(to: end)
        head.line(to: CGPoint(x: end.x - length * cos(angle + .pi / 6), y: end.y - length * sin(angle + .pi / 6)))
        head.lineWidth = width
        head.lineCapStyle = .round
        head.lineJoinStyle = .round
        color.setStroke()
        head.stroke()
    }

    private func beginTextEntry(atViewPoint viewPoint: CGPoint, imagePoint: CGPoint) {
        commitTextEntry()
        textOrigin = imagePoint
        textColor = session.selectedColor
        textFontSize = TextAnnotationStyle.fontSize(for: session.lineWidth)

        let editor = NSTextView(frame: CGRect(x: viewPoint.x, y: viewPoint.y, width: 10, height: 24))
        editor.delegate = self
        editor.drawsBackground = false
        editor.backgroundColor = .clear
        editor.isRichText = true
        editor.importsGraphics = false
        editor.allowsImageEditing = false
        editor.isHorizontallyResizable = true
        editor.isVerticallyResizable = false
        editor.textContainerInset = .zero
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = false
        editor.textContainer?.heightTracksTextView = true
        editor.textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: 100)
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.insertionPointColor = session.selectedColor.nsColor
        editor.setAccessibilityLabel("Text annotation")
        editor.setAccessibilityHelp("Type the annotation, drag it to reposition, then press Return to place it.")

        let pan = NSPanGestureRecognizer(target: self, action: #selector(dragTextEntry(_:)))
        pan.buttonMask = 0x1
        editor.addGestureRecognizer(pan)

        addSubview(editor)
        textView = editor
        resizeTextEntry()
        window?.makeFirstResponder(editor)
    }

    private func commitTextEntry() {
        guard let editor = textView,
              let origin = textOrigin,
              let color = textColor,
              let fontSize = textFontSize else { return }
        let value = editor.string
        editor.delegate = nil
        editor.removeFromSuperview()
        textView = nil
        textOrigin = nil
        textColor = nil
        textFontSize = nil
        session.addText(value, at: origin, color: color, fontSize: fontSize)
        window?.makeFirstResponder(self)
    }

    private func cancelTextEntry() {
        textView?.delegate = nil
        textView?.removeFromSuperview()
        textView = nil
        textOrigin = nil
        textColor = nil
        textFontSize = nil
        window?.makeFirstResponder(self)
    }

    private func resizeTextEntry() {
        guard let editor = textView,
              var origin = textOrigin,
              let color = textColor,
              let fontSize = textFontSize else { return }

        let imageRect = fittedImageRect
        guard imageRect.width > 0, imageRect.height > 0, session.imageSize.width > 0 else { return }
        let scale = imageRect.width / session.imageSize.width
        let attributes = TextAnnotationStyle.attributes(color: color, fontSize: fontSize * scale)
        editor.typingAttributes = attributes

        if let storage = editor.textStorage, storage.length > 0 {
            let selection = editor.selectedRange()
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
            editor.setSelectedRange(selection)
        }

        let measuringText = editor.string.isEmpty ? "Ag" : editor.string
        let measured = (measuringText as NSString).boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        let size = CGSize(
            width: min(imageRect.width, max(10, ceil(measured.width) + 3)),
            height: min(imageRect.height, max(18, ceil(measured.height)))
        )
        var viewOrigin = viewPoint(from: origin, imageRect: imageRect)
        viewOrigin.x = min(max(imageRect.minX, viewOrigin.x), max(imageRect.minX, imageRect.maxX - size.width))
        viewOrigin.y = min(max(imageRect.minY, viewOrigin.y), max(imageRect.minY, imageRect.maxY - size.height))
        editor.frame = CGRect(origin: viewOrigin, size: size)

        if let adjustedOrigin = imagePoint(from: viewOrigin) {
            origin = adjustedOrigin
            textOrigin = origin
        }
    }

    private func syncActiveTextColor(to color: RGBAColor) {
        guard let editor = textView,
              session.selectedTool == .text,
              textColor != color else { return }
        textColor = color
        editor.insertionPointColor = color.nsColor
        resizeTextEntry()
        window?.makeFirstResponder(editor)
    }

    @objc private func dragTextEntry(_ recognizer: NSPanGestureRecognizer) {
        let translation = recognizer.translation(in: self)
        guard translation != .zero else { return }
        moveTextEntry(by: translation)
        recognizer.setTranslation(.zero, in: self)
    }

    func moveTextEntry(by translation: CGPoint) {
        guard let editor = textView else { return }

        let imageRect = fittedImageRect
        var origin = CGPoint(
            x: editor.frame.minX + translation.x,
            y: editor.frame.minY + translation.y
        )
        origin.x = min(max(imageRect.minX, origin.x), max(imageRect.minX, imageRect.maxX - editor.frame.width))
        origin.y = min(max(imageRect.minY, origin.y), max(imageRect.minY, imageRect.maxY - editor.frame.height))
        editor.setFrameOrigin(origin)
        textOrigin = imagePoint(from: origin)
        window?.makeFirstResponder(editor)
    }

    private func clearLiveEdit() {
        startPoint = nil
        currentPoint = nil
        livePoints = []
        needsDisplay = true
    }

    private func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }
}
