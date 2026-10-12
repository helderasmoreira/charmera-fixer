import Foundation

struct Tools {
    let exiftool: URL?
    let ffmpeg: URL?
    let ffprobe: URL?

    static func locate() -> Tools {
        Tools(exiftool: find("exiftool"), ffmpeg: find("ffmpeg"), ffprobe: find("ffprobe"))
    }

    func missing(forPhotos photos: Bool, videos: Bool) -> [String] {
        var names: [String] = []
        if photos && exiftool == nil { names.append("exiftool") }
        if videos && (ffmpeg == nil || ffprobe == nil) { names.append("ffmpeg") }
        return names
    }

    private static func find(_ name: String) -> URL? {
        let dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin"]
        return dirs
            .map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

struct ProcessResult {
    let status: Int32
    let stdout: Data
    let stderr: String
}

enum Shell {
    static func run(_ executable: URL, _ arguments: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()

        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()

        return ProcessResult(
            status: process.terminationStatus,
            stdout: outData,
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }

    @discardableResult
    static func check(_ executable: URL, _ arguments: [String]) throws -> Data {
        let result = try run(executable, arguments)
        guard result.status == 0 else {
            throw ToolError(message: "\(executable.lastPathComponent) failed: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return result.stdout
    }
}
