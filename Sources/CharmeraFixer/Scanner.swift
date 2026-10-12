import Foundation

struct Scanner {
    let exiftool: URL?
    let ffprobe: URL?

    private static let photoExtensions: Set<String> = ["jpg", "jpeg"]
    private static let videoExtensions: Set<String> = ["avi"]

    static func mediaRoot(for url: URL) -> URL {
        let dcim = url.appendingPathComponent("DCIM")
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: dcim.path, isDirectory: &isDir), isDir.boolValue {
            return dcim
        }
        return url
    }

    func scan(_ location: URL) throws -> [CameraFile] {
        let root = Self.mediaRoot(for: location)
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw ToolError(message: "Couldn't read \(root.path).")
        }

        var files: [CameraFile] = []
        for case let url as URL in enumerator {
            guard !url.lastPathComponent.hasPrefix("._") else { continue }
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true else { continue }

            let ext = url.pathExtension.lowercased()
            let kind: FileKind
            if Self.photoExtensions.contains(ext) {
                kind = .photo
            } else if Self.videoExtensions.contains(ext) {
                kind = .video
            } else {
                continue
            }

            files.append(CameraFile(
                source: url,
                kind: kind,
                size: Int64(values.fileSize ?? 0),
                taken: values.contentModificationDate ?? Date()
            ))
        }

        if let ffprobe {
            for index in files.indices where files[index].kind == .video {
                files[index].taken -= Self.duration(of: files[index].source, ffprobe: ffprobe)
            }
        }

        files.sort { ($0.taken, $0.name) < ($1.taken, $1.name) }

        let photos = files.filter { $0.kind == .photo }.map(\.source)
        if let exiftool, !photos.isEmpty {
            let fixes = try readFixes(photos, exiftool: exiftool)
            for index in files.indices where files[index].kind == .photo {
                files[index].fix = fixes[files[index].source.path]
            }
        }
        return files
    }

    private func readFixes(_ photos: [URL], exiftool: URL) throws -> [String: ExifFix] {
        let argFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("charmera-\(UUID().uuidString).args")
        try photos.map(\.path).joined(separator: "\n").write(to: argFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: argFile) }

        let result = try Shell.run(exiftool, [
            "-json",
            "-ImageWidth", "-ImageHeight",
            "-ExifImageWidth", "-ExifImageHeight",
            "-ModifyDate", "-DateTimeOriginal", "-CreateDate",
            "-@", argFile.path,
        ])
        guard let entries = try? JSONSerialization.jsonObject(with: result.stdout) as? [[String: Any]] else {
            throw ToolError(message: "exiftool couldn't read the photos: \(result.stderr)")
        }

        var fixes: [String: ExifFix] = [:]
        for entry in entries {
            guard let path = entry["SourceFile"] as? String else { continue }
            let exifWidth = int(entry["ExifImageWidth"])
            let exifHeight = int(entry["ExifImageHeight"])
            fixes[path] = ExifFix(
                modifyDate: Self.fixDate(entry["ModifyDate"] as? String),
                dateTimeOriginal: Self.fixDate(entry["DateTimeOriginal"] as? String),
                createDate: Self.fixDate(entry["CreateDate"] as? String),
                width: Self.fixDimension(exifWidth, actual: int(entry["ImageWidth"])),
                height: Self.fixDimension(exifHeight, actual: int(entry["ImageHeight"])),
                originalWidth: exifWidth,
                originalHeight: exifHeight
            )
        }
        return fixes
    }

    static func duration(of url: URL, ffprobe: URL) -> TimeInterval {
        guard let output = try? Shell.check(ffprobe, ["-v", "quiet", "-show_entries", "format=duration", "-of", "csv=p=0", url.path]) else {
            return 0
        }
        return Double(String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    static func fixDate(_ raw: String?) -> String? {
        guard let parts = raw?.split(separator: ":", omittingEmptySubsequences: false), parts.count == 6 else {
            return nil
        }
        return "\(parts[0]):\(parts[1]):\(parts[2]) \(parts[3]):\(parts[4]):\(parts[5])"
    }

    static func fixDimension(_ exif: Int?, actual: Int?) -> Int? {
        guard let exif, let actual, exif != actual else { return nil }
        return actual
    }

    private func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }
}
