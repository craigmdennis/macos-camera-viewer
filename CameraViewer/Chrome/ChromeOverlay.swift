import SwiftUI

struct ChromeOverlay: View {
    let isVisible: Bool
    let isMuted: Bool
    let isLoading: Bool
    let zoomScale: CGFloat
    let cameras: [CameraConfig]
    let selectedCameraName: String?
    let onClose: () -> Void
    let onToggleMute: () -> Void
    let onSelectCamera: (CameraConfig) -> Void

    var body: some View {
        ZStack {
            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.5)
                    .tint(.white)
            }

            VStack {
                HStack(alignment: .top) {
                    leftControls            // close + mute
                    Spacer(minLength: 8)
                    if !cameras.isEmpty {
                        cameraPicker        // camera selector, top-right
                    }
                }
                .padding(.top, 10)
                .padding(.horizontal, 10)

                Spacer()
            }
            .opacity(isVisible ? 1 : 0)
            .animation(.easeInOut(duration: isVisible ? 0.15 : 0.25), value: isVisible)
            .allowsHitTesting(isVisible)

            VStack {
                Spacer()
                if zoomScale > 1.0 {
                    ZoomBadge(scale: zoomScale)
                        .padding(.bottom, 10)
                }
            }
            // Fades with the rest of the chrome when the pointer leaves the window.
            .opacity(isVisible ? 1 : 0)
            .animation(.easeInOut(duration: isVisible ? 0.15 : 0.25), value: isVisible)
            .allowsHitTesting(false)
        }
    }

    private var leftControls: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            Button(action: onToggleMute) {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isMuted ? "Unmute" : "Mute")
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(hudCapsule)
    }

    private var cameraPicker: some View {
        Menu {
            Picker("Camera", selection: cameraSelection) {
                ForEach(cameras, id: \.name) { camera in
                    Text(camera.name).tag(camera.name)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "video.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text(selectedCameraName ?? "Camera")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .frame(maxWidth: 180)
            .background(hudCapsule)
        }
        // .button + .plain so the label's HUD capsule shows (matches the left controls);
        // .borderlessButton draws its own chrome and hides the custom background.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Select camera")
    }

    private var cameraSelection: Binding<String> {
        Binding(
            get: { selectedCameraName ?? "" },
            set: { name in
                if let camera = cameras.first(where: { $0.name == name }) { onSelectCamera(camera) }
            }
        )
    }

    private var hudCapsule: some View {
        VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
            .clipShape(Capsule())
    }
}

private struct ZoomBadge: View {
    let scale: CGFloat

    var body: some View {
        Text(String(format: "%.1f×", scale))
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(
                VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
                    .clipShape(Capsule())
            )
    }
}

private struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
