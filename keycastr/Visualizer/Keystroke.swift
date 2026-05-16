import AppKit

public final class Keystroke: KeycastrEvent, @unchecked Sendable {
    public let keyCode: UInt16
    public let characters: String
    public let charactersIgnoringModifiers: String

    public override init(nsEvent event: NSEvent?) {
        self.keyCode = event?.keyCode ?? 0
        self.characters = event?.characters ?? ""
        self.charactersIgnoringModifiers = event?.charactersIgnoringModifiers ?? ""
        super.init(nsEvent: event)
    }

    public var isCommand: Bool {
        modifierFlags.contains(.control) || modifierFlags.contains(.command)
    }

    public var isModified: Bool {
        !modifierFlags.intersection([.control, .command, .option, .shift]).isEmpty
    }

    public override var description: String {
        "<Keystroke keyCode=\(keyCode) modifiers=\(modifierFlags.rawValue) characters=\(characters) charactersIgnoringModifiers=\(charactersIgnoringModifiers)>"
    }
}
