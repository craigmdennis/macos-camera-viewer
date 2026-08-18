import SwiftUI

/// Shared HUD-capsule look used by both the single-view chrome and the multi-tile chrome.
struct HUDCapsule: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(
                VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
                    .clipShape(Capsule())
            )
    }
}

extension View {
    func hudCapsule() -> some View { modifier(HUDCapsule()) }
}

struct VisualEffectBlur: NSViewRepresentable {
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
