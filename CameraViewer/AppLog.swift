import os

/// Structured logging via Apple's unified logging system. Unlike `NSLog`, `Logger`
/// output is visible in Release builds (Console.app, filterable by subsystem/category)
/// and is near-zero cost when not being collected.
///
/// View in Console.app or:  log show --predicate 'subsystem == "com.craigmdennis.cameraviewer"' --last 5m
enum AppLog {
    private static let subsystem = "com.craigmdennis.cameraviewer"

    static let rtsp = Logger(subsystem: subsystem, category: "rtsp")
    static let decode = Logger(subsystem: subsystem, category: "decode")
    static let config = Logger(subsystem: subsystem, category: "config")
}
