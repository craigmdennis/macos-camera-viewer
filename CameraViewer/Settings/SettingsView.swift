import SwiftUI

/// Camera management: list with reorder + delete, add/edit via a sheet. All edits write
/// through `CameraStore` immediately (live-on-save).
struct SettingsView: View {
    @ObservedObject var store: CameraStore
    @State private var editing: Editing?

    private enum Editing: Identifiable {
        case add
        case edit(index: Int)
        var id: String { switch self { case .add: return "add"; case .edit(let i): return "edit-\(i)" } }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.cameras.isEmpty {
                emptyState
            } else {
                cameraList
            }
        }
        .frame(width: 460, height: 360)
        .sheet(item: $editing) { editing in
            switch editing {
            case .add:
                CameraFormView(title: "Add Camera",
                               onCancel: { self.editing = nil },
                               onSave: { name, url in store.add(name: name, uri: url); self.editing = nil })
            case .edit(let index):
                let camera = store.cameras[index]
                CameraFormView(title: "Edit Camera", name: camera.name, uri: camera.uri,
                               onCancel: { self.editing = nil },
                               onSave: { name, url in store.update(at: index, name: name, uri: url); self.editing = nil })
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Cameras").font(.system(size: 16, weight: .semibold))
            Spacer()
            Button { editing = .add } label: { Label("Add", systemImage: "plus") }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var cameraList: some View {
        List {
            ForEach(Array(store.cameras.enumerated()), id: \.element.name) { index, camera in
                HStack(spacing: 10) {
                    Image(systemName: "video.fill").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(camera.name).font(.system(size: 13, weight: .medium))
                        Text(camera.uri.absoluteString)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Button { editing = .edit(index: index) } label: {
                        Image(systemName: "pencil")
                    }.buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
            }
            .onDelete { store.remove(at: $0) }
            .onMove { store.move(from: $0, to: $1) }
        }
        .listStyle(.inset)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "video.slash").font(.system(size: 32)).foregroundStyle(.secondary)
            Text("No cameras yet").font(.system(size: 14, weight: .medium))
            Text("Add a camera with its RTSPS URL from UniFi Protect.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button { editing = .add } label: { Label("Add Camera", systemImage: "plus") }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding(.horizontal, 40)
    }
}
