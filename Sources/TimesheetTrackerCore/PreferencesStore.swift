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
            Keys.defaultWorkdayStart: "09:00",
            Keys.defaultWorkdayStop: "17:00",
            Keys.notifyBeforeAutoStopEnabled: false,
            Keys.notifyBeforeAutoStopMinutes: 10,
        ])
    }

    private enum Keys {
        static let autoStopEnabled = "autoStopEnabled"
        static let autoStopTime = "autoStopTime"
        static let menuBarTaskNameMaxLength = "menuBarTaskNameMaxLength"
        static let lastAutoStopDay = "lastAutoStopDay"
        static let defaultWorkdayStart = "defaultWorkdayStart"
        static let defaultWorkdayStop = "defaultWorkdayStop"
        static let notifyBeforeAutoStopEnabled = "notifyBeforeAutoStopEnabled"
        static let notifyBeforeAutoStopMinutes = "notifyBeforeAutoStopMinutes"
        static let lastAutoStopWarningDay = "lastAutoStopWarningDay"
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
        Self.parseHHMM(autoStopTime)
    }

    public var defaultWorkdayStart: String {
        get { defaults.string(forKey: Keys.defaultWorkdayStart) ?? "09:00" }
        set { defaults.set(newValue, forKey: Keys.defaultWorkdayStart) }
    }

    public var defaultWorkdayStop: String {
        get { defaults.string(forKey: Keys.defaultWorkdayStop) ?? "17:00" }
        set { defaults.set(newValue, forKey: Keys.defaultWorkdayStop) }
    }

    public var defaultWorkdayStartHourMinute: (hour: Int, minute: Int) {
        Self.parseHHMM(defaultWorkdayStart) ?? (9, 0)
    }

    public var defaultWorkdayStopHourMinute: (hour: Int, minute: Int) {
        Self.parseHHMM(defaultWorkdayStop) ?? (17, 0)
    }

    public var notifyBeforeAutoStopEnabled: Bool {
        get { defaults.bool(forKey: Keys.notifyBeforeAutoStopEnabled) }
        set { defaults.set(newValue, forKey: Keys.notifyBeforeAutoStopEnabled) }
    }

    public var notifyBeforeAutoStopMinutes: Int {
        get {
            let m = defaults.integer(forKey: Keys.notifyBeforeAutoStopMinutes)
            return m > 0 ? m : 10
        }
        set { defaults.set(max(1, newValue), forKey: Keys.notifyBeforeAutoStopMinutes) }
    }

    /// Last local-date on which the pre-auto-stop notification fired. Guarantees
    /// it fires at most once per day.
    public var lastAutoStopWarningDay: String? {
        get { defaults.string(forKey: Keys.lastAutoStopWarningDay) }
        set {
            if let newValue { defaults.set(newValue, forKey: Keys.lastAutoStopWarningDay) }
            else { defaults.removeObject(forKey: Keys.lastAutoStopWarningDay) }
        }
    }

    private static func parseHHMM(_ s: String) -> (hour: Int, minute: Int)? {
        let parts = s.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return (h, m)
    }
}
