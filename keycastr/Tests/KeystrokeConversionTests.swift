import XCTest
import Carbon
@testable import Visualizer

/// 1:1 Swift port of `_legacy/KCVisualizerTests/KCKeystrokeConversionTests.m`.
///
/// NOTE: These tests assume a US-English keyboard layout (they call `TISCopyCurrentKeyboardLayoutInputSource()`).
/// Per-modifier display ordering follows Apple's menu convention: Control-Option-Shift-Command.
final class KeystrokeConversionTests: XCTestCase {

    private var keystroke: Keystroke!
    private var userDefaults: UserDefaults!
    private var eventTransformer: EventTransformer!

    override func setUp() {
        super.setUp()
        let layout = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        userDefaults = UserDefaults(suiteName: String(describing: type(of: self)))!
        eventTransformer = EventTransformer(keyboardLayout: layout, userDefaults: userDefaults)
    }

    override func tearDown() {
        userDefaults.removeObject(forKey: "default_displayModifiedCharacters")
        super.tearDown()
    }

    private func keystroke(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        characters: String,
        charactersIgnoringModifiers: String
    ) -> Keystroke {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: Date.timeIntervalSinceReferenceDate,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            isARepeat: false,
            keyCode: keyCode
        )!
        return Keystroke(nsEvent: event)
    }

    // MARK: - Numbers

    func test_convertsCtrlNumberToNumber() {
        // ctrl-7
        keystroke = keystroke(keyCode: 26, modifiers: NSEvent.ModifierFlags(rawValue: 262401), characters: "7", charactersIgnoringModifiers: "7")
        XCTAssertEqual(keystroke.convertToString(), "⌃7")
    }

    func test_convertsShiftNumberToShiftNumber() {
        // shift-7
        keystroke = keystroke(keyCode: 26, modifiers: NSEvent.ModifierFlags(rawValue: 131330), characters: "&", charactersIgnoringModifiers: "&")
        XCTAssertEqual(keystroke.convertToString(), "⇧7")
    }

    func test_convertsCtrlShiftNumberToNumber() {
        // ctrl-shift-7
        keystroke = keystroke(keyCode: 26, modifiers: NSEvent.ModifierFlags(rawValue: 393475), characters: "7", charactersIgnoringModifiers: "&")
        XCTAssertEqual(keystroke.convertToString(), "⌃⇧7")
    }

    func test_convertsCmdNumberToNumber() {
        // cmd-7
        keystroke = keystroke(keyCode: 26, modifiers: NSEvent.ModifierFlags(rawValue: 1048840), characters: "7", charactersIgnoringModifiers: "7")
        XCTAssertEqual(keystroke.convertToString(), "⌘7")
    }

    func test_convertsCmdShiftNumberToNumber() {
        // cmd-shift-7
        keystroke = keystroke(keyCode: 26, modifiers: NSEvent.ModifierFlags(rawValue: 1179914), characters: "7", charactersIgnoringModifiers: "&")
        XCTAssertEqual(keystroke.convertToString(), "⇧⌘7")
    }

    func test_convertsCmdOptNumberToNumber() {
        // cmd-opt-7
        keystroke = keystroke(keyCode: 26, modifiers: NSEvent.ModifierFlags(rawValue: 1573160), characters: "¶", charactersIgnoringModifiers: "7")
        XCTAssertEqual(keystroke.convertToString(), "⌥⌘7")
    }

    func test_convertsShiftOptionNumberToNumber() {
        // shift-opt-7
        keystroke = keystroke(keyCode: 26, modifiers: NSEvent.ModifierFlags(rawValue: 655650), characters: "»", charactersIgnoringModifiers: "7")
        XCTAssertEqual(keystroke.convertToString(), "⌥⇧7")
    }

    func test_convertsCmdOptShiftNumberToShiftedNumber() {
        // cmd-opt-shift-7
        keystroke = keystroke(keyCode: 26, modifiers: NSEvent.ModifierFlags(rawValue: 1704234), characters: "‡", charactersIgnoringModifiers: "&")
        XCTAssertEqual(keystroke.convertToString(), "⌥⇧⌘7")
    }

    // MARK: - Letters

    func test_convertsCtrlLetterToUppercaseLetter() {
        // ctrl-A
        keystroke = keystroke(keyCode: 0, modifiers: NSEvent.ModifierFlags(rawValue: 262401), characters: "\\^A", charactersIgnoringModifiers: "a")
        XCTAssertEqual(keystroke.convertToString(), "⌃A")
    }

    func test_convertsCtrlShiftLetterToLetter() {
        // ctrl-shift-A
        keystroke = keystroke(keyCode: 0, modifiers: NSEvent.ModifierFlags(rawValue: 393475), characters: "\\^A", charactersIgnoringModifiers: "a")
        XCTAssertEqual(keystroke.convertToString(), "⌃⇧A")
    }

    func test_convertsCtrlShiftCmdLetterToLetter() {
        // ctrl-shift-cmd-A
        keystroke = keystroke(keyCode: 0, modifiers: NSEvent.ModifierFlags(rawValue: 1442059), characters: "\\^A", charactersIgnoringModifiers: "A")
        XCTAssertEqual(keystroke.convertToString(), "⌃⇧⌘A")
    }

    func test_convertsCtrlOptLetterToUppercaseLetter() {
        // ctrl-opt-A
        keystroke = keystroke(keyCode: 0, modifiers: NSEvent.ModifierFlags(rawValue: 786721), characters: "\\^A", charactersIgnoringModifiers: "a")
        XCTAssertEqual(keystroke.convertToString(), "⌃⌥A")
    }

    func test_convertsCtrlOptShiftLetterToLetter() {
        // ctrl-opt-shift-A
        keystroke = keystroke(keyCode: 0, modifiers: NSEvent.ModifierFlags(rawValue: 917795), characters: "\\^A", charactersIgnoringModifiers: "A")
        XCTAssertEqual(keystroke.convertToString(), "⌃⌥⇧A")
    }

    func test_displaysOptLetterByDefault() {
        // opt-U
        keystroke = keystroke(keyCode: 32, modifiers: NSEvent.ModifierFlags(rawValue: 524576), characters: "", charactersIgnoringModifiers: "u")
        XCTAssertEqual(keystroke.convertToString(), "⌥U")
    }

    // MARK: - Function Row

    func test_convertsFnF1ToBrightnessDecrease() {
        keystroke = keystroke(keyCode: 145, modifiers: NSEvent.ModifierFlags(rawValue: 8388864), characters: "", charactersIgnoringModifiers: "")
        XCTAssertEqual(keystroke.convertToString(), "🔅")
    }

    func test_convertsFnF2ToBrightnessIncrease() {
        keystroke = keystroke(keyCode: 144, modifiers: NSEvent.ModifierFlags(rawValue: 8388864), characters: "", charactersIgnoringModifiers: "")
        XCTAssertEqual(keystroke.convertToString(), "🔆")
    }

    func test_convertsFnF3ToMissionControl() {
        keystroke = keystroke(keyCode: 160, modifiers: NSEvent.ModifierFlags(rawValue: 8388864), characters: "", charactersIgnoringModifiers: "")
        XCTAssertEqual(keystroke.convertToString(), "🖥")
    }

    func test_convertsFnF4ToLauncher() {
        keystroke = keystroke(keyCode: 131, modifiers: NSEvent.ModifierFlags(rawValue: 8388864), characters: "", charactersIgnoringModifiers: "")
        XCTAssertEqual(keystroke.convertToString(), "🚀")
    }

    // MARK: - JIS layout

    func test_convertsEisuKey() {
        keystroke = keystroke(keyCode: 102, modifiers: [], characters: "", charactersIgnoringModifiers: "")
        XCTAssertEqual(keystroke.convertToString(), "英数")
    }

    func test_convertsKanaKey() {
        keystroke = keystroke(keyCode: 104, modifiers: [], characters: "", charactersIgnoringModifiers: "")
        XCTAssertEqual(keystroke.convertToString(), "かな")
    }

    // MARK: - Displaying keycaps vs. modified characters

    func test_displayingKeycapsVsModifiedKeys() {
        // shift-opt-7
        keystroke = keystroke(keyCode: 26, modifiers: NSEvent.ModifierFlags(rawValue: 655650), characters: "»", charactersIgnoringModifiers: "7")

        userDefaults.set(true, forKey: "default_displayModifiedCharacters")
        XCTAssertEqual(eventTransformer.transformedValue(keystroke as Any?) as? String, "»")

        userDefaults.set(false, forKey: "default_displayModifiedCharacters")
        XCTAssertEqual(eventTransformer.transformedValue(keystroke as Any?) as? String, "⌥⇧7")
    }

    // MARK: - Special Cases

    func test_tabKey() {
        // tab character is UTF-8 "\t"
        keystroke = keystroke(keyCode: 48, modifiers: NSEvent.ModifierFlags(rawValue: 256), characters: "\t", charactersIgnoringModifiers: "\t")
        XCTAssertEqual(keystroke.convertToString(), "⇥")
    }

    func test_shiftTab() {
        // shift-tab character is UTF-16 U+0019
        let shiftTabChar = String(UnicodeScalar(0x19)!)
        keystroke = keystroke(keyCode: 48, modifiers: NSEvent.ModifierFlags(rawValue: 131330), characters: shiftTabChar, charactersIgnoringModifiers: shiftTabChar)
        XCTAssertEqual(keystroke.convertToString(), "⇤")
    }

    // MARK: - US English - Special Cases with Modifiers

    func test_optionShiftUp() {
        // option-shift-up: arrow keys always show their modifier glyphs regardless of displayModifiedCharacters
        let chars = String(format: "%lu", 0x00006000002f5c00 as CUnsignedLong)
        keystroke = keystroke(keyCode: 126, modifiers: NSEvent.ModifierFlags(rawValue: 11141410), characters: chars, charactersIgnoringModifiers: chars)

        userDefaults.set(false, forKey: "default_displayModifiedCharacters")
        XCTAssertEqual(eventTransformer.transformedValue(keystroke as Any?) as? String, "⌥⇧⇡")

        userDefaults.set(true, forKey: "default_displayModifiedCharacters")
        XCTAssertEqual(eventTransformer.transformedValue(keystroke as Any?) as? String, "⌥⇧⇡")
    }

    func test_optionUSpecialCase() {
        // opt-u should show ⌥u when displayModifiedCharacters is ON (no shift applied to base character)
        keystroke = keystroke(keyCode: 32, modifiers: NSEvent.ModifierFlags(rawValue: 524576), characters: "", charactersIgnoringModifiers: "u")
        userDefaults.set(true, forKey: "default_displayModifiedCharacters")
        XCTAssertEqual(eventTransformer.transformedValue(keystroke as Any?) as? String, "⌥u")
    }

    func test_optionESpecialCase() {
        keystroke = keystroke(keyCode: 14, modifiers: NSEvent.ModifierFlags(rawValue: 524576), characters: "", charactersIgnoringModifiers: "e")

        userDefaults.set(false, forKey: "default_displayModifiedCharacters")
        XCTAssertEqual(eventTransformer.transformedValue(keystroke as Any?) as? String, "⌥E")

        userDefaults.set(true, forKey: "default_displayModifiedCharacters")
        XCTAssertEqual(eventTransformer.transformedValue(keystroke as Any?) as? String, "⌥e")
    }

    func test_optionBacktickSpecialCase() {
        keystroke = keystroke(keyCode: 50, modifiers: NSEvent.ModifierFlags(rawValue: 524576), characters: "", charactersIgnoringModifiers: "`")

        userDefaults.set(false, forKey: "default_displayModifiedCharacters")
        XCTAssertEqual(eventTransformer.transformedValue(keystroke as Any?) as? String, "⌥`")

        userDefaults.set(true, forKey: "default_displayModifiedCharacters")
        XCTAssertEqual(eventTransformer.transformedValue(keystroke as Any?) as? String, "⌥`")
    }

    // MARK: - German - Special Case

    func test_commandSharpSDisplaysCommandSharpS() {
        // command-ß on a German keyboard layout.
        // Built-in capitalization is "SS" and there is a special glyph for capitalized sharp S.
        // To avoid confusion, fall back to displaying the keycap.
        keystroke = keystroke(keyCode: 27, modifiers: NSEvent.ModifierFlags(rawValue: 1048840), characters: "ß", charactersIgnoringModifiers: "ß")
        XCTAssertEqual(keystroke.convertToString(), "⌘ß")
    }
}
