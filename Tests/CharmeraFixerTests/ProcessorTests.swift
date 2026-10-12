import Foundation
import Testing
@testable import CharmeraFixer

private let tools = Tools.locate()
private let toolsInstalled = tools.exiftool != nil && tools.ffmpeg != nil && tools.ffprobe != nil

private func date(_ string: String) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.date(from: string)!
}

private func exif(_ url: URL, _ tags: [String]) throws -> [String: Any] {
    let output = try Shell.check(tools.exiftool!, ["-json"] + tags.map { "-\($0)" } + [url.path])
    return try #require((JSONSerialization.jsonObject(with: output) as? [[String: Any]])?.first)
}

private func makeCamera() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("charmera-\(UUID().uuidString)")
    let dcim = root.appendingPathComponent("DCIM")
    try FileManager.default.createDirectory(at: dcim, withIntermediateDirectories: true)

    let photo = dcim.appendingPathComponent("PICT0001.JPG")
    try Shell.check(tools.ffmpeg!, ["-loglevel", "error", "-f", "lavfi", "-i", "testsrc=size=1440x1080", "-frames:v", "1", photo.path])
    try Shell.check(tools.exiftool!, [
        "-overwrite_original", "-ExifImageWidth=640", "-ExifImageHeight=480",
        "-ModifyDate=2026:03:03 12:16:29", "-DateTimeOriginal=2026:03:03 12:16:29", photo.path,
    ])
    let jpeg = try Data(contentsOf: photo)
    try jpeg.replacing(Data("2026:03:03 12:16:29".utf8), with: Data("2026:03:03:12:16:29".utf8)).write(to: photo)
    try FileManager.default.setAttributes([.modificationDate: date("2026-03-03 12:16:29")], ofItemAtPath: photo.path)

    let bare = dcim.appendingPathComponent("PICT0002.JPG")
    try Shell.check(tools.ffmpeg!, ["-loglevel", "error", "-f", "lavfi", "-i", "testsrc=size=1440x1080", "-frames:v", "1", bare.path])
    try FileManager.default.setAttributes([.modificationDate: date("2026-03-03 12:18:00")], ofItemAtPath: bare.path)

    let video = dcim.appendingPathComponent("MOVI0001.AVI")
    try Shell.check(tools.ffmpeg!, [
        "-loglevel", "error", "-f", "lavfi", "-i", "testsrc=size=640x480:rate=30", "-f", "lavfi", "-i", "sine=sample_rate=16000",
        "-t", "3", "-c:v", "mjpeg", "-c:a", "pcm_s16le", "-ac", "1", video.path,
    ])
    try FileManager.default.setAttributes([.modificationDate: date("2026-03-03 12:20:05")], ofItemAtPath: video.path)

    FileManager.default.createFile(atPath: dcim.appendingPathComponent("._PICT0001.JPG").path, contents: Data())
    return root
}

@Test(.enabled(if: toolsInstalled, "needs exiftool and ffmpeg"))
func importsACharmeraCard() throws {
    let camera = try makeCamera()
    let output = camera.appendingPathComponent("Imported")
    defer { try? FileManager.default.removeItem(at: camera) }

    let files = try Scanner(exiftool: tools.exiftool, ffprobe: tools.ffprobe).scan(camera)
    #expect(files.map(\.name) == ["PICT0001.JPG", "PICT0002.JPG", "MOVI0001.AVI"])
    #expect(files[0].fix?.fixesDate == true)
    #expect(files[0].fix?.width == 1440)
    #expect(files[1].fix?.addsDate == true)
    #expect(abs(files[2].taken.timeIntervalSince(date("2026-03-03 12:20:02"))) < 0.5)

    let processor = Processor(tools: tools)
    let outputs = try files.map { try processor.process($0, into: output) { _ in } }
    #expect(outputs.map(\.lastPathComponent) == ["IMG_20260303_121629.jpg", "IMG_20260303_121800.jpg", "VID_20260303_122002.mp4"])
    #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).sorted() == outputs.map(\.lastPathComponent))

    let tags = try exif(outputs[0], ["ModifyDate", "DateTimeOriginal", "ExifImageWidth", "ExifImageHeight"])
    #expect(tags["ModifyDate"] as? String == "2026:03:03 12:16:29")
    #expect(tags["DateTimeOriginal"] as? String == "2026:03:03 12:16:29")
    #expect(tags["ExifImageWidth"] as? Int == 1440)
    #expect(tags["ExifImageHeight"] as? Int == 1080)

    let added = try exif(outputs[1], ["DateTimeOriginal", "CreateDate", "ModifyDate"])
    #expect(added["DateTimeOriginal"] as? String == "2026:03:03 12:18:00")
    #expect(added["CreateDate"] as? String == "2026:03:03 12:18:00")
    #expect(added["ModifyDate"] as? String == "2026:03:03 12:18:00")

    let probe = try Shell.check(tools.ffprobe!, [
        "-v", "error", "-show_entries", "stream=codec_name:format_tags=creation_time", "-of", "csv=p=0", outputs[2].path,
    ])
    let streams = String(decoding: probe, as: UTF8.self)
    #expect(streams.contains("h264"))
    #expect(streams.contains("aac"))
    let utc = ISO8601DateFormatter()
    let created = streams.split(separator: "\n").compactMap { utc.date(from: String($0.prefix(19)) + "Z") }.first
    #expect(created.map { abs($0.timeIntervalSince(date("2026-03-03 12:20:02"))) < 1 } == true)

    for (file, url) in zip(files, outputs) {
        let modified = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        #expect(modified.map { abs($0.timeIntervalSince(file.taken)) < 1 } == true)
    }
}
