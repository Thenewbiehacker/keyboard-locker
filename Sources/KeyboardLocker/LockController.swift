import AppKit
import Combine
import SwiftUI

final class LockController: NSObject, ObservableObject {

    enum Phase: Equatable {
        case idle
        case countdown(Int)
        case locked
    }

    // MARK: - User settings

    @Published var holdSeconds: Double = 5
    @Published var autoUnlockSeconds: Int = 60
    @Published var blockFnKey = true
    @Published var blockMediaKeys = true

    // MARK: - State

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var inputMonitoringGranted = false
    @Published private(set) var message: String?

    var permissionsGranted: Bool {
        accessibilityGranted && inputMonitoringGranted
    }

    let overlay = OverlayModel()

    private let locker = KeyboardLock()
    private var mainWindow: NSWindow?
    private var overlayWindows: [NSWindow] = []
    private var countdownTimer: Timer?
    private var permissionTimer: Timer?
    private var escMonitor: Any?
    private var statusItem: NSStatusItem?
    private var started = false

    // MARK: - Startup

    func start() {
        guard !started else { return }
        started = true

        overlay.holdSeconds = holdSeconds
        buildMainMenu()
        buildStatusItem()
        refreshPermissions()
        showMainWindow()

        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshPermissions()
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer

        locker.onProgress = { [weak self] progress in
            guard let self = self else { return }
            self.overlay.progress = progress
        }
        locker.onAutoUnlockTick = { [weak self] remaining in
            self?.overlay.autoUnlockRemaining = remaining
        }
        locker.onUnlock = { [weak self] in
            self?.finishUnlock()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func shutdown() {
        countdownTimer?.invalidate()
        permissionTimer?.invalidate()
        removeEscMonitor()
        locker.unlock()
        PowerAssertion.end()
    }

    func refreshPermissions() {
        let ax = Permissions.accessibility
        let im = Permissions.inputMonitoring
        if ax != accessibilityGranted { accessibilityGranted = ax }
        if im != inputMonitoringGranted { inputMonitoringGranted = im }
    }

    // MARK: - Main window

    func showMainWindow() {
        if mainWindow == nil {
            let hosting = NSHostingView(rootView: MainView(controller: self))
            let size = NSSize(width: 520, height: 600)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Keyboard Locker"
            window.contentView = hosting
            window.setContentSize(size)
            window.isReleasedWhenClosed = false
            window.center()
            mainWindow = window
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Locking

    func requestLock() {
        guard phase == .idle else { return }
        message = nil
        refreshPermissions()

        guard accessibilityGranted else {
            message = "Accessibility access is missing. Enable Keyboard Locker in System Settings › Privacy & Security › Accessibility."
            Permissions.requestAll()
            Permissions.openAccessibilitySettings()
            return
        }

        guard inputMonitoringGranted else {
            message = "Input Monitoring access is missing. Enable Keyboard Locker in System Settings › Privacy & Security › Input Monitoring."
            Permissions.requestAll()
            Permissions.openInputMonitoringSettings()
            return
        }

        overlay.holdSeconds = holdSeconds
        overlay.progress = 0
        overlay.countdown = 3
        overlay.mode = .countdown

        phase = .countdown(3)
        mainWindow?.orderOut(nil)
        presentOverlays()
        installEscMonitor()
        startCountdown()
    }

    private func startCountdown() {
        countdownTimer?.invalidate()
        var remaining = 3

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            remaining -= 1
            if remaining > 0 {
                self.overlay.countdown = remaining
                self.phase = .countdown(remaining)
            } else {
                timer.invalidate()
                self.countdownTimer = nil
                self.removeEscMonitor()
                self.engageLock()
            }
        }
        countdownTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func engageLock() {
        do {
            try locker.lock(
                holdSeconds: holdSeconds,
                autoUnlockAfter: TimeInterval(autoUnlockSeconds),
                blockFnKey: blockFnKey,
                blockMediaKeys: blockMediaKeys
            )
        } catch {
            dismissOverlays()
            phase = .idle
            message = error.localizedDescription
            showMainWindow()
            return
        }

        PowerAssertion.begin()
        overlay.progress = 0
        overlay.mode = .locked
        phase = .locked
        NSApp.activate(ignoringOtherApps: true)
        overlayWindows.first?.makeKeyAndOrderFront(nil)
    }

    func cancelCountdown() {
        guard case .countdown = phase else { return }
        countdownTimer?.invalidate()
        countdownTimer = nil
        removeEscMonitor()
        dismissOverlays()
        overlay.progress = 0
        phase = .idle
        showMainWindow()
    }

    private func finishUnlock() {
        guard phase == .locked else { return }
        locker.unlock()
        PowerAssertion.end()
        overlay.progress = 0
        overlay.mode = .unlocked
        phase = .idle

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            self.dismissOverlays()
            NSApp.terminate(nil)
        }
    }

    // MARK: - Overlay windows

    private func presentOverlays() {
        dismissOverlays()
        for screen in NSScreen.screens {
            let window = OverlayWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isMovable = false
            window.isMovableByWindowBackground = false
            window.ignoresMouseEvents = false
            window.animationBehavior = .none
            window.contentView = NSHostingView(
                rootView: LockOverlayView(model: overlay) { [weak self] in
                    self?.finishUnlock()
                }
            )
            window.setFrame(screen.frame, display: true)
            window.makeKeyAndOrderFront(nil)
            overlayWindows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func dismissOverlays() {
        for window in overlayWindows {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        overlayWindows.removeAll()
    }

    @objc private func screensChanged() {
        guard !overlayWindows.isEmpty else { return }
        let wasLocked = phase == .locked
        presentOverlays()
        if wasLocked {
            overlayWindows.first?.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Esc to cancel the countdown

    private func installEscMonitor() {
        removeEscMonitor()
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.cancelCountdown()
                return nil
            }
            return event
        }
    }

    private func removeEscMonitor() {
        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor)
            escMonitor = nil
        }
    }

    // MARK: - Menu bar

    private func buildMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)

        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "About Keyboard Locker",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit Keyboard Locker",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Keyboard Locker")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Keyboard Locker"
        }

        let menu = NSMenu()
        addItem(to: menu, title: "Open Keyboard Locker…", action: #selector(menuOpen))
        addItem(to: menu, title: "Lock Keyboard Now", action: #selector(menuLock))
        menu.addItem(.separator())
        addItem(to: menu, title: "Quit Keyboard Locker", action: #selector(menuQuit), key: "q")
        item.menu = menu
        statusItem = item
    }

    private func addItem(to menu: NSMenu, title: String, action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    @objc private func menuOpen() {
        showMainWindow()
    }

    @objc private func menuLock() {
        showMainWindow()
        requestLock()
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }
}

/// Borderless full-screen window that is allowed to become key, so it can be the
/// frontmost surface while the keyboard is locked.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
