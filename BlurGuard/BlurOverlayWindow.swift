import Cocoa

final class BlurOverlayWindow {
    private let window: NSWindow
    private let contentView: NSView
    private var messageLabel: NSTextField?
    private var messageDismissWorkItem: DispatchWorkItem?

    init(screen: NSScreen, reason: BlurReason) {
        contentView = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
        contentView.autoresizingMask = [.width, .height]

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
        window.contentView = contentView
        window.setFrame(screen.frame, display: true)

        setupContent(for: reason)
    }

    private func setupContent(for reason: BlurReason) {
        let (iconName, title, subtitle): (String, String, String)
        switch reason {
        case .cameraAway:
            iconName  = "figure.walk"
            title     = "You Walked Away"
            subtitle  = "Screen protected until you return"
        case .cameraPeek:
            iconName  = "eye.slash.fill"
            title     = "Someone's Watching"
            subtitle  = "Screen protected"
        case .idle:
            iconName  = "lock.fill"
            title     = "Screen Locked"
            subtitle  = "Press any key to unlock"
        case .manual:
            iconName  = "lock.fill"
            title     = "Screen Locked"
            subtitle  = "Press any key to unlock"
        }

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 72, weight: .light)
        icon.contentTintColor = .white
        icon.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 24, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = NSFont.systemFont(ofSize: 15, weight: .regular)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        subtitleLabel.alignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -44),
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 20),
            subtitleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
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

    func passThrough(_ enabled: Bool) {
        window.ignoresMouseEvents = enabled
    }

    func showMessage(_ text: String) {
        messageDismissWorkItem?.cancel()
        messageDismissWorkItem = nil
        messageLabel?.removeFromSuperview()

        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        label.textColor = .systemRed
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: 80),
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
