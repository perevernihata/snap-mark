import AppKit
import Foundation

private struct SelfTestFailure: Error, CustomStringConvertible {
    let description: String
}

@MainActor
enum SelfTestRunner {
    static func run() -> Int32 {
        var passed = 0
        var failed = 0

        runCase("selection geometry", passed: &passed, failed: &failed) {
            try expect(
                CaptureGeometry.normalizedRect(
                    from: CGPoint(x: 90, y: 70),
                    to: CGPoint(x: 20, y: 10)
                ) == CGRect(x: 20, y: 10, width: 70, height: 60),
                "reverse drag did not normalize"
            )
            try expect(
                CaptureGeometry.pixelCropRect(
                    selection: CGRect(x: 0, y: 0, width: 25, height: 10),
                    canvasSize: CGSize(width: 100, height: 50),
                    imageSize: CGSize(width: 200, height: 100)
                ) == CGRect(x: 0, y: 80, width: 50, height: 20),
                "top-left crop conversion is wrong"
            )
            try expect(
                CaptureGeometry.bottomLeftImageRect(
                    selection: CGRect(x: 10, y: 5, width: 30, height: 20),
                    canvasSize: CGSize(width: 100, height: 50),
                    imageSize: CGSize(width: 200, height: 100)
                ) == CGRect(x: 20, y: 10, width: 60, height: 40),
                "AppKit crop scaling is wrong"
            )
        }

        runCase("only area and window capture modes", passed: &passed, failed: &failed) {
            try expect(
                CaptureMode.allCases == [.area, .window],
                "a removed whole-display capture mode is still available"
            )
        }

        runCase("one selection overlay per display", passed: &passed, failed: &failed) {
            let globalFrame = CGRect(x: -2166, y: 0, width: 5760, height: 2062)
            let displays = [
                CGRect(x: 0, y: 0, width: 1512, height: 982),
                CGRect(x: -2166, y: 982, width: 1920, height: 1080),
                CGRect(x: 1674, y: 982, width: 1920, height: 1080),
                CGRect(x: -246, y: 982, width: 1920, height: 1080)
            ]
            let slices = SelectionOverlayLayout.slices(
                globalFrame: globalFrame,
                displayFrames: displays
            )
            try expect(slices.count == displays.count, "selection still uses one oversized cross-display window")
            try expect(
                slices.map(\.windowFrame) == displays,
                "selection overlay windows do not match the captured displays"
            )
            try expect(
                slices[0].sourceRect == CGRect(x: 2166, y: 0, width: 1512, height: 982),
                "main-display image slice is mapped to the wrong canvas region"
            )
        }

        runCase("lost selection overlay cannot wait forever", passed: &passed, failed: &failed) {
            try expect(
                SelectionOverlayHealth.shouldAbort(
                    expectedWindowCount: 4,
                    visibleWindowCount: 3,
                    appIsHidden: false
                ),
                "a missing display overlay leaves area capture waiting forever"
            )
            try expect(
                SelectionOverlayHealth.shouldAbort(
                    expectedWindowCount: 4,
                    visibleWindowCount: 4,
                    appIsHidden: true
                ),
                "hiding all overlay windows leaves area capture waiting forever"
            )
            try expect(
                !SelectionOverlayHealth.shouldAbort(
                    expectedWindowCount: 4,
                    visibleWindowCount: 4,
                    appIsHidden: false
                ),
                "a healthy overlay is canceled"
            )
        }

        runCase("selection overlay teardown waits for event return", passed: &passed, failed: &failed) {
            let window = OverlayRetirementProbeWindow(
                contentRect: CGRect(x: 0, y: 0, width: 32, height: 32),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            SelectionOverlayWindowPolicy.configure(window)
            let contentView = NSView(frame: CGRect(x: 0, y: 0, width: 32, height: 32))
            window.contentView = contentView
            let controller = NSWindowController(window: window)
            let scheduledWork = SelectionOverlayRetirement.prepare([controller])
            try expect(
                !window.didClose,
                "an overlay closed while its mouse or keyboard event was still executing"
            )
            try expect(window.contentView === contentView, "overlay content was released during its active event")
            scheduledWork()
            try expect(!window.didClose, "a pooled overlay was destroyed instead of being reused")
            try expect(window.contentView == nil, "the retired overlay kept its full screenshot in memory")
        }

        runCase("selection overlays use one ARC owner", passed: &passed, failed: &failed) {
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 32, height: 32),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            SelectionOverlayWindowPolicy.configure(window)
            try expect(
                !window.isReleasedWhenClosed,
                "an ARC-managed overlay is configured to release itself on close"
            )
            let controller = NSWindowController(window: window)
            try expect(controller.window === window, "the overlay window controller did not take ownership")

            let liveWindow = SelectionOverlayWindowPolicy.makeWindow()
            try expect(
                liveWindow.styleMask.contains(.nonactivatingPanel),
                "the area selector activates SnapMark over full-screen apps"
            )
            try expect(!liveWindow.hidesOnDeactivate, "the selector disappears while another app stays active")
            try expect(
                liveWindow.collectionBehavior.contains(.canJoinAllSpaces),
                "the selector cannot follow the active full-screen Space"
            )
            try expect(
                liveWindow.collectionBehavior.contains(.fullScreenAuxiliary),
                "the selector cannot appear above a full-screen app"
            )
        }

        runCase("area selector shows the live desktop", passed: &passed, failed: &failed) {
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 100, height: 80),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            SelectionOverlayWindowPolicy.configure(window)
            try expect(!window.isOpaque, "the area selector replaces the live desktop with an opaque window")
            try expect(
                window.backgroundColor.alphaComponent == 0,
                "the area selector has a solid background instead of showing the live desktop"
            )

            let interaction = SelectionInteraction(canvasBounds: CGRect(x: 0, y: 0, width: 100, height: 80))
            let view = SelectionOverlayView(
                frame: CGRect(x: 0, y: 0, width: 100, height: 80),
                sourceRect: CGRect(x: 0, y: 0, width: 100, height: 80),
                interaction: interaction
            )
            let representation = try require(
                view.bitmapImageRepForCachingDisplay(in: view.bounds),
                "could not allocate selector rendering output"
            )
            view.cacheDisplay(in: view.bounds, to: representation)
            let sample = try require(
                representation.colorAt(x: 50, y: 40)?.usingColorSpace(.sRGB),
                "could not sample selector rendering output"
            )
            try expect(
                sample.alphaComponent > 0.15 && sample.alphaComponent < 0.30,
                "the selector canvas paints a frozen bitmap over the live desktop"
            )
        }

