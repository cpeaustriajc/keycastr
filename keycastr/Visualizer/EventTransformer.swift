import AppKit
import Carbon

public final class EventTransformer: ValueTransformer, @unchecked Sendable {
    // MARK: - Glyph constants

    private static let commandKeyString = "\u{2318}"
    private static let optionKeyString = "\u{2325}"
    private static let controlKeyString = "\u{2303}"
    private static let shiftKeyString = "\u{21E7}"
    private static let leftTabString = "\u{21E4}"
    private static let mouseString = "🖱️"

    // MARK: - Special key map (keyCode -> glyph/label)

    private static let specialKeys: [UInt16: String] = [
        126: "\u{21E1}", // up
        125: "\u{21E3}", // down
        124: "\u{21E2}", // right
        123: "\u{21E0}", // left
        48: "\u{21E5}",  // tab
        53: "\u{238B}",  // escape
        71: "\u{2327}",  // clear
        51: "\u{232B}",  // delete
        117: "\u{2326}", // forward delete
        114: "?\u{20DD}", // help
        115: "\u{2196}", // home
        119: "\u{2198}", // end
        116: "\u{21DE}", // pgup
        121: "\u{21DF}", // pgdn
        36: "\u{21A9}",  // return
        76: "\u{21A9}",  // numpad enter
        145: "🔅",       // low brightness
        144: "🔆",       // high brightness
        160: "🖥",       // mission control
        131: "🚀",       // launcher
        177: "🔍",       // spotlight key
        176: "🎤",       // dictation key
        178: "\u{23FE}", // focus key
        49: "\u{2423}\u{200B}", // space
        179: "fn ",
        122: "F1 ", 120: "F2 ", 99: "F3 ", 118: "F4 ",
        96: "F5 ", 97: "F6 ", 98: "F7 ", 100: "F8 ",
        101: "F9 ", 109: "F10 ", 103: "F11 ", 111: "F12 ",
        105: "F13 ", 107: "F14 ", 113: "F15 ", 106: "F16 ",
        64: "F17 ", 79: "F18 ", 80: "F19 ", 90: "F20 ",
        0x66: "英数",
        0x68: "かな",
    ]

    // MARK: - State

    private let keyboardLayout: TISInputSource
    private let userDefaults: UserDefaults
    private let uchrData: UnsafePointer<UCKeyboardLayout>
    private var displayModifiedCharacters: Bool
    private var deadKeyState: UInt32 = 0
    private let observer: DefaultsObserver

    // MARK: - Lifecycle

