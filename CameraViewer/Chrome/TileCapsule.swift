import SwiftUI

/// One tile's mini chrome inside a split/grid layout: mute toggle (hidden until a
/// camera is assigned) + camera picker. Placeholder text when the tile is unassigned.
struct TileViewModel {
    let camera: CameraConfig?
    let isMuted: Bool
    let isLoading: Bool
}

struct TileCapsule: View {
    let model: TileViewModel
    let allCameras: [CameraConfig]
    // Hides the camera name (icons only) once the tile is too narrow to show it without
    // overlapping the global close/layout controls in the corner.
    let compact: Bool
    let onSelectCamera: (CameraConfig) -> Void
    let onToggleMute: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if model.camera != nil {
                Button(action: onToggleMute) {
                    Image(systemName: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.isMuted ? "Unmute" : "Mute")
            }

            Menu {
                Picker("Camera", selection: cameraSelection) {
                    ForEach(allCameras, id: \.name) { camera in
                        Text(camera.name).tag(camera.name)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 11, weight: .semibold))
                    if !compact {
                        Text(model.camera?.name ?? "Select camera")
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                    }
                }
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Select camera")
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
                .clipShape(Capsule())
        )
    }

    private var cameraSelection: Binding<String> {
        Binding(
            get: { model.camera?.name ?? "" },
            set: { name in
                if let camera = allCameras.first(where: { $0.name == name }) { onSelectCamera(camera) }
            }
        )
    }
}
