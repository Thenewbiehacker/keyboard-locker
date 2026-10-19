import Foundation
import IOKit.pwr_mgt

/// Keeps the display awake while the keyboard is locked, so the overlay does not
/// vanish mid-clean and make the app look frozen.
enum PowerAssertion {

    private static var assertionID: IOPMAssertionID = 0
    private static var active = false

    static func begin() {
        guard !active else { return }
        var newID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            "PreventUserIdleDisplaySleep" as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Keyboard Locker is locking the keyboard" as CFString,
            &newID
        )
        if result == kIOReturnSuccess {
            assertionID = newID
            active = true
        }
    }

    static func end() {
        guard active else { return }
        IOPMAssertionRelease(assertionID)
        active = false
    }
}
