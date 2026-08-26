enum CaptureRoute: Equatable {
    case systemAreaCapture
    case authorizationRequired
    case systemWindowCapture

    static func resolve(
        mode: CaptureMode,
        hasFullScreenRecordingAccess: Bool
    ) throws -> CaptureRoute {
        guard hasFullScreenRecordingAccess else {
            return .authorizationRequired
        }
        return mode == .window ? .systemWindowCapture : .systemAreaCapture
    }
}
