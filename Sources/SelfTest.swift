import Foundation

/// `BlackTea --self-test`: timer math, persistence/resume, and real power assertions
/// checked against `pmset -g assertions`. Uses a throwaway defaults suite and never
/// touches the login item or the real settings.
@MainActor
enum SelfTest {
    private static var failures = 0
    private static var passes = 0

    private static func check(_ cond: Bool, _ what: String) {
        if cond { passes += 1; print("  ok    \(what)") } else { failures += 1; print("  FAIL  \(what)") }
    }

    static func run() -> Int32 {
        print("BlackTea \(BuildInfo.version) self-test (pid \(getpid()))")
        timerMath()
        persistence()
        assertions()
        expiry()
        print(failures == 0 ? "PASS: \(passes) checks" : "FAILED: \(failures) of \(passes + failures) checks")
        return failures == 0 ? 0 : 1
    }

    // MARK: Timer math

    static func timerMath() {
        print("Timer math")
        check(DurationOption.all.map(\.minutes) == [60, 120, 180, 300, 480, 780, 1440, 0], "options are 1,2,3,5,8,13 h, 1 day, indefinitely")
        check(DurationOption.all.map(\.title) == ["1 Hour", "2 Hours", "3 Hours", "5 Hours", "8 Hours", "13 Hours", "1 Day", "Indefinitely"], "option titles")
        check(DurationOption(minutes: 780).seconds == 46_800, "13 hours = 46800 s")
        check(DurationOption(minutes: 1440).seconds == 86_400, "1 day = 86400 s")
        let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
        check(DurationOption(minutes: 120).endDate(from: t0) == t0.addingTimeInterval(7200), "2 h end date")
        check(DurationOption.indefinitely.endDate(from: t0) == nil, "indefinitely has no end date")
        check(DurationOption.from(minutes: 42) == .defaultOption, "unknown stored duration falls back to default")
        check(DurationOption.from(minutes: 300).minutes == 300, "known stored duration kept")
        let fmt: [(TimeInterval, String)] = [(0, "0s"), (45, "45s"), (59.2, "1m"), (60, "1m"), (61, "2m"), (3599, "1h"),
                                             (3600, "1h"), (7200, "2h"), (7140, "1h 59m"), (46_800, "13h"), (86_399, "24h"), (86_340, "23h 59m")]
        for (secs, want) in fmt {
            let got = TimeFormat.remaining(secs)
            check(got == want, "format \(secs)s -> \"\(want)\"" + (got == want ? "" : " (got \"\(got)\")"))
        }
    }

    // MARK: Persistence

    static func persistence() {
        print("Persistence")
        let suite = "com.beedesk.blacktea.selftest"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        guard let d1 = UserDefaults(suiteName: suite) else { check(false, "open defaults suite"); return }

        let fresh = SettingsStore(defaults: d1).load()
        check(fresh == SavedState(), "first launch defaults (Indefinitely, off, display off, start at login on)")

        let end = Date(timeIntervalSinceNow: 5000).addingTimeInterval(0)
        var s = SavedState(durationMinutes: 480, active: true, endDate: end, displayAwake: true, startAtLogin: false, loginInitialized: true)
        SettingsStore(defaults: d1).save(s)
        d1.synchronize()
        let loaded = SettingsStore(defaults: UserDefaults(suiteName: suite)!).load()
        check(loaded.durationMinutes == 480 && loaded.active && loaded.displayAwake && !loaded.startAtLogin && loaded.loginInitialized,
              "settings round-trip through UserDefaults")
        check(abs((loaded.endDate ?? .distantPast).timeIntervalSince(end)) < 0.001, "end date round-trip")
        s.active = false; s.endDate = nil
        SettingsStore(defaults: d1).save(s)
        check(SettingsStore(defaults: d1).load().endDate == nil, "end date cleared when off")

        print("Resume after relaunch")
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var r = ResumePolicy.resume(SavedState(active: false), now: now)
        check(!r.active, "off stays off")
        r = ResumePolicy.resume(SavedState(durationMinutes: 0, active: true, endDate: nil), now: now)
        check(r.active && r.endDate == nil, "indefinitely comes back on")
        let later = now.addingTimeInterval(3000)
        r = ResumePolicy.resume(SavedState(durationMinutes: 120, active: true, endDate: later), now: now)
        check(r.active && r.endDate == later, "running timer resumes with its remaining time (same end)")
        r = ResumePolicy.resume(SavedState(durationMinutes: 120, active: true, endDate: now.addingTimeInterval(-10)), now: now)
        check(!r.active, "timer that ran out while quit stays off")
        r = ResumePolicy.resume(SavedState(durationMinutes: 120, active: true, endDate: now.addingTimeInterval(10 * 86_400)), now: now)
        check(r.active && r.endDate == now.addingTimeInterval(86_400), "far-future end (clock change) clamped to 1 day")

        // Session-level: start, "relaunch" with a new session on the same store.
        let store = SettingsStore(defaults: d1)
        let a = AwakeSession(store: store, power: KeepAwake(name: "BlackTea self-test persistence"))
        a.start(DurationOption(minutes: 180))
        let savedEnd = a.endDate
        a.power.apply(active: false, display: false)   // simulate quit (assertions die with the process)
        let b = AwakeSession(store: store, power: KeepAwake(name: "BlackTea self-test persistence"))
        b.restore()
        check(b.isActive && b.duration.minutes == 180 && b.endDate == savedEnd && b.power.isHolding,
              "relaunch resumes 3 h timer with the remaining time and re-holds the assertion")
        b.stop()
        let c = AwakeSession(store: store, power: KeepAwake(name: "BlackTea self-test persistence"))
        c.restore()
        check(!c.isActive && !c.power.isHolding && c.duration.minutes == 180, "after Off, relaunch stays off and keeps the 3 h choice")
    }

