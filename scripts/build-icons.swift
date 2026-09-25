import AppKit

// Preserve the official artwork; remove only its transparent page margins.
let source = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: "Assets/KHUSeal.png")))!
var left = source.pixelsWide, top = source.pixelsHigh, right = 0, bottom = 0
for y in 0..<source.pixelsHigh {
    for x in 0..<source.pixelsWide where source.colorAt(x: x, y: y)!.alphaComponent > 0 {
        left = min(left, x); right = max(right, x)
        top = min(top, y); bottom = max(bottom, y)
    }
}
let glyph = source.cgImage!.cropping(to: CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1))!
let seal = NSImage(cgImage: glyph, size: NSSize(width: glyph.width, height: glyph.height))
let resources = "build/CampusBar.app/Contents/Resources"
let iconset = ".build/CampusBar.iconset"
try FileManager.default.createDirectory(atPath: resources, withIntermediateDirectories: true)
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

func render(width: Int, height: Int, appIcon: Bool, path: String) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    let canvas = NSRect(x: 0, y: 0, width: width, height: height)
    if appIcon {
        NSColor.white.setFill()
        let tile = canvas.insetBy(dx: CGFloat(width) * 0.06, dy: CGFloat(height) * 0.06)
        NSBezierPath(roundedRect: tile, xRadius: CGFloat(width) * 0.19, yRadius: CGFloat(height) * 0.19).fill()
    }
    let scale = min(CGFloat(width) / seal.size.width, CGFloat(height) / seal.size.height) * (appIcon ? 0.72 : 1)
    let size = NSSize(width: seal.size.width * scale, height: seal.size.height * scale)
    seal.draw(in: NSRect(x: (CGFloat(width) - size.width) / 2, y: (CGFloat(height) - size.height) / 2,
                        width: size.width, height: size.height))
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

for size in [16, 32, 128, 256, 512] {
    try render(width: size, height: size, appIcon: true, path: "\(iconset)/icon_\(size)x\(size).png")
    try render(width: size * 2, height: size * 2, appIcon: true, path: "\(iconset)/icon_\(size)x\(size)@2x.png")
}
try render(width: 22, height: 15, appIcon: false, path: "\(resources)/MenuIcon.png")
try render(width: 44, height: 30, appIcon: false, path: "\(resources)/MenuIcon@2x.png")
