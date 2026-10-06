import Carbon

/// Reserve Escape for the capture session. NSEvent global key monitors alone
/// can miss keys when another app is active or input monitoring is unavailable.
final class CaptureEscapeHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private(set) var isRegistered = false
    let action: () -> Void

    init(action: @escaping () -> Void) { self.action = action }

    func register() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, data in
            guard let event, let data else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                  id.signature == OSType(0x53434553), id.id == 1 else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<CaptureEscapeHotKey>.fromOpaque(data).takeUnretainedValue()
            owner.action()
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard result == noErr else { return }
        let id = EventHotKeyID(signature: OSType(0x53434553), id: 1)
        isRegistered = RegisterEventHotKey(53, 0, id, GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &hotKey) == noErr
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
        isRegistered = false
    }

    deinit { unregister() }
}
