import AppKit
import CoreGraphics
import Foundation

let outputPath = CommandLine.arguments.last { $0.lowercased().hasSuffix(".png") }
    ?? "TruthTranslator/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

let size = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Could not create bitmap")
}

guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Could not create graphics context")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.shouldAntialias = true
context.cgContext.setAllowsAntialiasing(true)
context.cgContext.setShouldAntialias(true)

let bounds = CGRect(x: 0, y: 0, width: size, height: size)
let colorSpace = CGColorSpaceCreateDeviceRGB()
let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        NSColor(red: 1.00, green: 0.43, blue: 0.70, alpha: 1).cgColor,
        NSColor(red: 0.76, green: 0.08, blue: 0.43, alpha: 1).cgColor
    ] as CFArray,
    locations: [0.0, 1.0]
)!
context.cgContext.drawLinearGradient(
    gradient,
    start: CGPoint(x: 90, y: size - 40),
    end: CGPoint(x: size - 80, y: 0),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)

let cFont = NSFont(name: "ArialRoundedMTBold", size: 835)
    ?? NSFont.systemFont(ofSize: 835, weight: .heavy)
let cShadow = NSShadow()
cShadow.shadowColor = NSColor(red: 0.36, green: 0.03, blue: 0.22, alpha: 0.26)
cShadow.shadowBlurRadius = 18
cShadow.shadowOffset = CGSize(width: 0, height: -10)

let cAttributes: [NSAttributedString.Key: Any] = [
    .font: cFont,
    .foregroundColor: NSColor.white,
    .shadow: cShadow
]
NSAttributedString(string: "C", attributes: cAttributes)
    .draw(at: CGPoint(x: 82, y: 123))

let emojiFont = NSFont(name: "AppleColorEmoji", size: 430)
    ?? NSFont(name: "Apple Color Emoji", size: 430)
    ?? NSFont.systemFont(ofSize: 430)
let emojiShadow = NSShadow()
emojiShadow.shadowColor = NSColor(red: 0.23, green: 0.02, blue: 0.20, alpha: 0.24)
emojiShadow.shadowBlurRadius = 12
emojiShadow.shadowOffset = CGSize(width: 0, height: -5)

let emojiAttributes: [NSAttributedString.Key: Any] = [
    .font: emojiFont,
    .shadow: emojiShadow
]
NSAttributedString(string: "😈", attributes: emojiAttributes)
    .draw(at: CGPoint(x: 330, y: 342))

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode PNG")
}

let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try pngData.write(to: outputURL)
print("Created app icon: \(outputPath)")
