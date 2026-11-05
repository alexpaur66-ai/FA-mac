import CoreGraphics
import CoreImage
import Foundation

/// The module grid of a QR code, computed by Core Image's generator (ADR 0003: the payloads live in the
/// core, drawing the code is the app's job). `size` modules per side, including the generator's quiet zone;
/// row 0 is the top row.
struct QRModules: Sendable {
    let size: Int
    private let dark: [Bool]

    func isDark(row: Int, column: Int) -> Bool { dark[row * size + column] }

    /// `correctionLevel` is "L", "M", "Q" or "H"; both payment formats ask for "M" (QR platba standard,
    /// EPC069-12). `encoding` turns the payload into the code's bytes: ISO-8859-1 for QR platba, whose
    /// payload the core builds from that character set (Latin-1 characters raw, the rest percent-encoded),
    /// UTF-8 for the EPC code (its character set 1). Nil when Core Image cannot produce the code (an empty
    /// payload, a character outside the encoding, or a payload too long for a QR).
    static func generate(_ payload: String, correctionLevel: String = "M", encoding: String.Encoding = .utf8) -> QRModules? {
        guard !payload.isEmpty, let message = payload.data(using: encoding),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(message, forKey: "inputMessage")
        filter.setValue(correctionLevel, forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let extent = output.extent.integral
        let width = Int(extent.width)
        let height = Int(extent.height)
        guard width > 0, width == height else { return nil }
        // The software renderer works on every Mac and on a build server without a GPU.
        let ciContext = CIContext(options: [.useSoftwareRenderer: true])
        guard let image = ciContext.createCGImage(output, from: extent),
              let provider = image.dataProvider, let data = provider.data, let bytes = CFDataGetBytePtr(data) else { return nil }
        let bytesPerRow = image.bytesPerRow
        let bytesPerPixel = max(1, image.bitsPerPixel / 8)
        guard CFDataGetLength(data) >= bytesPerRow * height else { return nil }
        // Copy the pixels while `data` is certainly alive: a raw pointer keeps neither the CFData nor the image.
        let pixels = [UInt8](UnsafeBufferPointer(start: bytes, count: bytesPerRow * height))
        withExtendedLifetime(data) {}
        var dark = [Bool](repeating: false, count: width * height)
        for row in 0..<height {
            for column in 0..<width {
                let offset = row * bytesPerRow + column * bytesPerPixel
                var low = 0
                for index in 0..<bytesPerPixel where pixels[offset + index] < 128 { low += 1 }
                // A dark module has every colour byte at 0 and at most the alpha byte at 255, whatever the
                // channel order; a light module has no byte below 128.
                dark[row * width + column] = low >= max(1, bytesPerPixel - 1)
            }
        }
        return QRModules(size: width, dark: dark)
    }
}
