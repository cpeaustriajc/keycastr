import AppKit
import Carbon

@MainActor
public protocol EventTapDelegate: AnyObject {
    func eventTap(_ tap: EventTap, noteKeystroke keystroke: Keystroke)
    func eventTap(_ tap: EventTap, noteMouseEvent event: MouseEvent)
    func eventTap(_ tap: EventTap, noteFlagsChanged flags: NSEvent.ModifierFlags)
}

@MainActor
public final class EventTap {
    public weak var delegate: (any EventTapDelegate)?

    public private(set) var tapInstalled = false

    private var keyEventTap: CFMachPort?
    private var mouseAndFlagsEventTap: CFMachPort?
    private var keyEventTapSource: CFRunLoopSource?
    private var mouseAndFlagsEventTapSource: CFRunLoopSource?

    public init() {}

    // CF resource cleanup is handled by ARC releasing the CFMachPort/CFRunLoopSource refs when
    // self deallocates. Callers should invoke `removeTap()` explicitly to invalidate before then.

    public enum InstallError: LocalizedError {
        case keyTapFailed
        case mouseTapFailed

        public var errorDescription: String? {
            switch self {
            case .keyTapFailed:
                return "Could not create key event tap! Permissions needed..."
            case .mouseTapFailed:
                return "Could not create mouse and modifiers event tap!"
            }
        }
    }

    public func installTap() throws {
        guard !tapInstalled else { return }

        let keyMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let keyTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: keyMask,
            callback: keyEventTapCallback,
            userInfo: context
        ) else {
            throw InstallError.keyTapFailed
        }
        self.keyEventTap = keyTap

        let mouseAndFlagsMask: CGEventMask =
            CGEventMask(1 << CGEventType.leftMouseDown.rawValue) |
            CGEventMask(1 << CGEventType.leftMouseUp.rawValue) |
            CGEventMask(1 << CGEventType.rightMouseDown.rawValue) |
            CGEventMask(1 << CGEventType.rightMouseUp.rawValue) |
            CGEventMask(1 << CGEventType.leftMouseDragged.rawValue) |
            CGEventMask(1 << CGEventType.rightMouseDragged.rawValue) |
            CGEventMask(1 << CGEventType.flagsChanged.rawValue) |
            CGEventMask(1 << CGEventType.otherMouseDown.rawValue) |
            CGEventMask(1 << CGEventType.otherMouseUp.rawValue) |
            CGEventMask(1 << CGEventType.otherMouseDragged.rawValue)

        guard let mfTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mouseAndFlagsMask,
            callback: mouseAndFlagsEventTapCallback,
            userInfo: context
        ) else {
            CFMachPortInvalidate(keyTap)
            self.keyEventTap = nil
            throw InstallError.mouseTapFailed
        }
        self.mouseAndFlagsEventTap = mfTap

        let keySource = CFMachPortCreateRunLoopSource(nil, keyTap, 0)
        let mfSource = CFMachPortCreateRunLoopSource(nil, mfTap, 0)
        self.keyEventTapSource = keySource
        self.mouseAndFlagsEventTapSource = mfSource

        let runLoop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(runLoop, keySource, .defaultMode)
        CFRunLoopAddSource(runLoop, mfSource, .defaultMode)

        tapInstalled = true
    }

    public func removeTap() {
        guard tapInstalled else { return }

        if let src = keyEventTapSource { CFRunLoopSourceInvalidate(src) }
        if let src = mouseAndFlagsEventTapSource { CFRunLoopSourceInvalidate(src) }
        keyEventTapSource = nil
        mouseAndFlagsEventTapSource = nil

        if let tap = keyEventTap { CFMachPortInvalidate(tap) }
        if let tap = mouseAndFlagsEventTap { CFMachPortInvalidate(tap) }
        keyEventTap = nil
        mouseAndFlagsEventTap = nil

        tapInstalled = false
    }

    // MARK: - Delivery (always on main actor — taps are added to the main run loop).

    fileprivate func deliverKey(_ keystroke: Keystroke) {
        delegate?.eventTap(self, noteKeystroke: keystroke)
    }

    fileprivate func deliverMouse(_ event: MouseEvent) {
        delegate?.eventTap(self, noteMouseEvent: event)
    }

    fileprivate func deliverFlags(_ flags: NSEvent.ModifierFlags) {
        delegate?.eventTap(self, noteFlagsChanged: flags)
    }
}

// MARK: - C callbacks (run on the run loop's thread; we install on the main run loop)

private func keyEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .keyDown, let nsEvent = NSEvent(cgEvent: event) {
        let keystroke = Keystroke(nsEvent: nsEvent)
        DispatchQueue.main.async { tap.deliverKey(keystroke) }
    }
    return Unmanaged.passUnretained(event)
}

private func mouseAndFlagsEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
    switch type {
    case .leftMouseDown, .rightMouseDown, .otherMouseDown,
         .leftMouseUp, .rightMouseUp, .otherMouseUp,
         .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
        if let nsEvent = NSEvent(cgEvent: event) {
            let mouseEvent = MouseEvent(nsEvent: nsEvent)
            DispatchQueue.main.async { tap.deliverMouse(mouseEvent) }
        }
    case .flagsChanged:
        let f = event.flags
        var modifiers: NSEvent.ModifierFlags = []
        if f.contains(.maskShift) { modifiers.insert(.shift) }
        if f.contains(.maskCommand) { modifiers.insert(.command) }
        if f.contains(.maskControl) { modifiers.insert(.control) }
        if f.contains(.maskAlternate) { modifiers.insert(.option) }
        DispatchQueue.main.async { tap.deliverFlags(modifiers) }
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}

// EventTap is a CF wrapper; it stays on main actor. Sendable conformance lets the C callback's
// `Unmanaged.fromOpaque(...).takeUnretainedValue()` cross the boundary without races, because the
// only mutation is restricted to MainActor methods.
extension EventTap: @unchecked Sendable {}
