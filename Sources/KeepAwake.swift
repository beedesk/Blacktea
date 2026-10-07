import Foundation
import IOKit.pwr_mgt

/// Owns the IOKit power assertions. Process exit (even a crash) releases them too.
final class KeepAwake {
    static let systemType = "PreventUserIdleSystemSleep"
    static let displayType = "PreventUserIdleDisplaySleep"

    let name: String
    private(set) var systemID = IOPMAssertionID(0)
    private(set) var displayID = IOPMAssertionID(0)

    init(name: String = "BlackTea keeping the Mac awake") { self.name = name }
    deinit { _ = apply(active: false, display: false) }

    var isHolding: Bool { systemID != 0 }
    var isHoldingDisplay: Bool { displayID != 0 }

    /// Creates/releases assertions to match the wanted state. Returns false if a create failed.
    @discardableResult
    func apply(active: Bool, display: Bool) -> Bool {
        var ok = true
        if active { if systemID == 0 { ok = create(Self.systemType, &systemID) && ok } } else { release(&systemID) }
        if active && display { if displayID == 0 { ok = create(Self.displayType, &displayID) && ok } } else { release(&displayID) }
        return ok
    }

    private func create(_ type: String, _ id: inout IOPMAssertionID) -> Bool {
        var newID = IOPMAssertionID(0)
        let r = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), name as CFString, &newID)
        guard r == kIOReturnSuccess else { return false }
        id = newID
        return true
    }

    private func release(_ id: inout IOPMAssertionID) {
        guard id != 0 else { return }
        IOPMAssertionRelease(id)
        id = 0
    }
}
