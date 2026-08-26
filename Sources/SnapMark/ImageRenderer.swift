import AppKit
import CoreGraphics

enum ImageRendererError: LocalizedError {
    case bitmapCreationFailed
    case cropFailed

    var errorDescription: String? {
        switch self {
        case .bitmapCreationFailed: return "SnapMark could not create an image buffer."
        case .cropFailed: return "The selected crop area is not valid."
        }
    }
}

enum ImageRenderer {
    static func render(baseImage: CGImage, annotations: [Annotation]) throws -> CGImage {
        let width = baseImage.width
        let height = baseImage.height
        guard let representation = makeBitmap(width: width, height: height),
              let context = NSGraphicsContext(bitmapImageRep: representation) else {
            throw ImageRendererError.bitmapCreationFailed
        }

        let size = CGSize(width: width, height: height)
        let bounds = CGRect(origin: .zero, size: size)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        NSImage(cgImage: baseImage, size: size).draw(
            in: bounds,
            from: .zero,
            operation: .copy,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )

        let ordinaryAnnotations = annotations.filter { !$0.isPrivacyEdit }
        for annotation in ordinaryAnnotations {
            draw(annotation, in: bounds, representation: representation, context: context)
        }

        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let output = representation.cgImage else {
            throw ImageRendererError.bitmapCreationFailed
        }
        let privacyAnnotations = annotations.filter(\.isPrivacyEdit)
        guard !privacyAnnotations.isEmpty else { return output }
        return try renderPrivacyEdits(baseImage: output, annotations: privacyAnnotations)
    }

