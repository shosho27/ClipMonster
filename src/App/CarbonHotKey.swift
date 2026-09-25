import Cocoa
import Carbon

/// System-wide hotkeys via Carbon `RegisterEventHotKey`. Works in the App
/// Sandbox without Accessibility or Input Monitoring.
final class CarbonHotKeyCenter {
    static let shared = CarbonHotKeyCenter()

    static let popoverID: UInt32 = 1
    static let pathPasteID: UInt32 = 2

    private var handlerRef: EventHandlerRef?
    private var hotKeys: [UInt32: Item] = [:]
    private let signature: OSType = 0x434C4D32 // "CLM2"

    private struct Item {
        var hotKeyRef: EventHotKeyRef
        var action: () -> Void
    }

    private init() {}

    @discardableResult
    func register(id: UInt32, shortcut: CustomShortcut, exclusive: Bool, action: @escaping () -> Void) -> OSStatus {
        unregister(id: id)
        installHandlerIfNeeded()

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        #if MAS
        _ = exclusive
        let options: OptionBits = 0
        #else
        let options: OptionBits = exclusive ? OptionBits(kEventHotKeyExclusive) : 0
        #endif
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            Self.carbonModifiers(for: shortcut),
            hotKeyID,
            GetApplicationEventTarget(),
            options,
            &hotKeyRef
        )
        if status == noErr, let hotKeyRef {
            hotKeys[id] = Item(hotKeyRef: hotKeyRef, action: action)
        }
        return status
    }

    func unregister(id: UInt32) {
        if let item = hotKeys.removeValue(forKey: id) {
            UnregisterEventHotKey(item.hotKeyRef)
        }
    }

    func unregisterAll() {
        for id in Array(hotKeys.keys) {
            unregister(id: id)
        }
    }

    private func invoke(id: UInt32) {
        guard let action = hotKeys[id]?.action else { return }
        DispatchQueue.main.async { action() }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        if status != noErr {
            handlerRef = nil
        }
    }

    private static let eventHandler: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        var hotKeyID = EventHotKeyID()
        let paramStatus = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard paramStatus == noErr else { return OSStatus(eventNotHandledErr) }
        let center = Unmanaged<CarbonHotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
        center.invoke(id: hotKeyID.id)
        return noErr
    }

    private static func carbonModifiers(for shortcut: CustomShortcut) -> UInt32 {
        let modifiers = NSEvent.ModifierFlags(rawValue: shortcut.modifiers)
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        return result
    }
}
