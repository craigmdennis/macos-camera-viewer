import Foundation

struct ReconnectPolicy {
    static let schedule: [TimeInterval] = [1, 2, 4, 8, 10]

    private(set) var consecutiveFailures: Int = 0

    mutating func recordFailure() -> TimeInterval {
        let index = min(consecutiveFailures, Self.schedule.count - 1)
        consecutiveFailures += 1
        return Self.schedule[index]
    }

    mutating func reset() {
        consecutiveFailures = 0
    }
}
