import Foundation

public final class PreferencesStore {
    public static let shared = PreferencesStore(defaults: .standard)

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.autoStopEnabled: true,
            Keys.autoStopTime: "18:00",
            Keys.menuBarTaskNameMaxLength: 20,
        ])
    }

    private enum Keys {
        static let autoStopEnabled = "autoStopEnabled"
        static let autoStopTime = "autoStopTime"
        static let menuBarTaskNameMaxLength = "menuBarTaskNameMaxLength"
        static let lastAutoStopDay = "lastAutoStopDay"
    }

    public var autoStopEnabled: Bool {
        get { defaults.bool(forKey: Keys.autoStopEnabled) }
        set { defaults.set(newValue, forKey: Keys.autoStopEnabled) }
    }

    public var autoStopTime: String {
        get { defaults.string(forKey: Keys.autoStopTime) ?? "18:00" }
        set { defaults.set(newValue, forKey: Keys.autoStopTime) }
    }

    public var menuBarTaskNameMaxLength: Int {
        get { defaults.integer(forKey: Keys.menuBarTaskNameMaxLength) }
        set { defaults.set(newValue, forKey: Keys.menuBarTaskNameMaxLength) }
    }

    /// Last local-date (yyyy-MM-dd) on which auto-stop fired. Used to guarantee
    /// auto-stop fires at most once per day, even across app restarts.
    public var lastAutoStopDay: String? {
        get { defaults.string(forKey: Keys.lastAutoStopDay) }
        set {
            if let newValue { defaults.set(newValue, forKey: Keys.lastAutoStopDay) }
            else { defaults.removeObject(forKey: Keys.lastAutoStopDay) }
        }
    }

    public var autoStopHourMinute: (hour: Int, minute: Int)? {
        let parts = autoStopTime.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return (h, m)
    }
}
