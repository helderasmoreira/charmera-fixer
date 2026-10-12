import Darwin
import Foundation

final class Processor: @unchecked Sendable {
    private let tools: Tools
    private let lock = NSLock()
    private var cancelled = false
    private var running: Process?

    private static let nameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()

    private static let creationTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter
    }()

    init(tools: Tools) {
        self.tools = tools
    }

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func cancel() {
        lock.withLock {
            cancelled = true
            running?.terminate()
        }
    }

    func process(_ file: CameraFile, into directory: URL, update: (FileStatus) -> Void) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        update(.copying)
        let finalExtension = file.kind == .video ? "mp4" : file.source.pathExtension.lowercased()
        let finalURL = Self.uniqueDestination(for: file, in: directory, extension: finalExtension)
        let copyURL = finalURL.deletingPathExtension().appendingPathExtension(file.source.pathExtension.lowercased())
        try copy(file.source, to: copyURL)

        do {
            switch file.kind {
            case .photo:
                if let fix = file.fix, fix.hasFixes {
                    update(.fixingExif)
                    try fixExif(copyURL, fix: fix)
                }
            case .video:
                update(.converting(0))
                try convert(copyURL, to: finalURL, creationTime: file.taken) { update(.converting($0)) }
                try FileManager.default.removeItem(at: copyURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: copyURL)
            if file.kind == .video { try? FileManager.default.removeItem(at: finalURL) }
            throw error
        }

        try FileManager.default.setAttributes(
            [.modificationDate: file.taken, .creationDate: file.taken],
            ofItemAtPath: finalURL.path
        )
        return finalURL
    }

    private static func uniqueDestination(for file: CameraFile, in directory: URL, extension ext: String) -> URL {
        let prefix = file.kind == .photo ? "IMG" : "VID"
        let base = "\(prefix)_\(nameFormatter.string(from: file.taken))"
        let sourceExt = file.source.pathExtension.lowercased()
        var counter = 0
        while true {
            let name = counter == 0 ? base : "\(base)_\(counter)"
            let candidate = directory.appendingPathComponent(name).appendingPathExtension(ext)
            let staging = directory.appendingPathComponent(name).appendingPathExtension(sourceExt)
            if !FileManager.default.fileExists(atPath: candidate.path),
               !FileManager.default.fileExists(atPath: staging.path) {
                return candidate
            }
            counter += 1
        }
    }

    private func copy(_ source: URL, to destination: URL) throws {
        let flags = copyfile_flags_t(COPYFILE_DATA | COPYFILE_EXCL)
        guard copyfile(source.path, destination.path, nil, flags) == 0 else {
            throw ToolError(message: "Copy failed: \(String(cString: strerror(errno)))")
        }
    }

    private func fixExif(_ url: URL, fix: ExifFix) throws {
        guard let exiftool = tools.exiftool else { throw ToolError(message: "exiftool is not installed.") }

        try Shell.check(exiftool, ["-all=", "-tagsfromfile", "@", "-all:all", "-unsafe", "-overwrite_original", url.path])

        let tags: [(String, String?)] = [
            ("ModifyDate", fix.modifyDate),
            ("DateTimeOriginal", fix.dateTimeOriginal),
            ("CreateDate", fix.createDate),
            ("ExifImageWidth", fix.width.map(String.init)),
            ("ExifImageHeight", fix.height.map(String.init)),
        ]
        let arguments = ["-overwrite_original"]
            + tags.compactMap { tag, value in value.map { "-\(tag)=\($0)" } }
            + [url.path]
        try Shell.check(exiftool, arguments)
    }

    private func convert(_ input: URL, to output: URL, creationTime: Date, progress: (Double) -> Void) throws {
        guard let ffmpeg = tools.ffmpeg, let ffprobe = tools.ffprobe else {
            throw ToolError(message: "ffmpeg is not installed.")
        }

        let duration = Scanner.duration(of: input, ffprobe: ffprobe)

        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = [
            "-y", "-nostdin", "-nostats", "-loglevel", "error",
            "-i", input.path,
            "-c:v", "libx264", "-crf", "18", "-preset", "medium", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "128k", "-ar", "44100",
            "-movflags", "+faststart",
            "-metadata", "creation_time=\(Self.creationTimeFormatter.string(from: creationTime))",
            "-progress", "pipe:1",
            output.path,
        ]
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try lock.withLock {
            if cancelled { throw CancellationError() }
            try process.run()
            running = process
        }
        defer { lock.withLock { running = nil } }

        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        let handle = outPipe.fileHandleForReading
        var buffer = Data()
        var lastPercent = -1
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex...newline)
                guard duration > 0, line.hasPrefix("out_time_us="),
                      let micros = Double(line.dropFirst("out_time_us=".count)) else { continue }
                let percent = min(micros / 1_000_000 / duration * 100, 100)
                if Int(percent) != lastPercent {
                    lastPercent = Int(percent)
                    progress(percent)
                }
            }
        }
        group.wait()
        process.waitUntilExit()

        if isCancelled { throw CancellationError() }
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw ToolError(message: "ffmpeg failed: \(message)")
        }
    }
}
