import AppKit
import CoreGraphics

enum KeyboardLockError: LocalizedError {
    case tapCreationFailed

    var errorDescription: String? {
        switch self {
        case .tapCreationFailed:
            return "macOS refused to start the keyboard filter. Enable Accessibility and Input Monitoring for Keyboard Locker, then try again."
        }
    }
}

/// Installs a session-level CGEventTap that swallows every keyboard event,
/// plus an optional HID-level tap that swallows system-defined media events.
///
/// While the tap is active:
///   * keyDown / keyUp are swallowed
///   * flagsChanged (Shift, Cmd, Ctrl, Opt, Caps Lock, Fn/Globe) is swallowed
///   * NX_SYSDEFINED (media / brightness keys) is swallowed when possible
///
/// Mouse events are untouched, so the pointer keeps working.
///
/// Holding Space for `holdSeconds` unlocks. The keyboard is also released when
/// the auto-unlock deadline passes, so a session can never trap the user.
///
/// Everything here runs on the main thread: the tap sources are added to the
/// main run loop, so callbacks are delivered on the main thread and no locking
/// is needed.
final class KeyboardLock {

    private static let spaceKeyCode: Int64 = 49
    /// NX_SYSDEFINED, used by media, brightness and volume keys.
    private static let systemDefinedType = CGEventType(rawValue: 14)!

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var mediaTap: CFMachPort?
    private var mediaRunLoopSource: CFRunLoopSource?
    private(set) var isLocked = false

    private var holdSeconds: TimeInterval = 5
    private var spaceDownAt: TimeInterval?
    private var progressTimer: Timer?

    private var autoUnlockDeadline: TimeInterval = 0
    private var autoUnlockTimer: Timer?

    private var lastTapDisable: TimeInterval = 0
    private var tapDisableCount = 0

    /// Called on the main thread with 0...1 while Space is held.
    var onProgress: ((Double) -> Void)?
    /// Called on the main thread with the seconds left before the automatic unlock.
    var onAutoUnlockTick: ((TimeInterval) -> Void)?
    /// Called on the main thread once the hold completes, on auto-unlock, or when we must fail open.
    var onUnlock: (() -> Void)?

    // MARK: - Lifecycle

    func lock(
        holdSeconds: TimeInterval,
        autoUnlockAfter: TimeInterval,
        blockFnKey: Bool,
        blockMediaKeys: Bool
    ) throws {
        guard !isLocked else { return }
        self.holdSeconds = max(1, holdSeconds)

        var mask: CGEventMask = 0
        mask |= CGEventMask(1) << CGEventType.keyDown.rawValue
        mask |= CGEventMask(1) << CGEventType.keyUp.rawValue
        if blockFnKey {
            mask |= CGEventMask(1) << CGEventType.flagsChanged.rawValue
        }
        if blockMediaKeys {
            mask |= CGEventMask(1) << Self.systemDefinedType.rawValue
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: keyboardTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw KeyboardLockError.tapCreationFailed
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            throw KeyboardLockError.tapCreationFailed
        }

        self.tap = tap
        runLoopSource = source
        lastTapDisable = 0
        tapDisableCount = 0
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        if blockMediaKeys {
            installMediaTap()
        }

        isLocked = true
        startAutoUnlockTimer(after: max(5, autoUnlockAfter))
    }

    /// Extra tap at the HID layer, scoped to NX_SYSDEFINED only.
    ///
    /// Some media/brightness keys are consumed below the session tap. When macOS
    /// lets us, a HID tap catches them. Creation can legitimately fail, and that
    /// is fine: the session tap still blocks every real key.
    private func installMediaTap() {
        let mask = CGEventMask(1) << Self.systemDefinedType.rawValue
        guard let mediaTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: mediaTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("Keyboard Locker: HID media tap unavailable, using session tap only.")
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, mediaTap, 0) else {
            CFMachPortInvalidate(mediaTap)
            return
        }

