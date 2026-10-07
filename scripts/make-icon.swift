// Renders the BlackTea app icon (1024x1024 PNG): a steaming cup on a black-tea gradient.
// Usage: swiftc scripts/make-icon.swift -o .build/make-icon && .build/make-icon out.png
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
let size = 1024
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let S = CGFloat(size)

// macOS-style rounded square with margin
let inset: CGFloat = S * 0.1
let rect = NSRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = S * 0.025
shadow.shadowOffset = NSSize(width: 0, height: -S * 0.01)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor.black.setFill()
path.fill()
NSGraphicsContext.restoreGraphicsState()

let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.62, green: 0.30, blue: 0.10, alpha: 1),   // amber tea
    NSColor(calibratedRed: 0.16, green: 0.07, blue: 0.03, alpha: 1)    // nearly black
])!
gradient.draw(in: path, angle: -70)

func drawSymbol(_ name: String, pointSize: CGFloat, center: NSPoint, color: NSColor) {
    let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) else { return }
    let sz = img.size
    img.draw(in: NSRect(x: center.x - sz.width / 2, y: center.y - sz.height / 2, width: sz.width, height: sz.height))
}
let cream = NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.86, alpha: 1)
drawSymbol("cup.and.heat.waves.fill", pointSize: S * 0.36, center: NSPoint(x: S * 0.5, y: S * 0.5), color: cream)

NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: outPath))
print("Wrote \(outPath)")
