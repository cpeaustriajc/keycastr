import AppKit
import Visualizer

// MARK: - SvelteView

/// Renders the modifier-flag grid and a sliding keystroke display using Tahoe glass materials.
@MainActor
final class SvelteView: NSView {

    // MARK: Stored state

    private var flags: NSEvent.ModifierFlags = []
    private var displayedString: String? = nil

    // MARK: Layout constants

    fileprivate static let modifierRowHeight: CGFloat = 30
    fileprivate static let modifierCellCornerRadius: CGFloat = 12
    fileprivate static let keystrokeCellCornerRadius: CGFloat = 16
    fileprivate static let cellSpacing: CGFloat = 4
    fileprivate static let containerPadding: CGFloat = 4

    // MARK: Glass subviews

    private let container: NSGlassEffectContainerView

    /// Modifier cells: [⇧, ⌃, ⌥, ⌘]
    private let shiftCell: ModifierCell
    private let controlCell: ModifierCell
    private let optionCell: ModifierCell
    private let commandCell: ModifierCell

    private let keystrokeCell: NSGlassEffectView
    private let keystrokeLabel: NSTextField

    // MARK: Init

    override init(frame frameRect: NSRect) {
        container = NSGlassEffectContainerView(frame: frameRect)
        container.spacing = 0

        shiftCell   = ModifierCell(glyph: "⇧")
        controlCell = ModifierCell(glyph: "⌃")
        optionCell  = ModifierCell(glyph: "⌥")
        commandCell = ModifierCell(glyph: "⌘")

        keystrokeCell = NSGlassEffectView(frame: .zero)
        keystrokeCell.cornerRadius = SvelteView.keystrokeCellCornerRadius
        keystrokeCell.style = .regular

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 48, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        label.lineBreakMode = .byClipping
        label.cell?.usesSingleLineMode = true
        label.translatesAutoresizingMaskIntoConstraints = false
        keystrokeLabel = label

        super.init(frame: frameRect)

        wantsLayer = true

        // Wire up container
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let modifierRow = NSStackView(views: [shiftCell, controlCell, optionCell, commandCell])
        modifierRow.orientation = .horizontal
        modifierRow.distribution = .fillEqually
        modifierRow.spacing = SvelteView.cellSpacing
        modifierRow.translatesAutoresizingMaskIntoConstraints = false

        let labelContainer = NSView()
        labelContainer.addSubview(keystrokeLabel)
        NSLayoutConstraint.activate([
            keystrokeLabel.centerXAnchor.constraint(equalTo: labelContainer.centerXAnchor),
            keystrokeLabel.centerYAnchor.constraint(equalTo: labelContainer.centerYAnchor),
            keystrokeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: labelContainer.leadingAnchor, constant: 8),
            keystrokeLabel.trailingAnchor.constraint(lessThanOrEqualTo: labelContainer.trailingAnchor, constant: -8),
        ])
        keystrokeCell.contentView = labelContainer

        keystrokeCell.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(modifierRow)
        contentView.addSubview(keystrokeCell)

        NSLayoutConstraint.activate([
            modifierRow.topAnchor.constraint(equalTo: contentView.topAnchor, constant: SvelteView.containerPadding),
            modifierRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: SvelteView.containerPadding),
            modifierRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -SvelteView.containerPadding),
            modifierRow.heightAnchor.constraint(equalToConstant: SvelteView.modifierRowHeight),

            keystrokeCell.topAnchor.constraint(equalTo: modifierRow.bottomAnchor, constant: SvelteView.cellSpacing),
            keystrokeCell.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: SvelteView.containerPadding),
            keystrokeCell.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -SvelteView.containerPadding),
            keystrokeCell.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -SvelteView.containerPadding),
        ])

        container.contentView = contentView

        updateModifierAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Public API

    func noteKeyEvent(_ event: KeycastrEvent) {
        let text = event.convertToString()
        if var existing = displayedString {
            existing.append(text)
            // Sliding window: keep last 6 characters
            if existing.count > 6 {
                existing = String(existing.suffix(6))
            }
            displayedString = existing
        } else {
            displayedString = text
        }
        refreshKeystrokeLabel()
    }

    func noteFlagsChanged(_ newFlags: NSEvent.ModifierFlags) {
        flags = newFlags
        displayedString = nil
        refreshKeystrokeLabel()
        updateModifierAppearance()
    }

    // MARK: - Private helpers

    private func refreshKeystrokeLabel() {
        let text = displayedString ?? ""
        keystrokeLabel.stringValue = text

        // Shrink-to-fit: decrement font size by 1pt until the text fits the cell width
        let availableWidth = keystrokeCell.bounds.width - 16
        guard availableWidth > 0, !text.isEmpty else {
            keystrokeLabel.font = .systemFont(ofSize: 48, weight: .medium)
            return
        }

        var fontSize: CGFloat = 48
        var textWidth = (text as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium)
        ]).width
        while textWidth > availableWidth && fontSize > 8 {
            fontSize -= 1
            textWidth = (text as NSString).size(withAttributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .medium)
            ]).width
        }
        keystrokeLabel.font = .systemFont(ofSize: fontSize, weight: .medium)
    }

    private func updateModifierAppearance() {
        let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast

        shiftCell.setActive(flags.contains(.shift), highContrast: highContrast)
        controlCell.setActive(flags.contains(.control), highContrast: highContrast)
        optionCell.setActive(flags.contains(.option), highContrast: highContrast)
        commandCell.setActive(flags.contains(.command), highContrast: highContrast)
    }
}

// MARK: - ModifierCell

/// A single glass modifier indicator pill with a centered glyph label.
@MainActor
private final class ModifierCell: NSGlassEffectView {

    private let glyphLabel: NSTextField

    init(glyph: String) {
        let label = NSTextField(labelWithString: glyph)
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        self.glyphLabel = label

        super.init(frame: .zero)
        cornerRadius = SvelteView.modifierCellCornerRadius
        style = .regular
        translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        contentView = container

        setActive(false, highContrast: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setActive(_ active: Bool, highContrast: Bool) {
        if active {
            glyphLabel.textColor = .controlAccentColor
            // High contrast: full opacity tint; otherwise use a subtle accent tint
            tintColor = highContrast
                ? NSColor.controlAccentColor.withAlphaComponent(0.4)
                : NSColor.controlAccentColor.withAlphaComponent(0.15)
        } else {
            glyphLabel.textColor = .secondaryLabelColor
            tintColor = nil
        }
    }
}
