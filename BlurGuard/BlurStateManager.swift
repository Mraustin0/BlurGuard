import Cocoa
import Combine
import CoreGraphics

enum BlurState: String {
    case active
    case countdown
    case blurred
    case unlocking
}

// Weak global for CGEventTap C callback — avoids raw unmanaged pointer.
// Access only inside the callback; do NOT store strong ref from here.
private weak var sharedManagerRef: BlurStateManager?

final class BlurStateManager: ObservableObject {
    static let shared = BlurStateManager()

    // Serial queue — all state mutations run here.
    private let stateQueue = DispatchQueue(label: "com.blurguard.state", qos: .userInteractive)

    @Published private(set) var currentState: BlurState = .active
    @Published var isEnabled: Bool = true {
        didSet {
            stateQueue.async { [weak self] in
                guard let self else { return }
                if self.isEnabled {
                    self.startMonitoring()
                } else {
                    self.stopMonitoring()
                    // FIX: also stop fallback polling when disabled via menu
                    self._stopFallbackPollingOnMain()
                    DispatchQueue.main.async { self.removeAllOverlays() }
                    self.setState(.active)
                }
            }
        }
    }

    private let idleMonitor = IdleMonitor()
    private let settings = SettingsManager.shared
    private let unlockHandler = UnlockHandler()

    private var countdownSeconds: Int = 10
    private var countdownTimer: Timer?
    private var countdownOverlay: CountdownOverlay?
    private var blurWindows: [BlurOverlayWindow] = []
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var blurStartTime: Date = .distantPast
    private var fallbackTimer: Timer?
    private var isAuthenticating = false

    private init() {
        sharedManagerRef = self
        startMonitoring()
    }

    deinit {
        sharedManagerRef = nil
    }

