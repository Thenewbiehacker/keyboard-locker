// Renders a 1024x1024 PNG app icon: a keyboard glyph on a dark gradient,
// with a lock badge in the corner. Run by build.sh, not needed at runtime.
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let canvas: CGFloat = 1024

func tintedSymbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSImage? {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else { return nil }
    let size = base.size
    guard size.width > 1, size.height > 1 else { return nil }

    let tinted = NSImage(size: size)
    tinted.lockFocus()
    color.setFill()
    NSRect(origin: .zero, size: size).fill()
    base.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .destinationIn, fraction: 1)
    tinted.unlockFocus()
    return tinted
}

let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

// Rounded background with a vertical gradient.
let backgroundRect = NSRect(x: 40, y: 40, width: canvas - 80, height: canvas - 80)
let background = NSBezierPath(roundedRect: backgroundRect, xRadius: 225, yRadius: 225)
if let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.20, green: 0.25, blue: 0.42, alpha: 1),
    NSColor(srgbRed: 0.05, green: 0.07, blue: 0.14, alpha: 1)
]) {
    gradient.draw(in: background, angle: -75)
}

// Keyboard.
if let keyboard = tintedSymbol("keyboard", pointSize: 400, weight: .light, color: .white) {
    let size = keyboard.size
    let rect = NSRect(
        x: (canvas - size.width) / 2,
        y: (canvas - size.height) / 2 + 30,
        width: size.width,
        height: size.height
    )
    keyboard.draw(in: rect)
}

// Lock badge.
let badgeCenter = NSPoint(x: 752, y: 306)
let badgeRadius: CGFloat = 136
let badgeRect = NSRect(
    x: badgeCenter.x - badgeRadius,
    y: badgeCenter.y - badgeRadius,
    width: badgeRadius * 2,
    height: badgeRadius * 2
)
let badge = NSBezierPath(ovalIn: badgeRect)
NSColor(srgbRed: 0.06, green: 0.08, blue: 0.16, alpha: 1).setFill()
badge.fill()
NSColor.white.withAlphaComponent(0.20).setStroke()
badge.lineWidth = 8
badge.stroke()

if let lock = tintedSymbol("lock.fill", pointSize: 150, weight: .semibold, color: .white) {
    let size = lock.size
    let rect = NSRect(
        x: badgeCenter.x - size.width / 2,
        y: badgeCenter.y - size.height / 2,
        width: size.width,
        height: size.height
    )
    lock.draw(in: rect)
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("icon generation failed\n".utf8))
    exit(1)
}

do {
    try png.write(to: URL(fileURLWithPath: outputPath))
} catch {
    FileHandle.standardError.write(Data("could not write icon: \(error)\n".utf8))
    exit(1)
}
