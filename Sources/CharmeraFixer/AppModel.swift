import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    enum Phase {
        case waiting, scanning, ready, processing, finished
    }

    @Published var phase: Phase = .waiting
    @Published var source: URL?
    @Published var files: [CameraFile] = []
    @Published var errorMessage: String?
    @Published var autoLaunch = AutoLaunch.isEnabled
    @Published var destination: URL {
        didSet { UserDefaults.standard.set(destination.path, forKey: "destination") }
    }

    let tools = Tools.locate()
    private var processor: Processor?
    private var observers: [NSObjectProtocol] = []

    init() {
        if let saved = UserDefaults.standard.string(forKey: "destination") {
            destination = URL(fileURLWithPath: saved)
        } else {
            destination = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Pictures/KodakCharmera")
        }

        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] note in
            guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            MainActor.assumeIsolated { self?.volumeMounted(url) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] note in
            guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            MainActor.assumeIsolated { self?.volumeUnmounted(url) }
        })

        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        if let camera = volumes.first(where: Self.isCamera) {
            open(camera)
        }
    }

    var photoCount: Int { files.filter { $0.kind == .photo }.count }
    var videoCount: Int { files.filter { $0.kind == .video }.count }
    var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }
    var failedCount: Int { files.filter { if case .failed = $0.status { true } else { false } }.count }
    var isVolume: Bool { source?.path.hasPrefix("/Volumes/") == true }

    var missingTools: [String] {
        tools.missing(forPhotos: photoCount > 0, videos: videoCount > 0)
    }

    var overallProgress: Double {
        guard !files.isEmpty else { return 0 }
        let done = files.reduce(0.0) { sum, file in
            switch file.status {
            case .done, .failed: sum + 1
            case .converting(let percent): sum + percent / 100
            default: sum
            }
        }
        return done / Double(files.count)
    }

    func open(_ url: URL) {
        guard phase != .processing else { return }
        source = url
        scan()
    }

    func scan() {
        guard let source else { return }
        phase = .scanning
        files = []
        let scanner = Scanner(exiftool: tools.exiftool, ffprobe: tools.ffprobe)
        Task.detached {
            do {
                let found = try scanner.scan(source)
                await MainActor.run {
                    self.files = found
                    self.phase = .ready
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.phase = .ready
                }
            }
        }
    }

    func start() {
        guard phase == .ready, !files.isEmpty, missingTools.isEmpty else { return }
        let processor = Processor(tools: tools)
        self.processor = processor
        phase = .processing
        for index in files.indices { files[index].status = .pending }

        let jobs = files
        let destination = destination
        Task.detached {
            for (index, file) in jobs.enumerated() {
                if processor.isCancelled { break }
                let set: @Sendable (FileStatus) -> Void = { status in
                    Task { @MainActor in
                        guard !self.files[index].status.isFinished else { return }
                        self.files[index].status = status
                    }
                }
                do {
                    let output = try processor.process(file, into: destination, update: set)
                    await MainActor.run {
                        self.files[index].destination = output
                        self.files[index].status = .done
                    }
                } catch is CancellationError {
                    set(.failed("Cancelled"))
                } catch {
                    set(.failed(error.localizedDescription))
                }
            }
            await MainActor.run {
                self.phase = .finished
                self.processor = nil
            }
        }
    }

    func cancel() {
        processor?.cancel()
    }

    func chooseSource() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose the camera, or a folder containing its DCIM files."
        panel.directoryURL = source ?? URL(fileURLWithPath: "/Volumes")
        if panel.runModal() == .OK, let url = panel.url {
            open(url)
        }
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = destination
        if panel.runModal() == .OK, let url = panel.url {
            destination = url
        }
    }

    func revealDestination() {
        let outputs = files.compactMap(\.destination)
        if outputs.isEmpty {
            NSWorkspace.shared.open(destination)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(outputs)
        }
    }

    func eject() {
        guard let source, isVolume, phase != .processing else { return }
        let volume = URL(fileURLWithPath: "/Volumes").appendingPathComponent(source.pathComponents[2])
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: volume)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setAutoLaunch(_ enabled: Bool) {
        do {
            try AutoLaunch.setEnabled(enabled)
        } catch {
            errorMessage = error.localizedDescription
        }
        autoLaunch = AutoLaunch.isEnabled
    }

    private func volumeMounted(_ url: URL) {
        guard Self.isCamera(url), phase != .processing, phase != .ready || files.isEmpty else { return }
        open(url)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func volumeUnmounted(_ url: URL) {
        guard let source, source.path.hasPrefix(url.path), phase != .processing else { return }
        self.source = nil
        if phase != .finished { files = [] }
        phase = files.isEmpty ? .waiting : .finished
    }

    private static func isCamera(_ url: URL) -> Bool {
        guard url.path.hasPrefix("/Volumes/") else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("DCIM").path, isDirectory: &isDir) && isDir.boolValue
    }
}
