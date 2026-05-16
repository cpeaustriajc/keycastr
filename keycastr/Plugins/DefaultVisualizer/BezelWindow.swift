import AppKit
import QuartzCore
import Visualizer

@MainActor
final class BezelWindow: NSPanel {

    // Tahoe HIG: tight content-hugging bezel anchored near the screen bottom.
    private static let bezelSpacing: CGFloat = 8      // vertical gap between stacked bezels
    private static let bottomInset: CGFloat = 80      // distance from screen bottom to lowest bezel
    private static let cornerRadius: CGFloat = 18

    private weak var currentBezelView: BezelView?
    private var bezelStack: [BezelView] = []
    private var lineBreakWorkItem: DispatchWorkItem?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        alphaValue = 1
        hasShadow = true
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        hidesOnDeactivate = false

        let host = NSView(frame: NSRect(origin: .zero, size: NSSize(width: 120, height: 40)))
        host.wantsLayer = true
        contentView = host

        repositionToAnchor()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Returns the desired anchor point (bottom-center of the bezel stack) on the main screen.
    private func anchorPoint() -> NSPoint {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        return NSPoint(x: screen.midX, y: screen.minY + Self.bottomInset)
    }

    private func repositionToAnchor() {
        let p = anchorPoint()
        let f = frame
        let newOrigin = NSPoint(x: p.x - f.width / 2, y: p.y)
        setFrameOrigin(newOrigin)
    }

    // MARK: - Append public API

    func add(keystroke: Keystroke) {
        cancelLineBreak()
        if keystroke.isCommand {
            currentBezelView = nil
        }
        append(string: keystroke.convertToString())
    }

    func add(mouseEvent: MouseEvent) {
        switch mouseEvent.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            currentBezelView = nil
            append(string: mouseEvent.convertToString())
        default:
            break
        }
    }

    private func append(string: String) {
        if let existing = currentBezelView {
            existing.append(string)
        } else {
            spawnNewBezel(initialString: string)
        }
        relayoutStack()
        scheduleLineBreak()
    }

    private func spawnNewBezel(initialString: String) {
        guard let host = contentView else { return }

        let view = BezelView(
            text: initialString,
            tintColor: backgroundTint(),
            fontSize: userFontSize(),
            textColor: userTextColor()
        )
        host.addSubview(view)
        bezelStack.append(view)
        view.beginFadeOutCountdown(delay: userFadeDelay(), duration: userFadeDuration()) { [weak self, weak view] in
            guard let self, let view else { return }
            self.bezelStack.removeAll { $0 === view }
            self.relayoutStack()
        }
        currentBezelView = view
    }

    /// Resize the bezels, then resize/reposition the window so the stack fits exactly,
    /// anchored at the bottom-center of the screen with newest bezel on top.
    private func relayoutStack() {
        guard let host = contentView else { return }

        // Refresh intrinsic sizes for every bezel (text may have appended).
        for v in bezelStack { v.refreshIntrinsicSize() }

        let widest = bezelStack.map { $0.frame.width }.max() ?? 120
        let heights = bezelStack.map { $0.frame.height }
        let totalHeight = heights.reduce(0, +) + max(0, CGFloat(bezelStack.count - 1)) * Self.bezelSpacing
        let newSize = NSSize(width: max(widest, 60), height: max(totalHeight, 40))

        // Resize window keeping the bottom anchor stable.
        let anchor = anchorPoint()
        let newFrame = NSRect(
            x: anchor.x - newSize.width / 2,
            y: anchor.y,
            width: newSize.width,
            height: newSize.height
        )
        setFrame(newFrame, display: true, animate: false)

        // Layout subviews: newest on top, oldest at bottom of host (Cocoa coords).
        var y = newSize.height
        for view in bezelStack.reversed() {
            let h = view.frame.height
            y -= h
            view.frame = NSRect(
                x: (newSize.width - view.frame.width) / 2,
                y: y,
                width: view.frame.width,
                height: h
            )
            y -= Self.bezelSpacing
        }
        host.frame = NSRect(origin: .zero, size: newSize)
    }

    private func cancelLineBreak() {
        lineBreakWorkItem?.cancel()
        lineBreakWorkItem = nil
    }

    private func scheduleLineBreak() {
        cancelLineBreak()
        let delay = UserDefaults.standard.double(forKey: "default.keystrokeDelay")
        let resolved = delay > 0 ? delay : 0.5
        let item = DispatchWorkItem { [weak self] in
            self?.currentBezelView = nil
        }
        lineBreakWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + resolved, execute: item)
    }

    // MARK: - User defaults helpers

    private func backgroundTint() -> NSColor {
        guard let data = UserDefaults.standard.data(forKey: "default.bezelColor"),
              let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
        else {
            return NSColor(calibratedWhite: 0, alpha: 0.18)
        }
        return color
    }

    private func userTextColor() -> NSColor {
        guard let data = UserDefaults.standard.data(forKey: "default.textColor"),
              let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
        else {
            return .labelColor
        }
        return color
    }

    private func userFontSize() -> CGFloat {
        let v = UserDefaults.standard.double(forKey: "default.fontSize")
        return v > 0 ? CGFloat(v) : 16.0
    }

    private func userFadeDelay() -> TimeInterval {
        let v = UserDefaults.standard.double(forKey: "default.fadeDelay")
        return v > 0 ? v : 2.0
    }

    private func userFadeDuration() -> TimeInterval {
        let v = UserDefaults.standard.double(forKey: "default.fadeDuration")
        return v > 0 ? v : 0.2
    }
}

