// Deterministic offline visual check: no capture permission or moving lid required.
// Usage: make render-test. PNGs and results.txt land in build/render-test-out.
import AppKit
import Metal

enum RenderTestError: Error { case failed(String) }
func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw RenderTestError.failed(message) }
}
let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/render-test-out")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let width = 1280, height = 832
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

/// Fixed type, light/dark windows, widgets and icons expose focus quality at every height.
func syntheticDesktop() throws -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    try bytes.withUnsafeMutableBytes { storage in
        guard let ctx = CGContext(data: storage.baseAddress, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: colorSpace, bitmapInfo: bitmapInfo) else {
            throw RenderTestError.failed("Could not create fixture bitmap")
        }
        // Top-left coordinates, with this exact BGRA buffer uploaded directly to Metal.
        ctx.translateBy(x: 0, y: CGFloat(height)); ctx.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        defer { NSGraphicsContext.restoreGraphicsState() }
        func rounded(_ rect: CGRect, _ radius: CGFloat, _ fill: CGColor) {
            ctx.setFillColor(fill)
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.fillPath()
        }
        func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat,
                  _ fill: UInt32 = 0x232331, weight: NSFont.Weight = .regular, mono: Bool = false) {
            let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
                            : NSFont.systemFont(ofSize: size, weight: weight)
            (value as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [
                .font: font, .foregroundColor: NSColor(cgColor: color(fill))!
            ])
        }
        func line(_ x: CGFloat, _ y: CGFloat, _ length: CGFloat, _ fill: CGColor) {
            ctx.setFillColor(fill); ctx.fill(CGRect(x: x, y: y, width: length, height: 1))
        }
        func window(_ rect: CGRect, dark: Bool, title: String) {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 32, color: color(0x100F24, 0.35))
            rounded(rect, 14, color(dark ? 0x20202D : 0xFCFAFC))
            ctx.restoreGState(); ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 14, cornerHeight: 14, transform: nil)); ctx.clip()
            ctx.setFillColor(color(dark ? 0x2D2C3B : 0xF1EDF3))
            ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 43))
            ctx.restoreGState()
            let dots: [UInt32] = [0xFF6058, 0xFEBC2E, 0x28C840]
            for (i, hex) in dots.enumerated() {
                ctx.setFillColor(color(hex))
                ctx.fillEllipse(in: CGRect(x: rect.minX + 17 + CGFloat(i) * 19, y: rect.minY + 16, width: 11, height: 11))
            }
            text(title, rect.minX + 98, rect.minY + 12, 13, dark ? 0xDCD8E9 : 0x5F5968, weight: .medium)
        }
        let gradient = CGGradient(colorsSpace: colorSpace,
            colors: [color(0x171A38), color(0x6B4A75), color(0xDA8DAB), color(0x402748)] as CFArray,
            locations: [0, 0.38, 0.65, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
        let distant = CGMutablePath()
        distant.move(to: CGPoint(x: 0, y: 615))
        distant.addCurve(to: CGPoint(x: 1280, y: 450), control1: CGPoint(x: 500, y: 175), control2: CGPoint(x: 795, y: 720))
        distant.addLine(to: CGPoint(x: 1280, y: 832)); distant.addLine(to: CGPoint(x: 0, y: 832)); distant.closeSubpath()
        ctx.addPath(distant); ctx.setFillColor(color(0x322338)); ctx.fillPath()
        let dune = CGMutablePath()
        dune.move(to: CGPoint(x: 0, y: 795))
        dune.addCurve(to: CGPoint(x: 1280, y: 586), control1: CGPoint(x: 465, y: 820), control2: CGPoint(x: 704, y: 348))
        dune.addLine(to: CGPoint(x: 1280, y: 832)); dune.addLine(to: CGPoint(x: 0, y: 832)); dune.closeSubpath()
        ctx.addPath(dune); ctx.setFillColor(color(0x1E1B2C)); ctx.fillPath()
        ctx.setFillColor(color(0x171627, 0.40)); ctx.fill(CGRect(x: 0, y: 0, width: width, height: 30))
        text("●", 21, 5, 14, 0xFFFFFF, weight: .semibold)
        text("Bendy", 52, 6, 13, 0xFFFFFF, weight: .bold)
        text("File     Edit     View     Window     Help", 115, 6, 13, 0xF4ECF7)
        text("Fri Sep 11     9:41 AM", 1101, 6, 12, 0xF4ECF7, weight: .medium)
        rounded(CGRect(x: 43, y: 65, width: 186, height: 153), 22, color(0x254A7E, 0.91))
        text("Cupertino", 60, 82, 16, 0xEFF5FF, weight: .medium)
        text("72°", 59, 104, 43, 0xFFFFFF, weight: .light)
        text("☀  Sunny", 61, 163, 15, 0xF6E4A0)
        text("H:76°  L:58°", 61, 187, 12, 0xD6E8FF)
        rounded(CGRect(x: 245, y: 65, width: 186, height: 153), 22, color(0xF7DAE5, 0.94))
        text("FRIDAY", 263, 84, 12, 0xA64365, weight: .semibold)
        text("11", 260, 103, 44, 0x442738, weight: .light)
        rounded(CGRect(x: 263, y: 166, width: 3, height: 33), 1.5, color(0xA65286))
        text("Design review", 275, 165, 13, 0x442738, weight: .semibold)
        text("10:30–11:00 AM", 275, 184, 11, 0x865F76)
        text("DESKTOP / TOP EDGE", 978, 65, 12, 0xFBE4F4, weight: .semibold, mono: true)
        window(CGRect(x: 68, y: 251, width: 728, height: 412), dark: false, title: "Studio Notes")
        text("A little room to focus.", 98, 318, 28, 0x272331, weight: .semibold)
        text("Ideas become clearer when everything else falls away.", 99, 363, 15, 0x706775)
        line(99, 404, 661, color(0xE8E1EB))
        text("TODAY", 99, 425, 11, 0x97768E, weight: .bold)
        let tasks = ["Refine the first impression", "Give every detail a purpose", "Keep the important things in focus", "Make the transition feel effortless"]
        for (i, task) in tasks.enumerated() {
            let y = 457 + CGFloat(i) * 39
            rounded(CGRect(x: 100, y: y + 2, width: 16, height: 16), 5, color(i == 0 ? 0xA274AA : 0xEBE5EF))
            if i == 0 { text("✓", 102, y, 12, 0xFFFFFF, weight: .bold) }
            text(task, 131, y, 15, 0x4C4353)
        }
        text("Updated just now", 100, 629, 11, 0xA296A6)
        window(CGRect(x: 710, y: 308, width: 512, height: 393), dark: true, title: "Quiet hours — Now Playing")
        let album = CGGradient(colorsSpace: colorSpace,
            colors: [color(0xC880A9), color(0x6D629D), color(0x293A5C)] as CFArray, locations: [0, 0.5, 1])!
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: CGRect(x: 739, y: 382, width: 128, height: 128), cornerWidth: 12, cornerHeight: 12, transform: nil)); ctx.clip()
        ctx.drawLinearGradient(album, start: CGPoint(x: 739, y: 382), end: CGPoint(x: 867, y: 510), options: [])
        ctx.setFillColor(color(0xF0C5D9, 0.70)); ctx.fillEllipse(in: CGRect(x: 763, y: 405, width: 67, height: 67))
        ctx.restoreGState()
        text("Evening light", 890, 399, 22, 0xF4EBF7, weight: .semibold)
        text("A softer kind of sound", 891, 433, 13, 0xB9A9C9)
        text("Ambient / 2026", 891, 462, 11, 0x8C819B)
        line(740, 540, 452, color(0x454052)); line(740, 540, 177, color(0xD6ACD4))
        ctx.setFillColor(color(0xF6D9EE)); ctx.fillEllipse(in: CGRect(x: 912, y: 536, width: 9, height: 9))
        text("1:42", 740, 550, 11, 0xA899B7, mono: true); text("4:18", 1164, 550, 11, 0xA899B7, mono: true)
        text("◀◀       Ⅱ       ▶▶", 864, 589, 23, 0xEADBED, weight: .medium)
        text("FOCUS MIX", 741, 657, 10, 0x9985A8, weight: .semibold); text("Lossless", 1137, 657, 10, 0x9985A8)
        text("MACBOOK HINGE / BOTTOM EDGE", 33, 796, 10, 0xD2B9D5, mono: true)
        rounded(CGRect(x: 346, y: 745, width: 587, height: 72), 22, color(0xE2D7E8, 0.35))
        let icons: [(UInt32, String)] = [(0x429AD8, "↔"), (0xE7EDF2, "◉"), (0x428FE9, "@"), (0xF2F1E9, "11"),
            (0xF4C453, "≡"), (0x52B768, "●"), (0xCE6099, "♫"), (0x5395D9, "A"), (0x7E7F8D, "⚙")]
        for (i, icon) in icons.enumerated() {
            let x = 361 + CGFloat(i) * 62
            rounded(CGRect(x: x, y: 757, width: 49, height: 49), 12, color(icon.0))
            text(icon.1, x + (i == 3 ? 9 : 11), 764, 27, i == 1 || i == 3 || i == 4 ? 0x3F4052 : 0xFFFFFF, weight: .medium)
        }
        // Subtle alternating ticks give the actual bottom two pixel rows spatial detail.
        for i in 0..<16 {
            ctx.setFillColor(color(i.isMultiple(of: 2) ? 0x1E1B2C : 0x302C42))
            ctx.fill(CGRect(x: i * 80, y: height - 2, width: 80, height: 2))
        }
    }
    return bytes
}
func save(_ bytes: [UInt8], _ name: String) throws {
    guard let provider = CGDataProvider(data: Data(bytes) as CFData),
          let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                              bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                              provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw RenderTestError.failed("Could not encode \(name)")
    }
    try png.write(to: outDir.appendingPathComponent(name))
}
guard let device = MTLCreateSystemDefaultDevice(), let renderer = BendRenderer(device: device) else {
    throw RenderTestError.failed("Metal device or bend renderer is unavailable")
}
let sourceBytes = try syntheticDesktop()
try require(stride(from: 3, to: sourceBytes.count, by: 4).allSatisfy { sourceBytes[$0] == 255 }, "Fixture must be opaque BGRA")
try save(sourceBytes, "source-desktop.png")
let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
descriptor.usage = [.shaderRead]; descriptor.storageMode = .shared
guard let source = device.makeTexture(descriptor: descriptor) else { throw RenderTestError.failed("Could not create source texture") }
sourceBytes.withUnsafeBytes { buffer in
    source.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: buffer.baseAddress!, bytesPerRow: width * 4)
}
func render(_ uniforms: BendUniforms, with renderer: BendRenderer) throws -> [UInt8] {
    guard let texture = renderer.renderOffscreen(source: source, uniforms: uniforms, width: width, height: height) else {
        throw RenderTestError.failed("Offscreen rendering failed")
    }
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
    try require(stride(from: 3, to: bytes.count, by: 4).allSatisfy { bytes[$0] == 255 }, "Rendered output must remain opaque")
    return bytes
}
func validate(_ u: BendUniforms) throws {
    for vector in [u.p0, u.p1, u.p2, u.p3] {
        try require((0..<4).allSatisfy { vector[$0].isFinite }, "Uniforms must be finite")
    }
    try require(u.p0.z > 0 && u.p0.w > 0, "Eye must be above and in front of hinge")
    try require((0..<4).allSatisfy { (0...1).contains(u.p2[$0]) }, "Effect controls must stay in 0…1")
    try require((0...1).contains(u.p3.x), "Keystone must stay in 0…1")
}
struct RenderCase {
    let name: String
    let tilt: Double
    var clearAngle: Double = 90
    var perspective: Double = 0.58
    var blur: Double = 0.85
    var shadow: Double = 0.28
    var keystone: Double = 0.4
    var optics: BendOptics = .duo
    var uniforms: BendUniforms {
        BendMath.uniforms(tilt: tilt, clearAngle: clearAngle,
                          eye: BendMath.eye(perspective: perspective, heightRatio: 0.5),
                          blur: blur, shadow: shadow, keystone: keystone, optics: optics)
    }
}
// Identity is a pixel-level promise, including at unusual clear angles.
var maximumIdentityError = 0
for clearAngle in [40.0, 90.0, 115.0] {
    for optics in BendOptics.allCases {
        let u = RenderCase(name: "identity", tilt: 0, clearAngle: clearAngle, optics: optics).uniforms
        try validate(u)
        let actual = try render(u, with: renderer)
        let error = zip(sourceBytes, actual).reduce(0) { max($0, abs(Int($1.0) - Int($1.1))) }
        maximumIdentityError = max(maximumIdentityError, error)
        // One 8-bit level allows texture-filter rounding; any blur or shading fails.
        try require(error <= 1, "Identity differs by \(error) at clear angle \(clearAngle), optics \(optics)")
    }
}
var validatedUniformSets = 0
for clearAngle in [40.0, 90.0, 115.0] {
    for tilt in [-5.0, 0, 8, 20, 35, 50, 90, 180] {
        for perspective in [0.0, 0.5, 1] {
            for optics in BendOptics.allCases {
                try validate(RenderCase(name: "bounds", tilt: tilt, clearAngle: clearAngle, perspective: perspective, optics: optics).uniforms)
                validatedUniformSets += 1
            }
        }
    }
}
let cases: [RenderCase] = [
    RenderCase(name: "00-duo-flat", tilt: 0),
    RenderCase(name: "01-duo-closed08", tilt: 8),
    RenderCase(name: "02-duo-closed20", tilt: 20),
    RenderCase(name: "03-duo-closed35", tilt: 35),
    RenderCase(name: "04-duo-closed50", tilt: 50),
    RenderCase(name: "05-duo-clear40-closed08", tilt: 8, clearAngle: 40),
    RenderCase(name: "06-duo-clear115-closed35", tilt: 35, clearAngle: 115),
    RenderCase(name: "07-duo-no-blur", tilt: 35, blur: 0),
    RenderCase(name: "08-duo-no-shadow", tilt: 35, shadow: 0),
    RenderCase(name: "09-duo-no-blur-or-shadow", tilt: 35, blur: 0, shadow: 0),
    RenderCase(name: "10-silk-closed30", tilt: 30, perspective: 0.72, blur: 0.25, shadow: 0.25, optics: .glass),
    RenderCase(name: "11-frost-closed40", tilt: 40, perspective: 0.62, blur: 0.90, shadow: 0.30, optics: .glass),
    RenderCase(name: "12-shade-closed30", tilt: 30, perspective: 0.75, blur: 0.15, shadow: 0.85, optics: .glass),
    RenderCase(name: "13-silk-keystone1", tilt: 30, perspective: 0.55, blur: 0.25, shadow: 0.25, keystone: 1, optics: .glass),
    RenderCase(name: "14-trueduo-closed08", tilt: 8, optics: .trueDuo),
    RenderCase(name: "15-trueduo-closed20", tilt: 20, optics: .trueDuo),
    RenderCase(name: "16-trueduo-closed35", tilt: 35, optics: .trueDuo),
    RenderCase(name: "17-trueduo-closed50", tilt: 50, optics: .trueDuo),
    RenderCase(name: "18-trueduo-clear115-closed35", tilt: 35, clearAngle: 115, optics: .trueDuo),
    RenderCase(name: "19-trueduo-flat-perspective", tilt: 35, perspective: 0.0, optics: .trueDuo),
    RenderCase(name: "20-trueduo-no-blur", tilt: 35, blur: 0, optics: .trueDuo)
]
for test in cases {
    try validate(test.uniforms)
    try save(render(test.uniforms, with: renderer), "\(test.name).png")
    print("wrote \(test.name).png")
}
// The bottom hinge remains fixed while content higher on the panel moves and diffuses.
// The last two rows contain low-contrast ticks, so this also catches horizontal displacement.
let hinged = try render(RenderCase(name: "hinge", tilt: 20).uniforms, with: renderer)
let hingeStart = (height - 2) * width * 4
let hingeError = (hingeStart..<sourceBytes.count).reduce(0) {
    max($0, abs(Int(sourceBytes[$1]) - Int(hinged[$1])))
}
try require(hingeError <= 4, "Bottom hinge moved or diffused excessively: \(hingeError)/255 channel error")
// True Duo shows the desktop as a rectangle standing in space: the hinge stays anchored, the
// sides pull in as the lid comes down, and what the glass no longer covers dissolves into black
// over a soft band rather than ending on a line or smearing the edge pixels outward.
func rowBrightness(_ row: Int, in rendered: [UInt8]) -> Int {
    stride(from: row * width * 4, to: (row + 1) * width * 4, by: 4).reduce(0) {
        max($0, Int(rendered[$1]), Int(rendered[$1 + 1]), Int(rendered[$1 + 2]))
    }
}
func pixelBrightness(_ x: Int, _ y: Int, in rendered: [UInt8]) -> Int {
    let i = (y * width + x) * 4
    return max(Int(rendered[i]), Int(rendered[i + 1]), Int(rendered[i + 2]))
}
func hingeError(_ rendered: [UInt8]) -> Int {
    ((height - 2) * width * 4..<rendered.count).reduce(0) {
        max($0, abs(Int(sourceBytes[$1]) - Int(rendered[$1])))
    }
}
var narrowestFade = Int.max
var widestWedge = 0
var trueDuoHinge = 0
for tilt in [35.0, 50] {
    let panel = try render(RenderCase(name: "trueduo", tilt: tilt, optics: .trueDuo).uniforms, with: renderer)
    // The hinge stays anchored and clear. Exact keystone resamples the bottom rows by a
    // fraction of a pixel, so the tick pattern there lands a couple of levels off Duo's.
    let hinge = hingeError(panel)
    let duo = try render(RenderCase(name: "duo", tilt: tilt, optics: .duo).uniforms, with: renderer)
    let duoHinge = hingeError(duo)
    trueDuoHinge = max(trueDuoHinge, hinge)
    try require(hinge <= 8,
                "True Duo moved the hinge at \(tilt)°: \(hinge)/255 versus Duo's \(duoHinge)/255")
    for corner in [0, width - 1] {
        try require(pixelBrightness(corner, 0, in: panel) <= 2,
                    "True Duo top corner \(corner) is not black at \(tilt)°: \(pixelBrightness(corner, 0, in: panel))/255")
    }
    // A quarter of the way down, the side wedge meets the picture. Scanning inward, black has
    // to give way gradually. The threshold follows the row's own content rather than a fixed
    // level, since what the screen shows up there is the fixture's own business.
    let row = (0..<width).map { pixelBrightness($0, height / 4, in: panel) }
    let full = row.max() ?? 0
    try require(full > 8, "True Duo is entirely black a quarter down at \(tilt)°")
    guard let darkEnd = row.firstIndex(where: { $0 > 4 }),
          let lit = row.firstIndex(where: { Double($0) >= Double(full) * 0.6 }) else {
        throw RenderTestError.failed("True Duo never reaches lit content at \(tilt)°")
    }
    narrowestFade = min(narrowestFade, lit - darkEnd)
    widestWedge = max(widestWedge, lit)
    try require(lit - darkEnd >= 8,
                "True Duo edge is a hard cut at \(tilt)°: black to lit in \(lit - darkEnd) pixels")
    try require(rowBrightness(height / 2, in: panel) > 20, "True Duo went dark across the middle at \(tilt)°")
    // The screen keeps its full height: the top of the panel shows the top of the desktop, which
    // in the fixture is its dark menu bar. Duo, cropping and magnifying, shows the middle of the
    // desktop up there instead — the white notes window.
    try require(pixelBrightness(width / 2, 0, in: panel) < 100,
                "True Duo is not showing the top of the desktop at \(tilt)°: \(pixelBrightness(width / 2, 0, in: panel))/255")
    try require(pixelBrightness(width / 2, 0, in: duo) > 200, "Duo stopped cropping; the fixture or Duo changed")
}
// Duo at the same tilt keeps filling the panel, so the two styles really do differ.
let duoPanel = try render(RenderCase(name: "duo-corner", tilt: 35, optics: .duo).uniforms, with: renderer)
try require(pixelBrightness(0, 0, in: duoPanel) > 8, "Duo's corner went black; True Duo's fade leaked into Duo")
// Switching blur/shadow off must not retain cached effects from the preceding frame.
let disabled = RenderCase(name: "disabled", tilt: 35, blur: 0, shadow: 0).uniforms
_ = try render(RenderCase(name: "warm-cache", tilt: 50, blur: 1, shadow: 1).uniforms, with: renderer)
let warmed = try render(disabled, with: renderer)
guard let freshRenderer = BendRenderer(device: device) else { throw RenderTestError.failed("Could not initialize comparison renderer") }
let fresh = try render(disabled, with: freshRenderer)
try require(warmed == fresh, "Blur/shadow disabled depends on a previous rendered frame")
let report = """
PASS — identity maximum channel error: \(maximumIdentityError)/255 (nine clear-angle/optics combinations)
PASS — \(validatedUniformSets) uniform sets finite and bounded
PASS — fixture and all rendered frames have opaque alpha
PASS — bottom hinge maximum channel error at 20° closure: \(hingeError)/255
PASS — True Duo hinge no worse than Duo's (\(trueDuoHinge)/255) and top corners black at 35° and 50° closure; the dissolve spans at least \(narrowestFade) pixels inside a wedge up to \(widestWedge) wide, the screen keeps its full height where Duo has cropped its top away
PASS — disabling blur and shadow is independent of the previous frame
Rendered \(cases.count) named previews plus source-desktop.png at \(width) × \(height).
The menu bar marks the top; the dock and hinge label mark the bottom.

"""
try report.write(to: outDir.appendingPathComponent("results.txt"), atomically: true, encoding: .utf8)
print(report)
