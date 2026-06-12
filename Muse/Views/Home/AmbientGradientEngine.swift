import SwiftUI
import UIKit

struct AmbientGradientColors: Equatable {
    var top: Color
    var bottom: Color

    static let fallback = AmbientGradientColors(
        top: Color(hex: "5F7059"),
        bottom: Color(hex: "16140F")
    )
}

/// Builds the tone-matched ambient glow behind the Glass detail screen.
/// Mirrors the web prototype: downsample, saturation-weighted regions, boost, darken bottom.
enum AmbientGradientEngine {

    private static let sampleSize = 16

    static func colors(for tile: SampleTile) -> AmbientGradientColors {
        let image = renderGradient(top: UIColor(tile.topColor), bottom: UIColor(tile.bottomColor))
        return colors(from: image) ?? .fallback
    }

    static func colors(from image: UIImage) -> AmbientGradientColors? {
        guard let cgImage = image.cgImage else { return nil }

        let size = sampleSize
        let half = size / 2
        var top = WeightedRGB()
        var bottom = WeightedRGB()

        // Sample through an explicit sRGB / RGBA8 buffer: the previous path read
        // raw renderer bytes whose channel order isn't guaranteed (often BGRA),
        // which swapped red and blue and produced off-tone glows.
        let bytesPerRow = size * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * size)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: &buffer,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        for y in 0..<size {
            for x in 0..<size {
                let offset = y * bytesPerRow + x * 4
                let r = CGFloat(buffer[offset])
                let g = CGFloat(buffer[offset + 1])
                let b = CGFloat(buffer[offset + 2])
                let maxC = max(r, g, b)
                let minC = min(r, g, b)
                let weight = 1 + ((maxC - minC) / 255) * 3
                if y < half {
                    top.add(r: r, g: g, b: b, weight: weight)
                } else {
                    bottom.add(r: r, g: g, b: b, weight: weight)
                }
            }
        }

        let topColor = boost(
            r: top.r / top.weight,
            g: top.g / top.weight,
            b: top.b / top.weight,
            saturationFactor: 1.18,
            lightnessRange: 0.32...0.66
        )
        let bottomColor = boost(
            r: bottom.r / bottom.weight,
            g: bottom.g / bottom.weight,
            b: bottom.b / bottom.weight,
            saturationFactor: 1.18,
            lightnessRange: 0.10...0.26
        )
        return AmbientGradientColors(top: topColor, bottom: bottomColor)
    }

    // MARK: - Private

    private struct WeightedRGB {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var weight: CGFloat = 0

        mutating func add(r: CGFloat, g: CGFloat, b: CGFloat, weight: CGFloat) {
            self.r += r * weight
            self.g += g * weight
            self.b += b * weight
            self.weight += weight
        }
    }

    private static func renderGradient(top: UIColor, bottom: UIColor) -> UIImage {
        let size = CGSize(width: sampleSize, height: sampleSize)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else { return }
            ctx.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: 0, y: size.height),
                options: []
            )
        }
    }

    private static func boost(
        r: CGFloat,
        g: CGFloat,
        b: CGFloat,
        saturationFactor: CGFloat,
        lightnessRange: ClosedRange<CGFloat>
    ) -> Color {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1)
            .getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        saturation = min(1, saturation * saturationFactor)
        brightness = min(lightnessRange.upperBound, max(lightnessRange.lowerBound, brightness))
        return Color(hue: Double(hue), saturation: Double(saturation), brightness: Double(brightness), opacity: Double(alpha))
    }
}
