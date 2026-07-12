#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private enum StatusBarMaskError: Error, CustomStringConvertible {
    case missingArguments
    case unreadableImage(String)
    case unwritableImage(String)

    var description: String {
        switch self {
        case .missingArguments:
            return "Usage: mask_ios_status_bar.swift image.png [image.png ...]"
        case .unreadableImage(let path):
            return "Could not read image: \(path)"
        case .unwritableImage(let path):
            return "Could not write masked image: \(path)"
        }
    }
}

private let maskHeight = Int(ProcessInfo.processInfo.environment["CHADDROP_STATUS_BAR_MASK_HEIGHT"] ?? "180") ?? 180
private let fillColor = CGColor(red: 0.08, green: 0.07, blue: 0.10, alpha: 1.0)

private func maskStatusBar(in path: String) throws {
    let url = URL(fileURLWithPath: path)
    guard
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw StatusBarMaskError.unreadableImage(path)
    }

    let pixelWidth = sourceImage.width
    let pixelHeight = sourceImage.height
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    guard let context = CGContext(
        data: nil,
        width: pixelWidth,
        height: pixelHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw StatusBarMaskError.unwritableImage(path)
    }

    context.interpolationQuality = .high
    context.draw(
        sourceImage,
        in: CGRect(x: 0, y: 0, width: CGFloat(pixelWidth), height: CGFloat(pixelHeight))
    )

    let clampedMaskHeight = min(max(maskHeight, 0), pixelHeight)
    context.setFillColor(fillColor)
    context.fill(
        CGRect(
            x: 0,
            y: CGFloat(pixelHeight - clampedMaskHeight),
            width: CGFloat(pixelWidth),
            height: CGFloat(clampedMaskHeight)
        )
    )

    guard
        let outputImage = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else {
        throw StatusBarMaskError.unwritableImage(path)
    }

    CGImageDestinationAddImage(destination, outputImage, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw StatusBarMaskError.unwritableImage(path)
    }

    print("Masked iOS status bar: \(path)")
}

do {
    let imagePaths = Array(CommandLine.arguments.dropFirst())
    guard !imagePaths.isEmpty else {
        throw StatusBarMaskError.missingArguments
    }

    for imagePath in imagePaths {
        try maskStatusBar(in: imagePath)
    }
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
