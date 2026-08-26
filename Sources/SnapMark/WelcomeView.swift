import AppKit
import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var history: HistoryStore
    @ObservedObject private var preferences: AppPreferences

    init() {
        history = AppModel.shared.history
        preferences = AppModel.shared.preferences
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(red: 0.91, green: 0.94, blue: 1.0).opacity(0.42)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 34) {
                        captureCard
                        recentCaptures
                    }
                    .padding(.horizontal, 52)
                    .padding(.top, 54)
                    .padding(.bottom, 44)
                    .frame(maxWidth: 1060)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear { history.reload() }
    }

    private var topBar: some View {
        ZStack {
            WindowDragArea()
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.30, green: 0.48, blue: 1), Color(red: 0.52, green: 0.31, blue: 0.96)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 34, height: 34)
                    .overlay(Image(systemName: "viewfinder").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white))
                    .shadow(color: .blue.opacity(0.22), radius: 7, y: 3)

                Text("SnapMark")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Spacer()
                Button {
                    history.revealInFinder()
                } label: {
                    Label("Open captures", systemImage: "folder")
                }
                .buttonStyle(.borderless)
                .disabled(history.items.isEmpty)

                SettingsLink {
                    Image(systemName: "gearshape")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help("Settings")
            }
            .padding(.leading, 84)
            .padding(.trailing, 20)
        }
        .frame(height: 58)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var captureCard: some View {
        VStack(spacing: 26) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.10))
                    .frame(width: 88, height: 88)
                Circle()
                    .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
                    .frame(width: 70, height: 70)
                Image(systemName: "viewfinder")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 8) {
                Text("Capture. Mark. Done.")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Select across displays, then crop, draw, type, or hide details.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    model.beginCapture(.area)
                } label: {
                    Label("Capture area", systemImage: "viewfinder")
                        .frame(minWidth: 132)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("2", modifiers: [.command, .shift])

                Button {
                    model.beginCapture(.window)
                } label: {
                    Label("Capture window", systemImage: "macwindow")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            HStack(spacing: 12) {
                Text("Delay")
                    .foregroundStyle(.secondary)
                Picker("Delay", selection: $preferences.delaySeconds) {
                    Text("None").tag(0)
                    Text("3 sec").tag(3)
                    Text("5 sec").tag(5)
                    Text("10 sec").tag(10)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 270)

                Divider().frame(height: 20)
                Text("⌃⇧⌘4 anywhere")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 42)
        .padding(.horizontal, 54)
        .frame(maxWidth: 690)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.55), lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: 30, y: 14)
    }

    @ViewBuilder
    private var recentCaptures: some View {
        if history.items.isEmpty {
            VStack(spacing: 8) {
                Text("Recent captures will appear here")
                    .font(.system(size: 14, weight: .medium))
                Text("SnapMark keeps the latest 30 on this Mac.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 4)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Recent")
                        .font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Text("\(history.items.count) captures")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(history.items.prefix(12)) { item in
                            RecentCaptureCard(item: item) { model.open(item) }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
            .frame(maxWidth: 860)
        }
    }
}

private struct RecentCaptureCard: View {
    let item: HistoryItem
    let action: () -> Void
    @State private var thumbnail: NSImage?

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.secondary.opacity(0.1)
                            .overlay(ProgressView().controlSize(.small))
                    }
                }
                .frame(width: 184, height: 104)
                .clipped()
                .background(Color.black.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Text(item.date, style: .relative)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(9)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .task(id: item.id) {
            let image = await Task.detached(priority: .utility) {
                HistoryStore.loadThumbnail(at: item.url)
            }.value
            guard !Task.isCancelled, let image else { return }
            thumbnail = NSImage(
                cgImage: image,
                size: CGSize(width: image.width, height: image.height)
            )
        }
    }
}
