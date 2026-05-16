import AppKit
import Visualizer

// MARK: - Display option

public enum DefaultVisualizerDisplayOption: Int, Sendable {
    case commandKeysOnly = 0
    case allModifiedKeys = 1
    case allKeys = 2

    public static let `default`: DefaultVisualizerDisplayOption = .commandKeysOnly
}

// MARK: - Factory (principal class)

@objc(DefaultVisualizerFactory)
@MainActor
public final class DefaultVisualizerFactory: NSObject, VisualizerFactory {
    public var visualizerName: String { "Default" }
    public var visualizerType: any Visualizer.Type { DefaultVisualizer.self }
    public func makeVisualizer() -> any Visualizer { DefaultVisualizer() }

    @objc public override init() {
        // Plugin loader instantiates via init() on the main thread (run loop). The Obj-C runtime
        // does not honor @MainActor isolation, so this initializer is invoked dynamically.
        MainActor.assumeIsolated { _ = () }
        super.init()
    }
}

// MARK: - Preferences view

@MainActor
public final class DefaultPreferencesView: NSView {
    public let commandKeysOnlyButton: NSButton
    public let allModifiedKeysButton: NSButton
    public let allKeysButton: NSButton

    public weak var target: AnyObject?
    public var action: Selector?

    public override init(frame frameRect: NSRect) {
        commandKeysOnlyButton = NSButton(radioButtonWithTitle: "Command Keys Only", target: nil, action: nil)
        allModifiedKeysButton = NSButton(radioButtonWithTitle: "All Modified Keys", target: nil, action: nil)
        allKeysButton = NSButton(radioButtonWithTitle: "All Keys", target: nil, action: nil)
        super.init(frame: frameRect)
        commandKeysOnlyButton.translatesAutoresizingMaskIntoConstraints = false
        allModifiedKeysButton.translatesAutoresizingMaskIntoConstraints = false
        allKeysButton.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: [commandKeysOnlyButton, allModifiedKeysButton, allKeysButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -16),
        ])
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public func wireActions(target: AnyObject, action: Selector) {
        self.target = target
        self.action = action
        for button in [commandKeysOnlyButton, allModifiedKeysButton, allKeysButton] {
            button.target = target
            button.action = action
        }
    }

    public func refreshSelection(displayMode: DefaultVisualizerDisplayOption) {
        commandKeysOnlyButton.state = displayMode == .commandKeysOnly ? .on : .off
        allModifiedKeysButton.state = displayMode == .allModifiedKeys ? .on : .off
        allKeysButton.state = displayMode == .allKeys ? .on : .off
    }
}

// MARK: - Visualizer instance

@MainActor
public final class DefaultVisualizer: NSObject, Visualizer {

    public var displayMode: DefaultVisualizerDisplayOption = .commandKeysOnly {
        didSet { _preferencesView.refreshSelection(displayMode: displayMode) }
    }

    private lazy var _preferencesView: DefaultPreferencesView = {
        let v = DefaultPreferencesView(frame: NSRect(x: 0, y: 0, width: 320, height: 140))
        v.wireActions(target: self, action: #selector(preferencesViewDidSelectDisplayOption(_:)))
        v.refreshSelection(displayMode: displayMode)
        return v
    }()

    public var preferencesView: NSView? { _preferencesView }

    /// Test hook — returns the typed view.
    public var defaultPreferencesView: DefaultPreferencesView { _preferencesView }

    public var visualizerName: String { "Default" }

    private let bezelWindow: BezelWindow

    public override init() {
        self.bezelWindow = BezelWindow()
        super.init()
        configureDisplayMode(with: .standard)
    }

    // MARK: - Visualizer

    public static var visualizerDefaults: [String: Any] {
        var defaults: [String: Any] = [
            "default.commandKeysOnly": false,
            "default.allModifiedKeys": false,
            "default.allKeys": true,
            "default.fadeDelay": 2.0,
            "default.fadeDuration": 0.2,
            "default.fontSize": 16.0,
            "default.keystrokeDelay": 0.5,
            "default_displayModifiedCharacters": false,
        ]
        if let bezelData = try? NSKeyedArchiver.archivedData(
            withRootObject: NSColor(calibratedWhite: 0, alpha: 0.8),
            requiringSecureCoding: false
        ) {
            defaults["default.bezelColor"] = bezelData
        }
        if let textData = try? NSKeyedArchiver.archivedData(
            withRootObject: NSColor(calibratedWhite: 1, alpha: 1),
            requiringSecureCoding: false
        ) {
            defaults["default.textColor"] = textData
        }
        return defaults
    }

    public func showVisualizer(_ sender: Any?) { bezelWindow.orderFront(sender) }
    public func hideVisualizer(_ sender: Any?) { bezelWindow.orderOut(sender) }
    public func deactivateVisualizer(_ sender: Any?) { bezelWindow.orderOut(sender) }

    public func noteKeyEvent(_ event: KeycastrEvent) {
        guard let keystroke = event as? Keystroke else { return }
        if !keystroke.isCommand && shouldOnlyDisplayCommandKeys {
            return
        }
        if !keystroke.isModified && shouldOnlyDisplayModifiedKeys {
            return
        }
        bezelWindow.add(keystroke: keystroke)
    }

    public func noteFlagsChanged(_ flags: NSEvent.ModifierFlags) { /* no-op */ }

    public func noteMouseEvent(_ event: MouseEvent) {
        bezelWindow.add(mouseEvent: event)
    }

    // MARK: - Display option

    public var shouldOnlyDisplayCommandKeys: Bool { displayMode == .commandKeysOnly }
    public var shouldOnlyDisplayModifiedKeys: Bool { displayMode == .allModifiedKeys }

    public func configureDisplayMode(with userDefaults: UserDefaults) {
        if userDefaults.bool(forKey: "default.commandKeysOnly") {
            displayMode = .commandKeysOnly
        } else if userDefaults.bool(forKey: "default.allModifiedKeys") {
            displayMode = .allModifiedKeys
        } else {
            displayMode = .allKeys
        }
    }

    @objc public func preferencesViewDidSelectDisplayOption(_ sender: Any?) {
        let mode: DefaultVisualizerDisplayOption
        let view = _preferencesView
        if (sender as AnyObject?) === view.commandKeysOnlyButton {
            mode = .commandKeysOnly
        } else if (sender as AnyObject?) === view.allModifiedKeysButton {
            mode = .allModifiedKeys
        } else if (sender as AnyObject?) === view.allKeysButton {
            mode = .allKeys
        } else {
            mode = .default
        }
        setDisplayMode(mode)
    }

    public func setDisplayMode(_ mode: DefaultVisualizerDisplayOption) {
        displayMode = mode
        let ud = UserDefaults.standard
        ud.set(mode == .commandKeysOnly, forKey: "default.commandKeysOnly")
        ud.set(mode == .allModifiedKeys, forKey: "default.allModifiedKeys")
        ud.set(mode == .allKeys, forKey: "default.allKeys")
    }
}
