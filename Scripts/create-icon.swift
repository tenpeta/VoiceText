import AppKit
import CoreGraphics
import CoreText

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
        let context = graphics.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let rect = CGRect(x: 65, y: 65, width: 894, height: 894)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 198, cornerHeight: 198, transform: nil)); context.clip()
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [NSColor.systemIndigo.cgColor, NSColor(calibratedRed: 0.13, green: 0.27, blue: 0.72, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 130, y: 950), end: CGPoint(x: 920, y: 80), options: [])
        let text = "文" as NSString
        let font = NSFont(name: "PingFangSC-Semibold", size: 530) ?? .systemFont(ofSize: 530, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let measured = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (1024 - measured.width) / 2, y: 285), withAttributes: attributes)
        context.setStrokeColor(NSColor(calibratedRed: 0.48, green: 0.94, blue: 0.86, alpha: 1).cgColor)
        context.setLineWidth(26); context.setLineCap(.round)
        for (i, height) in [34.0, 76, 118, 58, 92, 40, 68].enumerated() {
            let x = 350 + CGFloat(i) * 54
            context.move(to: CGPoint(x: x, y: 228 - height / 2)); context.addLine(to: CGPoint(x: x, y: 228 + height / 2)); context.strokePath()
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}

// A single vector template is shared by the input menu and switcher.
// The character is cut out so the system can tint the keycap in either appearance.
let iconURL = root.appendingPathComponent("Resources/InputSourceIcon.pdf")
var mediaBox = CGRect(x: 0, y: 0, width: 22, height: 16)
let pdf = CGContext(iconURL as CFURL, mediaBox: &mediaBox, nil)!
pdf.beginPDFPage(nil)
let outline = CGMutablePath()
outline.addRoundedRect(in: mediaBox, cornerWidth: 4, cornerHeight: 4)
let font = CTFontCreateWithName("PingFangSC-Semibold" as CFString, 12, nil)
var character: UniChar = 0x6587 // 文
var glyph: CGGlyph = 0
precondition(CTFontGetGlyphsForCharacters(font, &character, &glyph, 1))
let characterPath = CTFontCreatePathForGlyph(font, glyph, nil)!
let bounds = characterPath.boundingBoxOfPath
let position = CGAffineTransform(translationX: 11 - bounds.midX, y: 8 - bounds.midY)
outline.addPath(characterPath, transform: position)
pdf.addPath(outline)
pdf.setFillColor(NSColor.black.cgColor)
pdf.drawPath(using: .eoFill)
pdf.endPDFPage()
pdf.closePDF()
