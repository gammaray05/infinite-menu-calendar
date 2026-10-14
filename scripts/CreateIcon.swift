import AppKit

let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        NSColor(srgbRed: 0.15, green: 0.4, blue: 0.9, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 210, yRadius: 210).fill()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: 210, y: 210, width: 604, height: 604), xRadius: 65, yRadius: 65).fill()
        NSColor(srgbRed: 0.1, green: 0.3, blue: 0.72, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 210, y: 675, width: 604, height: 139), xRadius: 55, yRadius: 55).fill()
        for x in [355, 665] {
            NSColor.white.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: 744, width: 32, height: 135), xRadius: 16, yRadius: 16).fill()
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 310, weight: .medium),
            .foregroundColor: NSColor(srgbRed: 0.1, green: 0.3, blue: 0.72, alpha: 1)]
        let text = "∞" as NSString
        let textSize = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: 512 - textSize.width / 2, y: 280), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let url = URL(fileURLWithPath: directory).appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }
}
