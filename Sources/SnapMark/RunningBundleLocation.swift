import Foundation

struct RunningBundleLocation {
    let bundleURL: URL
    let executableURL: URL

    init(bundle: Bundle = .main) {
        bundleURL = bundle.bundleURL.standardizedFileURL
        executableURL = (bundle.executableURL ?? bundle.bundleURL).standardizedFileURL
    }

    init(bundleURL: URL, executableURL: URL) {
        self.bundleURL = bundleURL.standardizedFileURL
        self.executableURL = executableURL.standardizedFileURL
    }

    func isAvailable(fileManager: FileManager = .default) -> Bool {
        var bundleIsDirectory: ObjCBool = false
        let bundleExists = fileManager.fileExists(atPath: bundleURL.path, isDirectory: &bundleIsDirectory)
        return bundleExists && bundleIsDirectory.boolValue && fileManager.isExecutableFile(atPath: executableURL.path)
    }
}