        self.mediaTap = mediaTap
        mediaRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: mediaTap, enable: true)
    }

    func unlock() {
        guard isLocked else { return }
        isLocked = false
        cancelHold()

        autoUnlockTimer?.invalidate()
        autoUnlockTimer = nil
        autoUnlockDeadline = 0

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        tap = nil

        if let source = mediaRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        mediaRunLoopSource = nil
        if let mediaTap = mediaTap {
            CGEvent.tapEnable(tap: mediaTap, enable: false)
            CFMachPortInvalidate(mediaTap)
        }
        mediaTap = nil

        releaseStuckModifiers()
    }

    // MARK: - Space hold

    private func startHold() {
        guard spaceDownAt == nil else { return }
        spaceDownAt = ProcessInfo.processInfo.systemUptime
        progressTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
        onProgress?(0)
    }

    private func cancelHold() {
        spaceDownAt = nil
        progressTimer?.invalidate()
        progressTimer = nil
        onProgress?(0)
    }

    private func tick() {
        guard let start = spaceDownAt else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let progress = min(1, elapsed / holdSeconds)
        onProgress?(progress)
        if progress >= 1 {
            cancelHold()
            onUnlock?()
        }
    }

    // MARK: - Auto unlock

    private func startAutoUnlockTimer(after seconds: TimeInterval) {
        autoUnlockDeadline = ProcessInfo.processInfo.systemUptime + seconds
        onAutoUnlockTick?(seconds)

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.autoUnlockTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        autoUnlockTimer = timer
    }

    private func autoUnlockTick() {
        let remaining = autoUnlockDeadline - ProcessInfo.processInfo.systemUptime
        if remaining <= 0 {
            autoUnlockTimer?.invalidate()
            autoUnlockTimer = nil
            onAutoUnlockTick?(0)
            onUnlock?()
            return
        }
        onAutoUnlockTick?(remaining)
    }

    // MARK: - Event handling (main thread only)

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {

        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // The window server killed our tap. Turn it back on immediately.
            // If it keeps happening, fail open rather than leaving the user
            // with a dead keyboard.
            guard let tap = tap else { return nil }
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastTapDisable > 3 {
                tapDisableCount = 0
            }
            lastTapDisable = now
            tapDisableCount += 1

            if tapDisableCount > 8 {
                CGEvent.tapEnable(tap: tap, enable: false)
                DispatchQueue.main.async { [weak self] in self?.onUnlock?() }
            } else {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return nil

        case .keyDown:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if code == Self.spaceKeyCode && !isRepeat {
                startHold()
            }
            return nil

        case .keyUp:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            if code == Self.spaceKeyCode {
                cancelHold()
            }
            return nil

        case .flagsChanged:
            return nil

        default:
            // NX_SYSDEFINED and anything else we asked for.
            return nil
        }
    }

    /// Media tap: only NX_SYSDEFINED arrives here. Re-enable this tap if the
    /// system disables it, and keep swallowing the events.
    fileprivate func handleMedia(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let mediaTap = mediaTap {
                CGEvent.tapEnable(tap: mediaTap, enable: true)
            }
            return nil
        default:
            return nil
        }
    }

    /// Clears modifier state that was physically held when the tap went in,
    /// so nothing comes back stuck after unlocking.
    private func releaseStuckModifiers() {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let modifiers: [(CGEventFlags, CGKeyCode)] = [
            (.maskShift, 56), (.maskShift, 60),
            (.maskControl, 59), (.maskControl, 62),
            (.maskAlternate, 58), (.maskAlternate, 61),
            (.maskCommand, 55), (.maskCommand, 54),
            (.maskSecondaryFn, 63)
        ]
        for (flag, keyCode) in modifiers where flags.contains(flag) {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else { continue }
            event.flags = []
            event.post(tap: .cghidEventTap)
        }
    }
}

private func keyboardTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
    let lock = Unmanaged<KeyboardLock>.fromOpaque(userInfo).takeUnretainedValue()
    return lock.handle(type: type, event: event)
}

private func mediaTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
    let lock = Unmanaged<KeyboardLock>.fromOpaque(userInfo).takeUnretainedValue()
    return lock.handleMedia(type: type, event: event)
}