    func shutdown() {
        // FIX: avoid deadlock — don't stateQueue.sync from main thread.
        // Instead run cleanup async and let the run loop drain naturally.
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.stopMonitoring()
            self.removeEventTap()
        }
        _stopFallbackPollingOnMain()
        DispatchQueue.main.async { self.removeAllOverlays() }
    }

    // MARK: - Thread-safe state setter

    private func setState(_ newState: BlurState) {
        guard currentState != newState else { return }
        DispatchQueue.main.async { self.currentState = newState }
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        idleMonitor.onIdleTimeUpdated = { [weak self] idleTime in
            self?.stateQueue.async { self?.handleIdleUpdate(idleTime) }
        }
        idleMonitor.start()
    }

    private func stopMonitoring() {
        idleMonitor.stop()
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    private func handleIdleUpdate(_ idleTime: TimeInterval) {
        guard isEnabled else { return }
        if currentState == .active, idleTime >= settings.idleTimeout {
            transitionTo(.countdown)
        }
    }

    private func transitionTo(_ newState: BlurState) {
        guard currentState != newState else { return }
        let oldState = currentState
        setState(newState)

        switch newState {
        case .active:
            startMonitoring()
        case .countdown:
            stopMonitoring()
            DispatchQueue.main.async { self.startCountdown() }
        case .blurred:
            if oldState == .countdown {
                DispatchQueue.main.async { self.dismissCountdownOverlay() }
            }
            blurStartTime = Date()
            DispatchQueue.main.async { self.showBlurOverlays() }
            installEventTap()
        case .unlocking:
            DispatchQueue.main.async { self.attemptUnlock() }
        }
    }

    // MARK: - Countdown (main thread)

    private func startCountdown() {
        countdownSeconds = 10
        showCountdownOverlay()

        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let idleTime = IdleMonitor.userIdleTime()
            if idleTime < 2.0 {
                self.cancelCountdown()
                return
            }
            self.countdownSeconds -= 1
            self.countdownOverlay?.updateCount(self.countdownSeconds)
            if self.countdownSeconds <= 0 {
                self.countdownTimer?.invalidate()
                self.countdownTimer = nil
                self.stateQueue.async { [weak self] in self?.transitionTo(.blurred) }
            }
        }
    }

    private func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        dismissCountdownOverlay()
        stateQueue.async { [weak self] in self?.transitionTo(.active) }
    }

    private func showCountdownOverlay() {
        let overlay = CountdownOverlay()
        overlay.show(count: countdownSeconds)
        countdownOverlay = overlay
    }

    private func dismissCountdownOverlay() {
        countdownOverlay?.dismiss()
        countdownOverlay = nil
    }

    // MARK: - Blur Overlays (main thread)

    private func showBlurOverlays() {
        removeAllOverlays()
        for screen in NSScreen.screens {
            let window = BlurOverlayWindow(screen: screen)
            window.show()
            blurWindows.append(window)
        }
    }

    private func removeAllOverlays() {
        for window in blurWindows { window.dismiss() }
        blurWindows.removeAll()
    }

    // MARK: - Event Tap

    private func installEventTap() {
        removeEventTap()

        guard AXIsProcessTrusted() else {
            notifyAccessibilityRequired()
            startFallbackPolling()
            return
        }

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        // FIX: break retain cycle — callback captures nothing strongly.
        // All access goes through sharedManagerRef (weak). The async block
        // captures manager with [weak manager] so it doesn't extend lifetime.
        let callback: CGEventTapCallBack = { _, type, event, _ in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = sharedManagerRef?.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passRetained(event)
            }

            // Snapshot weak ref once — safe for the duration of this C callback
            guard let manager = sharedManagerRef else {
                return Unmanaged.passRetained(event)
            }

            // FIX: move elapsed + state check onto stateQueue so blurStartTime
            // is always read on the same queue it is written on (no data race).
            manager.stateQueue.async { [weak manager] in
                guard let manager else { return }
                let elapsed = Date().timeIntervalSince(manager.blurStartTime)
                guard elapsed >= 1.0 else { return }
                if manager.currentState == .blurred {
                    manager.transitionTo(.unlocking)
                }
            }
            return nil
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: nil
        ) else {
            startFallbackPolling()
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        // FIX: stop fallback polling now that the event tap is installed.
        _stopFallbackPollingOnMain()
    }

    private func removeEventTap() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
    }

    private func notifyAccessibilityRequired() {
        DispatchQueue.main.async {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(opts as CFDictionary)
        }
    }

    // MARK: - Fallback Polling

    private func startFallbackPolling() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.fallbackTimer?.invalidate()
            self.fallbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.stateQueue.async { [weak self] in
                    guard let self, self.currentState == .blurred else { return }
                    let elapsed = Date().timeIntervalSince(self.blurStartTime)
                    guard elapsed > 1.0 else { return }
                    if IdleMonitor.userIdleTime() < 1.0 {
                        self._stopFallbackPollingOnMain()
                        self.transitionTo(.unlocking)
                    }
                }
            }
        }
    }

    /// Stop fallback timer on main thread without going through stateQueue
    /// (avoids deadlock when called from main or stateQueue).
    private func _stopFallbackPollingOnMain() {
        DispatchQueue.main.async { [weak self] in
            self?.fallbackTimer?.invalidate()
            self?.fallbackTimer = nil
        }
    }

    // MARK: - Unlock (main thread)

    private func attemptUnlock() {
        // FIX: guard against concurrent auth calls (e.g. event fires during failure recovery)
        guard !isAuthenticating else { return }
        isAuthenticating = true

        stateQueue.async { [weak self] in
            self?.removeEventTap()
        }
        _stopFallbackPollingOnMain()

        for window in blurWindows { window.passThrough(true) }

        unlockHandler.authenticate { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isAuthenticating = false
                switch result {
                case .success:
                    self.removeAllOverlays()
                    self.stateQueue.async { [weak self] in self?.transitionTo(.active) }
                case .failure(let reason):
                    for window in self.blurWindows {
                        window.passThrough(false)
                        window.showMessage(reason)
                    }
                    self.blurStartTime = Date()
                    self.installEventTap()
                    self.stateQueue.async { [weak self] in self?.transitionTo(.blurred) }
                }
            }
        }
    }
}
