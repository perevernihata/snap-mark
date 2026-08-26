import SwiftUI

struct EditorView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var session: EditorSession

    var body: some View {
        VStack(spacing: 0) {
            editorTopBar
            Divider()
            toolBar
            Divider()
            HStack(spacing: 0) {
                AnnotationCanvas(session: session)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.105, green: 0.11, blue: 0.13), Color(red: 0.15, green: 0.16, blue: 0.19)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Divider()
                inspector
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var editorTopBar: some View {
        ZStack {
            WindowDragArea()
            HStack(spacing: 8) {
                Button {
                    model.closeEditor()
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderless)
                .help("Back to captures")

                RoundedRectangle(cornerRadius: 7)
                    .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 27, height: 27)
                    .overlay(Image(systemName: "viewfinder").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white))
                Text("SnapMark")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))

                Divider().frame(height: 20).padding(.horizontal, 5)

                Button(action: model.undo) { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!session.canUndo)
                    .help("Undo ⌘Z")
                Button(action: model.redo) { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!session.canRedo)
                    .help("Redo ⇧⌘Z")

                Spacer()
                Text("\(Int(session.imageSize.width)) × \(Int(session.imageSize.height))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())

                Button(action: model.share) {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("Share")

                Button(action: model.save) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)

                Button(action: model.copy) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            .padding(.leading, 78)
            .padding(.trailing, 15)
        }
        .frame(height: 58)
        .background(.ultraThinMaterial)
    }

    private var toolBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                toolGroup([.pen, .highlight, .arrow, .rectangle, .text])
                toolbarDivider
                toolGroup([.pixelate, .blackout])
                toolbarDivider
                toolGroup([.crop])
            }
            .padding(.horizontal, 18)
        }
        .frame(height: 62)
        .background(.ultraThinMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Editing tools")
    }

    @ViewBuilder
    private func toolGroup(_ tools: [EditorTool]) -> some View {
        ForEach(tools) { tool in
            EditorToolButton(
                tool: tool,
                isSelected: session.selectedTool == tool,
                action: { session.selectedTool = tool }
            )
        }
    }

    private var toolbarDivider: some View {
        Divider()
            .frame(height: 28)
            .padding(.horizontal, 3)
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    Image(systemName: session.selectedTool.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32, height: 32)
                        .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("SELECTED TOOL")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.7)
                            .foregroundStyle(.tertiary)
                        Text(session.selectedTool.title)
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                Text(toolHint)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if session.selectedTool == .pixelate || session.selectedTool == .blackout {
                Label("Applied permanently when copied or saved", systemImage: "checkmark.shield.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            if session.selectedTool != .pixelate && session.selectedTool != .blackout && session.selectedTool != .crop {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Color")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 9), count: 4), spacing: 9) {
                        ForEach(palette, id: \.self) { color in
                            Button {
                                session.selectedColor = color
                            } label: {
                                Circle()
                                    .fill(Color(nsColor: color.nsColor))
                                    .frame(width: 26, height: 26)
                                    .overlay(
                                        Circle().stroke(.primary.opacity(session.selectedColor == color ? 0.8 : 0.12), lineWidth: session.selectedColor == color ? 2 : 1)
                                    )
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(colorName(color))
                            .accessibilityValue(session.selectedColor == color ? "Selected" : "")
                        }
                    }
                }
            }

            if session.selectedTool != .pixelate && session.selectedTool != .blackout && session.selectedTool != .crop && session.selectedTool != .text {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Size")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(session.lineWidth)) px")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $session.lineWidth, in: 2...18, step: 1)
                }
            }

            Divider()
            VStack(alignment: .leading, spacing: 9) {
                Label("Esc cancels a live edit", systemImage: "escape")
                Label("⌘Z undoes any edit", systemImage: "arrow.uturn.backward")
                if session.selectedTool == .text {
                    Label("Return places the text", systemImage: "return")
                    Label("Drag text while typing to move it", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            if let message = session.statusMessage {
                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            }

            Spacer()

            Button {
                model.beginCapture(.area)
            } label: {
                Label("New capture", systemImage: "plus.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(18)
        .frame(width: 230)
        .background(FrostedBackground(material: .sidebar))
    }

    private var palette: [RGBAColor] {
        [.coral, .orange, .yellow, .mint, .blue, .violet, .white, .black]
    }

    private var toolHint: String {
        switch session.selectedTool {
        case .pen: return "Draw freehand on the image."
        case .highlight: return "Sweep over anything that needs emphasis."
        case .arrow: return "Drag from the start to the point of interest."
        case .rectangle: return "Drag a box around an area."
        case .text: return "Click and type. Drag to move; Return places it."
        case .pixelate: return "Drag over sensitive details to hide them."
        case .blackout: return "Drag to replace exported pixels with solid black. The raw capture remains in local history."
        case .crop: return "Drag the part to keep. The crop applies on release."
        }
    }

    private func colorName(_ color: RGBAColor) -> String {
        switch color {
        case .coral: return "Coral"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .mint: return "Mint"
        case .blue: return "Blue"
        case .violet: return "Violet"
        case .white: return "White"
        case .black: return "Black"
        default: return "Annotation color"
        }
    }
}

private struct EditorToolButton: View {
    let tool: EditorTool
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: tool.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 17)
                Text(tool.title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.82))
            .padding(.horizontal, 11)
            .frame(height: 36)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .background(
                isSelected ? Color.accentColor.opacity(0.13) : Color.primary.opacity(isHovered ? 0.06 : 0),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("\(tool.title) (\(tool.shortcut))")
        .accessibilityLabel(tool.title)
        .accessibilityValue(isSelected ? "Selected" : "")
    }
}
