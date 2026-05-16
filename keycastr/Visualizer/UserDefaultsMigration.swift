import AppKit

public enum UserDefaultsMigration {
    public static let colorKeyNames: [String] = ["default.textColor", "default.bezelColor"]

    /// Migrates the default visualizer's NSColor data stored in NSUserDefaults from the deprecated
    /// NSArchiver/NSUnarchiver format to NSKeyedArchiver/NSKeyedUnarchiver, and removes a stale
    /// Svelte preference key.
    public static func performMigration(_ userDefaults: UserDefaults) {
        for colorKey in colorKeyNames {
            guard let data = userDefaults.data(forKey: colorKey) else { continue }

            // Try the legacy NSUnarchiver first. If it succeeds, re-archive with NSKeyedArchiver.
            let legacyColor: NSColor? = {
                let unarchiver = NSUnarchiver(forReadingWith: data)
                let value = unarchiver?.decodeObject()
                return value as? NSColor
            }()

            guard let color = legacyColor else { continue }

            if let newData = try? NSKeyedArchiver.archivedData(
                withRootObject: color,
                requiringSecureCoding: false
            ) {
                userDefaults.set(newData, forKey: colorKey)
            }
        }

        userDefaults.removeObject(forKey: "svelte.allKeystrokes")
    }
}
