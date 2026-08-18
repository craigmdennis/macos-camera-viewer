import AppKit

/// Positions a set of tile drawable views according to `PiPLayout.frames`. All geometry
/// logic lives in that pure function; this view just re-runs it on every layout pass.
final class TileGridView: NSView {
    static let spacing: CGFloat = 2

    var layoutMode: PiPLayout = .single {
        didSet { layoutTiles() }
    }

    private var tileViews: [NSView] = []

    func setTileViews(_ views: [NSView]) {
        tileViews.forEach { $0.removeFromSuperview() }
        tileViews = views
        tileViews.forEach { addSubview($0) }
        layoutTiles()
    }

    // Frame-based (not the constraint-driven `layout()` pass) to match the rest of the
    // app's manual-frame AppKit style and fire reliably on every autoresize.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutTiles()
    }

    private func layoutTiles() {
        let frames = PiPLayout.frames(for: layoutMode, containerSize: bounds.size, spacing: Self.spacing)
        for (view, frame) in zip(tileViews, frames) {
            view.frame = frame
        }
    }
}
