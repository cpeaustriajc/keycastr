import AppKit

public final class MouseEvent: KeycastrEvent, @unchecked Sendable {
    public let locationInWindow: NSPoint

    public override init(nsEvent event: NSEvent?) {
        self.locationInWindow = event?.locationInWindow ?? .zero
        super.init(nsEvent: event)
    }

    public override var description: String {
        "<MouseEvent location=\(NSStringFromPoint(locationInWindow)) modifiers=\(modifierFlags.rawValue)>"
    }
}
