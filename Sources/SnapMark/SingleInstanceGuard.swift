import Darwin
import Foundation

/// Holds a non-blocking per-user file lock for the lifetime of the app. Launch Services
/// normally coalesces app launches, but this also covers duplicate bundle registrations
/// and users starting the Mach-O executable directly.
final class SingleInstanceGuard {
    private let lockURL: URL
    private var descriptor: Int32 = -1

    init(lockURL: URL? = nil) {
        self.lockURL = lockURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("com.ivanfioravanti.snapmark-\(getuid()).lock")
    }

    deinit {
        release()
    }

    @discardableResult
    func acquire() -> Bool {
        guard descriptor == -1 else { return true }
        let opened = Darwin.open(
            lockURL.path,
            O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW,
            S_IRUSR | S_IWUSR
        )
        guard opened >= 0 else { return false }
        guard flock(opened, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(opened)
            return false
        }
        descriptor = opened
        return true
    }

    func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
        descriptor = -1
    }
}
