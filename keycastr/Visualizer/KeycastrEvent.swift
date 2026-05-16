import AppKit

public class KeycastrEvent: NSObject, @unchecked Sendable {
    public let type: NSEvent.EventType
    public let modifierFlags: NSEvent.ModifierFlags

    public init(nsEvent event: NSEvent?) {
        self.type = event?.type ?? .applicationDefined
        self.modifierFlags = event?.modifierFlags ?? []
        super.init()
    }

    public func convertToString() -> String {
        return EventTransformer.current.transformedValue(self) as? String ?? ""
    }
}
