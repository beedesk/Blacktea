import Foundation

/// The non-UI core: on/off, timer, persistence, assertions.
@MainActor
final class AwakeSession: NSObject {
    let store: SettingsStore
    let power: KeepAwake
    private(set) var state: SavedState
    var onChange: (() -> Void)?
    private var expiryTimer: Timer?

    init(store: SettingsStore, power: KeepAwake) {
        self.store = store
        self.power = power
        self.state = store.load()
        super.init()
    }

    var isActive: Bool { state.active }
    var duration: DurationOption { state.duration }
    var displayAwake: Bool { state.displayAwake }
    var endDate: Date? { state.active ? state.endDate : nil }

    func remaining(now: Date = Date()) -> TimeInterval? {
        endDate.map { max(0, $0.timeIntervalSince(now)) }
    }

    /// Applies the saved on/off state at launch (see `ResumePolicy`).
    func restore(now: Date = Date()) {
        let r = ResumePolicy.resume(state, now: now)
        state.active = r.active
        state.endDate = r.endDate
        commit()
    }

    /// Turns on for `option` (or the remembered duration), counting from `now`.
    /// `seconds` overrides the length (self-test only).
    func start(_ option: DurationOption? = nil, now: Date = Date(), seconds: TimeInterval? = nil) {
        if let option { state.durationMinutes = option.minutes }
        state.active = true
        if let seconds { state.endDate = now.addingTimeInterval(seconds) } else { state.endDate = state.duration.endDate(from: now) }
        commit()
    }

    func stop() {
        state.active = false
        state.endDate = nil
        commit()
    }

    func toggle() { state.active ? stop() : start() }

    func setDisplayAwake(_ on: Bool) {
        state.displayAwake = on
        commit()
    }

    func updatePrefs(_ change: (inout SavedState) -> Void) {
        change(&state)
        store.save(state)
    }

    /// Turns off if the timer has run out (also called after wake, since timers pause during sleep).
    func checkExpiry(now: Date = Date()) {
        guard state.active, let end = state.endDate else { return }
        if end <= now.addingTimeInterval(0.5) { stop() } else { scheduleExpiry() }
    }

    private func commit() {
        if !power.apply(active: state.active, display: state.displayAwake) && state.active {
            NSLog("BlackTea: could not create the power assertion")
            state.active = false
            state.endDate = nil
            power.apply(active: false, display: false)
        }
        store.save(state)
        scheduleExpiry()
        onChange?()
    }

    private func scheduleExpiry() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        guard state.active, let end = state.endDate else { return }
        let t = Timer(timeInterval: max(0.1, end.timeIntervalSinceNow), target: self,
                      selector: #selector(expiryFired), userInfo: nil, repeats: false)
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        expiryTimer = t
    }

    @objc private func expiryFired() { checkExpiry() }
}
