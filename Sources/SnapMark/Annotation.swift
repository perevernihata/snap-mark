import AppKit

struct RGBAColor: Equatable, Codable, Hashable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat = 1

    init(_ color: NSColor) {
        let converted = color.usingColorSpace(.sRGB) ?? color
        red = converted.redComponent
        green = converted.greenComponent
        blue = converted.blueComponent
        alpha = converted.alphaComponent
    }

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    static let coral = RGBAColor(red: 0.98, green: 0.27, blue: 0.32)
    static let orange = RGBAColor(red: 1.00, green: 0.57, blue: 0.16)
    static let yellow = RGBAColor(red: 1.00, green: 0.82, blue: 0.17)
    static let mint = RGBAColor(red: 0.20, green: 0.78, blue: 0.58)
    static let blue = RGBAColor(red: 0.20, green: 0.53, blue: 0.96)
    static let violet = RGBAColor(red: 0.58, green: 0.38, blue: 0.96)
    static let white = RGBAColor(red: 1, green: 1, blue: 1)
    static let black = RGBAColor(red: 0.08, green: 0.09, blue: 0.11)
}

enum TextAnnotationStyle {
    static let defaultFontSize: CGFloat = 24
    static let fontSizeRange: ClosedRange<CGFloat> = 12...72

    static func clampedFontSize(_ fontSize: CGFloat) -> CGFloat {
        min(max(fontSizeRange.lowerBound, fontSize), fontSizeRange.upperBound)
    }

    static func attributes(color: RGBAColor, fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: color.nsColor,
            .strokeColor: NSColor.black.withAlphaComponent(0.18),
            .strokeWidth: -0.7
        ]
    }
}

enum EditorTool: String, CaseIterable, Identifiable {
    case pen
    case highlight
    case arrow
    case rectangle
    case text
    case pixelate
    case blackout
    case crop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pen: return "Pen"
        case .highlight: return "Highlight"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .text: return "Text"
        case .pixelate: return "Pixelate"
        case .blackout: return "Blackout"
        case .crop: return "Crop"
        }
    }

    var systemImage: String {
        switch self {
        case .pen: return "pencil.tip"
        case .highlight: return "highlighter"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .text: return "textformat"
        case .pixelate: return "square.grid.3x3.square"
        case .blackout: return "rectangle.fill"
        case .crop: return "crop"
        }
    }

    var shortcut: String {
        switch self {
        case .pen: return "P"
        case .highlight: return "H"
        case .arrow: return "A"
        case .rectangle: return "R"
        case .text: return "T"
        case .pixelate: return "B"
        case .blackout: return "X"
        case .crop: return "C"
        }
    }
}

enum Annotation: Equatable {
    case pen(points: [CGPoint], color: RGBAColor, width: CGFloat)
    case highlight(points: [CGPoint], color: RGBAColor, width: CGFloat)
    case arrow(start: CGPoint, end: CGPoint, color: RGBAColor, width: CGFloat)
    case rectangle(rect: CGRect, color: RGBAColor, width: CGFloat)
    case text(origin: CGPoint, value: String, color: RGBAColor, fontSize: CGFloat)
    case pixelate(rect: CGRect)
    case blackout(rect: CGRect)
}
