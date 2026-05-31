import SwiftUI

/// First-run flow for someone with zero cameras: explain where to find the RTSPS URL in
/// UniFi Protect, then add the first camera (with a live connection test) via the shared
/// `CameraFormView`. Adding the camera starts the viewer; `onComplete` closes the window.
struct OnboardingView: View {
    @ObservedObject var store: CameraStore
    let onComplete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            intro
                .frame(width: 280)
                .padding(24)
                .background(.quaternary.opacity(0.4))

            CameraFormView(
                title: "Add Your First Camera",
                onCancel: { NSApp.terminate(nil) },
                onSave: { name, url in
                    store.add(name: name, uri: url)
                    onComplete()
                }
            )
        }
        .frame(width: 700, height: 320)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "video.badge.plus")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(.tint)
            Text("Welcome to Camera Viewer")
                .font(.system(size: 17, weight: .semibold))
            Text("A floating window for your UniFi Protect cameras.")
                .font(.system(size: 13)).foregroundStyle(.secondary)

            Divider().padding(.vertical, 2)

            Text("Find your camera's URL").font(.system(size: 12, weight: .semibold))
            VStack(alignment: .leading, spacing: 8) {
                step(1, "Open UniFi Protect → camera Settings")
                step(2, "Advanced → RTSP, enable a stream")
                step(3, "Copy the rtsps:// URL and paste it here")
            }
            Spacer()
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)")
                .font(.system(size: 11, weight: .bold))
                .frame(width: 18, height: 18)
                .background(Circle().fill(.tint.opacity(0.18)))
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}
