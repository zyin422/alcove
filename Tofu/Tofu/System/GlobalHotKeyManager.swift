import AppKit
import Carbon

/// Protocol for hotkey registration and dispatch, allowing unit test verification without Carbon event loops.
@MainActor
protocol HotKeyManaging: AnyObject {
    var isRegistered: Bool { get }
    var onTrigger: (() -> Void)? { get set }
    func register() -> Bool
    func unregister()
}

/// Global HotKey Manager registering system-wide shortcuts (default: ⌃⌥Space)
/// Uses Carbon EventHotKey API for zero-accessibility-permission global capture across macOS spaces.
@MainActor
final class GlobalHotKeyManager: HotKeyManaging {
    static let shared = GlobalHotKeyManager()

    var onTrigger: (() -> Void)?
    private(set) var isRegistered = false

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    let keyCode: UInt32
    let modifiers: UInt32

    /// Default hotkey: Control + Option + Space (kVK_Space: 49)
    init(keyCode: UInt32 = UInt32(kVK_Space), modifiers: UInt32 = UInt32(controlKey | optionKey)) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    @discardableResult
    func register() -> Bool {
        guard !isRegistered else { return true }

        var gMyHotKeyID = EventHotKeyID()
        gMyHotKeyID.signature = OSType(0x544F4655) // 'TOFU'
        gMyHotKeyID.id = 1

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { (_, event, userData) -> OSStatus in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamName(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if status == noErr && hotKeyID.signature == OSType(0x544F4655) && hotKeyID.id == 1 {
                DispatchQueue.main.async {
                    let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                    manager.trigger()
                }
            }
            return noErr
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, selfPtr, &eventHandler)
        guard handlerStatus == noErr else { return false }

        let regStatus = RegisterEventHotKey(keyCode, modifiers, gMyHotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if regStatus == noErr {
            isRegistered = true
            return true
        } else {
            if let eventHandler {
                RemoveEventHandler(eventHandler)
                self.eventHandler = nil
            }
            return false
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        isRegistered = false
    }

    func trigger() {
        onTrigger?()
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
