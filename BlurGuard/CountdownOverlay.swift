import Cocoa

final class CountdownOverlay {
    private var window: NSWindow?
    private var countLabel: NSTextField?
    private var messageLabel: NSTextField?

    func show(count: Int) {
        guard let mainScreen = NSScreen.main else { return }

        let panelWidth: CGFloat = 300
        let panelHeight: CGFloat = 150
        let screenFrame = mainScreen.frame
        let origin = NSPoint(
            x: screenFrame.midX - panelWidth / 2,
            y: screenFrame.midY - panelHeight / 2
        )

        let win = NSWindow(
            contentRect: NSRect(origin: origin, size: NSSize(width: panelWidth, height: panelHeight)),
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: mainScreen
        )
        win.level = .screenSaver + 1
        win.isOpaque = false
        win.backgroundColor = .clear
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let visualEffect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 20
        visualEffect.layer?.masksToBounds = true
        win.contentView = visualEffect

        let countField = NSTextField(labelWithString: "\(count)")
        countField.font = NSFont.monospacedDigitSystemFont(ofSize: 48, weight: .bold)
        countField.textColor = .white
        countField.alignment = .center
        countField.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(countField)

        let msgField = NSTextField(labelWithString: "Screen locking in \(count)s")
        msgField.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        msgField.textColor = .secondaryLabelColor
        msgField.alignment = .center
        msgField.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(msgField)

        NSLayoutConstraint.activate([
            countField.centerXAnchor.constraint(equalTo: visualEffect.centerXAnchor),
            countField.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor, constant: -15),
            msgField.centerXAnchor.constraint(equalTo: visualEffect.centerXAnchor),
            msgField.topAnchor.constraint(equalTo: countField.bottomAnchor, constant: 8),
        ])

        win.makeKeyAndOrderFront(nil)
        self.window = win
        self.countLabel = countField
        self.messageLabel = msgField
    }

    func updateCount(_ count: Int) {
        countLabel?.stringValue = "\(count)"
        messageLabel?.stringValue = "Screen locking in \(count)s"
    }

    func dismiss() {
        window?.orderOut(nil)
        window = nil
        countLabel = nil
        messageLabel = nil
    }
}
