import SwiftUI

/// Chrome for a split/grid layout: one `TileCapsule` per tile, positioned with the same
/// `PiPLayout.frames` geometry the AppKit grid view uses (so they always line up), plus a
/// global close + layout-switcher cluster in the top-left corner. Fades with hover exactly
/// like the single-view `ChromeOverlay`.
struct MultiChromeOverlay: View {
    let isVisible: Bool
    let layout: PiPLayout
    let tiles: [TileViewModel]
    let allCameras: [CameraConfig]
    let onClose: () -> Void
    let onChangeLayout: (PiPLayout) -> Void
    let onSelectCamera: (Int, CameraConfig) -> Void
    let onToggleMute: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(Array(tileFrames(in: geo.size).enumerated()), id: \.offset) { index, frame in
                    tileOverlay(index: index, frame: frame)
                }
                globalControls
                    .padding(.top, 10)
                    .padding(.leading, 10)
            }
        }
        .opacity(isVisible ? 1 : 0)
        .animation(.easeInOut(duration: isVisible ? 0.15 : 0.25), value: isVisible)
        .allowsHitTesting(isVisible)
    }

    private func tileOverlay(index: Int, frame: CGRect) -> some View {
        ZStack {
            if index < tiles.count, tiles[index].isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.2)
                    .tint(.white)
            }
            if index < tiles.count {
                TileCapsule(
                    model: tiles[index],
                    allCameras: allCameras,
                    compact: frame.width < 220,
                    onSelectCamera: { onSelectCamera(index, $0) },
                    onToggleMute: { onToggleMute(index) }
                )
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 8)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
    }

    /// `PiPLayout.frames` is AppKit-style (origin bottom-left); flip to SwiftUI's
    /// top-left origin so the chrome lines up with the AppKit-hosted grid view.
    private func tileFrames(in size: CGSize) -> [CGRect] {
        PiPLayout.frames(for: layout, containerSize: size, spacing: TileGridView.spacing).map { rect in
            CGRect(x: rect.minX, y: size.height - rect.maxY, width: rect.width, height: rect.height)
        }
    }

    private var globalControls: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            Menu {
                ForEach(PiPLayout.allCases, id: \.self) { option in
                    Button(option.displayName) { onChangeLayout(option) }
                }
            } label: {
                Image(systemName: "rectangle.grid.2x2")
                    .font(.system(size: 16, weight: .semibold))
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
}