        runCase("live selection maps into the later capture", passed: &passed, failed: &failed) {
            let desktop = try require(SelectionDesktop(displayFrames: [
                CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080),
                CGRect(x: 0, y: 0, width: 1_512, height: 982)
            ]), "selection desktop was nil")
            let selection = CGRect(x: 1_800, y: 100, width: 400, height: 300)
            try expect(
                desktop.screenRect(for: selection) == CGRect(x: -120, y: 100, width: 400, height: 300),
                "selection did not map from overlay coordinates into global screen coordinates"
            )
        }

        runCase("area capture uses Quartz screen coordinates", passed: &passed, failed: &failed) {
            let primary = CGRect(x: 0, y: 0, width: 1_512, height: 982)
            try expect(
                ScreenCaptureCoordinateSpace.quartzRect(
                    fromAppKit: CGRect(x: 100, y: 100, width: 400, height: 300),
                    primaryDisplayFrame: primary
                ) == CGRect(x: 100, y: 582, width: 400, height: 300),
                "a main-display selection is vertically inverted"
            )
            try expect(
                ScreenCaptureCoordinateSpace.quartzRect(
                    fromAppKit: CGRect(x: -2_166, y: 982, width: 1_920, height: 1_080),
                    primaryDisplayFrame: primary
                ) == CGRect(x: -2_166, y: -1_080, width: 1_920, height: 1_080),
                "a display above the primary maps to the wrong screen"
            )
        }

        runCase("selection overlay allocation is bounded by display count", passed: &passed, failed: &failed) {
            let pool = SelectionOverlayWindowPool()
            var created = 0
            let makeController = {
                created += 1
                return NSWindowController(window: NSWindow(
                    contentRect: .zero,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                ))
            }
            _ = pool.acquire(count: 4, makeWindowController: makeController)
            _ = pool.acquire(count: 4, makeWindowController: makeController)
            _ = pool.acquire(count: 2, makeWindowController: makeController)
            try expect(created == 4, "repeated captures allocated another set of overlay windows")
            _ = pool.acquire(count: 6, makeWindowController: makeController)
            try expect(created == 6, "the pool did not grow for newly connected displays")
            try expect(pool.allocatedCount == 6, "the overlay pool lost track of its bounded capacity")
        }

        runCase("stale overlay callbacks cannot cancel a new selection", passed: &passed, failed: &failed) {
            var state = SelectionOverlaySessionState()
            let previousSession = UUID()
            let currentSession = UUID()
            state.activate(previousSession)
            state.activate(currentSession)
            try expect(
                !state.finish(previousSession),
                "a callback from a retired overlay finished the current selection"
            )
            try expect(
                state.activeID == currentSession,
                "a stale callback cleared the current selection identity"
            )
            try expect(state.finish(currentSession), "the current selection could not finish")
            try expect(state.activeID == nil, "a completed selection remained active")
        }

        runCase("selection drag crosses display windows", passed: &passed, failed: &failed) {
            let interaction = SelectionInteraction(
                canvasBounds: CGRect(x: 0, y: 0, width: 5760, height: 2062)
            )
            var completed: CGRect?
            interaction.onComplete = { completed = $0 }
            interaction.begin(at: CGPoint(x: 2500, y: 700))
            interaction.drag(to: CGPoint(x: 2800, y: 1250))
            interaction.end(at: CGPoint(x: 2800, y: 1250))
            try expect(
                completed == CGRect(x: 2500, y: 700, width: 300, height: 550),
                "a drag crossing the display seam did not produce one shared selection"
            )
            try expect(
                completed?.minY ?? .infinity < 982 && completed?.maxY ?? 0 > 982,
                "the shared selection does not span both display windows"
            )
        }

        runCase("flattened privacy edits", passed: &passed, failed: &failed) {
            let base = try require(makeSolidImage(width: 80, height: 60, color: .white), "could not make test image")
            let output = try ImageRenderer.render(
                baseImage: base,
                annotations: [.blackout(rect: CGRect(x: 5, y: 4, width: 30, height: 20))]
            )
            let representation = NSBitmapImageRep(cgImage: output)
            let black = try require(representation.colorAtBottomLeft(x: 10, y: 10), "could not sample blacked-out pixel")
            let white = try require(representation.colorAtBottomLeft(x: 60, y: 45), "could not sample untouched pixel")
            try expect(black.isNearlyBlack, "blackout did not replace exported pixels; sampled \(black)")
            try expect(white.isNearlyWhite, "blackout modified pixels outside its bounds")
        }

        runCase("pixelate visibly obscures pixels", passed: &passed, failed: &failed) {
            let base = try require(makeCheckerboardImage(width: 96, height: 72), "could not make pixelate fixture")
            let rect = CGRect(x: 18, y: 14, width: 55, height: 43)
            let output = try ImageRenderer.render(baseImage: base, annotations: [.pixelate(rect: rect)])
            let before = NSBitmapImageRep(cgImage: base)
            let after = NSBitmapImageRep(cgImage: output)
            let even = try require(before.colorAtBottomLeft(x: 20, y: 20), "could not sample checkerboard even pixel")
            let odd = try require(before.colorAtBottomLeft(x: 21, y: 20), "could not sample checkerboard odd pixel")
            try expect(even.colorDistance(to: odd) > 2.5, "pixelate test fixture has no visible detail")

            var changedInside = 0
            var changedOutside = 0
            for y in 0..<72 {
                for x in 0..<96 {
                    guard let original = before.colorAtBottomLeft(x: x, y: y),
                          let rendered = after.colorAtBottomLeft(x: x, y: y) else { continue }
                    let changed = original.colorDistance(to: rendered) > 0.10
                    if rect.contains(CGPoint(x: x, y: y)) {
                        changedInside += changed ? 1 : 0
                    } else {
                        changedOutside += changed ? 1 : 0
                    }
                }
            }

            try expect(changedInside > 1_000, "pixelate left most selected pixels unchanged (changed \(changedInside))")
            try expect(changedOutside == 0, "pixelate changed \(changedOutside) pixels outside the selection")
        }

        runCase("privacy gestures create visible edits", passed: &passed, failed: &failed) {
            let image = try require(makeCheckerboardImage(width: 320, height: 200), "could not make gesture fixture")
            let session = EditorSession(image: image)
            let canvas = AnnotationCanvasNSView(session: session)
            canvas.frame = CGRect(x: 0, y: 0, width: 400, height: 300)

            session.selectedTool = .pixelate
            drag(canvas: canvas, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 160))
            try expect(session.annotations.count == 1, "one pixelate drag did not create an edit")

            session.selectedTool = .blackout
            drag(canvas: canvas, from: CGPoint(x: 220, y: 120), to: CGPoint(x: 300, y: 180))
            try expect(session.annotations.count == 2, "one blackout drag did not create an edit")

            let rendered = try session.renderedImage()
            let representation = NSBitmapImageRep(cgImage: rendered)
            let blackout = try require(representation.colorAtBottomLeft(x: 210, y: 90), "could not sample gesture blackout")
            try expect(blackout.isNearlyBlack, "blackout gesture did not flatten to black pixels")
        }

        runCase("every drawing tool works in one drag", passed: &passed, failed: &failed) {
            let tools: [EditorTool] = [.pen, .highlight, .arrow, .rectangle, .pixelate, .blackout]
            for tool in tools {
                let image = try require(makeCheckerboardImage(width: 320, height: 200), "could not make \(tool.title) fixture")
                let session = EditorSession(image: image)
                let canvas = AnnotationCanvasNSView(session: session)
                canvas.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
                session.selectedTool = tool
                drag(canvas: canvas, from: CGPoint(x: 85, y: 90), to: CGPoint(x: 215, y: 175))
                try expect(
                    session.annotations.count == 1 && annotation(session.annotations[0], matches: tool),
                    "\(tool.title) required more than one drag or created the wrong edit"
                )
            }

            let cropImage = try require(makeCheckerboardImage(width: 320, height: 200), "could not make crop fixture")
            let cropSession = EditorSession(image: cropImage)
            let cropCanvas = AnnotationCanvasNSView(session: cropSession)
            cropCanvas.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
            cropSession.selectedTool = .crop
            drag(canvas: cropCanvas, from: CGPoint(x: 85, y: 90), to: CGPoint(x: 215, y: 175))
            try expect(cropSession.imageSize != CGSize(width: 320, height: 200), "Crop did not apply in one drag")
        }

        runCase("blackout always wins overlapping privacy edits", passed: &passed, failed: &failed) {
            let base = try require(makeCheckerboardImage(width: 100, height: 80), "could not make overlap fixture")
            let rect = CGRect(x: 20, y: 15, width: 50, height: 40)
            let output = try ImageRenderer.render(
                baseImage: base,
                annotations: [.blackout(rect: rect), .pixelate(rect: rect)]
            )
            let color = try require(
                NSBitmapImageRep(cgImage: output).colorAtBottomLeft(x: 45, y: 35),
                "could not sample overlapping privacy edit"
            )
            try expect(color.isNearlyBlack, "a later pixelation exposed pixels under a blackout")
        }

        runCase("bottom-left crop orientation", passed: &passed, failed: &failed) {
            let base = try require(makeSplitImage(width: 100, height: 80), "could not make split image")
            let cropped = try ImageRenderer.crop(image: base, to: CGRect(x: 0, y: 0, width: 100, height: 30))
            let sample = try require(NSBitmapImageRep(cgImage: cropped).colorAt(x: 50, y: 15), "could not sample crop")
            try expect(cropped.width == 100 && cropped.height == 30, "crop dimensions are wrong")
            try expect(sample.isMostlyRed, "crop came from the wrong image edge")
        }

        runCase("all annotation renderers", passed: &passed, failed: &failed) {
            let base = try require(DemoImageFactory.make(width: 520, height: 340), "could not make demo image")
            let annotations: [Annotation] = [
                .pen(points: [CGPoint(x: 20, y: 30), CGPoint(x: 90, y: 110), CGPoint(x: 150, y: 70)], color: .blue, width: 6),
                .highlight(points: [CGPoint(x: 35, y: 180), CGPoint(x: 280, y: 180)], color: .yellow, width: 22),
                .arrow(start: CGPoint(x: 70, y: 60), end: CGPoint(x: 320, y: 230), color: .coral, width: 5),
                .rectangle(rect: CGRect(x: 250, y: 80, width: 130, height: 90), color: .mint, width: 4),
                .text(origin: CGPoint(x: 180, y: 270), value: "Review", color: .black, fontSize: 24),
                .pixelate(rect: CGRect(x: 390, y: 60, width: 90, height: 70)),
                .blackout(rect: CGRect(x: 20, y: 280, width: 100, height: 30))
            ]
            let output = try ImageRenderer.render(baseImage: base, annotations: annotations)
            let png = try require(ExportService.pngData(for: output), "PNG encoding failed")
            let jpeg = try require(ExportService.jpegData(for: output), "JPEG encoding failed")
            let decodedPNG = try require(NSBitmapImageRep(data: png)?.cgImage, "PNG decoding failed")
            let decodedJPEG = try require(NSBitmapImageRep(data: jpeg)?.cgImage, "JPEG decoding failed")
            try expect(decodedPNG.width == 520 && decodedPNG.height == 340, "PNG dimensions changed")
            try expect(decodedJPEG.width == 520 && decodedJPEG.height == 340, "JPEG dimensions changed")
            try expect(png.count > 5_000 && jpeg.count > 5_000, "encoded image is unexpectedly small")
        }

        runCase("editor undo, crop, and redo", passed: &passed, failed: &failed) {
            let image = try require(DemoImageFactory.make(width: 320, height: 200), "could not make editor image")
            let session = EditorSession(image: image)
            session.addText("Review this", at: CGPoint(x: 40, y: 40))
            try expect(session.annotations.count == 1 && session.canUndo, "text annotation was not added")
            session.crop(to: CGRect(x: 20, y: 30, width: 180, height: 120))
            try expect(session.imageSize == CGSize(width: 180, height: 120), "crop did not apply")
            try expect(session.annotations.isEmpty, "crop did not flatten prior annotations")
            session.undo()
            try expect(session.imageSize == CGSize(width: 320, height: 200), "crop undo did not restore base image")
            try expect(session.annotations.count == 1, "crop undo did not restore annotations")
            session.redo()
            try expect(session.imageSize == CGSize(width: 180, height: 120), "crop redo did not restore crop")
        }

        runCase("annotation canvas owns drag gestures", passed: &passed, failed: &failed) {
            let image = try require(makeSolidImage(width: 320, height: 200, color: .white), "could not make canvas image")
            let canvas = AnnotationCanvasNSView(session: EditorSession(image: image))
            let titleBarDragArea = WindowDragArea.DragView()
            try expect(
                !canvas.mouseDownCanMoveWindow,
                "canvas drag is eligible to move the whole window"
            )
            try expect(
                canvas.acceptsFirstMouse(for: nil),
                "the first click on an inactive editor canvas is discarded"
            )
            try expect(
                titleBarDragArea.mouseDownCanMoveWindow,
                "dedicated title-bar drag area no longer moves the window"
            )
        }

        runCase("live text entry matches the annotation", passed: &passed, failed: &failed) {
            let image = try require(makeSolidImage(width: 800, height: 600, color: .white), "could not make text fixture")
            let session = EditorSession(image: image)
            session.selectedTool = .text
            session.selectedColor = .coral
            session.lineWidth = 6
            let canvas = AnnotationCanvasNSView(session: session)
            canvas.frame = CGRect(x: 0, y: 0, width: 800, height: 600)

            let down = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: CGPoint(x: 200, y: 200),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )!
            canvas.mouseDown(with: down)
            let editor = try require(canvas.subviews.first, "text entry did not create an inline editor")

            let attributed: NSAttributedString
            let liveFont: NSFont?
            let transparent: Bool
            var activeTextView: NSTextView?
            if let field = editor as? NSTextField {
                field.stringValue = " Test "
                attributed = field.attributedStringValue
                liveFont = field.font
                transparent = !field.drawsBackground && !field.isBezeled && !field.isBordered
            } else if let textView = editor as? NSTextView {
                let value = NSAttributedString(string: " Test ", attributes: textView.typingAttributes)
                textView.textStorage?.setAttributedString(value)
                textView.didChangeText()
                attributed = textView.attributedString()
                liveFont = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
                transparent = !textView.drawsBackground
                activeTextView = textView
            } else {
                throw SelfTestFailure(description: "inline text editor uses an unsupported view")
            }

            let expectedFontSize = max(18, session.lineWidth * 4) * 0.9
            let strokeWidth = attributed.length > 0
                ? (attributed.attribute(.strokeWidth, at: 0, effectiveRange: nil) as? NSNumber)?.doubleValue
                : nil
            var problems: [String] = []
            if editor.frame.width > 100 { problems.append("the short-text box is \(Int(editor.frame.width)) points wide") }
            if !transparent { problems.append("the editor draws opaque box chrome") }
            if abs((liveFont?.pointSize ?? 0) - expectedFontSize) > 0.25 {
                problems.append("live font size does not match the rendered annotation")
            }
            if abs((strokeWidth ?? 0) - (-0.7)) > 0.01 {
                problems.append("live text omits the rendered text styling")
            }
            if !editor.gestureRecognizers.contains(where: { $0 is NSPanGestureRecognizer }) {
                problems.append("text cannot be dragged while editing")
            }

            let beforeMove = editor.frame.origin
            canvas.moveTextEntry(by: CGPoint(x: 34, y: 21))
            let afterMove = editor.frame.origin
            if abs(afterMove.x - beforeMove.x - 34) > 0.25 || abs(afterMove.y - beforeMove.y - 21) > 0.25 {
                problems.append("the active text did not follow a drag")
            }

            if let activeTextView {
                let committed = canvas.textView(activeTextView, doCommandBy: #selector(NSResponder.insertNewline(_:)))
                if !committed {
                    problems.append("Return did not place the active text")
                } else if case let .text(origin, value, color, fontSize) = session.annotations.last {
                    let imageRect = CaptureGeometry.aspectFit(imageSize: session.imageSize, in: canvas.bounds, padding: 30)
                    let expectedOrigin = CaptureGeometry.imagePoint(
                        fromViewPoint: afterMove,
                        imageRect: imageRect,
                        imageSize: session.imageSize
                    )
                    if value != " Test " { problems.append("committing changed the typed characters") }
                    if color != .coral || abs(fontSize - 24) > 0.01 {
                        problems.append("committing changed the live text style")
                    }
                    if let expectedOrigin,
                       hypot(origin.x - expectedOrigin.x, origin.y - expectedOrigin.y) > 0.25 {
                        problems.append("committed text snapped back after dragging")
                    }
                } else {
                    problems.append("Return did not create a text annotation")
                }
            }
            try expect(problems.isEmpty, problems.joined(separator: "; "))
        }

        runCase("active text follows palette changes", passed: &passed, failed: &failed) {
            let image = try require(makeSolidImage(width: 800, height: 600, color: .white), "could not make text-color fixture")
            let session = EditorSession(image: image)
            session.selectedTool = .text
            session.selectedColor = .coral
            let canvas = AnnotationCanvasNSView(session: session)
            canvas.frame = CGRect(x: 0, y: 0, width: 800, height: 600)

            let down = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: CGPoint(x: 200, y: 200),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )!
            canvas.mouseDown(with: down)
            let editor = try require(canvas.subviews.first as? NSTextView, "text entry did not create an inline editor")
            editor.textStorage?.setAttributedString(NSAttributedString(string: "Palette", attributes: editor.typingAttributes))
            editor.didChangeText()

            session.selectedColor = .blue
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

            let liveColor = try require(
                editor.attributedString().attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
                "active text has no foreground color"
            )
            try expect(
                RGBAColor(liveColor) == .blue,
                "clicking a palette color after starting text leaves the live text in its old color"
            )

            _ = canvas.textView(editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
            if case let .text(_, _, color, _) = session.annotations.last {
                try expect(color == .blue, "committing after a palette change saves the old text color")
            } else {
                throw SelfTestFailure(description: "Return did not create the recolored text annotation")
            }
        }

        runCase("local history retention", passed: &passed, failed: &failed) {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("SnapMarkSelfTest-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let store = HistoryStore(directory: directory, limit: 2)
            let image = try require(DemoImageFactory.make(width: 100, height: 70), "could not make history image")
            _ = try store.save(image, date: Date(timeIntervalSince1970: 1))
            _ = try store.save(image, date: Date(timeIntervalSince1970: 2))
            _ = try store.save(image, date: Date(timeIntervalSince1970: 3))
            try expect(store.items.count == 2, "history retention limit failed")
            try expect(abs((store.items.first?.date.timeIntervalSince1970 ?? 0) - 3) < 1, "newest history item is missing")
            try expect(!store.items.contains { $0.date.timeIntervalSince1970 == 1 }, "oldest history item was not removed")
        }

        runCase("history files are owner-only", passed: &passed, failed: &failed) {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("SnapMarkSelfTest-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o755)]
            )
            let image = try require(DemoImageFactory.make(width: 100, height: 70), "could not make private-history image")
            let data = try require(ExportService.pngData(for: image), "could not encode private-history image")
            let existingURL = directory.appendingPathComponent("ExistingCapture.png")
            try data.write(to: existingURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o644)],
                ofItemAtPath: existingURL.path
            )

            let store = HistoryStore(directory: directory)
            let saved = try store.save(image)
            let directoryMode = try require(
                FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber,
                "history directory has no permission mode"
            ).intValue & 0o777
            let existingMode = try require(
                FileManager.default.attributesOfItem(atPath: existingURL.path)[.posixPermissions] as? NSNumber,
                "existing history item has no permission mode"
            ).intValue & 0o777
            let savedMode = try require(
                FileManager.default.attributesOfItem(atPath: saved.url.path)[.posixPermissions] as? NSNumber,
                "saved history item has no permission mode"
            ).intValue & 0o777

            try expect(directoryMode == 0o700, "history directory is not owner-only")
            try expect(existingMode == 0o600, "existing history item was not made owner-only")
            try expect(savedMode == 0o600, "new history item is not owner-only")
        }

        runCase("history refresh and bounded thumbnails", passed: &passed, failed: &failed) {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("SnapMarkSelfTest-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let store = HistoryStore(directory: directory)
            try expect(store.items.isEmpty, "new history directory was not empty")
            let image = try require(DemoImageFactory.make(width: 1_200, height: 800), "could not make history fixture")
            let data = try require(ExportService.pngData(for: image), "could not encode history fixture")
            let externalURL = directory.appendingPathComponent("ExternalCapture.png")
            try data.write(to: externalURL, options: .atomic)

            store.reload()
            try expect(store.items.count == 1, "history did not discover an externally added capture")
            let thumbnail = try require(
                HistoryStore.loadThumbnail(at: externalURL, maxPixelSize: 180),
                "history thumbnail did not decode"
            )
            try expect(max(thumbnail.width, thumbnail.height) <= 180, "history thumbnail decoded at full resolution")
            let reopened = try require(HistoryStore.loadImage(at: externalURL), "full history image did not decode")
            try expect(reopened.width == 1_200 && reopened.height == 800, "full history image dimensions changed")
        }

        runCase("capture watchdog deadline", passed: &passed, failed: &failed) {
            let probe = TimeoutProbe()
            let semaphore = DispatchSemaphore(value: 0)
            Task.detached {
                let start = Date()
                do {
                    _ = try await AsyncTimeout.run(
                        seconds: 0.05,
                        timeoutError: CaptureServiceError.timedOut("Test capture")
                    ) {
                        try await Task.sleep(for: .seconds(5))
                        return 1
                    }
                } catch let error as CaptureServiceError {
                    if case .timedOut = error {
                        probe.recordTimeout(elapsed: Date().timeIntervalSince(start))
                    }
                } catch {
                    probe.recordUnexpected(error)
                }
                semaphore.signal()
            }

            try expect(semaphore.wait(timeout: .now() + 1) == .success, "capture watchdog never returned")
            let result = probe.snapshot()
            try expect(result.timedOut, "capture watchdog did not report a timeout: \(result.error ?? "no error")")
            try expect(result.elapsed < 0.5, "capture watchdog returned too slowly")
        }

        runCase("moved-bundle detection", passed: &passed, failed: &failed) {
            let missingBundle = FileManager.default.temporaryDirectory
                .appendingPathComponent("Missing-\(UUID().uuidString).app", isDirectory: true)
            let missingExecutable = missingBundle.appendingPathComponent("Contents/MacOS/SnapMark")
            let location = RunningBundleLocation(bundleURL: missingBundle, executableURL: missingExecutable)
            try expect(!location.isAvailable(), "a missing running bundle was reported as available")
        }

        runCase("single-instance process lock", passed: &passed, failed: &failed) {
            let lockURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("SnapMarkSelfTest-\(UUID().uuidString).lock")
            defer { try? FileManager.default.removeItem(at: lockURL) }
            let first = SingleInstanceGuard(lockURL: lockURL)
            let second = SingleInstanceGuard(lockURL: lockURL)
            try expect(first.acquire(), "the first app instance could not acquire its lock")
            try expect(!second.acquire(), "a second app instance acquired the same lock")
            first.release()
            try expect(second.acquire(), "the lock was not released when the first instance quit")
        }

        runCase("single-instance lock refuses symlinks", passed: &passed, failed: &failed) {
            let stem = "SnapMarkSelfTest-\(UUID().uuidString)"
            let targetURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(stem)-target.lock")
            let symlinkURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(stem)-link.lock")
            defer {
                try? FileManager.default.removeItem(at: symlinkURL)
                try? FileManager.default.removeItem(at: targetURL)
            }
            try Data().write(to: targetURL, options: .atomic)
            try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: targetURL)

            let guardInstance = SingleInstanceGuard(lockURL: symlinkURL)
            try expect(!guardInstance.acquire(), "the process lock followed a symbolic link")
        }

        runCase("permission-free capture routing", passed: &passed, failed: &failed) {
            let areaRoute = try CaptureRoute.resolve(mode: .area, hasFullScreenRecordingAccess: false)
            let windowRoute = try CaptureRoute.resolve(mode: .window, hasFullScreenRecordingAccess: false)
            let authorizedRoute = try CaptureRoute.resolve(mode: .area, hasFullScreenRecordingAccess: true)
            try expect(
                areaRoute == .authorizationRequired,
                "unauthorized area capture still launches a process that triggers the recurring macOS prompt"
            )
            try expect(
                windowRoute == .authorizationRequired,
                "unauthorized window capture still starts a recording process"
            )
            try expect(
                authorizedRoute == .systemAreaCapture,
                "full access did not use the area-capture path"
            )

            let authorizedWindow = try CaptureRoute.resolve(mode: .window, hasFullScreenRecordingAccess: true)
            try expect(
                authorizedWindow == .systemWindowCapture,
                "authorized window capture did not start in one-click window-selection mode"
            )

        }

        runCase("end-to-end file export", passed: &passed, failed: &failed) {
            let image = try require(DemoImageFactory.make(width: 400, height: 260), "could not make pipeline image")
            let session = EditorSession(image: image)
            session.add(.pen(points: [CGPoint(x: 30, y: 30), CGPoint(x: 80, y: 90)], color: .violet, width: 7))
            session.addText("Ship it", at: CGPoint(x: 170, y: 150))
            session.crop(to: CGRect(x: 20, y: 20, width: 340, height: 210))
            session.add(.blackout(rect: CGRect(x: 15, y: 15, width: 40, height: 30)))
            let output = try session.renderedImage()
            let data = try require(ExportService.pngData(for: output), "pipeline PNG encoding failed")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("SnapMarkSelfTest-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: url) }
            try data.write(to: url, options: .atomic)
            let reopened = try require(NSImage(contentsOf: url), "exported file did not reopen")
            var rect = CGRect(origin: .zero, size: reopened.size)
            let decoded = try require(reopened.cgImage(forProposedRect: &rect, context: nil, hints: nil), "reopened file had no pixels")
            try expect(decoded.width == 340 && decoded.height == 210, "pipeline export dimensions are wrong")
        }

        print("\nSnapMark self-test: \(passed) passed, \(failed) failed")
        return failed == 0 ? 0 : 1
    }

    private static func runCase(
        _ name: String,
        passed: inout Int,
        failed: inout Int,
        body: () throws -> Void
    ) {
        do {
            try body()
            passed += 1
            print("PASS  \(name)")
        } catch {
            failed += 1
            print("FAIL  \(name): \(error)")
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw SelfTestFailure(description: message) }
    }

    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw SelfTestFailure(description: message) }
        return value
    }

    private static func makeSolidImage(width: Int, height: Int, color: NSColor) -> CGImage? {
        drawImage(width: width, height: height) {
            color.setFill()
            CGRect(x: 0, y: 0, width: width, height: height).fill()
        }
    }

    private static func makeSplitImage(width: Int, height: Int) -> CGImage? {
        drawImage(width: width, height: height) {
            NSColor.systemRed.setFill()
            CGRect(x: 0, y: 0, width: width, height: height / 2).fill()
            NSColor.systemBlue.setFill()
            CGRect(x: 0, y: height / 2, width: width, height: height / 2).fill()
        }
    }

    private static func makeCheckerboardImage(width: Int, height: Int) -> CGImage? {
        drawImage(width: width, height: height) {
            for y in 0..<height {
                for x in 0..<width {
                    ((x + y).isMultiple(of: 2) ? NSColor.black : NSColor.white).setFill()
                    CGRect(x: x, y: y, width: 1, height: 1).fill()
                }
            }
        }
    }

    private static func drag(canvas: AnnotationCanvasNSView, from start: CGPoint, to end: CGPoint) {
        let down = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: start,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )!
        let dragged = NSEvent.mouseEvent(
            with: .leftMouseDragged,
            location: end,
            modifierFlags: [],
            timestamp: 0.1,
            windowNumber: 0,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 1
        )!
        let up = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: end,
            modifierFlags: [],
            timestamp: 0.2,
            windowNumber: 0,
            context: nil,
            eventNumber: 3,
            clickCount: 1,
            pressure: 0
        )!
        canvas.mouseDown(with: down)
        canvas.mouseDragged(with: dragged)
        canvas.mouseUp(with: up)
    }

    private static func annotation(_ annotation: Annotation, matches tool: EditorTool) -> Bool {
        switch (annotation, tool) {
        case (.pen, .pen), (.highlight, .highlight), (.arrow, .arrow),
             (.rectangle, .rectangle), (.pixelate, .pixelate), (.blackout, .blackout):
            return true
        default:
            return false
        }
    }

    private static func drawImage(width: Int, height: Int, drawing: () -> Void) -> CGImage? {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: representation) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        drawing()
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return representation.cgImage
    }
}

