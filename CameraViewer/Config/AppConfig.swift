import Foundation

struct AppConfig: Codable, Equatable {
    var rtspsURL: URL
}

enum AppConfigError: Error {
    case fileNotFound(path: URL)
    case malformed(underlying: Error)
}

enum AppConfigLoader {
    static let fileName = "config.json"
    static let appSupportFolderName = "CameraViewer"

    static var defaultDirectoryURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(appSupportFolderName, isDirectory: true)
    }

    static var defaultFileURL: URL {
        defaultDirectoryURL.appendingPathComponent(fileName)
    }

    static func load(from url: URL = defaultFileURL) throws -> AppConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AppConfigError.fileNotFound(path: url)
        }
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            throw AppConfigError.malformed(underlying: error)
        }
    }

    static func writeStub(to url: URL = defaultFileURL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let stub = """
        {
          "_comment": "Replace rtspsURL with your camera's RTSPS URL (Protect web UI → Settings → Advanced → RTSP).",
          "rtspsURL": "rtsps://10.0.0.1:7441/YOUR_CAMERA_ID?enableSrtp"
        }

        """
        try Data(stub.utf8).write(to: url, options: .atomic)
    }
}
