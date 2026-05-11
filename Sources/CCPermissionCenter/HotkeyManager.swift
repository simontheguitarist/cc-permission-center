import AppKit
import Carbon.HIToolbox

/// Registers a small set of global hotkeys via the Carbon Event API.
/// Works without Accessibility permission because hotkeys are dispatched
/// by the system before they reach any app.
@MainActor
final class HotkeyManager {
    struct Binding {
        let id: UInt32
        let keyCode: UInt32
        let modifiers: UInt32
        let handler: () -> Void
    }

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var eventHandlerInstalled = false
    private var eventHandlerRef: EventHandlerRef?

    func register(_ bindings: [Binding]) {
        installEventHandlerIfNeeded()
        unregisterAll()
        for binding in bindings {
            let hotKeyID = EventHotKeyID(signature: HotkeyManager.signature, id: binding.id)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                binding.keyCode,
                binding.modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                refs[binding.id] = ref
                handlers[binding.id] = binding.handler
            } else {
                NSLog("Hotkey register failed (id=\(binding.id), status=\(status))")
            }
        }
    }

    func unregisterAll() {
        for (_, ref) in refs {
            UnregisterEventHotKey(ref)
        }
        refs.removeAll()
        handlers.removeAll()
    }

    private func installEventHandlerIfNeeded() {
        guard !eventHandlerInstalled else { return }
        eventHandlerInstalled = true

        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
        ]

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let callback: EventHandlerUPP = { _, eventRef, userData in
            guard let eventRef, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard err == noErr else { return err }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                manager.handlers[hotKeyID.id]?()
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventTypes,
            selfPtr,
            &eventHandlerRef
        )
    }

    deinit {
        for (_, ref) in refs { UnregisterEventHotKey(ref) }
        if let h = eventHandlerRef { RemoveEventHandler(h) }
    }

    private static let signature: OSType = {
        // 'CCPC'
        return (OSType(0x43) << 24) | (OSType(0x43) << 16) | (OSType(0x50) << 8) | OSType(0x43)
    }()
}

/// Carbon modifier masks for convenience.
enum HotkeyModifiers {
    static let ctrlOpt: UInt32 = UInt32(controlKey | optionKey)
}

/// Canonical key codes used by our app.
enum HotkeyKey {
    static let a: UInt32 = UInt32(kVK_ANSI_A)
    static let r: UInt32 = UInt32(kVK_ANSI_R)
    static let j: UInt32 = UInt32(kVK_ANSI_J)
}
