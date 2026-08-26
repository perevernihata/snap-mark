import Combine
import Foundation

@MainActor
final class AppPreferences: ObservableObject {
    @Published var delaySeconds: Int {
        didSet { defaults.set(delaySeconds, forKey: Keys.delaySeconds) }
    }

    @Published var keepHistory: Bool {
        didSet { defaults.set(keepHistory, forKey: Keys.keepHistory) }
    }

    @Published var copyAfterCapture: Bool {
        didSet { defaults.set(copyAfterCapture, forKey: Keys.copyAfterCapture) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        delaySeconds = defaults.object(forKey: Keys.delaySeconds) as? Int ?? 0
        keepHistory = defaults.object(forKey: Keys.keepHistory) as? Bool ?? true
        copyAfterCapture = defaults.object(forKey: Keys.copyAfterCapture) as? Bool ?? false
    }

    private enum Keys {
        static let delaySeconds = "captureDelaySeconds"
        static let keepHistory = "keepCaptureHistory"
        static let copyAfterCapture = "copyAfterCapture"
    }
}
