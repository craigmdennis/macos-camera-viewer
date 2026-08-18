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
    let onChangeLayout: (PiPLayout) -> Void
    let quickReturnLayout: PiPLayout?

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

            if let quickReturnLayout {
                Button(action: { onChangeLayout(quickReturnLayout) }) {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.system(size: 18, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to \(quickReturnLayout.displayName)")
            }

            Menu {
                ForEach(PiPLayout.allCases, id: \.self) { layout in
                    Button(layout.displayName) { onChangeLayout(layout) }
                }
            } label: {
                Image(systemName: "rectangle.grid.2x2")
                    .font(.system(size: 18, weight: .semibold))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Change layout")
        }
        .foregroundStyle(.primary)
        .hudCapsule()
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
            .background(
                VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
                    .clipShape(Capsule())
            )
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
