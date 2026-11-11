import Foundation
import CoreImage

/// Draws the pairing code as a QR code in the terminal, so pairing is
/// "point the phone at the screen" rather than retyping a long link.
enum PairingQR {

    static func render(_ text: String) -> String? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let image = filter.outputImage else { return nil }

        let extent = image.extent.integral
        let width = Int(extent.width), height = Int(extent.height)
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        CIContext().render(
            image,
            toBitmap: &pixels,
            rowBytes: width * 4,
            bounds: extent,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        func dark(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, y >= 0, x < width, y < height else { return false }
            return pixels[(y * width + x) * 4] < 128
        }

        // Two modules per character row using half blocks, drawn dark
        // on light with a quiet zone so it scans on any terminal theme.
        let quiet = 2
        var lines: [String] = []
        var y = -quiet
        while y < height + quiet {
            var line = ""
            for x in -quiet..<(width + quiet) {
                switch (dark(x, y), dark(x, y + 1)) {
                case (true, true):   line += " "
                case (true, false):  line += "\u{2584}"
                case (false, true):  line += "\u{2580}"
                case (false, false): line += "\u{2588}"
                }
            }
            lines.append(line)
            y += 2
        }
        return lines.joined(separator: "\n")
    }
}
