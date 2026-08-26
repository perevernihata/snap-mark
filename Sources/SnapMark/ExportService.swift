import AppKit
import UniformTypeIdentifiers

enum ExportServiceError: LocalizedError {
    case encodingFailed
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "SnapMark could not encode the image."
        case .saveFailed: return "SnapMark could not save the image."
        }
    }
}

@MainActor
enum ExportService {
    static func copyToClipboard(_ image: CGImage) throws {
        guard let data = pngData(for: image) else { throw ExportServiceError.encodingFailed }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setData(data, forType: .png) else { throw ExportServiceError.saveFailed }
    }

    @discardableResult
    static func showSavePanel(for image: CGImage, suggestedName: String) throws -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save screenshot"
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [.png, .jpeg]
        panel.isExtensionHidden = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let isJPEG = ["jpg", "jpeg"].contains(url.pathExtension.lowercased())
        let data = isJPEG ? jpegData(for: image) : pngData(for: image)
        guard let data else { throw ExportServiceError.encodingFailed }
        try data.write(to: url, options: .atomic)
        return url
    }

    static func showSharePicker(for image: CGImage) {
        let nsImage = NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
        guard let contentView = NSApp.keyWindow?.contentView else { return }
        NSSharingServicePicker(items: [nsImage]).show(
            relativeTo: CGRect(x: contentView.bounds.midX, y: contentView.bounds.maxY, width: 1, height: 1),
            of: contentView,
            preferredEdge: .minY
        )
    }

    static func pngData(for image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    static func jpegData(for image: CGImage, quality: CGFloat = 0.92) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(
            using: .jpeg,
            properties: [.compressionFactor: quality]
        )
    }
}
