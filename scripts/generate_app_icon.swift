import AppKit
import Foundation

struct IconPalette {
    static let shellTop = NSColor(calibratedRed: 0.93, green: 0.95, blue: 0.98, alpha: 1)
    static let shellBottom = NSColor(calibratedRed: 0.77, green: 0.82, blue: 0.89, alpha: 1)
    static let shellEdge = NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.42)
    static let menuBarTop = NSColor(calibratedRed: 0.18, green: 0.20, blue: 0.23, alpha: 0.96)
    static let menuBarBottom = NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.15, alpha: 0.98)
    static let notch = NSColor(calibratedRed: 0.04, green: 0.04, blue: 0.05, alpha: 1)
    static let dialTop = NSColor(calibratedRed: 0.99, green: 1.0, blue: 1.0, alpha: 0.98)
    static let dialBottom = NSColor(calibratedRed: 0.90, green: 0.93, blue: 0.98, alpha: 0.96)
    static let dialStroke = NSColor(calibratedRed: 0.18, green: 0.22, blue: 0.29, alpha: 0.18)
    static let hand = NSColor(calibratedRed: 0.14, green: 0.17, blue: 0.24, alpha: 0.95)
    static let accentStart = NSColor(calibratedRed: 0.20, green: 0.67, blue: 0.99, alpha: 1)
    static let accentEnd = NSColor(calibratedRed: 0.25, green: 0.88, blue: 0.77, alpha: 1)
    static let status = NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.45)
}

let fileManager = FileManager.default
let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let resourcesDirectory = root.appendingPathComponent("Resources", isDirectory: true)
let iconsetDirectory = resourcesDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let icnsFile = resourcesDirectory.appendingPathComponent("AppIcon.icns")

try fileManager.createDirectory(at: resourcesDirectory, withIntermediateDirectories: true)
if fileManager.fileExists(atPath: iconsetDirectory.path) {
    try fileManager.removeItem(at: iconsetDirectory)
}
try fileManager.createDirectory(at: iconsetDirectory, withIntermediateDirectories: true)

let requestedFiles: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for item in requestedFiles {
    let data = try drawIcon(pixelSize: item.pixels)
    try data.write(to: iconsetDirectory.appendingPathComponent(item.name), options: .atomic)
}

try writeICNS()

print("Generated iconset at \(iconsetDirectory.path)")
print("Generated icns at \(icnsFile.path)")

func drawIcon(pixelSize: Int) throws -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    rep.size = NSSize(width: pixelSize, height: pixelSize)

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        throw NSError(domain: "IconGeneration", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create graphics context"])
    }
    NSGraphicsContext.current = context

    let rect = NSRect(x: 0, y: 0, width: CGFloat(pixelSize), height: CGFloat(pixelSize))
    NSColor.clear.setFill()
    rect.fill()

    drawShell(in: rect)
    drawMenuBar(in: rect)
    drawDial(in: rect)

    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGeneration", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to encode icon PNG"])
    }
    return data
}

func writeICNS() throws {
    let representations: [(type: String, filename: String)] = [
        ("icp4", "icon_16x16.png"),
        ("icp5", "icon_32x32.png"),
        ("icp6", "icon_32x32@2x.png"),
        ("ic07", "icon_128x128.png"),
        ("ic08", "icon_256x256.png"),
        ("ic09", "icon_512x512.png"),
        ("ic10", "icon_512x512@2x.png"),
    ]

    var chunks: [Data] = []

    for representation in representations {
        let fileURL = iconsetDirectory.appendingPathComponent(representation.filename)
        let pngData = try Data(contentsOf: fileURL)

        var chunk = Data()
        chunk.append(representation.type.data(using: .ascii)!)
        chunk.append(uint32Data(UInt32(pngData.count + 8)))
        chunk.append(pngData)
        chunks.append(chunk)
    }

    let totalLength = 8 + chunks.reduce(0) { $0 + $1.count }
    var icnsData = Data()
    icnsData.append("icns".data(using: .ascii)!)
    icnsData.append(uint32Data(UInt32(totalLength)))
    chunks.forEach { icnsData.append($0) }

    try icnsData.write(to: icnsFile, options: .atomic)
}

func uint32Data(_ value: UInt32) -> Data {
    var bigEndian = value.bigEndian
    return Data(bytes: &bigEndian, count: MemoryLayout<UInt32>.size)
}

func drawShell(in rect: NSRect) {
    let shellRect = rect.insetBy(dx: rect.width * 0.07, dy: rect.height * 0.07)
    let shellRadius = rect.width * 0.225
    let shellPath = NSBezierPath(roundedRect: shellRect, xRadius: shellRadius, yRadius: shellRadius)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.16)
    shadow.shadowBlurRadius = rect.width * 0.035
    shadow.shadowOffset = NSSize(width: 0, height: -rect.height * 0.018)
    shadow.set()

    let shellGradient = NSGradient(colors: [IconPalette.shellTop, IconPalette.shellBottom])!
    shellGradient.draw(in: shellPath, angle: 90)

    NSGraphicsContext.saveGraphicsState()
    shellPath.addClip()
    let bloomRect = shellRect.insetBy(dx: rect.width * 0.03, dy: rect.height * 0.03)
    let bloomGradient = NSGradient(
        starting: NSColor(calibratedWhite: 1, alpha: 0.30),
        ending: NSColor(calibratedWhite: 1, alpha: 0.0)
    )!
    bloomGradient.draw(fromCenter: NSPoint(x: bloomRect.midX, y: bloomRect.maxY - rect.height * 0.04),
                       radius: 0,
                       toCenter: NSPoint(x: bloomRect.midX, y: bloomRect.maxY - rect.height * 0.04),
                       radius: rect.width * 0.46,
                       options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])
    NSGraphicsContext.restoreGraphicsState()

    IconPalette.shellEdge.setStroke()
    shellPath.lineWidth = max(2, rect.width * 0.0045)
    shellPath.stroke()
}

