import AppKit

enum DemoImageFactory {
    static func make(width: Int = 1280, height: Int = 760) -> CGImage? {
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
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        NSGradient(colors: [
            NSColor(srgbRed: 0.10, green: 0.13, blue: 0.20, alpha: 1),
            NSColor(srgbRed: 0.17, green: 0.23, blue: 0.36, alpha: 1)
        ])?.draw(in: bounds, angle: 22)

        let card = CGRect(x: 145, y: 115, width: 990, height: 530)
        NSColor.white.withAlphaComponent(0.96).setFill()
        NSBezierPath(roundedRect: card, xRadius: 28, yRadius: 28).fill()

        let title: NSString = "A clean screenshot starts with a clear point."
        title.draw(
            at: CGPoint(x: 215, y: 500),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 36, weight: .bold),
                .foregroundColor: NSColor(srgbRed: 0.10, green: 0.12, blue: 0.17, alpha: 1)
            ]
        )
        let body: NSString = "Use the toolbar to draw, add text, hide sensitive details, or crop again."
        body.draw(
            at: CGPoint(x: 215, y: 442),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 20, weight: .regular),
                .foregroundColor: NSColor(srgbRed: 0.34, green: 0.37, blue: 0.44, alpha: 1)
            ]
        )

        for index in 0..<4 {
            let bar = CGRect(x: 215, y: 240 + CGFloat(index * 42), width: CGFloat(390 + index * 95), height: 18)
            NSColor(srgbRed: 0.82, green: 0.85, blue: 0.91, alpha: 1).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 9, yRadius: 9).fill()
        }

        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return representation.cgImage
    }
}
