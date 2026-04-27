import Cocoa

final class BlurOverlayWindow {
    private let window: NSWindow
    private let contentView: NSView
    private var messageLabel: NSTextField?
    private var messageDismissWorkItem: DispatchWorkItem?

    init(screen: NSScreen, reason: BlurReason) {
        contentView = Self.makeDimView(size: screen.frame.size)

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

        addCenteredContent(for: reason)
    }

    // MARK: - Public API

    func show() {
        window.level = .screenSaver
        window.ignoresMouseEvents = false
        window.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        window.orderOut(nil)
        window.close()
    }

    /// Allow clicks to pass through to the system auth dialog while blur is still visible.
    func passThrough(_ enabled: Bool) {
        window.ignoresMouseEvents = enabled
    }

    func showMessage(_ text: String) {
        messageDismissWorkItem?.cancel()
        messageLabel?.removeFromSuperview()

        let label = makeMessageLabel(text)
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

    // MARK: - Layout helpers

    private func addCenteredContent(for reason: BlurReason) {
        let (iconName, title, subtitle) = displayContent(for: reason)

        let icon = makeIconView(symbolName: iconName)
        let titleLabel    = makeTextLabel(title,    font: .systemFont(ofSize: 24, weight: .semibold), alpha: 1.0)
        let subtitleLabel = makeTextLabel(subtitle, font: .systemFont(ofSize: 15, weight: .regular),  alpha: 0.5)

        [icon, titleLabel, subtitleLabel].forEach { contentView.addSubview($0) }

        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -44),
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 20),
            subtitleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
        ])
    }

    private func displayContent(for reason: BlurReason) -> (icon: String, title: String, subtitle: String) {
        switch reason {
        case .cameraAway:
            return ("figure.walk",    "You Walked Away",       "Screen protected until you return")
        case .cameraPeek:
            return ("eye.slash.fill", "Someone's Watching",    "Screen protected")
        case .idle, .manual:
            return ("lock.fill",      "Screen Locked",         "Press any key to unlock")
        }
    }

    // MARK: - View factories

    private static func makeDimView(size: NSSize) -> NSView {
        let view = NSView(frame: NSRect(origin: .zero, size: size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
        view.autoresizingMask = [.width, .height]
        return view
    }

    private func makeIconView(symbolName: String) -> NSImageView {
        let view = NSImageView()
        view.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        view.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 72, weight: .light)
        view.contentTintColor = .white
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    private func makeTextLabel(_ text: String, font: NSFont, alpha: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font      = font
        label.textColor = NSColor.white.withAlphaComponent(alpha)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func makeMessageLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font      = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .systemRed
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
}
