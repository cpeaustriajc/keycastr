import AppKit
import Visualizer

// MARK: - Factory (principal class)

@objc(SvelteVisualizerFactory)
@MainActor
public final class SvelteVisualizerFactory: NSObject, VisualizerFactory {
    public var visualizerName: String { "Svelte" }
    public var visualizerType: any Visualizer.Type { SvelteVisualizer.self }
    public func makeVisualizer() -> any Visualizer { SvelteVisualizer() }

    @objc public override init() {
        // Plugin loader instantiates via init() on the main thread (run loop). The Obj-C runtime
        // does not honor @MainActor isolation, so this initializer is invoked dynamically.
        MainActor.assumeIsolated { _ = () }
        super.init()
    }
}

// MARK: - Preferences view

@MainActor
public final class SveltePreferencesView: NSView {
    public let displayAllButton: NSButton

    public override init(frame frameRect: NSRect) {
        displayAllButton = NSButton(checkboxWithTitle: "Display all keystrokes", target: nil, action: nil)
        super.init(frame: frameRect)
        displayAllButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(displayAllButton)
        NSLayoutConstraint.activate([
            displayAllButton.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            displayAllButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            displayAllButton.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -16),
        ])
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public func wireAction(target: AnyObject, action: Selector) {
        displayAllButton.target = target
        displayAllButton.action = action
    }

    public func refreshState(displayAll: Bool) {
        displayAllButton.state = displayAll ? .on : .off
    }
}

// MARK: - Visualizer instance

@MainActor
public final class SvelteVisualizer: NSObject, Visualizer {

    public var visualizerName: String { "Svelte" }

    private var displayAll: Bool = false {
        didSet { _preferencesView.refreshState(displayAll: displayAll) }
    }

    private let panel: NSPanel
    private let svelteView: SvelteView

    private lazy var _preferencesView: SveltePreferencesView = {
        let v = SveltePreferencesView(frame: NSRect(x: 0, y: 0, width: 320, height: 80))
        v.wireAction(target: self, action: #selector(displayAllCheckboxChanged(_:)))
        v.refreshState(displayAll: displayAll)
        return v
    }()

    public var preferencesView: NSView? { _preferencesView }

    // nonisolated(unsafe) allows deinit (which is nonisolated) to call removeObserver.
    // The token is set once on the main actor and only read in deinit, so this is safe.
    nonisolated(unsafe) private var defaultsObserver: NSObjectProtocol?

    public override init() {
        let initialRect = NSRect(x: 10, y: 10, width: 200, height: 100)

        let panel = NSPanel(
            contentRect: initialRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = .canJoinAllSpaces
        panel.hidesOnDeactivate = false

        let view = SvelteView(frame: NSRect(origin: .zero, size: initialRect.size))
        panel.contentView = view

        self.panel = panel
        self.svelteView = view

        super.init()

        // Restore saved frame (must happen after super.init)
        panel.setFrameUsingName("svelte.windowFrame", force: true)
        panel.setFrameAutosaveName("svelte.windowFrame")

        // Read initial value
        displayAll = UserDefaults.standard.bool(forKey: "svelte.displayAll")

        // Observe changes
        let observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.displayAll = UserDefaults.standard.bool(forKey: "svelte.displayAll")
        }
        self.defaultsObserver = observer
    }

    deinit {
        if let observer = defaultsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Visualizer

    public static var visualizerDefaults: [String: Any] {
        ["svelte.displayAll": true]
    }

    public func showVisualizer(_ sender: Any?) { panel.orderFront(sender) }
    public func hideVisualizer(_ sender: Any?) { panel.orderOut(sender) }
    public func deactivateVisualizer(_ sender: Any?) { panel.orderOut(sender) }

    public func noteKeyEvent(_ event: KeycastrEvent) {
        guard let keystroke = event as? Keystroke else { return }
        if !displayAll && !keystroke.isCommand { return }
        svelteView.noteKeyEvent(keystroke)
    }

    public func noteMouseEvent(_ event: MouseEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            svelteView.noteKeyEvent(event)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            svelteView.noteFlagsChanged(event.modifierFlags)
        default:
            break
        }
    }

    public func noteFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        svelteView.noteFlagsChanged(flags)
    }

    // MARK: - Preferences action

    @objc private func displayAllCheckboxChanged(_ sender: Any?) {
        let newValue = _preferencesView.displayAllButton.state == .on
        displayAll = newValue
        UserDefaults.standard.set(newValue, forKey: "svelte.displayAll")
    }
}
