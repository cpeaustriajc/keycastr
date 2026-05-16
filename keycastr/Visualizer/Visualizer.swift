import AppKit

/// A visualizer plugin's runtime instance. Implementations live in `.kcplugin` bundles.
@MainActor
public protocol Visualizer: AnyObject {
    static var visualizerDefaults: [String: Any] { get }

    var preferencesView: NSView? { get }
    var visualizerName: String { get }

    func showVisualizer(_ sender: Any?)
    func hideVisualizer(_ sender: Any?)
    func deactivateVisualizer(_ sender: Any?)

    func noteKeyEvent(_ event: KeycastrEvent)
    func noteFlagsChanged(_ flags: NSEvent.ModifierFlags)
    func noteMouseEvent(_ event: MouseEvent)
}

/// A visualizer plugin's principal class. Each `.kcplugin` bundle's Info.plist `NSPrincipalClass`
/// must point at a `VisualizerFactory`-conforming `NSObject` subclass.
@MainActor
public protocol VisualizerFactory: AnyObject {
    var visualizerName: String { get }
    var visualizerType: Visualizer.Type { get }
    func makeVisualizer() -> Visualizer
}
