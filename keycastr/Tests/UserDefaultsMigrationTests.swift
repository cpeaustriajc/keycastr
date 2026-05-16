import XCTest
import AppKit
@testable import Visualizer

/// 1:1 Swift port of `_legacy/KCVisualizerTests/KCUserDefaultsMigrationTests.m`.
final class UserDefaultsMigrationTests: XCTestCase {

    func test_migratingUserDefaults() throws {
        let colorKeyNames = UserDefaultsMigration.colorKeyNames
        let suiteName = String(describing: type(of: self))
        let userDefaults = UserDefaults(suiteName: suiteName)!

        // Pre-seed with a value archived in the legacy NSArchiver format.
        let inputColor = NSColor(calibratedWhite: 0, alpha: 0.8)
        let legacyData = NSArchiver.archivedData(withRootObject: inputColor)
        userDefaults.set(legacyData, forKey: colorKeyNames.first!)

        // Sanity check: the data is legacy-encoded and the deprecated unarchiver can read it
        // (alpha component ~= 0.8).
        let storedData = userDefaults.data(forKey: colorKeyNames.first!)!
        let unarchivedColor = NSUnarchiver.unarchiveObject(with: storedData) as? NSColor
        XCTAssertNotNil(unarchivedColor)
        XCTAssertEqual(unarchivedColor!.alphaComponent, 0.8, accuracy: 0.01)

        // Run the migration.
        UserDefaultsMigration.performMigration(userDefaults)

        // After migration, the data should be NSKeyedArchiver-encoded and the modern API recovers it.
        let migratedData = userDefaults.data(forKey: colorKeyNames.first!)!
        let migratedColor = try XCTUnwrap(
            NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: migratedData)
        )
        XCTAssertEqual(migratedColor.alphaComponent, 0.8, accuracy: 0.01)
    }
}
