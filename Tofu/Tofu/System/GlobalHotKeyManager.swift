import AppKit
import Carbon

/// Actions dispatched by system-wide hotkeys.
enum GlobalHotKeyAction: UInt32, CaseIterable {
    case quickThought = 1
    case toggleMute = 2
    case toggleHUD = 3

    var keyCode: UInt32 {
        switch self {
        case .quickThought: return UInt32(kVK_Space)   // 49
        case .toggleMute: return UInt32(kVK_ANSI_M)    // 46
        case .toggleHUD: return UInt32(kVK_ANSI_H)     // 4
        }
    }

    var modifiers: UInt32 {
        UInt32(controlKey | optionKey)
    }
}

/// Protocol for hotkey registration and dispatch, allowing unit test verification without Carbon event loops.
@MainActor
protocol HotKeyManaging: AnyObject {
    var isRegistered: Bool { get }
    var onTrigger: (() -> Void)? { get set }
    var onToggleMute: (() -> Void)? { get set }
    var onToggleHUD: (() -> Void)? { get set }
    func register() -> Bool
    func unregister()
    func dispatch(action: GlobalHotKeyAction)
}

/// Global HotKey Manager registering system-wide shortcuts (default: ⌃⌥Space, ⌃⌥M, ⌃⌥H)
/// Uses Carbon EventHotKey API for zero-accessibility-permission global capture across macOS spaces.
@MainActor
final class GlobalHotKeyManager: HotKeyManaging {
    static let shared = GlobalHotKeyManager()

    var onTrigger: (() -> Void)?
    var onToggleMute: (() -> Void)?
    var onToggleHUD: (() -> Void)?
    private(set) var isRegistered = false

    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
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
            if status == noErr && hotKeyID.signature == OSType(0x544F4655) {
                if let action = GlobalHotKeyAction(rawValue: hotKeyID.id) {
                    DispatchQueue.main.async {
                        let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                        manager.dispatch(action: action)
                    }
                }
            }
            return noErr
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, selfPtr, &eventHandler)
        guard handlerStatus == noErr else { return false }

        for action in GlobalHotKeyAction.allCases {
            var hotKeyID = EventHotKeyID()
            hotKeyID.signature = OSType(0x544F4655) // 'TOFU'
            hotKeyID.id = action.rawValue

            var ref: EventHotKeyRef?
            let key = action == .quickThought ? keyCode : action.keyCode
            let mods = action == .quickThought ? modifiers : action.modifiers
            let regStatus = RegisterEventHotKey(key, mods, hotKeyID, GetApplicationEventTarget(), 0, &ref)
            if regStatus == noErr, let ref {
                hotKeyRefs[action.rawValue] = ref
            }
        }

        isRegistered = !hotKeyRefs.isEmpty
        return isRegistered
    }

    func unregister() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        isRegistered = false
    }

    func trigger() {
        dispatch(action: .quickThought)
    }

    func dispatch(action: GlobalHotKeyAction) {
        switch action {
        case .quickThought:
            onTrigger?()
        case .toggleMute:
            onToggleMute?()
        case .toggleHUD:
            onToggleHUD?()
        }
    }

    deinit {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
