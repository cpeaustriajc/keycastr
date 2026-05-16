import XCTest
@testable import Visualizer

/// 1:1 Swift port of `_legacy/KCVisualizerTests/KCDefaultVisualizerTests.m`.
///
/// The Obj-C test loads the plugin from the test bundle's PlugIns directory and asks the registry
/// for a "Default" visualizer. The Swift port compiles the plugin's source directly into the test
/// target (configured in `project.yml`) and registers the factory through `VisualizerRegistry`,
/// preserving the same surface and assertions.
final class DefaultVisualizerTests: XCTestCase {

    nonisolated(unsafe) private var visualizer: DefaultVisualizer!

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            VisualizerRegistry.register(DefaultVisualizerFactory())
            self.visualizer = VisualizerRegistry.visualizer(named: "Default") as? DefaultVisualizer
        }
        XCTAssertNotNil(visualizer)
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            VisualizerRegistry.unloadPlugins()
            self.visualizer = nil
        }
        super.tearDown()
    }

    @MainActor
    private func performTargetAction(on control: NSControl) {
        guard let target = control.target, let action = control.action else { return }
        _ = target.perform(action, with: control)
    }

    @MainActor
    func test_settingAndRetrievingDisplayOptions() {
        let view = visualizer.defaultPreferencesView

        performTargetAction(on: view.commandKeysOnlyButton)
        XCTAssertTrue(visualizer.shouldOnlyDisplayCommandKeys)
        XCTAssertFalse(visualizer.shouldOnlyDisplayModifiedKeys)

        performTargetAction(on: view.allModifiedKeysButton)
        XCTAssertFalse(visualizer.shouldOnlyDisplayCommandKeys)
        XCTAssertTrue(visualizer.shouldOnlyDisplayModifiedKeys)

        performTargetAction(on: view.allKeysButton)
        XCTAssertFalse(visualizer.shouldOnlyDisplayCommandKeys)
        XCTAssertFalse(visualizer.shouldOnlyDisplayModifiedKeys)
    }

    @MainActor
    func test_loadingDefaults() {
        let suite = UserDefaults(suiteName: String(describing: type(of: self)))!

        suite.set(true, forKey: "default.commandKeysOnly")
        visualizer.configureDisplayMode(with: suite)
        XCTAssertTrue(visualizer.shouldOnlyDisplayCommandKeys)
        suite.set(false, forKey: "default.commandKeysOnly")

        suite.set(true, forKey: "default.allModifiedKeys")
        visualizer.configureDisplayMode(with: suite)
        XCTAssertTrue(visualizer.shouldOnlyDisplayModifiedKeys)
        suite.set(false, forKey: "default.allModifiedKeys")
    }
}
