import Cocoa

final class BlurOverlayWindow {
    private let window: NSWindow
    private let blurView: NSVisualEffectView
    private var messageLabel: NSTextField?

    init(screen: NSScreen) {
        blurView = NSVisualEffectView(frame: NSRect(origin: .zero, size: screen.frame.size))
        blurView.material = .hudWindow
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.autoresizingMask = [.width, .height]

        window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = blurView
        window.setFrame(screen.frame, display: true)

        // Lock icon in center
        let lockIcon = NSImageView()
        lockIcon.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Locked")
        lockIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 64, weight: .light)
        lockIcon.contentTintColor = .white
        lockIcon.translatesAutoresizingMaskIntoConstraints = false
        blurView.addSubview(lockIcon)

        let label = NSTextField(labelWithString: "BlurGuard Active")
        label.font = NSFont.systemFont(ofSize: 20, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        blurView.addSubview(label)

        NSLayoutConstraint.activate([
            lockIcon.centerXAnchor.constraint(equalTo: blurView.centerXAnchor),
            lockIcon.centerYAnchor.constraint(equalTo: blurView.centerYAnchor, constant: -30),
            label.centerXAnchor.constraint(equalTo: blurView.centerXAnchor),
            label.topAnchor.constraint(equalTo: lockIcon.bottomAnchor, constant: 16),
        ])
    }

    func show() {
        window.level = .screenSaver
        window.ignoresMouseEvents = false
        window.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        window.orderOut(nil)
        window.close()
    }

    /// Keep blur visible but let clicks pass through to the system auth dialog.
    /// passThrough(true)  → clicks pass through (auth dialog usable)
    /// passThrough(false) → clicks blocked (screen is locked)
    func passThrough(_ enabled: Bool) {
        window.ignoresMouseEvents = enabled  // true = ignore = pass through
    }

    private var messageDismissWorkItem: DispatchWorkItem?

    func showMessage(_ text: String) {
        // Cancel any pending dismiss from a previous message
        messageDismissWorkItem?.cancel()
        messageDismissWorkItem = nil
        messageLabel?.removeFromSuperview()

        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        label.textColor = .systemRed
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        blurView.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: blurView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: blurView.centerYAnchor, constant: 60),
        ])
        messageLabel = label

        let workItem = DispatchWorkItem { [weak self] in
            self?.messageLabel?.removeFromSuperview()
            self?.messageLabel = nil
        }
        messageDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
    }
}
