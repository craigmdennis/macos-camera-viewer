import AppKit

/// Damped spring toward a target; semi-implicit Euler so it is stable at any frame rate.
/// Slightly underdamped so the window overshoots the corner by a few px and settles.
enum Spring {
    static let stiffness: CGFloat = 220
    static let damping: CGFloat = 24

    static func step(position: CGPoint, velocity: CGPoint, target: CGPoint, dt: CGFloat)
        -> (position: CGPoint, velocity: CGPoint) {
        let ax = -stiffness * (position.x - target.x) - damping * velocity.x
        let ay = -stiffness * (position.y - target.y) - damping * velocity.y
        let v = CGPoint(x: velocity.x + ax * dt, y: velocity.y + ay * dt)
        return (CGPoint(x: position.x + v.x * dt, y: position.y + v.y * dt), v)
    }

    static func settled(position: CGPoint, velocity: CGPoint, target: CGPoint) -> Bool {
        abs(position.x - target.x) < 0.5 && abs(position.y - target.y) < 0.5
            && abs(velocity.x) < 2 && abs(velocity.y) < 2
    }
}

/// Drives an NSWindow's origin with `Spring` on a timer. `NSAnimationContext` cannot
/// overshoot, so the elastic dock is done by hand.
final class WindowSpring {
    private weak var window: NSWindow?
    private var timer: Timer?
    private let dt: CGFloat = 1 / 60

    init(window: NSWindow) { self.window = window }

    var isAnimating: Bool { timer != nil }

    func animate(toOrigin target: CGPoint, initialVelocity: CGPoint, onSettle: @escaping () -> Void) {
        cancel()
        var position = window?.frame.origin ?? target
        var velocity = initialVelocity
        let timer = Timer(timeInterval: TimeInterval(dt), repeats: true) { [weak self] t in
            guard let self, let window = self.window else { t.invalidate(); return }
            (position, velocity) = Spring.step(position: position, velocity: velocity, target: target, dt: self.dt)
            if Spring.settled(position: position, velocity: velocity, target: target) {
                window.setFrameOrigin(target)
                self.cancel()
                onSettle()
            } else {
                window.setFrameOrigin(position)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}
