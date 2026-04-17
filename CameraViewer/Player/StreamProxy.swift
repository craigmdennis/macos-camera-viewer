import Foundation

/// Spawns go2rtc as a subprocess to bridge RTSPS (+ SRTP) → plain RTSP on localhost.
/// VLCKit 3.x cannot consume RTSPS directly, so the rest of the app talks to
/// `StreamProxy.localURL` instead of the user's Unifi URL.
final class StreamProxy {
    static let streamName = "camera"
    static let listenHost = "127.0.0.1"
    static let listenPort = 8554

    static var localURL: URL {
        URL(string: "rtsp://\(listenHost):\(listenPort)/\(streamName)")!
    }

    private var process: Process?
    private var configURL: URL?

    func start(upstream: URL) throws {
        stop()
        guard let binary = Bundle.main.url(forResource: "go2rtc", withExtension: nil) else {
            throw StreamProxyError.binaryNotFound
        }
        let configURL = try writeConfig(upstream: upstream)
        self.configURL = configURL

        let process = Process()
        process.executableURL = binary
        process.arguments = ["-config", configURL.path]
        process.standardOutput = pipeLogging("go2rtc.stdout")
        process.standardError = pipeLogging("go2rtc.stderr")
        try process.run()
        self.process = process
        NSLog("StreamProxy: go2rtc started pid=%d upstream=%@ local=%@",
              process.processIdentifier,
              upstream.absoluteString,
              Self.localURL.absoluteString)
    }

    func stop() {
        if let process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        process = nil
        if let configURL {
            try? FileManager.default.removeItem(at: configURL)
        }
        configURL = nil
    }

    deinit {
        stop()
    }

    private func writeConfig(upstream: URL) throws -> URL {
        let yaml = """
        api:
          listen: ""
        rtsp:
          listen: "\(Self.listenHost):\(Self.listenPort)"
        log:
          level: info
        streams:
          \(Self.streamName):
            - "\(upstream.absoluteString)#backchannel=0"

        """
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraViewer", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("go2rtc-\(UUID().uuidString).yaml")
        try Data(yaml.utf8).write(to: url, options: .atomic)
        return url
    }

    private func pipeLogging(_ label: String) -> Pipe {
        let pipe = Pipe()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(separator: "\n") where !line.isEmpty {
                NSLog("[%@] %@", label, String(line))
            }
        }
        return pipe
    }
}

enum StreamProxyError: Error, CustomStringConvertible {
    case binaryNotFound

    var description: String {
        switch self {
        case .binaryNotFound:
            return "go2rtc binary not found in app bundle (expected Resources/go2rtc)."
        }
    }
}