    static func crop(image: CGImage, to rect: CGRect) throws -> CGImage {
        let sourceSize = CGSize(width: image.width, height: image.height)
        guard let clipped = CaptureGeometry.clamped(rect, to: sourceSize, minimumSize: 2) else {
            throw ImageRendererError.cropFailed
        }

        guard let representation = makeBitmap(
            width: Int(clipped.width.rounded(.down)),
            height: Int(clipped.height.rounded(.down))
        ), let context = NSGraphicsContext(bitmapImageRep: representation) else {
            throw ImageRendererError.bitmapCreationFailed
        }

        let destination = CGRect(x: 0, y: 0, width: clipped.width, height: clipped.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        NSImage(cgImage: image, size: sourceSize).draw(
            in: destination,
            from: clipped,
            operation: .copy,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let cropped = representation.cgImage else { throw ImageRendererError.cropFailed }
        return cropped
    }

    private static func draw(
        _ annotation: Annotation,
        in bounds: CGRect,
        representation: NSBitmapImageRep,
        context: NSGraphicsContext
    ) {
        switch annotation {
        case let .pen(points, color, width):
            stroke(points: points, color: color.nsColor, width: width)

        case let .highlight(points, color, width):
            stroke(points: points, color: color.nsColor.withAlphaComponent(0.34), width: width, lineCap: .square)

        case let .arrow(start, end, color, width):
            let path = NSBezierPath()
            path.move(to: start)
            path.line(to: end)
            path.lineWidth = width
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            color.nsColor.setStroke()
            path.stroke()

            let angle = atan2(end.y - start.y, end.x - start.x)
            let headLength = max(14, width * 4.5)
            let head = NSBezierPath()
            head.move(to: CGPoint(
                x: end.x - headLength * cos(angle - .pi / 6),
                y: end.y - headLength * sin(angle - .pi / 6)
            ))
            head.line(to: end)
            head.line(to: CGPoint(
                x: end.x - headLength * cos(angle + .pi / 6),
                y: end.y - headLength * sin(angle + .pi / 6)
            ))
            head.lineWidth = width
            head.lineCapStyle = .round
            head.lineJoinStyle = .round
            head.stroke()

        case let .rectangle(rect, color, width):
            let path = NSBezierPath(roundedRect: rect.standardized, xRadius: width * 1.4, yRadius: width * 1.4)
            path.lineWidth = width
            color.nsColor.setStroke()
            path.stroke()

        case let .text(origin, value, color, fontSize):
            (value as NSString).draw(
                at: origin,
                withAttributes: TextAnnotationStyle.attributes(color: color, fontSize: fontSize)
            )

        case let .pixelate(rect):
            assertionFailure("Privacy edits are rendered in a separate flattening pass: \(rect)")

        case let .blackout(rect):
            assertionFailure("Privacy edits are rendered in a separate flattening pass: \(rect)")
        }
    }

    private static func renderPrivacyEdits(
        baseImage: CGImage,
        annotations: [Annotation]
    ) throws -> CGImage {
        guard let representation = makeBitmap(width: baseImage.width, height: baseImage.height),
              let context = NSGraphicsContext(bitmapImageRep: representation) else {
            throw ImageRendererError.bitmapCreationFailed
        }

        let size = CGSize(width: baseImage.width, height: baseImage.height)
        let bounds = CGRect(origin: .zero, size: size)
        let source = NSBitmapImageRep(cgImage: baseImage)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSImage(cgImage: baseImage, size: size).draw(
            in: bounds,
            from: .zero,
            operation: .copy,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )

        // Pixelate first and blackout last so an overlapping pixelation can never reveal
        // pixels that the user explicitly replaced with solid black.
        for annotation in annotations {
            guard case let .pixelate(rect) = annotation else { continue }
            drawPixelation(in: rect, source: source)
        }
        for annotation in annotations {
            guard case let .blackout(rect) = annotation else { continue }
            NSColor.black.setFill()
            rect.standardized.intersection(bounds).fill()
        }

        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let result = representation.cgImage else {
            throw ImageRendererError.bitmapCreationFailed
        }
        return result
    }

    private static func stroke(
        points: [CGPoint],
        color: NSColor,
        width: CGFloat,
        lineCap: NSBezierPath.LineCapStyle = .round
    ) {
        guard let first = points.first else { return }
        let path = NSBezierPath()
        path.move(to: first)
        for point in points.dropFirst() {
            path.line(to: point)
        }
        path.lineWidth = width
        path.lineCapStyle = lineCap
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }

    private static func drawPixelation(
        in rect: CGRect,
        source: NSBitmapImageRep
    ) {
        let imageSize = CGSize(width: source.pixelsWide, height: source.pixelsHigh)
        guard let clipped = CaptureGeometry.clamped(rect, to: imageSize, minimumSize: 2) else { return }

        // Explicit block fills are reliable across Retina and color spaces. The previous
        // in-place NSImage downscale/upscale path cached the pre-edit CGImage and silently
        // returned the untouched source image.
        let blockSize = max(10, min(18, floor(min(clipped.width, clipped.height) / 5)))

        var y = clipped.minY
        while y < clipped.maxY {
            var x = clipped.minX
            while x < clipped.maxX {
                let block = CGRect(
                    x: x,
                    y: y,
                    width: min(blockSize, clipped.maxX - x),
                    height: min(blockSize, clipped.maxY - y)
                )
                if let color = averageColor(in: block, representation: source) {
                    color.setFill()
                    block.fill()
                }
                x += blockSize
            }
            y += blockSize
        }
    }

    private static func averageColor(in rect: CGRect, representation: NSBitmapImageRep) -> NSColor? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        var count: CGFloat = 0

        for yFraction in [0.2, 0.5, 0.8] as [CGFloat] {
            for xFraction in [0.2, 0.5, 0.8] as [CGFloat] {
                let x = min(representation.pixelsWide - 1, max(0, Int(rect.minX + rect.width * xFraction)))
                let bottomLeftY = min(representation.pixelsHigh - 1, max(0, Int(rect.minY + rect.height * yFraction)))
                let bitmapY = representation.pixelsHigh - 1 - bottomLeftY
                guard let raw = representation.colorAt(x: x, y: bitmapY),
                      let color = raw.usingColorSpace(.sRGB) else { continue }
                red += color.redComponent
                green += color.greenComponent
                blue += color.blueComponent
                alpha += color.alphaComponent
                count += 1
            }
        }

        guard count > 0 else { return nil }
        return NSColor(
            srgbRed: red / count,
            green: green / count,
            blue: blue / count,
            alpha: alpha / count
        )
    }

    private static func makeBitmap(width: Int, height: Int) -> NSBitmapImageRep? {
        guard width > 0, height > 0 else { return nil }
        return NSBitmapImageRep(
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
        )
    }
}

private extension Annotation {
    var isPrivacyEdit: Bool {
        switch self {
        case .pixelate, .blackout: return true
        default: return false
        }
    }
}
