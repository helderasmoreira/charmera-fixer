import Foundation

enum FileKind: String {
    case photo = "Photo"
    case video = "Video"
}

enum FileStatus: Equatable {
    case pending
    case copying
    case fixingExif
    case converting(Double)
    case done
    case failed(String)

    var isFinished: Bool {
        switch self {
        case .done, .failed: true
        default: false
        }
    }
}

struct ExifFix {
    var modifyDate: String?
    var dateTimeOriginal: String?
    var createDate: String?
    var width: Int?
    var height: Int?
    var originalWidth: Int?
    var originalHeight: Int?

    var fixesDate: Bool { modifyDate != nil || dateTimeOriginal != nil || createDate != nil }
    var fixesDimensions: Bool { width != nil || height != nil }
    var hasFixes: Bool { fixesDate || fixesDimensions }
}

struct CameraFile: Identifiable {
    let id = UUID()
    let source: URL
    let kind: FileKind
    let size: Int64
    var taken: Date
    var fix: ExifFix?
    var destination: URL?
    var status: FileStatus = .pending

    var name: String { source.lastPathComponent }

    var fixDescription: String {
        switch kind {
        case .video:
            return "Convert to MP4, set date"
        case .photo:
            guard let fix, fix.hasFixes else { return "None needed" }
            var parts: [String] = []
            if fix.fixesDate { parts.append("Date format") }
            if fix.fixesDimensions {
                let from = "\(fix.originalWidth ?? 0)×\(fix.originalHeight ?? 0)"
                let to = "\(fix.width ?? fix.originalWidth ?? 0)×\(fix.height ?? fix.originalHeight ?? 0)"
                parts.append("Size \(from) → \(to)")
            }
            return parts.joined(separator: ", ")
        }
    }
}

struct ToolError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
