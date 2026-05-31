import Foundation

/// One-shot "Test connection" used by the Settings/onboarding camera form. Runs the real
/// RTSP handshake via `RTSPClient` just far enough to prove the camera is reachable and
/// offers a video track, then tears down. Reuses the production client so a passing test
/// means the same path playback uses actually works.
final class CameraProbe {
    enum Result: Equatable {
        case success(videoCodec: String)
        case failure(String)
    }

    private var client: RTSPClient?
    private var timeoutWork: DispatchWorkItem?
    private var finished = false
    private var completion: ((Result) -> Void)?

    /// Probe `url`, calling `completion` once on the main queue. Resolves on the first of:
    /// a DESCRIBE that yields a video track (success), a client failure, or `timeout`.
    func run(url: URL, timeout: TimeInterval = 8, completion: @escaping (Result) -> Void) {
        self.completion = completion

        let client = RTSPClient(url: url)
        self.client = client

        client.onSDP = { [weak self] sdp in
            if let video = sdp.video {
                self?.finish(.success(videoCodec: video.encoding))
            } else {
                self?.finish(.failure("Connected, but no video track was offered."))
            }
        }
        client.onState = { [weak self] state in
            if case .failed(let message) = state { self?.finish(.failure(message)) }
        }

        let work = DispatchWorkItem { [weak self] in
            self?.finish(.failure("Timed out after \(Int(timeout))s — check the URL and that the camera is reachable."))
        }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)

        client.start()
    }

    func cancel() { finish(.failure("Cancelled")) }

    private func finish(_ result: Result) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.finished else { return }
            self.finished = true
            self.timeoutWork?.cancel()
            self.client?.stop()
            self.client = nil
            self.completion?(result)
            self.completion = nil
        }
    }
}
