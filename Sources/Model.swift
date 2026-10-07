import Foundation

/// One entry of the timer list. `minutes == 0` means "Indefinitely".
struct DurationOption: Equatable, Hashable {
    let minutes: Int

    static let all: [DurationOption] = [60, 120, 180, 300, 480, 780, 1440, 0].map(DurationOption.init)
    static let indefinitely = DurationOption(minutes: 0)
    static let defaultOption = indefinitely

    /// Returns the option for a stored value, falling back to the default for anything unknown.
    static func from(minutes: Int) -> DurationOption {
        all.first { $0.minutes == minutes } ?? defaultOption
    }

    var isIndefinite: Bool { minutes == 0 }
    var seconds: TimeInterval { TimeInterval(minutes * 60) }

    var title: String {
        switch minutes {
        case 0: return "Indefinitely"
        case 1440: return "1 Day"
        case 60: return "1 Hour"
        default: return "\(minutes / 60) Hours"
        }
    }

    func endDate(from start: Date) -> Date? {
        isIndefinite ? nil : start.addingTimeInterval(seconds)
    }
}

enum TimeFormat {
    /// "45s", "12m", "2h", "1h 59m", "23h 59m". Minutes are rounded up so a fresh
    /// 2-hour timer reads "2h" rather than "1h 59m".
    static func remaining(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        if total < 60 { return "\(total)s" }
        let mins = (total + 59) / 60
        let h = mins / 60, m = mins % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

/// Everything BlackTea remembers between launches.
struct SavedState: Equatable {
    var durationMinutes: Int = DurationOption.defaultOption.minutes
    var active: Bool = false
    var endDate: Date? = nil          // nil while active = indefinitely
    var displayAwake: Bool = false
    var startAtLogin: Bool = true     // user preference; the system state lives in SMAppService
    var loginInitialized: Bool = false

    var duration: DurationOption { DurationOption.from(minutes: durationMinutes) }
}

final class SettingsStore {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private enum Key {
        static let duration = "durationMinutes"
        static let active = "active"
        static let endDate = "endDate"
        static let display = "keepDisplayAwake"
        static let login = "startAtLogin"
        static let loginInit = "loginInitialized"
    }

    func load() -> SavedState {
        var s = SavedState()
        if defaults.object(forKey: Key.duration) != nil {
            s.durationMinutes = DurationOption.from(minutes: defaults.integer(forKey: Key.duration)).minutes
        }
        s.active = defaults.bool(forKey: Key.active)
        s.endDate = defaults.object(forKey: Key.endDate) as? Date
        s.displayAwake = defaults.bool(forKey: Key.display)
        if defaults.object(forKey: Key.login) != nil { s.startAtLogin = defaults.bool(forKey: Key.login) }
        s.loginInitialized = defaults.bool(forKey: Key.loginInit)
        return s
    }

    func save(_ s: SavedState) {
        defaults.set(s.durationMinutes, forKey: Key.duration)
        defaults.set(s.active, forKey: Key.active)
        if let end = s.endDate { defaults.set(end, forKey: Key.endDate) } else { defaults.removeObject(forKey: Key.endDate) }
        defaults.set(s.displayAwake, forKey: Key.display)
        defaults.set(s.startAtLogin, forKey: Key.login)
        defaults.set(s.loginInitialized, forKey: Key.loginInit)
    }
}

/// What to do with a saved on/off state at launch.
/// - Off stays off.
/// - Indefinitely (no end date) comes back on.
/// - A timer resumes with its *remaining* time (the original end time is kept), so a
///   relaunch or reboot never extends it. If it ran out while BlackTea wasn't running, it stays off.
enum ResumePolicy {
    static func resume(_ s: SavedState, now: Date) -> (active: Bool, endDate: Date?) {
        guard s.active else { return (false, nil) }
        guard let end = s.endDate else { return (true, nil) }
        guard end.timeIntervalSince(now) >= 1 else { return (false, nil) }
        // Guard against clock changes: never resume longer than the longest option.
        let maxEnd = now.addingTimeInterval(DurationOption(minutes: 1440).seconds)
        return (true, min(end, maxEnd))
    }
}
