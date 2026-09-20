import Carbon
import Foundation
import os.log

@MainActor
final class CarbonGlobalHotkeyBackend: GlobalHotkeyBackend {
    private static let signatureSeed: OSType = fourCharCode("GMBH")
    private static var signatureCounter: OSType = 0

    private let signature: OSType
    private let logger = Logger(subsystem: "com.mourato.GitMenuBar", category: "Shortcuts")

    private var nextHotkeyID: UInt32 = 1
    private var eventHandlerRef: EventHandlerRef?
    private var hotkeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var registrationsByID: [UInt32: HotkeyRegistration] = [:]

    init() {
        signature = Self.nextSignature()
    }

    var registeredHotkeyCount: Int {
        hotkeyRefs.count
    }

    func registerAll(_ registrations: [HotkeyRegistration]) {
        unregisterAll()
        guard !registrations.isEmpty, ensureEventHandlerInstalled() else { return }

        for registration in registrations {
            let internalID = nextInternalID()
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: signature, id: internalID)
            let status = RegisterEventHotKey(
                registration.keyCode,
                registration.modifiers,
                hotKeyID,
                GetEventDispatcherTarget(),
                0,
                &hotKeyRef
            )

            guard status == noErr, let hotKeyRef else {
                logger.error(
                    "Failed to register global shortcut \(registration.id, privacy: .public), status=\(status, privacy: .public)"
                )
                continue
            }

            hotkeyRefs[internalID] = hotKeyRef
            registrationsByID[internalID] = registration
        }
    }

    func unregisterAll() {
        for ref in hotkeyRefs.values {
            UnregisterEventHotKey(ref)
        }

        hotkeyRefs.removeAll()
        registrationsByID.removeAll()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func nextInternalID() -> UInt32 {
        defer { nextHotkeyID &+= 1 }
        return nextHotkeyID
    }

    private func ensureEventHandlerInstalled() -> Bool {
        guard eventHandlerRef == nil else { return true }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            Self.hotkeyEventHandler,
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )

        guard status == noErr else {
            logger.error("Failed to install global shortcut event handler, status=\(status, privacy: .public)")
            return false
        }
        return true
    }

    private func handleHotkey(id: UInt32) {
        registrationsByID[id]?.onKeyDown()
    }

    private static let hotkeyEventHandler: EventHandlerUPP = { _, event, userData in
        guard let userData, let event else { return OSStatus(eventNotHandledErr) }

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
        guard status == noErr else { return status }

        let backend = Unmanaged<CarbonGlobalHotkeyBackend>
            .fromOpaque(userData)
            .takeUnretainedValue()
        guard hotKeyID.signature == backend.signature else {
            return OSStatus(eventNotHandledErr)
        }

        let id = hotKeyID.id
        Task { @MainActor [weak backend] in
            backend?.handleHotkey(id: id)
        }
        return noErr
    }

    private static func nextSignature() -> OSType {
        defer { signatureCounter &+= 1 }
        return signatureSeed &+ signatureCounter
    }

    private static func fourCharCode(_ string: String) -> OSType {
        string.utf8.prefix(4).reduce(into: OSType(0)) { result, scalar in
            result = (result << 8) + OSType(scalar)
        }
    }
}
