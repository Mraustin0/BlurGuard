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

        stateManager.$currentState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.updateMenuBarIcon(for: state)
            }
            .store(in: &cancellables)
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "BlurGuard")
        }

        let menu = NSMenu()

        let toggleItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled(_:)), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.state = stateManager.isEnabled ? .on : .off
        toggleItem.tag = 1
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit BlurGuard", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func updateMenuBarIcon(for state: BlurState) {
        guard let button = statusItem.button else { return }
        let iconName: String
        switch state {
        case .active:
            iconName = "lock.shield"
        case .countdown:
            iconName = "lock.shield.fill"
        case .blurred:
            iconName = "lock.shield.fill"
        case .unlocking:
            iconName = "lock.open"
        }
        button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "BlurGuard")
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        stateManager.isEnabled.toggle()
        sender.state = stateManager.isEnabled ? .on : .off
    }

    @objc private func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "BlurGuard Settings"
        window.contentViewController = hostingController
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        settingsWindow = window
    }

    @objc private func quitApp() {
        stateManager.shutdown()
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === settingsWindow {
            settingsWindow = nil
        }
    }
}