    // MARK: Power assertions

    static func pmsetLines() -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["-g", "assertions"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
    }

    /// Our own lines in `pmset -g assertions` of the given type.
    static func pmsetHas(_ type: String, name: String) -> Bool {
        let pid = "pid \(getpid())("
        return pmsetLines().contains { $0.contains(pid) && $0.contains(type) && $0.contains(name) }
    }

    static func assertions() {
        print("Power assertions (pmset -g assertions)")
        let name = "BlackTea self-test \(UUID().uuidString.prefix(8))"
        let power = KeepAwake(name: name)
        check(!pmsetHas(KeepAwake.systemType, name: name), "nothing held before start")

        check(power.apply(active: true, display: false), "create PreventUserIdleSystemSleep")
        check(power.isHolding && !power.isHoldingDisplay, "holding system assertion only")
        check(pmsetHas(KeepAwake.systemType, name: name), "pmset lists PreventUserIdleSystemSleep for this pid")
        check(!pmsetHas(KeepAwake.displayType, name: name), "pmset: no display assertion while option is off")

        check(power.apply(active: true, display: true), "turn on Keep Display Awake")
        check(pmsetHas(KeepAwake.displayType, name: name), "pmset lists PreventUserIdleDisplaySleep")
        check(pmsetHas(KeepAwake.systemType, name: name), "system assertion still held")

        power.apply(active: true, display: false)
        check(!pmsetHas(KeepAwake.displayType, name: name) && pmsetHas(KeepAwake.systemType, name: name),
              "turning display option off releases only the display assertion")

        power.apply(active: false, display: true)
        check(!power.isHolding && !power.isHoldingDisplay, "released on Off")
        check(!pmsetHas(KeepAwake.systemType, name: name) && !pmsetHas(KeepAwake.displayType, name: name),
              "pmset no longer lists our assertions")
    }

    // MARK: Timer expiry (real run loop)

    static func expiry() {
        print("Timer expiry")
        let suite = "com.beedesk.blacktea.selftest"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: UserDefaults(suiteName: suite)!)
        let name = "BlackTea self-test expiry \(UUID().uuidString.prefix(8))"
        let session = AwakeSession(store: store, power: KeepAwake(name: name))
        session.setDisplayAwake(true)
        session.start(DurationOption(minutes: 60), seconds: 2)
        check(session.isActive && pmsetHas(KeepAwake.systemType, name: name) && pmsetHas(KeepAwake.displayType, name: name),
              "2 s test timer started, both assertions held")
        if let r = session.remaining() { check(r > 1 && r <= 2, "remaining time counts down (\(String(format: "%.2f", r)) s)") }
        RunLoop.main.run(until: Date().addingTimeInterval(3.5))
        check(!session.isActive && !session.power.isHolding, "timer ended: session off")
        check(!pmsetHas(KeepAwake.systemType, name: name) && !pmsetHas(KeepAwake.displayType, name: name),
              "timer ended: pmset shows assertions released")
        let saved = store.load()
        check(!saved.active && saved.endDate == nil && saved.durationMinutes == 60 && saved.displayAwake,
              "expired state persisted (off, duration and display option kept)")
    }
}
