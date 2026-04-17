import SwiftUI

@main
struct CameraViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }  // No Settings window; SwiftUI requires a Scene.
    }
}
