import Cocoa
import Combine
import SwiftUI

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsPopover: NSPopover?
    private var cancellables = Set<AnyCancellable>()

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupHotkey()

        BlurStateManager.shared.$currentState
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)

        BlurStateManager.shared.$isPaused
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)

        BlurStateManager.shared.$isEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "BlurGuard")
            button.action = #selector(togglePanel)
            button.target = self
        }
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let s = BlurStateManager.shared
        if s.isPaused {
            button.image = NSImage(systemSymbolName: "pause.circle.fill", accessibilityDescription: "BlurGuard")
            return
        }
        let name: String
        switch s.currentState {
        case .active:    name = s.isEnabled ? "lock.shield"      : "lock.slash"
        case .countdown: name = "lock.shield.fill"
        case .blurred:   name = "lock.shield.fill"
        case .unlocking: name = "lock.open"
        }
        button.image = NSImage(systemSymbolName: name, accessibilityDescription: "BlurGuard")
    }

    // MARK: - Panel

    @objc private func togglePanel() {
        if settingsPopover == nil {
            let vc = NSHostingController(rootView: SettingsView())
            vc.view.wantsLayer = true
            vc.view.layer?.backgroundColor = CGColor.clear
            let p = NSPopover()
            p.contentViewController = vc
            p.contentSize = NSSize(width: 300, height: 480)
            p.behavior = .transient
            p.animates = true
            settingsPopover = p
        }
        guard let button = statusItem.button else { return }
        if settingsPopover?.isShown == true {
            settingsPopover?.performClose(nil)
        } else {
            BlurStateManager.shared.rolloverPeekCountIfNeeded()
            settingsPopover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        HotkeyManager.shared.update()
        HotkeyManager.shared.onTrigger = { BlurStateManager.shared.triggerInstantBlur() }
    }
}
