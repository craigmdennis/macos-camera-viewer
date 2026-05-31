import Foundation

/// Format validation for a camera URL entered in Settings. Confirms it parses as an
/// rtsp(s) URL with a host and a non-empty path. This is the cheap pre-check; the
/// Settings UI additionally offers a live "Test connection" that runs a real RTSP
/// DESCRIBE (see `CameraProbe`).
enum CameraURLValidator {
    static func validate(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "rtsps" || scheme == "rtsp",
              let host = url.host, !host.isEmpty,
              url.path.count > 1            // more than just "/"
        else { return nil }
        return url
    }
}
