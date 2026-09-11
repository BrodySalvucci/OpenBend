// Renders the OpenBend app icon (a laptop with a bending screen) to an .icns.
// Usage: swift scripts/make-icon.swift build/AppIcon.icns
import AppKit

func draw(size: CGFloat) -> CGImage? {
    let px = Int(size)
    guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    let s = size
    ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))

    // Squircle background.
    let inset = s * 0.055
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let bg = CGPath(roundedRect: rect, cornerWidth: s * 0.21, cornerHeight: s * 0.21, transform: nil)
    ctx.addPath(bg); ctx.clip()
    let colors = [CGColor(red: 0.17, green: 0.19, blue: 0.36, alpha: 1), CGColor(red: 0.04, green: 0.04, blue: 0.08, alpha: 1)] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

    // Keyboard deck.
    let deckY = s * 0.28
    let deck = CGRect(x: s * 0.16, y: deckY, width: s * 0.68, height: s * 0.05)
    ctx.setFillColor(CGColor(red: 0.82, green: 0.84, blue: 0.9, alpha: 1))
    ctx.addPath(CGPath(roundedRect: deck, cornerWidth: s * 0.02, cornerHeight: s * 0.02, transform: nil)); ctx.fillPath()

    // Bending screen: a keystone whose top edge has swung back and shrunk.
    let bottomL = CGPoint(x: s * 0.22, y: deckY + s * 0.05)
    let bottomR = CGPoint(x: s * 0.78, y: deckY + s * 0.05)
    let topL = CGPoint(x: s * 0.31, y: s * 0.66)
    let topR = CGPoint(x: s * 0.69, y: s * 0.66)
    let screen = CGMutablePath()
    screen.move(to: bottomL); screen.addLine(to: bottomR); screen.addLine(to: topR); screen.addLine(to: topL); screen.closeSubpath()
    ctx.saveGState()
    ctx.addPath(screen); ctx.clip()
    let screenColors = [CGColor(red: 0.55, green: 0.75, blue: 1.0, alpha: 1), CGColor(red: 0.25, green: 0.4, blue: 0.85, alpha: 1)] as CFArray
    let sg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: screenColors, locations: [0, 1])!
    ctx.drawLinearGradient(sg, start: CGPoint(x: 0, y: bottomL.y), end: CGPoint(x: 0, y: topL.y), options: [])
    // Shade toward the top, like the lid's shadow.
    let shade = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.55)] as CFArray, locations: [0.35, 1])!
    ctx.drawLinearGradient(shade, start: CGPoint(x: 0, y: bottomL.y), end: CGPoint(x: 0, y: topL.y), options: [])
    ctx.restoreGState()
    ctx.addPath(screen)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.55))
    ctx.setLineWidth(max(1, s * 0.012)); ctx.strokePath()

    return ctx.makeImage()
}

let args = CommandLine.arguments
guard args.count > 1 else { print("usage: make-icon.swift <out.icns>"); exit(1) }
let out = URL(fileURLWithPath: args[1])
let iconset = out.deletingPathExtension().appendingPathExtension("iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = CGFloat(base * scale)
        guard let image = draw(size: px) else { continue }
        let rep = NSBitmapImageRep(cgImage: image)
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try task.run(); task.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(task.terminationStatus == 0 ? "wrote \(out.path)" : "iconutil failed")
exit(task.terminationStatus)
