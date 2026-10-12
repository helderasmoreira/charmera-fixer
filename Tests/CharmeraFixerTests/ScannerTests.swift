import Foundation
import Testing
@testable import CharmeraFixer

@Test func fixesTheSixPartCharmeraDate() {
    #expect(Scanner.fixDate("2026:03:03:12:16:29") == "2026:03:03 12:16:29")
}

@Test(arguments: [nil, "2026:03:03 12:16:29", "2026:03:03", ""])
func leavesOtherDatesAlone(_ raw: String?) {
    #expect(Scanner.fixDate(raw) == nil)
}

@Test func correctsADimensionThatDiffersFromTheImage() {
    #expect(Scanner.fixDimension(640, actual: 1440) == 1440)
}

@Test func leavesMatchingOrMissingDimensionsAlone() {
    #expect(Scanner.fixDimension(1440, actual: 1440) == nil)
    #expect(Scanner.fixDimension(nil, actual: 1440) == nil)
    #expect(Scanner.fixDimension(640, actual: nil) == nil)
}

@Test func describesPhotoFixes() {
    var file = CameraFile(source: URL(fileURLWithPath: "/DCIM/PICT0001.JPG"), kind: .photo, size: 0, taken: Date())
    #expect(file.fixDescription == "None needed")

    file.fix = ExifFix(modifyDate: "2026:03:03 12:16:29", width: 1440, height: 1080, originalWidth: 640, originalHeight: 480)
    #expect(file.fixDescription == "Date format, Size 640×480 → 1440×1080")
}
