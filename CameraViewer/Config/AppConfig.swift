import Foundation

struct CameraConfig: Codable, Equatable {
    var name: String
    var uri: URL
}

struct AppConfig: Codable, Equatable {
    var cameras: [CameraConfig]
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
            let config = try JSONDecoder().decode(AppConfig.self, from: data)
            guard !config.cameras.isEmpty else {
                throw AppConfigError.malformed(underlying: NSError(
                    domain: "AppConfig", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "cameras array must not be empty"]
                ))
            }
            return config
        } catch let appErr as AppConfigError {
            throw appErr
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
          "_comment": "Add your cameras below. Find RTSPS URLs in Protect web UI → Settings → Advanced → RTSP.",
          "cameras": [
            { "name": "Front Door", "uri": "rtsps://10.0.0.1:7441/YOUR_CAMERA_ID_1?enableSrtp" },
            { "name": "Back Yard",  "uri": "rtsps://10.0.0.1:7441/YOUR_CAMERA_ID_2?enableSrtp" }
          ]
        }

        """
        try Data(stub.utf8).write(to: url, options: .atomic)
    }
}
