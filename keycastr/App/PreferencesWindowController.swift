import AppKit
import Visualizer

@MainActor
final class PreferencesWindowController: NSWindowController, NSToolbarDelegate {

    private struct Pane {
        let identifier: NSToolbarItem.Identifier
        let label: String
        let symbolName: String
        let viewBuilder: @MainActor () -> NSView
    }

    private weak var appController: AppController?
    private var panes: [Pane] = []
    private var paneViewCache: [NSToolbarItem.Identifier: NSView] = [:]
    private var visualizerPaneHost: NSView?

    init(controller: AppController) {
        self.appController = controller
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "KeyCastr Preferences"
        window.toolbarStyle = .preference
        super.init(window: window)
        configurePanes()
        configureToolbar()
        selectPane(identifier: panes[0].identifier)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Panes

    private func configurePanes() {
        panes = [
            Pane(
                identifier: NSToolbarItem.Identifier("general"),
                label: "General",
                symbolName: "gearshape",
                viewBuilder: { [weak self] in self?.buildGeneralPane() ?? NSView() }
            ),
            Pane(
                identifier: NSToolbarItem.Identifier("visualizer"),
                label: "Visualizer",
                symbolName: "keyboard.fill",
                viewBuilder: { [weak self] in self?.buildVisualizerPane() ?? NSView() }
            ),
            Pane(
                identifier: NSToolbarItem.Identifier("mouse"),
                label: "Mouse",
                symbolName: "cursorarrow.click",
                viewBuilder: { [weak self] in self?.buildMousePane() ?? NSView() }
            ),
            Pane(
                identifier: NSToolbarItem.Identifier("about"),
                label: "About",
                symbolName: "info.circle",
                viewBuilder: { [weak self] in self?.buildAboutPane() ?? NSView() }
            ),
        ]
    }

    private func configureToolbar() {
        let toolbar = NSToolbar(identifier: "KeyCastrPreferences")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconAndLabel
        window?.toolbar = toolbar
    }

    private func selectPane(identifier: NSToolbarItem.Identifier) {
        guard let pane = panes.first(where: { $0.identifier == identifier }) else { return }
        let view = paneViewCache[identifier] ?? {
            let v = pane.viewBuilder()
            paneViewCache[identifier] = v
            return v
        }()

        guard let window = self.window else { return }
        let target = view.fittingSize
        let contentSize = NSSize(width: max(target.width, 480), height: max(target.height, 280))
        var newFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize))
        let old = window.frame
        newFrame.origin.x = old.midX - newFrame.width / 2
        newFrame.origin.y = old.maxY - newFrame.height

