import Cocoa

final class CountdownOverlay {
    private var window: NSWindow?
    private var countLabel: NSTextField?
    private var messageLabel: NSTextField?

    private let panelSize = NSSize(width: 300, height: 150)

    func show(count: Int) {
        // Fall back to any available screen if main display is disconnected.
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        let win = makeWindow(on: screen)
        let panel = makeGlassPanel(size: panelSize)
        win.contentView = panel

        let countField = makeLabel(text: "\(count)", font: .monospacedDigitSystemFont(ofSize: 48, weight: .bold))
        let msgField   = makeLabel(text: subtitle(for: count), font: .systemFont(ofSize: 16, weight: .medium))
        msgField.textColor = .secondaryLabelColor

        panel.addSubview(countField)
        panel.addSubview(msgField)

        NSLayoutConstraint.activate([
            countField.centerXAnchor.constraint(equalTo: panel.centerXAnchor),
            countField.centerYAnchor.constraint(equalTo: panel.centerYAnchor, constant: -15),
            msgField.centerXAnchor.constraint(equalTo: panel.centerXAnchor),
            msgField.topAnchor.constraint(equalTo: countField.bottomAnchor, constant: 8),
        ])

        win.makeKeyAndOrderFront(nil)
        window     = win
        countLabel = countField
        messageLabel = msgField
    }

    func updateCount(_ count: Int) {
        countLabel?.stringValue   = "\(count)"
        messageLabel?.stringValue = subtitle(for: count)
    }

    func dismiss() {
        window?.orderOut(nil)
        window?.close()
        window       = nil
        countLabel   = nil
        messageLabel = nil
    }

    // MARK: - Private helpers

    private func subtitle(for count: Int) -> String {
        "Screen locking in \(count)s"
    }

    private func makeWindow(on screen: NSScreen) -> NSWindow {
        let origin = NSPoint(
            x: screen.frame.midX - panelSize.width / 2,
            y: screen.frame.midY - panelSize.height / 2
        )
        let win = NSWindow(
            contentRect: NSRect(origin: origin, size: panelSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        // Level above screenSaver so it sits on top of the blur overlay.
        win.level = .screenSaver + 1
        win.isOpaque = false
        win.backgroundColor = .clear
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return win
    }

    private func makeGlassPanel(size: NSSize) -> NSVisualEffectView {
        let view = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        view.material     = .hudWindow
        view.blendingMode = .behindWindow
        view.state        = .active
        view.wantsLayer   = true
        view.layer?.cornerRadius  = 20
        view.layer?.masksToBounds = true
        return view
    }

    private func makeLabel(text: String, font: NSFont) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font      = font
        field.textColor = .white
        field.alignment = .center
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }
}
