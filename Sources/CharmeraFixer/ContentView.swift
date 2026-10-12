import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 480)
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: model.source == nil ? "camera" : "camera.fill")
                .font(.system(size: 28))
                .foregroundStyle(model.source == nil ? Color.secondary : Color.accentColor)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.source.map { $0.lastPathComponent } ?? "No camera connected")
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Choose Folder…", action: model.chooseSource)
                .disabled(model.phase == .processing)
            if model.source != nil {
                Button("Rescan", action: model.scan)
                    .disabled(model.phase == .processing || model.phase == .scanning)
            }
            if model.isVolume {
                Button("Eject", action: model.eject)
                    .disabled(model.phase == .processing)
            }
        }
        .padding(16)
    }

    private var subtitle: String {
        guard let source = model.source else {
            return "Plug in the Charmera over USB, or choose a folder with its files."
        }
        guard model.phase != .scanning else { return "Scanning \(source.path)…" }
        let size = ByteCountFormatter.string(fromByteCount: model.totalBytes, countStyle: .file)
        return "\(model.photoCount) photos, \(model.videoCount) videos, \(size)"
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .waiting:
            ContentUnavailableView(
                "Waiting for the camera",
                systemImage: "cable.connector",
                description: Text("Connect your Kodak Charmera and its photos and videos will show up here.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .scanning:
            ProgressView("Reading files…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready, .processing, .finished:
            if model.files.isEmpty {
                ContentUnavailableView(
                    "No photos or videos found",
                    systemImage: "photo.on.rectangle",
                    description: Text("Looked for JPG and AVI files in \(model.source?.path ?? "the selected folder").")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                fileTable
            }
        }
    }

    private var fileTable: some View {
        Table(model.files) {
            TableColumn("File") { file in
                Label(file.name, systemImage: file.kind == .photo ? "photo" : "video")
            }
            .width(min: 140, ideal: 150)
            TableColumn("Size") { file in
                Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 70)
            TableColumn("Taken") { file in
                Text(file.taken.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 140)
            TableColumn("Fixes") { file in
                Text(file.fixDescription)
            }
            .width(min: 160, ideal: 280)
            TableColumn("Status") { file in
                StatusView(status: file.status)
            }
            .width(min: 100, ideal: 110)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Save to")
                    .foregroundStyle(.secondary)
                Text((model.destination.path as NSString).abbreviatingWithTildeInPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Change…", action: model.chooseDestination)
                    .disabled(model.phase == .processing)
                Spacer()
                Toggle("Open when camera connects", isOn: Binding(
                    get: { model.autoLaunch },
                    set: { model.setAutoLaunch($0) }
                ))
                .toggleStyle(.checkbox)
                .help("Opens this app whenever a volume named “Untitled” with a DCIM folder is mounted.")
            }

            if !model.missingTools.isEmpty {
                Label {
                    Text("Missing \(model.missingTools.joined(separator: " and ")). Install with ")
                        + Text("brew install \(model.missingTools.joined(separator: " "))").font(.body.monospaced())
                        + Text(", then reopen the app.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                }
            }

            HStack(spacing: 12) {
                if model.phase == .processing || model.phase == .finished {
                    ProgressView(value: model.overallProgress)
                    Text(progressText)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .fixedSize()
                } else {
                    Spacer()
                }
                if model.phase == .processing {
                    Button("Cancel", role: .cancel, action: model.cancel)
                } else if model.phase == .finished {
                    Button("Show in Finder", action: model.revealDestination)
                    Button("Import Again") {
                        model.phase = .ready
                        model.start()
                    }
                    .disabled(model.source == nil)
                } else {
                    Button("Import \(model.files.count) Files", action: model.start)
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.phase != .ready || model.files.isEmpty || !model.missingTools.isEmpty)
                }
            }
        }
        .padding(16)
    }

    private var progressText: String {
        let finished = model.files.filter(\.status.isFinished).count
        if model.phase == .finished {
            let failed = model.failedCount
            return failed == 0 ? "All \(finished) files imported" : "\(finished - failed) imported, \(failed) failed"
        }
        return "\(finished) of \(model.files.count)"
    }
}

private struct StatusView: View {
    let status: FileStatus

    var body: some View {
        switch status {
        case .pending:
            Text("Waiting").foregroundStyle(.secondary)
        case .copying:
            Label("Copying…", systemImage: "doc.on.doc")
        case .fixingExif:
            Label("Fixing EXIF…", systemImage: "wrench.adjustable")
        case .converting(let percent):
            HStack(spacing: 6) {
                ProgressView(value: percent, total: 100).frame(width: 60)
                Text("\(Int(percent))%").monospacedDigit()
            }
        case .done:
            Label("Done", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let message):
            Label("Failed", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .help(message)
        }
    }
}
