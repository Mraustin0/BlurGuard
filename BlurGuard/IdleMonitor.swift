import CoreGraphics
import Foundation

final class IdleMonitor {
    var onIdleTimeUpdated: ((TimeInterval) -> Void)?

    private var timer: Timer?

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            let idleTime = IdleMonitor.userIdleTime()
            self?.onIdleTimeUpdated?(idleTime)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Returns seconds since the last real user input (keyboard or mouse),
    /// ignoring system-generated events that can reset the generic idle counter.
    static func userIdleTime() -> TimeInterval {
        let source = CGEventSourceStateID.combinedSessionState
        let mouseMoved = CGEventSource.secondsSinceLastEventType(source, eventType: .mouseMoved)
        let leftDown = CGEventSource.secondsSinceLastEventType(source, eventType: .leftMouseDown)
        let rightDown = CGEventSource.secondsSinceLastEventType(source, eventType: .rightMouseDown)
        let keyDown = CGEventSource.secondsSinceLastEventType(source, eventType: .keyDown)
        let flagsChanged = CGEventSource.secondsSinceLastEventType(source, eventType: .flagsChanged)
        let scrollWheel = CGEventSource.secondsSinceLastEventType(source, eventType: .scrollWheel)
        return min(mouseMoved, leftDown, rightDown, keyDown, flagsChanged, scrollWheel)
    }
}