        window.title = "KeyCastr — \(pane.label)"
        window.toolbar?.selectedItemIdentifier = identifier
        window.setFrame(newFrame, display: true, animate: window.isVisible)
        window.contentView = makeGlassHost(content: view)
    }

    private func makeGlassHost(content: NSView) -> NSView {
        let container = NSGlassEffectContainerView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let host = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -20),
            content.topAnchor.constraint(equalTo: host.topAnchor, constant: 20),
            content.bottomAnchor.constraint(lessThanOrEqualTo: host.bottomAnchor, constant: -20),
        ])
        container.contentView = host
        return container
    }

    // MARK: - Pane builders

    private func buildGeneralPane() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12

        let title = sectionLabel("Visualizer")
        stack.addArrangedSubview(title)

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.translatesAutoresizingMaskIntoConstraints = false
        if let names = appController?.availableVisualizerNames {
            popup.addItems(withTitles: names)
            popup.selectItem(withTitle: appController?.currentVisualizerName ?? "Default")
        }
        popup.target = self
        popup.action = #selector(visualizerSelectionChanged(_:))
        stack.addArrangedSubview(popup)

        stack.addArrangedSubview(divider())

        let launchTitle = sectionLabel("Launch")
        stack.addArrangedSubview(launchTitle)

        let launchCheckbox = NSButton(checkboxWithTitle: "Show preferences at launch", target: self, action: #selector(toggleVisibleAtLaunch(_:)))
        launchCheckbox.state = UserDefaults.standard.bool(forKey: "alwaysShowPrefs") ? .on : .off
        stack.addArrangedSubview(launchCheckbox)

        return wrap(stack)
    }

    private func buildVisualizerPane() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12

        stack.addArrangedSubview(sectionLabel("Active visualizer settings"))

        let host = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false
        visualizerPaneHost = host
        embedCurrentVisualizerPreferences(into: host)
        stack.addArrangedSubview(host)

        return wrap(stack)
    }

    private func buildMousePane() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12

        stack.addArrangedSubview(sectionLabel("Mouse click display"))

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.translatesAutoresizingMaskIntoConstraints = false
        if let names = appController?.mouseDisplayOptionNames {
            popup.addItems(withTitles: names)
            if let idx = appController?.currentMouseDisplayOptionIndex {
                popup.selectItem(at: idx)
            }
        }
        popup.target = self
        popup.action = #selector(mouseOptionChanged(_:))
        stack.addArrangedSubview(popup)

        return wrap(stack)
    }

    private func buildAboutPane() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8

        let name = NSTextField(labelWithString: "KeyCastr")
        name.font = .systemFont(ofSize: 22, weight: .semibold)
        stack.addArrangedSubview(name)

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let versionLabel = NSTextField(labelWithString: "Version \(version)")
        versionLabel.font = .systemFont(ofSize: 13, weight: .regular)
        versionLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(versionLabel)

        let copyright = NSTextField(labelWithString: "© 2009–2026 Stephen Deken, Andrew Kitchen, and contributors.")
        copyright.font = .systemFont(ofSize: 11, weight: .regular)
        copyright.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(copyright)

        return wrap(stack)
    }

    private func embedCurrentVisualizerPreferences(into host: NSView) {
        for sub in host.subviews { sub.removeFromSuperview() }
        guard let name = appController?.currentVisualizerName,
              let prefView = VisualizerRegistry.factory(named: name)?.makeVisualizer().preferencesView else {
            let placeholder = NSTextField(labelWithString: "No settings available for the current visualizer.")
            placeholder.textColor = .secondaryLabelColor
            placeholder.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(placeholder)
            NSLayoutConstraint.activate([
                placeholder.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                placeholder.topAnchor.constraint(equalTo: host.topAnchor),
            ])
            return
        }
        prefView.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(prefView)
        NSLayoutConstraint.activate([
            prefView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            prefView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            prefView.topAnchor.constraint(equalTo: host.topAnchor),
            prefView.bottomAnchor.constraint(lessThanOrEqualTo: host.bottomAnchor),
        ])
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = .systemFont(ofSize: 13, weight: .semibold)
        f.textColor = .secondaryLabelColor
        return f
    }

    private func divider() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func wrap(_ inner: NSStackView) -> NSView {
        let outer = NSView()
        inner.translatesAutoresizingMaskIntoConstraints = false
        outer.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: outer.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: outer.trailingAnchor),
            inner.topAnchor.constraint(equalTo: outer.topAnchor),
            inner.bottomAnchor.constraint(lessThanOrEqualTo: outer.bottomAnchor),
        ])
        return outer
    }

    // MARK: - Actions

    @objc private func visualizerSelectionChanged(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title else { return }
        appController?.switchVisualizer(named: title)
        if let host = visualizerPaneHost {
            embedCurrentVisualizerPreferences(into: host)
        }
    }

    @objc private func toggleVisibleAtLaunch(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "alwaysShowPrefs")
    }

    @objc private func mouseOptionChanged(_ sender: NSPopUpButton) {
        appController?.currentMouseDisplayOptionIndex = sender.indexOfSelectedItem
    }

    @objc private func toolbarItemSelected(_ sender: NSToolbarItem) {
        selectPane(identifier: sender.itemIdentifier)
    }

    // MARK: - NSToolbarDelegate

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let pane = panes.first(where: { $0.identifier == itemIdentifier }) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = pane.label
        item.paletteLabel = pane.label
        item.image = NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: pane.label)
        item.target = self
        item.action = #selector(toolbarItemSelected(_:))
        return item
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        panes.map(\.identifier)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        panes.map(\.identifier)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        panes.map(\.identifier)
    }
}
