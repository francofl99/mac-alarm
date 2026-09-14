import AppKit
import Carbon.HIToolbox

final class HotKeyCenter {
    static let shared = HotKeyCenter()

    var onTrigger: (() -> Void)?

    private var handlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?

    private init() {}

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        unregister()

        if handlerRef == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                HotKeyCenter.shared.onTrigger?()
                return noErr
            }, 1, &spec, nil, &handlerRef)
        }

        let id = EventHotKeyID(signature: OSType(0x4D414C4D), id: 1)
        return RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef) == noErr
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}