    public init(keyboardLayout: TISInputSource, userDefaults: UserDefaults) {
        self.keyboardLayout = keyboardLayout
        self.userDefaults = userDefaults
        let layoutDataRef = TISGetInputSourceProperty(
            keyboardLayout,
            kTISPropertyUnicodeKeyLayoutData
        )
        let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self)
        let bytes = CFDataGetBytePtr(layoutData)!
        self.uchrData = UnsafeRawPointer(bytes).bindMemory(to: UCKeyboardLayout.self, capacity: 1)
        self.displayModifiedCharacters = userDefaults.bool(forKey: "default_displayModifiedCharacters")
        self.observer = DefaultsObserver()
        super.init()
        self.observer.transformer = self
        userDefaults.addObserver(
            self.observer,
            forKeyPath: "default_displayModifiedCharacters",
            options: .new,
            context: nil
        )
        Self.registerInputSourceObserver()
    }

    deinit {
        userDefaults.removeObserver(observer, forKeyPath: "default_displayModifiedCharacters")
    }

    // MARK: - ValueTransformer overrides

    public override class func transformedValueClass() -> AnyClass {
        NSString.self
    }

    public override class func allowsReverseTransformation() -> Bool {
        false
    }

    public override func transformedValue(_ value: Any?) -> Any? {
        guard let event = value as? KeycastrEvent else { return nil }
        return transform(event)
    }

    // MARK: - Currently-active transformer (lazy singleton)

    private static let currentLock = NSRecursiveLock()
    nonisolated(unsafe) private static var _current: EventTransformer?

    public static var current: EventTransformer {
        currentLock.lock()
        defer { currentLock.unlock() }
        if let existing = _current { return existing }
        let layout = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        let transformer = EventTransformer(
            keyboardLayout: layout,
            userDefaults: .standard
        )
        _current = transformer
        return transformer
    }

    fileprivate static func invalidateCurrent() {
        currentLock.lock()
        _current = nil
        currentLock.unlock()
    }

    private static let observerLock = NSLock()
    nonisolated(unsafe) private static var inputSourceObserverRegistered = false

    fileprivate static func registerInputSourceObserver() {
        observerLock.lock()
        defer { observerLock.unlock() }
        guard !inputSourceObserverRegistered else { return }
        inputSourceObserverRegistered = true
        let center = CFNotificationCenterGetDistributedCenter()
        CFNotificationCenterAddObserver(
            center,
            nil,
            { _, _, _, _, _ in
                EventTransformer.invalidateCurrent()
            },
            kTISNotifySelectedKeyboardInputSourceChanged,
            nil,
            .deliverImmediately
        )
    }

    // MARK: - KVO bridge

    fileprivate final class DefaultsObserver: NSObject {
        weak var transformer: EventTransformer?

        override func observeValue(
            forKeyPath keyPath: String?,
            of object: Any?,
            change: [NSKeyValueChangeKey: Any]?,
            context: UnsafeMutableRawPointer?
        ) {
            guard keyPath == "default_displayModifiedCharacters",
                  let newValue = change?[.newKey] as? Bool,
                  let transformer else { return }
            transformer.displayModifiedCharacters = newValue
        }
    }

    // MARK: - Core conversion

    private func transform(_ event: KeycastrEvent) -> String {
        let modifiers = event.modifierFlags
        let hasOption = modifiers.contains(.option)
        let hasShift = modifiers.contains(.shift)
        let isCommand = !modifiers.intersection([.control, .command]).isEmpty
        var needsShiftGlyph = false

        var response = ""

        if modifiers.contains(.control) {
            response.append(Self.controlKeyString)
        }

        if hasOption && (isCommand || !displayModifiedCharacters) {
            response.append(Self.optionKeyString)
        }

        if hasShift {
            if isCommand {
                response.append(Self.shiftKeyString)
            } else if hasOption && !displayModifiedCharacters {
                response.append(Self.shiftKeyString)
            } else {
                needsShiftGlyph = !displayModifiedCharacters
            }
        }

        if modifiers.contains(.command) {
            if needsShiftGlyph {
                response.append(Self.shiftKeyString)
                needsShiftGlyph = false
            }
            response.append(Self.commandKeyString)
        }

        if event is MouseEvent {
            if needsShiftGlyph {
                response.append(Self.shiftKeyString)
            }
            response.append(Self.mouseString)
            return response
        }

        guard let keystroke = event as? Keystroke else { return response }

        // Bare shift-tab → left-tab glyph
        if hasShift, !keystroke.isCommand, !hasOption, keystroke.keyCode == 48 {
            response.append(Self.leftTabString)
            return response
        }

        if needsShiftGlyph {
            response.append(Self.shiftKeyString)
            needsShiftGlyph = false
        }

        let appendModifiers: (Bool) -> Void = { [hasOption, hasShift] append in
            if append && !keystroke.isCommand {
                if hasOption { response.append(Self.optionKeyString) }
                if hasShift { response.append(Self.shiftKeyString) }
            }
        }

        if let specialKeyString = Self.specialKeys[keystroke.keyCode] {
            appendModifiers(displayModifiedCharacters)
            response.append(specialKeyString)
            return response
        }

        if displayModifiedCharacters && !isCommand {
            if !keystroke.characters.isEmpty {
                response.append(keystroke.characters)
            } else {
                appendModifiers(displayModifiedCharacters)
                response.append(translatedCharacter(for: keystroke))
            }
        } else {
            response.append(translatedCharacter(for: keystroke))
        }

        // Commands, shifted keystrokes, and option combinations (when displayModifiedCharacters is NO) should be uppercased.
        // Special case: keycode 27 (German ß) is not shifted.
        if (isCommand || hasShift || (hasOption && !displayModifiedCharacters)) && keystroke.keyCode != 27 {
            response = response.uppercased()
        }

        return response
    }

    private func translatedCharacter(for keystroke: Keystroke) -> String {
        if shouldReturnOriginalCharacters(forKeyCode: keystroke.keyCode, characters: keystroke.characters),
           keystroke.isCommand {
            return keystroke.characters
        }
        return translate(keyCode: keystroke.keyCode)
    }

    private func shouldReturnOriginalCharacters(forKeyCode keyCode: UInt16, characters: String) -> Bool {
        keyCode == 27 && characters == "ß"
    }

    private func translate(keyCode: UInt16) -> String {
        var deadKey: UInt32 = deadKeyState
        var unicodeString = [UniChar](repeating: 0, count: 4)
        var length: Int = 0
        let result = UCKeyTranslate(
            uchrData,
            keyCode,
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKey,
            unicodeString.count,
            &length,
            &unicodeString
        )
        guard result == noErr else { return "" }
        deadKeyState = deadKey
        return String(utf16CodeUnits: unicodeString, count: length)
    }
}
