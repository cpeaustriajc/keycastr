import AppKit

@MainActor
public enum VisualizerRegistry {
    private static var factories: [String: any VisualizerFactory] = [:]

    public static var availableFactories: [any VisualizerFactory] {
        Array(factories.values)
    }

    public static func register(_ factory: any VisualizerFactory) {
        factories[factory.visualizerName] = factory
    }

    public static func unloadPlugins() {
        factories.removeAll()
    }

    public static func visualizer(named name: String) -> (any Visualizer)? {
        factories[name]?.makeVisualizer()
    }

    public static func factory(named name: String) -> (any VisualizerFactory)? {
        factories[name]
    }

    /// Loads every `.kcplugin` in the given directory, instantiates each bundle's principal class,
    /// and registers it as a `VisualizerFactory`.
    public static func loadPlugins(from directoryURL: URL) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for url in contents where url.pathExtension == "kcplugin" {
            guard let bundle = Bundle(url: url) else {
                NSLog("Skipping non-bundle plugin candidate: \(url.lastPathComponent)")
                continue
            }
            guard bundle.load() else {
                NSLog("Could not load \(url.lastPathComponent) from \(directoryURL.path)")
                continue
            }
            guard let principalClass = bundle.principalClass as? NSObject.Type else {
                NSLog("Plugin \(url.lastPathComponent) has no principal class")
                continue
            }
            let instance = principalClass.init()
            guard let factory = instance as? (any VisualizerFactory) else {
                NSLog("Plugin \(url.lastPathComponent) principal class does not conform to VisualizerFactory")
                continue
            }
            register(factory)
        }
    }

    /// Aggregated user-defaults dictionary across all registered plugins. Apps merge this with their
    /// own defaults and pass it to `UserDefaults.standard.register(defaults:)`.
    public static var aggregatedDefaults: [String: Any] {
        var combined: [String: Any] = [:]
        for factory in factories.values {
            for (k, v) in factory.visualizerType.visualizerDefaults {
                combined[k] = v
            }
        }
        return combined
    }
}