@MainActor
final class BezelView: NSView {
    // Tight Tahoe-style padding inside the glass.
    private static let horizontalInset: CGFloat = 12
    private static let verticalInset: CGFloat = 6
    private static let cornerRadius: CGFloat = 18
    private static let minWidth: CGFloat = 60
    private static let maxWidth: CGFloat = 1200

    private let glassView: NSGlassEffectView
    private let textField: NSTextField
    private let textColor: NSColor
    private let fontSize: CGFloat

    private var fadeOutWorkItem: DispatchWorkItem?

    init(text: String, tintColor: NSColor, fontSize: CGFloat, textColor: NSColor) {
        self.textColor = textColor
        self.fontSize = fontSize

        let textField = NSTextField(labelWithString: text)
        textField.font = .systemFont(ofSize: fontSize, weight: .medium)
        textField.textColor = textColor
        textField.alignment = .center
        textField.lineBreakMode = .byClipping
        textField.usesSingleLineMode = true
        textField.maximumNumberOfLines = 1
        textField.drawsBackground = false
        textField.isBezeled = false
        textField.isEditable = false
        textField.isSelectable = false
        self.textField = textField

        let glass = NSGlassEffectView(frame: .zero)
        glass.cornerRadius = Self.cornerRadius
        glass.tintColor = tintColor
        glass.style = .clear
        glass.wantsLayer = true
        self.glassView = glass

        super.init(frame: .zero)
        wantsLayer = true
        let contentHost = NSView(frame: .zero)
        contentHost.wantsLayer = true
        contentHost.addSubview(textField)
        glass.contentView = contentHost
        addSubview(glass)
        refreshIntrinsicSize()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func append(_ string: String) {
        textField.stringValue.append(string)
        refreshIntrinsicSize()
    }

    /// Recompute the view's frame to hug the text exactly, then center the text inside.
    func refreshIntrinsicSize() {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium)
        ]
        let bounding = (textField.stringValue as NSString)
            .boundingRect(
                with: NSSize(width: Self.maxWidth, height: .greatestFiniteMagnitude),
                options: [.usesFontLeading],
                attributes: attributes
            )
        // Add a small safety buffer to account for sub-pixel kerning.
        let textWidth = ceil(bounding.width) + 2
        let textHeight = ceil(bounding.height)

        let bezelWidth = min(Self.maxWidth, max(Self.minWidth, textWidth + 2 * Self.horizontalInset))
        let bezelHeight = max(2 * Self.cornerRadius, textHeight + 2 * Self.verticalInset)
        let newSize = NSSize(width: bezelWidth, height: bezelHeight)
        if frame.size != newSize {
            setFrameSize(newSize)
        }

        glassView.frame = bounds
        glassView.contentView?.frame = bounds

        // Center the textField (intrinsic size) within the bezel.
        let availableWidth = bezelWidth - 2 * Self.horizontalInset
        let actualWidth = min(textWidth, availableWidth)
        let textOrigin = NSPoint(
            x: (bezelWidth - actualWidth) / 2,
            y: (bezelHeight - textHeight) / 2
        )
        textField.frame = NSRect(origin: textOrigin, size: NSSize(width: actualWidth, height: textHeight))
    }

    func beginFadeOutCountdown(delay: TimeInterval, duration: TimeInterval, onComplete: @escaping () -> Void) {
        fadeOutWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.fadeOut(over: duration, onComplete: onComplete)
        }
        fadeOutWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func fadeOut(over duration: TimeInterval, onComplete: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.removeFromSuperview()
            onComplete()
        })
    }
}
