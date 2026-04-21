import Cocoa
import Combine
import SwiftUI

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var stateManager: BlurStateManager!
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        stateManager = BlurStateManager.shared

        setupMenuBar()
        setupHotkey()

        stateManager.$currentState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.updateMenuBarIcon() }
            .store(in: &cancellables)

        stateManager.$isEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                self?.statusItem.menu?.item(withTag: 1)?.state = enabled ? .on : .off
            }
            .store(in: &cancellables)

        stateManager.$isPaused
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateMenuBarIcon() }
            .store(in: &cancellables)
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        let s = SettingsManager.shared
        HotkeyManager.shared.update(
            keyCode: UInt32(s.hotkeyKeyCode),
            carbonModifiers: UInt32(s.hotkeyModifiers)
        )
        HotkeyManager.shared.onTrigger = { [weak self] in
            self?.stateManager.triggerInstantBlur()
        }
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "BlurGuard")
        }

        let menu = NSMenu()
        menu.delegate = self

        // Tag 1: Enabled toggle
        let toggleItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled(_:)), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.state = stateManager.isEnabled ? .on : .off
        toggleItem.tag = 1
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        // Tag 2: Instant Lock
        let lockItem = NSMenuItem(title: "Instant Lock  \(SettingsManager.shared.hotkeyDisplay)",
                                  action: #selector(instantLock), keyEquivalent: "")
        lockItem.target = self
        lockItem.tag = 2
        menu.addItem(lockItem)

        menu.addItem(.separator())

        // Tag 3: Pause submenu (hidden when paused)
        let pauseItem = NSMenuItem(title: "Pause Protection", action: nil, keyEquivalent: "")
        pauseItem.tag = 3
        let pauseMenu = NSMenu()
        let p1 = NSMenuItem(title: "For 1 Hour", action: #selector(pauseFor1Hour), keyEquivalent: "")
        p1.target = self
        let p2 = NSMenuItem(title: "For 2 Hours", action: #selector(pauseFor2Hours), keyEquivalent: "")
        p2.target = self
        let pIndef = NSMenuItem(title: "Until Manually Resumed", action: #selector(pauseIndefinitely), keyEquivalent: "")
        pIndef.target = self
        pauseMenu.addItem(p1)
        pauseMenu.addItem(p2)
        pauseMenu.addItem(pIndef)
        pauseItem.submenu = pauseMenu
        menu.addItem(pauseItem)

        // Tag 4: Paused status label (visible when paused, disabled)
        let pausedLabel = NSMenuItem(title: "Paused", action: nil, keyEquivalent: "")
        pausedLabel.tag = 4
        pausedLabel.isEnabled = false
        pausedLabel.isHidden = true
        menu.addItem(pausedLabel)

        // Tag 5: Resume (visible when paused)
        let resumeItem = NSMenuItem(title: "Resume Protection", action: #selector(resumeProtection), keyEquivalent: "")
        resumeItem.target = self
        resumeItem.tag = 5
        resumeItem.isHidden = true
        menu.addItem(resumeItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit BlurGuard", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func updateMenuBarIcon() {
        guard let button = statusItem.button else { return }
        if stateManager.isPaused {
            button.image = NSImage(systemSymbolName: "pause.circle.fill", accessibilityDescription: "BlurGuard Paused")
            return
        }
        let iconName: String
        switch stateManager.currentState {
        case .active:    iconName = "lock.shield"
        case .countdown: iconName = "lock.shield.fill"
        case .blurred:   iconName = "lock.shield.fill"
        case .unlocking: iconName = "lock.open"
        }
        button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "BlurGuard")
    }

    // MARK: - Actions

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        stateManager.isEnabled.toggle()
    }

    @objc private func instantLock() {
        stateManager.triggerInstantBlur()
    }

    @objc private func pauseFor1Hour()    { stateManager.pause(for: 3600) }
    @objc private func pauseFor2Hours()   { stateManager.pause(for: 7200) }
    @objc private func pauseIndefinitely() { stateManager.pause(for: nil) }
    @objc private func resumeProtection() { stateManager.resume() }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let hostingController = NSHostingController(rootView: SettingsView())
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 450, height: 460),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "BlurGuard Settings"
            window.contentViewController = hostingController
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            settingsWindow = window
        }
        // Defer to next run loop so the status-bar menu is fully closed first.
        // Activate before makeKeyAndOrderFront — required on macOS 14+ for accessory apps.
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.settingsWindow else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func quitApp() {
        stateManager.shutdown()
        NSApp.terminate(nil)
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusItem.menu else { return }
        let paused = stateManager.isPaused
        menu.item(withTag: 3)?.isHidden = paused
        menu.item(withTag: 4)?.isHidden = !paused
        menu.item(withTag: 5)?.isHidden = !paused

        // Update "Instant Lock" hotkey label if user changed it
        menu.item(withTag: 2)?.title = "Instant Lock  \(SettingsManager.shared.hotkeyDisplay)"

        if paused {
            var label = "Paused"
            if let end = stateManager.pauseEndDate, end.timeIntervalSinceNow > 0 {
                let mins = Int(ceil(end.timeIntervalSinceNow / 60))
                label = "Paused — \(mins)m remaining"
            }
            menu.item(withTag: 4)?.title = label
        }
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === settingsWindow {
            settingsWindow = nil
        }
    }
}
