import Carbon
import Foundation

private let notchCaptureHotKeySignature: OSType = 0x4E_43_41_50 // "NCAP"

private func notchCaptureHotKeyEventHandler(
    _ handlerCall: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

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
    guard
        status == noErr,
        hotKeyID.signature == notchCaptureHotKeySignature,
        let action = GlobalHotKeyAction(rawValue: hotKeyID.id)
    else {
        return OSStatus(eventNotHandledErr)
    }

    let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in
        manager.receive(action: action)
    }
    return noErr
}

public enum GlobalHotKeyAction: UInt32, CaseIterable, Hashable, Sendable {
    // Keep this identifier stable so existing composer shortcut preferences
    // remain valid. The retired selection shortcut used identifier 1.
    case openComposer = 2
}

public struct GlobalHotKeyDefinition: Hashable, Sendable {
    public let keyCode: UInt32
    public let modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public enum GlobalHotKeyError: LocalizedError {
    case eventHandlerInstallationFailed(OSStatus)
    case registrationFailed(action: GlobalHotKeyAction, status: OSStatus)

    public var errorDescription: String? {
        switch self {
        case let .eventHandlerInstallationFailed(status):
            return "Could not install the global shortcut handler (OSStatus \(status))."
        case let .registrationFailed(action, status):
            return "Could not register \(action) (OSStatus \(status)); the shortcut may be used by another app."
        }
    }
}

/// Holds the Carbon registrations outside actor isolation so `deinit` can tear
/// them down synchronously from any thread. Removing the handler before the
/// manager deallocates matters: the installed callback holds an unretained
/// pointer to the manager.
private final class HotKeyRegistrationLifetime: @unchecked Sendable {
    var eventHandlerRef: EventHandlerRef?
    var hotKeyRefs: [GlobalHotKeyAction: EventHotKeyRef] = [:]

    func unregisterHotKeys() {
        for reference in hotKeyRefs.values {
            UnregisterEventHotKey(reference)
        }
        hotKeyRefs.removeAll()
    }

    func invalidate() {
        unregisterHotKeys()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}

@MainActor
public final class GlobalHotKeyManager {
    public typealias ActionHandler = @MainActor (GlobalHotKeyAction) -> Void

    public static let defaultDefinitions: [GlobalHotKeyAction: GlobalHotKeyDefinition] = [
        .openComposer: GlobalHotKeyDefinition(
            keyCode: UInt32(kVK_ANSI_N),
            modifiers: UInt32(controlKey | shiftKey)
        ),
    ]

    public var onAction: ActionHandler?
    public private(set) var definitions: [GlobalHotKeyAction: GlobalHotKeyDefinition] = [:]

    private let registrations = HotKeyRegistrationLifetime()

    public init(onAction: ActionHandler? = nil) throws {
        self.onAction = onAction
        try installEventHandler()
    }

    deinit {
        registrations.invalidate()
    }

    public func registerDefaults() throws {
        try register(Self.defaultDefinitions)
    }

    /// Atomically replaces the active shortcut set. On failure the method attempts
    /// to restore the previous registrations before throwing.
    public func register(_ newDefinitions: [GlobalHotKeyAction: GlobalHotKeyDefinition]) throws {
        let oldDefinitions = definitions
        unregisterAll()

        do {
            for action in GlobalHotKeyAction.allCases {
                guard let definition = newDefinitions[action] else { continue }
                try register(action, definition: definition)
            }
            definitions = newDefinitions
        } catch {
            unregisterAll()
            for action in GlobalHotKeyAction.allCases {
                guard let definition = oldDefinitions[action] else { continue }
                try? register(action, definition: definition)
            }
            definitions = oldDefinitions
            throw error
        }
    }

    public func unregisterAll() {
        registrations.unregisterHotKeys()
        definitions.removeAll()
    }

    private func installEventHandler() throws {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            notchCaptureHotKeyEventHandler,
            1,
            &eventType,
            context,
            &registrations.eventHandlerRef
        )
        guard status == noErr else {
            throw GlobalHotKeyError.eventHandlerInstallationFailed(status)
        }
    }

    private func register(
        _ action: GlobalHotKeyAction,
        definition: GlobalHotKeyDefinition
    ) throws {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: notchCaptureHotKeySignature, id: action.rawValue)
        let status = RegisterEventHotKey(
            definition.keyCode,
            definition.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr, let hotKeyRef else {
            throw GlobalHotKeyError.registrationFailed(action: action, status: status)
        }
        registrations.hotKeyRefs[action] = hotKeyRef
    }

    fileprivate func receive(action: GlobalHotKeyAction) {
        onAction?(action)
    }
}
