import AppKit

let iconset = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let size = CGFloat(pixels)
    let tile = NSRect(x: 0, y: 0, width: size, height: size).insetBy(dx: size * 0.1, dy: size * 0.1)
    let shape = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(starting: NSColor(calibratedRed: 0.99, green: 0.75, blue: 0.10, alpha: 1), ending: NSColor(calibratedRed: 0.89, green: 0.20, blue: 0.12, alpha: 1))!
        .draw(in: shape, angle: -90)

    let configuration = NSImage.SymbolConfiguration(pointSize: tile.width * 0.5, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
        let scale = tile.width * 0.56 / max(symbol.size.width, symbol.size.height)
        let symbolSize = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
        symbol.draw(in: NSRect(x: tile.midX - symbolSize.width / 2, y: tile.midY - symbolSize.height / 2, width: symbolSize.width, height: symbolSize.height))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: iconset.appending(path: "icon_\(points)x\(points).png"))
    try render(pixels: points * 2).write(to: iconset.appending(path: "icon_\(points)x\(points)@2x.png"))
}
