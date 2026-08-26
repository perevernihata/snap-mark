import CoreGraphics

enum CaptureGeometry {
    static func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    static func aspectFit(imageSize: CGSize, in bounds: CGRect, padding: CGFloat = 0) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }

        let available = bounds.insetBy(dx: padding, dy: padding)
        let scale = min(available.width / imageSize.width, available.height / imageSize.height)
        let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: available.midX - fittedSize.width / 2,
            y: available.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    static func imagePoint(
        fromViewPoint point: CGPoint,
        imageRect: CGRect,
        imageSize: CGSize
    ) -> CGPoint? {
        guard imageRect.contains(point), imageRect.width > 0, imageRect.height > 0 else { return nil }
        return CGPoint(
            x: (point.x - imageRect.minX) * imageSize.width / imageRect.width,
            y: (point.y - imageRect.minY) * imageSize.height / imageRect.height
        )
    }

    static func viewPoint(
        fromImagePoint point: CGPoint,
        imageRect: CGRect,
        imageSize: CGSize
    ) -> CGPoint {
        CGPoint(
            x: imageRect.minX + point.x * imageRect.width / imageSize.width,
            y: imageRect.minY + point.y * imageRect.height / imageSize.height
        )
    }

    /// Converts a selection measured from the bottom-left of a point-sized canvas
    /// into the top-left pixel coordinates expected by CGImage cropping.
    static func pixelCropRect(
        selection: CGRect,
        canvasSize: CGSize,
        imageSize: CGSize
    ) -> CGRect {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return .zero }

        let clipped = selection.standardized.intersection(CGRect(origin: .zero, size: canvasSize))
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return .zero }

        let scaleX = imageSize.width / canvasSize.width
        let scaleY = imageSize.height / canvasSize.height
        let minX = floor(clipped.minX * scaleX)
        let minY = floor((canvasSize.height - clipped.maxY) * scaleY)
        let maxX = ceil(clipped.maxX * scaleX)
        let maxY = ceil((canvasSize.height - clipped.minY) * scaleY)

        return CGRect(
            x: max(0, minX),
            y: max(0, minY),
            width: min(imageSize.width, maxX) - max(0, minX),
            height: min(imageSize.height, maxY) - max(0, minY)
        ).integral
    }

    /// Scales a bottom-left selection from display points into image pixels.
    /// This is useful when the image is drawn through AppKit, which also uses
    /// bottom-left coordinates.
    static func bottomLeftImageRect(
        selection: CGRect,
        canvasSize: CGSize,
        imageSize: CGSize
    ) -> CGRect {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return .zero }
        let clipped = selection.standardized.intersection(CGRect(origin: .zero, size: canvasSize))
        guard !clipped.isNull else { return .zero }

        let scaleX = imageSize.width / canvasSize.width
        let scaleY = imageSize.height / canvasSize.height
        return CGRect(
            x: floor(clipped.minX * scaleX),
            y: floor(clipped.minY * scaleY),
            width: ceil(clipped.width * scaleX),
            height: ceil(clipped.height * scaleY)
        ).integral
    }

    static func clamped(_ rect: CGRect, to size: CGSize, minimumSize: CGFloat = 1) -> CGRect? {
        let result = rect.standardized.intersection(CGRect(origin: .zero, size: size)).integral
        guard !result.isNull, result.width >= minimumSize, result.height >= minimumSize else { return nil }
        return result
    }
}
