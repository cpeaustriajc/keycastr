import AppKit
import QuartzCore

@MainActor
public protocol MouseEventVisualizerDelegate: AnyObject {
    func mouseEventVisualizer(_ visualizer: MouseEventVisualizer, didNote event: MouseEvent)
}

@MainActor
public final class MouseEventVisualizer {

    public enum DisplayOption: Int, CaseIterable {
        case none = 0
        case withPointer = 1
        case withVisualizer = 2
        case withPointerAndVisualizer = 3

        public var localizedName: String {
            switch self {
            case .none: return "None"
            case .withPointer: return "With Mouse Pointer"
            case .withVisualizer: return "With Current Visualizer"
            case .withPointerAndVisualizer: return "With Pointer and Visualizer"
            }
        }
    }

    public weak var delegate: (any MouseEventVisualizerDelegate)?

    public let displayOptionNames: [String] = DisplayOption.allCases.map(\.localizedName)

    public var selectedMouseDisplayOptionIndex: Int {
        didSet {
            UserDefaults.standard.set(selectedMouseDisplayOptionIndex, forKey: Self.displayOptionKey)
            updateWindowVisibility()
        }
    }

    public var currentMouseDisplayOptionName: String {
        get { displayOptionNames[max(0, min(displayOptionNames.count - 1, selectedMouseDisplayOptionIndex))] }
        set {
            if let idx = displayOptionNames.firstIndex(of: newValue) {
                selectedMouseDisplayOptionIndex = idx
            }
        }
    }

    public var isEnabled: Bool { selectedMouseDisplayOptionIndex > 0 }

    private static let displayOptionKey = "mouse.displayOption"
    private var window: RingWindow?

    public init() {
        self.selectedMouseDisplayOptionIndex = UserDefaults.standard.integer(forKey: Self.displayOptionKey)
        updateWindowVisibility()
    }

    public func noteMouseEvent(_ event: MouseEvent) {
        // Options 1 & 3 render the click ring under the pointer. Mouse-up always passes through
        // so a stuck animation can't accumulate.
        if selectedMouseDisplayOptionIndex == 1 ||
            selectedMouseDisplayOptionIndex == 3 ||
            Self.isMouseUp(event) {
            window?.update(with: event)
        }

        // Options 2 & 3 forward the event to the keystroke visualizer via the delegate.
        if selectedMouseDisplayOptionIndex >= 2 {
            delegate?.mouseEventVisualizer(self, didNote: event)
        }
    }

    private static func isMouseUp(_ event: MouseEvent) -> Bool {
        switch event.type {
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return true
        default:
            return false
        }
    }

    private func updateWindowVisibility() {
        guard NSApp != nil else { return }
        if selectedMouseDisplayOptionIndex == 0 {
            window?.orderOut(nil)
            window = nil
        } else if window == nil {
            let w = RingWindow()
            w.orderFrontRegardless()
            window = w
        }
    }
}

// MARK: - Ring Window

@MainActor
private final class RingWindow: NSWindow {
    private static let radius: CGFloat = 22.0
    private static let strokeWidth: CGFloat = 2.0

    private var rippleLayers: [CAShapeLayer] = []

    init() {
        let diameter = 2 * Self.radius
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: diameter, height: diameter),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        alphaValue = 1
        ignoresMouseEvents = true
        collectionBehavior = .canJoinAllSpaces
        hasShadow = false

        let host = FlippedView(frame: contentRect(forFrameRect: frame))
        host.wantsLayer = true
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func update(with event: MouseEvent) {
        // Move the window so the pointer sits dead-center.
        let origin = NSPoint(
            x: event.locationInWindow.x - Self.radius,
            y: event.locationInWindow.y - Self.radius
        )
        setFrameOrigin(origin)

        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            emitRipple()
        default:
            break
        }
    }

    private func emitRipple() {
        guard let host = contentView else { return }
        if host.layer == nil { host.wantsLayer = true }
        guard let hostLayer = host.layer else { return }

        let ring = CAShapeLayer()
        let diameter = 2 * Self.radius
        let inset = Self.strokeWidth
        let bounds = CGRect(x: inset, y: inset, width: diameter - 2 * inset, height: diameter - 2 * inset)
        ring.path = CGPath(ellipseIn: bounds, transform: nil)
        ring.strokeColor = NSColor.controlAccentColor.cgColor
        ring.fillColor = NSColor.clear.cgColor
        ring.lineWidth = Self.strokeWidth
        ring.opacity = 1.0
        hostLayer.addSublayer(ring)
        rippleLayers.append(ring)

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion {
            attachFade(to: ring, duration: 0.25)
        } else {
            attachConcentricRipple(to: ring)
        }
    }

    private func attachFade(to layer: CAShapeLayer, duration: CFTimeInterval) {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0
        fade.duration = duration
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        layer.add(fade, forKey: "fade")
        scheduleRemoval(of: layer, after: duration)
    }

    private func attachConcentricRipple(to layer: CAShapeLayer) {
        let duration: CFTimeInterval = 0.55
        let group = CAAnimationGroup()
        group.duration = duration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        // Scale outward with spring damping.
        let scale = CASpringAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.6
        scale.toValue = 1.6
        scale.damping = 10
        scale.mass = 1
        scale.stiffness = 100
        scale.initialVelocity = 6
        scale.duration = duration

        // Fade out concurrently.
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0

        group.animations = [scale, fade]
        layer.add(group, forKey: "ripple")
        scheduleRemoval(of: layer, after: duration)
    }

    private func scheduleRemoval(of layer: CAShapeLayer, after delay: CFTimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak layer] in
            guard let self, let layer else { return }
            layer.removeFromSuperlayer()
            self.rippleLayers.removeAll { $0 === layer }
        }
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
