import AppKit
import Combine
import Foundation
import ImageIO

struct HistoryItem: Identifiable, Hashable {
    let url: URL
    let date: Date

    var id: URL { url }
}

enum HistoryStoreError: LocalizedError {
    case privateStorageUnavailable

    var errorDescription: String? {
        "SnapMark could not secure its Recent capture folder. Recent history is unavailable."
    }
}

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [HistoryItem] = []

    let directory: URL
    private let fileManager: FileManager
    private let limit: Int
    private var storageIsPrivate = false

    init(directory: URL? = nil, fileManager: FileManager = .default, limit: Int = 30) {
        self.fileManager = fileManager
        self.limit = limit

        if let directory {
            self.directory = directory
        } else if let override = ProcessInfo.processInfo.environment["SNAPMARK_HISTORY_DIR"], !override.isEmpty {
            self.directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.directory = support.appendingPathComponent("SnapMark/Captures", isDirectory: true)
        }

        storageIsPrivate = secureDirectory()
        reload()
    }

    @discardableResult
    func save(_ image: CGImage, date: Date = Date()) throws -> HistoryItem {
        guard secureDirectory() else {
            throw HistoryStoreError.privateStorageUnavailable
        }
        guard let data = ExportService.pngData(for: image) else {
            throw ExportServiceError.encodingFailed
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        let url = uniqueURL(stem: "SnapMark_\(formatter.string(from: date))")
        try data.write(to: url, options: .atomic)
        do {
            try fileManager.setAttributes([
                .modificationDate: date,
                .posixPermissions: NSNumber(value: 0o600)
            ], ofItemAtPath: url.path)
        } catch {
            try? fileManager.removeItem(at: url)
            throw HistoryStoreError.privateStorageUnavailable
        }
        reload()
        trimIfNeeded()
        return HistoryItem(url: url, date: date)
    }

    func load(_ item: HistoryItem) -> CGImage? {
        Self.loadImage(at: item.url)
    }

    nonisolated static func loadImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
    }

    nonisolated static func loadThumbnail(at url: URL, maxPixelSize: Int = 420) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    func reload() {
        guard storageIsPrivate || secureDirectory() else {
            items = []
            return
        }

        let keys: Set<URLResourceKey> = [
            .creationDateKey,
            .contentModificationDateKey,
            .isRegularFileKey,
            .isSymbolicLinkKey
        ]
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )) ?? []

        items = urls.compactMap { url -> HistoryItem? in
            guard url.pathExtension.lowercased() == "png",
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true else { return nil }
            do {
                try fileManager.setAttributes(
                    [.posixPermissions: NSNumber(value: 0o600)],
                    ofItemAtPath: url.path
                )
            } catch {
                return nil
            }
            return HistoryItem(url: url, date: values.contentModificationDate ?? values.creationDate ?? .distantPast)
        }.sorted { $0.date > $1.date }
    }

    @discardableResult
    private func secureDirectory() -> Bool {
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o700)],
                ofItemAtPath: directory.path
            )
            storageIsPrivate = true
            return true
        } catch {
            storageIsPrivate = false
            return false
        }
    }

    private func uniqueURL(stem: String) -> URL {
        var candidate = directory.appendingPathComponent(stem).appendingPathExtension("png")
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(stem)-\(suffix)").appendingPathExtension("png")
            suffix += 1
        }
        return candidate
    }

    private func trimIfNeeded() {
        guard items.count > limit else { return }
        for item in items.dropFirst(limit) {
            try? fileManager.removeItem(at: item.url)
        }
        reload()
    }
}
