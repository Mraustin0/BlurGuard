import Cocoa
import Combine
import CoreGraphics

// MARK: - Types

enum BlurState {
    case active, countdown, blurred, unlocking
}

enum BlurReason {
    case idle, cameraAway, cameraPeek, manual
}

// MARK: - BlurStateManager

// CGEventTap callbacks are plain C functions and can't capture Swift objects.
// We route back into the manager through this weak global instead of an
// unsafe unmanaged pointer.
private weak var sharedManagerRef: BlurStateManager?

final class BlurStateManager: ObservableObject {

    static let shared = BlurStateManager()

    // MARK: - Published state (main thread)

    @Published private(set) var currentState: BlurState = .active
    @Published private(set) var isPaused:     Bool      = false
    @Published private(set) var pauseEndDate: Date?     = nil
    @Published private(set) var peekCount:    Int       = BlurStateManager.loadPeekCountForToday()

    // Persistence keys for the peek counter.
    private static let peekCountKey     = "peekCountToday"
    private static let peekCountDateKey = "peekCountDate"

    // Reads stored peek count only if it was last updated today; otherwise 0.
    private static func loadPeekCountForToday() -> Int {
        let defaults = UserDefaults.standard
        guard let date = defaults.object(forKey: peekCountDateKey) as? Date,
              Calendar.current.isDateInToday(date)
        else { return 0 }
        return defaults.integer(forKey: peekCountKey)
    }

    @Published var isEnabled: Bool = true {
        didSet { isEnabled ? enableProtection() : disableProtection() }
    }

    // MARK: - Private state

    // All BlurState mutations run on stateQueue to avoid data races.
    // @Published vars above are written via DispatchQueue.main.async.
    private let stateQueue = DispatchQueue(label: "com.blurguard.state", qos: .userInteractive)
    private var queueState:  BlurState = .active  // stateQueue only
    private var queuePaused: Bool      = false     // stateQueue only

    private var lastBlurReason: BlurReason = .idle

    private let idleMonitor    = IdleMonitor()
    private let cameraMonitor  = CameraPresenceMonitor()
    private let settings       = SettingsManager.shared
    private let unlockHandler  = UnlockHandler()

    private var pauseTimer:    Timer?
    private var countdownTimer: Timer?
    private var countdownOverlay: CountdownOverlay?
    private var countdownSeconds = 10

    private var blurWindows:   [BlurOverlayWindow] = []
    private var eventTap:      CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var blurStartTime: Date = .distantPast
    private var fallbackTimer: Timer?
    private var isAuthenticating = false

    private var settingsObserver: Any?

    // MARK: - Init / deinit

    private init() {
        sharedManagerRef = self
        setupCameraCallbacks()
        if settings.cameraEnabled { cameraMonitor.start() }
        startIdleMonitoring()
        observeSettingsChanges()
    }

    deinit {
        sharedManagerRef = nil
        if let obs = settingsObserver { NotificationCenter.default.removeObserver(obs) }
    }

    func shutdown() {
        cameraMonitor.stop()
        stateQueue.async { [weak self] in
            self?.stopIdleMonitoring()
            self?.removeEventTap()
        }
        stopFallbackTimerOnMain()
        DispatchQueue.main.async { self.removeAllOverlays() }
    }

    // MARK: - Public controls

    func triggerInstantBlur() {
        stateQueue.async { [weak self] in
            guard let self, self.isEnabled, !self.queuePaused else { return }
            guard self.queueState == .active || self.queueState == .countdown else { return }
            self.lastBlurReason = .manual
            self.stopIdleMonitoring()
            self.transition(to: .blurred)
        }
    }

