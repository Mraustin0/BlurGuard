import CoreGraphics
import Foundation

final class IdleMonitor {
    var onIdleTimeUpdated: ((TimeInterval) -> Void)?

    private var timer: Timer?

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.onIdleTimeUpdated?(IdleMonitor.secondsSinceLastInput())
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // CGEventSource gives per-event-type idle times. We take the minimum across
    // all input types so that any real input resets the counter — using the
    // generic HIDSystemActivity clock is unreliable because system animations
    // can reset it without actual user input.
    static func secondsSinceLastInput() -> TimeInterval {
        let src = CGEventSourceStateID.combinedSessionState
        return [
            CGEventSource.secondsSinceLastEventType(src, eventType: .mouseMoved),
            CGEventSource.secondsSinceLastEventType(src, eventType: .leftMouseDown),
            CGEventSource.secondsSinceLastEventType(src, eventType: .rightMouseDown),
            CGEventSource.secondsSinceLastEventType(src, eventType: .keyDown),
            CGEventSource.secondsSinceLastEventType(src, eventType: .flagsChanged),
            CGEventSource.secondsSinceLastEventType(src, eventType: .scrollWheel),
        ].min() ?? .infinity
    }

    // Legacy alias so call sites that used userIdleTime() still compile.
    static func userIdleTime() -> TimeInterval { secondsSinceLastInput() }
}