private final class TimeoutProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var didTimeOut = false
    private var elapsedSeconds: TimeInterval = .infinity
    private var unexpectedError: String?

    func recordTimeout(elapsed: TimeInterval) {
        lock.lock()
        didTimeOut = true
        elapsedSeconds = elapsed
        lock.unlock()
    }

    func recordUnexpected(_ error: Error) {
        lock.lock()
        unexpectedError = error.localizedDescription
        lock.unlock()
    }

    func snapshot() -> (timedOut: Bool, elapsed: TimeInterval, error: String?) {
        lock.lock()
        let result = (didTimeOut, elapsedSeconds, unexpectedError)
        lock.unlock()
        return result
    }
}

private final class OverlayRetirementProbeWindow: NSWindow {
    private(set) var didClose = false

    override func close() {
        didClose = true
        super.close()
    }
}

private extension NSColor {
    func colorDistance(to other: NSColor) -> CGFloat {
        let lhs = usingColorSpace(.sRGB) ?? self
        let rhs = other.usingColorSpace(.sRGB) ?? other
        return abs(lhs.redComponent - rhs.redComponent)
            + abs(lhs.greenComponent - rhs.greenComponent)
            + abs(lhs.blueComponent - rhs.blueComponent)
    }

    var isNearlyBlack: Bool {
        let color = usingColorSpace(.sRGB) ?? self
        return color.redComponent < 0.05 && color.greenComponent < 0.05 && color.blueComponent < 0.05
    }

    var isNearlyWhite: Bool {
        let color = usingColorSpace(.sRGB) ?? self
        return color.redComponent > 0.95 && color.greenComponent > 0.95 && color.blueComponent > 0.95
    }

    var isMostlyRed: Bool {
        let color = usingColorSpace(.sRGB) ?? self
        return color.redComponent > 0.7 && color.redComponent > color.blueComponent * 1.7
    }
}

private extension NSBitmapImageRep {
    func colorAtBottomLeft(x: Int, y: Int) -> NSColor? {
        colorAt(x: x, y: pixelsHigh - 1 - y)
    }
}