    func pause(for duration: TimeInterval?) {
        cameraMonitor.stop()
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.queuePaused = true
            self.stopIdleMonitoring()
            self.stopFallbackTimerOnMain()
            DispatchQueue.main.async { self.removeAllOverlays() }
            self.setQueueState(.active)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isPaused = true
            self.pauseTimer?.invalidate()
            if let duration {
                self.pauseEndDate = Date().addingTimeInterval(duration)
                self.pauseTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                    self?.resume()
                }
            } else {
                self.pauseEndDate = nil
            }
        }
    }

    func resume() {
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.queuePaused = false
            if self.isEnabled { self.startIdleMonitoring() }
        }
        if settings.cameraEnabled && isEnabled { cameraMonitor.start() }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isPaused    = false
            self.pauseEndDate = nil
            self.pauseTimer?.invalidate()
            self.pauseTimer  = nil
        }
    }

    // MARK: - Enable / disable

    private func enableProtection() {
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.startIdleMonitoring()
            if self.settings.cameraEnabled { self.cameraMonitor.start() }
        }
    }

    private func disableProtection() {
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.stopIdleMonitoring()
            self.stopFallbackTimerOnMain()
            self.cameraMonitor.stop()
            DispatchQueue.main.async { self.removeAllOverlays() }
            self.setQueueState(.active)
        }
    }

    // MARK: - Camera callbacks

    private func setupCameraCallbacks() {
        cameraMonitor.onPeekDetected = { [weak self] in
            self?.stateQueue.async { self?.triggerFromCamera(reason: .cameraPeek) }
        }
        cameraMonitor.onUserAway = { [weak self] in
            self?.stateQueue.async { self?.triggerFromCamera(reason: .cameraAway) }
        }
        cameraMonitor.onPermissionDenied = { [weak self] in
            // Camera access was denied — flip the setting off so the toggle in
            // the panel reflects what's actually happening (or rather, isn't).
            self?.settings.cameraEnabled = false
        }
    }

    private func triggerFromCamera(reason: BlurReason) {
        guard isEnabled, !queuePaused else { return }
        guard queueState == .active || queueState == .countdown else { return }

        // Respect the auto-pause app list for camera triggers too.
        if isIgnoredAppRunning() { return }

        lastBlurReason = reason
        if reason == .cameraPeek { incrementPeekCount() }
        stopIdleMonitoring()
        transition(to: .blurred)
    }

    private func isIgnoredAppRunning() -> Bool {
        guard !settings.ignoredBundleIDs.isEmpty else { return false }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        return !settings.ignoredBundleIDs.isDisjoint(with: running)
    }

    private func incrementPeekCount() {
        DispatchQueue.main.async {
            self.rolloverPeekCountIfNeeded()
            self.peekCount += 1
            let defaults = UserDefaults.standard
            defaults.set(self.peekCount, forKey: Self.peekCountKey)
            defaults.set(Date(),         forKey: Self.peekCountDateKey)
        }
    }

    // Resets the in-memory peek counter to 0 if the stored date isn't today.
    // Called on increment and whenever the settings panel becomes visible so
    // a long-running app doesn't display yesterday's number.
    func rolloverPeekCountIfNeeded() {
        let defaults = UserDefaults.standard
        let date = defaults.object(forKey: Self.peekCountDateKey) as? Date
        if date == nil || !Calendar.current.isDateInToday(date!) {
            if peekCount != 0 { peekCount = 0 }
            defaults.set(0, forKey: Self.peekCountKey)
        }
    }

    private func observeSettingsChanges() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.syncCameraMonitor() }
    }

    private func syncCameraMonitor() {
        if settings.cameraEnabled && isEnabled && !isPaused {
            cameraMonitor.start()
        } else {
            cameraMonitor.stop()
        }
    }

    // MARK: - State machine

    private func setQueueState(_ newState: BlurState) {
        guard queueState != newState else { return }
        queueState = newState
        DispatchQueue.main.async { self.currentState = newState }
    }

    private func transition(to newState: BlurState) {
        guard queueState != newState else { return }
        let previous = queueState
        setQueueState(newState)

        switch newState {
        case .active:
            startIdleMonitoring()

        case .countdown:
            stopIdleMonitoring()
            DispatchQueue.main.async { self.beginCountdown() }

        case .blurred:
            if previous == .countdown {
                DispatchQueue.main.async { self.dismissCountdown() }
            }
            blurStartTime = Date()
            if previous != .unlocking {
                DispatchQueue.main.async { self.showBlurOverlays() }
            }
            installEventTap()

        case .unlocking:
            DispatchQueue.main.async { self.attemptUnlock() }
        }
    }

    // MARK: - Idle monitoring

    private func startIdleMonitoring() {
        idleMonitor.onIdleTimeUpdated = { [weak self] idleTime in
            self?.stateQueue.async { self?.handleIdleUpdate(idleTime) }
        }
        // Timer.scheduledTimer needs a running RunLoop, which only the main
        // thread reliably has — DispatchQueue threads don't.
        DispatchQueue.main.async { [weak self] in self?.idleMonitor.start() }
    }

    private func stopIdleMonitoring() {
        // Timer.invalidate() must run on the same runloop that scheduled it.
        DispatchQueue.main.async { [weak self] in
            self?.idleMonitor.stop()
            self?.countdownTimer?.invalidate()
            self?.countdownTimer = nil
        }
    }

    private func handleIdleUpdate(_ idleTime: TimeInterval) {
        guard isEnabled, !queuePaused else { return }
        guard queueState == .active else { return }
        if isIgnoredAppRunning() { return }
        if idleTime >= settings.idleTimeout {
            lastBlurReason = .idle
            transition(to: .countdown)
        }
    }

    // MARK: - Countdown (main thread)

    private func beginCountdown() {
        countdownSeconds = 10
        countdownOverlay = CountdownOverlay()
        countdownOverlay?.show(count: countdownSeconds)

        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }

            // Cancel if user moved — idle time resets when input is detected.
            if IdleMonitor.secondsSinceLastInput() < 2.0 {
                self.cancelCountdown()
                return
            }

            self.countdownSeconds -= 1
            self.countdownOverlay?.updateCount(self.countdownSeconds)

            if self.countdownSeconds <= 0 {
                self.countdownTimer?.invalidate()
                self.countdownTimer = nil
                self.stateQueue.async { self.transition(to: .blurred) }
            }
        }
    }

    private func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        dismissCountdown()
        stateQueue.async { self.transition(to: .active) }
    }

    private func dismissCountdown() {
        countdownOverlay?.dismiss()
        countdownOverlay = nil
    }

    // MARK: - Blur overlays (main thread)

    private func showBlurOverlays() {
        removeAllOverlays()
        let reason = lastBlurReason
        for screen in NSScreen.screens {
            let overlay = BlurOverlayWindow(screen: screen, reason: reason)
            overlay.show()
            blurWindows.append(overlay)
        }
    }

    private func removeAllOverlays() {
        blurWindows.forEach { $0.dismiss() }
        blurWindows.removeAll()
    }

    // MARK: - Event tap
    //
    // CGEventTap lets us detect any keypress/mouse-move while the screen is
    // blurred without relying on the app being frontmost.
    // We use .listenOnly so events are never suppressed — we only observe.

    private func installEventTap() {
        removeEventTap()

        guard AXIsProcessTrusted() else {
            promptAccessibilityPermission()
            startFallbackPolling()
            return
        }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)       |
            (1 << CGEventType.mouseMoved.rawValue)     |
            (1 << CGEventType.leftMouseDown.rawValue)  |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        // The callback is a plain C closure — it cannot capture self.
        // All access goes through sharedManagerRef (weak global at file scope).
        let callback: CGEventTapCallBack = { _, type, event, _ in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = sharedManagerRef?.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passRetained(event)
            }

            guard let manager = sharedManagerRef else { return Unmanaged.passRetained(event) }

            // Read blurStartTime on stateQueue to avoid a data race.
            manager.stateQueue.async { [weak manager] in
                guard let manager else { return }
                guard Date().timeIntervalSince(manager.blurStartTime) >= 1.0 else { return }
                if manager.queueState == .blurred { manager.transition(to: .unlocking) }
            }
            return Unmanaged.passRetained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: nil
        ) else {
            startFallbackPolling()
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        stopFallbackTimerOnMain()
    }

    private func removeEventTap() {
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
    }

    private func promptAccessibilityPermission() {
        DispatchQueue.main.async {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
    }

    // MARK: - Fallback polling (used when accessibility permission is not granted)

    private func startFallbackPolling() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.fallbackTimer?.invalidate()
            self.fallbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.stateQueue.async { [weak self] in
                    guard let self, self.queueState == .blurred else { return }
                    guard Date().timeIntervalSince(self.blurStartTime) > 1.0 else { return }
                    if IdleMonitor.secondsSinceLastInput() < 1.0 {
                        self.stopFallbackTimerOnMain()
                        self.transition(to: .unlocking)
                    }
                }
            }
        }
    }

    // Stopping the timer must happen on the main thread (where it was scheduled).
    // This helper is safe to call from either stateQueue or main.
    private func stopFallbackTimerOnMain() {
        DispatchQueue.main.async { [weak self] in
            self?.fallbackTimer?.invalidate()
            self?.fallbackTimer = nil
        }
    }

    // MARK: - Unlock (main thread)

    private func attemptUnlock() {
        guard !isAuthenticating else { return }
        isAuthenticating = true

        stateQueue.async { [weak self] in self?.removeEventTap() }
        stopFallbackTimerOnMain()
        blurWindows.forEach { $0.passThrough(true) }

        // Bring the app forward so the Touch ID / password dialog is visible.
        NSApp.activate(ignoringOtherApps: true)

        // Safety net: if LAContext never calls back (e.g. hardware failure),
        // reset after 30 s so the user isn't permanently locked out.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, self.isAuthenticating else { return }
            self.isAuthenticating = false
            self.blurWindows.forEach { $0.passThrough(false) }
            self.stateQueue.async { self.transition(to: .blurred) }
        }

        unlockHandler.authenticate(requireAuth: authRequired()) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isAuthenticating = false
                switch result {
                case .success:
                    self.removeAllOverlays()
                    self.stateQueue.async { self.transition(to: .active) }
                case .failure(let message):
                    self.blurWindows.forEach {
                        $0.passThrough(false)
                        $0.showMessage(message)
                    }
                    self.stateQueue.async { self.transition(to: .blurred) }
                }
            }
        }
    }

    private func authRequired() -> Bool {
        switch lastBlurReason {
        case .cameraPeek: return settings.peekResponse == "lock"
        case .cameraAway: return settings.awayResponse == "lock"
        case .idle, .manual: return settings.requireAuth
        }
    }
}
