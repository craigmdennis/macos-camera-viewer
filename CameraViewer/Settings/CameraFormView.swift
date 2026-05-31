import SwiftUI

/// Add/edit form for a single camera, shared by Settings and onboarding. Validates the
/// URL format inline and offers a live "Test connection" that runs a real RTSP probe.
struct CameraFormView: View {
    let title: String
    @State private var name: String
    @State private var urlText: String
    @State private var testState: TestState = .idle
    private let probe = CameraProbe()
    let onCancel: () -> Void
    let onSave: (String, URL) -> Void

    enum TestState: Equatable {
        case idle, testing, ok(String), failed(String)
    }

    init(title: String, name: String = "", uri: URL? = nil,
         onCancel: @escaping () -> Void, onSave: @escaping (String, URL) -> Void) {
        self.title = title
        self._name = State(initialValue: name)
        self._urlText = State(initialValue: uri?.absoluteString ?? "")
        self.onCancel = onCancel
        self.onSave = onSave
    }

    private var validURL: URL? { CameraURLValidator.validate(urlText) }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && validURL != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.system(size: 15, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.caption).foregroundStyle(.secondary)
                TextField("Front Door", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("RTSPS URL").font(.caption).foregroundStyle(.secondary)
                TextField("rtsps://10.0.0.1:7441/…?enableSrtp", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: urlText, perform: { _ in testState = .idle })
                if !urlText.isEmpty && validURL == nil {
                    Text("Must be an rtsps:// or rtsp:// URL with a host and path.")
                        .font(.caption).foregroundStyle(.red)
                }
            }

            HStack(spacing: 10) {
                Button("Test Connection") { runTest() }
                    .disabled(validURL == nil || testState == .testing)
                testStatusLabel
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Save") {
                    if let url = validURL { onSave(name.trimmingCharacters(in: .whitespaces), url) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 420, height: 280)
    }

    @ViewBuilder private var testStatusLabel: some View {
        switch testState {
        case .idle:
            EmptyView()
        case .testing:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Testing…").foregroundStyle(.secondary) }
                .font(.caption)
        case .ok(let codec):
            Label("Connected (\(codec))", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .font(.caption).foregroundStyle(.red).lineLimit(2)
        }
    }

    private func runTest() {
        guard let url = validURL else { return }
        testState = .testing
        probe.run(url: url) { result in
            switch result {
            case .success(let codec): testState = .ok(codec)
            case .failure(let message): testState = .failed(message)
            }
        }
    }
}