func drawMenuBar(in rect: NSRect) {
    let panelRect = NSRect(
        x: rect.width * 0.15,
        y: rect.height * 0.68,
        width: rect.width * 0.70,
        height: rect.height * 0.14
    )
    let radius = panelRect.height / 2
    let panelPath = NSBezierPath(roundedRect: panelRect, xRadius: radius, yRadius: radius)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.18)
    shadow.shadowBlurRadius = rect.width * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -rect.height * 0.01)
    shadow.set()

    let gradient = NSGradient(colors: [IconPalette.menuBarTop, IconPalette.menuBarBottom])!
    gradient.draw(in: panelPath, angle: 90)

    NSGraphicsContext.saveGraphicsState()
    panelPath.addClip()
    let topGlow = NSBezierPath(roundedRect: NSRect(x: panelRect.minX, y: panelRect.midY, width: panelRect.width, height: panelRect.height / 2),
                               xRadius: radius,
                               yRadius: radius)
    NSColor(calibratedWhite: 1, alpha: 0.08).setFill()
    topGlow.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSColor(calibratedWhite: 1, alpha: 0.12).setStroke()
    panelPath.lineWidth = max(1.5, rect.width * 0.003)
    panelPath.stroke()

    let notchRect = NSRect(
        x: rect.midX - rect.width * 0.095,
        y: panelRect.maxY - rect.height * 0.035,
        width: rect.width * 0.19,
        height: rect.height * 0.042
    )
    let notchPath = NSBezierPath(roundedRect: notchRect, xRadius: notchRect.height / 2, yRadius: notchRect.height / 2)
    IconPalette.notch.setFill()
    notchPath.fill()

    let indicatorWidth = rect.width * 0.022
    let indicatorHeight = rect.height * 0.008
    for index in 0..<3 {
        let indicatorRect = NSRect(
            x: panelRect.maxX - rect.width * 0.12 + CGFloat(index) * rect.width * 0.035,
            y: panelRect.midY - indicatorHeight / 2,
            width: indicatorWidth,
            height: indicatorHeight
        )
        let indicator = NSBezierPath(roundedRect: indicatorRect, xRadius: indicatorHeight / 2, yRadius: indicatorHeight / 2)
        IconPalette.status.setFill()
        indicator.fill()
    }
}

func drawDial(in rect: NSRect) {
    let dialRect = NSRect(
        x: rect.width * 0.275,
        y: rect.height * 0.20,
        width: rect.width * 0.45,
        height: rect.width * 0.45
    )
    let dialPath = NSBezierPath(ovalIn: dialRect)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.14)
    shadow.shadowBlurRadius = rect.width * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -rect.height * 0.015)
    shadow.set()

    let dialGradient = NSGradient(colors: [IconPalette.dialTop, IconPalette.dialBottom])!
    dialGradient.draw(in: dialPath, angle: 90)

    IconPalette.dialStroke.setStroke()
    dialPath.lineWidth = max(2, rect.width * 0.005)
    dialPath.stroke()

    let center = NSPoint(x: dialRect.midX, y: dialRect.midY)
    let outerRadius = dialRect.width * 0.58 / 2
    let accentPath = NSBezierPath()
    accentPath.lineWidth = rect.width * 0.032
    accentPath.lineCapStyle = .round
    accentPath.appendArc(withCenter: center, radius: outerRadius, startAngle: 212, endAngle: 24, clockwise: false)
    let accentGradient = NSGradient(colors: [IconPalette.accentStart, IconPalette.accentEnd])!
    accentGradient.draw(in: accentPath, angle: 15)

    drawClockHand(center: center, angleDegrees: 54, length: dialRect.width * 0.24, thickness: rect.width * 0.022)
    drawClockHand(center: center, angleDegrees: 326, length: dialRect.width * 0.16, thickness: rect.width * 0.028)

    let hubRect = NSRect(x: center.x - rect.width * 0.022, y: center.y - rect.width * 0.022, width: rect.width * 0.044, height: rect.width * 0.044)
    let hubPath = NSBezierPath(ovalIn: hubRect)
    IconPalette.hand.setFill()
    hubPath.fill()

    let baseRect = NSRect(
        x: rect.width * 0.35,
        y: rect.height * 0.17,
        width: rect.width * 0.30,
        height: rect.height * 0.035
    )
    let basePath = NSBezierPath(roundedRect: baseRect, xRadius: baseRect.height / 2, yRadius: baseRect.height / 2)
    let baseGradient = NSGradient(colors: [
        IconPalette.accentStart.withAlphaComponent(0.92),
        IconPalette.accentEnd.withAlphaComponent(0.92),
    ])!
    baseGradient.draw(in: basePath, angle: 0)
}

func drawClockHand(center: NSPoint, angleDegrees: CGFloat, length: CGFloat, thickness: CGFloat) {
    let radians = angleDegrees * .pi / 180
    let endPoint = NSPoint(
        x: center.x + cos(radians) * length,
        y: center.y + sin(radians) * length
    )

    let handPath = NSBezierPath()
    handPath.move(to: center)
    handPath.line(to: endPoint)
    handPath.lineWidth = thickness
    handPath.lineCapStyle = .round
    IconPalette.hand.setStroke()
    handPath.stroke()
}
