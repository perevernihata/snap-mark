import AppKit
import Carbon

private let snapMarkHotKeySignature: OSType = 0x534E4D4B // SNMK

private let snapMarkHotKeyHandler: EventHandlerUPP = { _, event, _ in
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr, hotKeyID.signature == snapMarkHotKeySignature else {
        return OSStatus(eventNotHandledErr)
    }

    Task { @MainActor in
        AppModel.shared.beginCapture(.area)
    }
    return noErr
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let singleInstance = SingleInstanceGuard()
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var ownsInstanceLock = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        ownsInstanceLock = singleInstance.acquire()
        guard !ownsInstanceLock else { return }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.ivanfioravanti.snapmark")
            .first(where: { $0.processIdentifier != ownPID })?
            .activate(options: [.activateAllWindows])
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ownsInstanceLock else { return }
        NSApp.setActivationPolicy(.regular)
        registerGlobalHotKey()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        let existingMainWindow = sender.windows.contains { window in
            window.level == .normal && !(window is NSPanel)
        }
        guard existingMainWindow else { return true }
        Task { @MainActor in AppModel.shared.showMainWindow() }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        singleInstance.release()
    }

    private func registerGlobalHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            snapMarkHotKeyHandler,
            1,
            &eventType,
            nil,
            &eventHandler
        )

        let hotKeyID = EventHotKeyID(signature: snapMarkHotKeySignature, id: 1)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_4),
            UInt32(controlKey | shiftKey | cmdKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
    }
}
