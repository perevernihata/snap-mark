import AppKit
import Combine

private struct EditorSnapshot {
    let baseImage: CGImage
    let annotations: [Annotation]
}

@MainActor
final class EditorSession: ObservableObject {
    @Published private(set) var baseImage: CGImage
    @Published private(set) var annotations: [Annotation] = []
    @Published var selectedTool: EditorTool = .arrow
    @Published var selectedColor: RGBAColor = .coral
    @Published var lineWidth: CGFloat = 6
    @Published var textFontSize: CGFloat = TextAnnotationStyle.defaultFontSize
    @Published var statusMessage: String?
    let textEntryFocusRequests = PassthroughSubject<Void, Never>()

    private var undoStack: [EditorSnapshot] = []
    private var redoStack: [EditorSnapshot] = []
    private let stackLimit = 50

    init(image: CGImage) {
        baseImage = image
    }

    var imageSize: CGSize {
        CGSize(width: baseImage.width, height: baseImage.height)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func add(_ annotation: Annotation) {
        pushUndo()
        annotations.append(annotation)
        statusMessage = nil
    }

    func addText(_ value: String, at origin: CGPoint) {
        addText(
            value,
            at: origin,
            color: selectedColor,
            fontSize: textFontSize
        )
    }

    func addText(_ value: String, at origin: CGPoint, color: RGBAColor, fontSize: CGFloat) {
        guard value.rangeOfCharacter(from: .whitespacesAndNewlines.inverted) != nil else { return }
        add(.text(
            origin: origin,
            value: value,
            color: color,
            fontSize: TextAnnotationStyle.clampedFontSize(fontSize)
        ))
    }

    func requestTextEntryFocus() {
        textEntryFocusRequests.send()
    }

    func crop(to rect: CGRect) {
        guard let clipped = CaptureGeometry.clamped(rect, to: imageSize, minimumSize: 12) else {
            statusMessage = "Drag a larger crop area."
            return
        }

        do {
            let flattened = try ImageRenderer.render(baseImage: baseImage, annotations: annotations)
            let cropped = try ImageRenderer.crop(image: flattened, to: clipped)
            pushUndo()
            baseImage = cropped
            annotations = []
            statusMessage = "Cropped to \(cropped.width) × \(cropped.height)"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(EditorSnapshot(baseImage: baseImage, annotations: annotations))
        baseImage = snapshot.baseImage
        annotations = snapshot.annotations
        statusMessage = "Undid last edit"
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(EditorSnapshot(baseImage: baseImage, annotations: annotations))
        baseImage = snapshot.baseImage
        annotations = snapshot.annotations
        statusMessage = "Redid edit"
    }

    func renderedImage() throws -> CGImage {
        try ImageRenderer.render(baseImage: baseImage, annotations: annotations)
    }

    private func pushUndo() {
        undoStack.append(EditorSnapshot(baseImage: baseImage, annotations: annotations))
        if undoStack.count > stackLimit {
            undoStack.removeFirst(undoStack.count - stackLimit)
        }
        redoStack.removeAll()
    }
}
