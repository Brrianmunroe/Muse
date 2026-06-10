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
        guard let cgImage = downsample(image, to: sampleSize) else { return nil }

        let width = sampleSize
        let height = sampleSize
        let half = height / 2
        var top = WeightedRGB()
        var bottom = WeightedRGB()

        guard let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return nil }

        let bpp = cgImage.bitsPerPixel / 8
        let rowBytes = cgImage.bytesPerRow

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * rowBytes + x * bpp
                let r = CGFloat(bytes[offset])
                let g = CGFloat(bytes[offset + 1])
                let b = CGFloat(bytes[offset + 2])
                let maxC = max(r, g, b)
                let minC = min(r, g, b)
                let weight = 1 + ((maxC - minC) / 255) * 4
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
            saturationFactor: 1.45,
            lightnessRange: 0.30...0.62
        )
        let bottomColor = boost(
            r: bottom.r / bottom.weight,
            g: bottom.g / bottom.weight,
            b: bottom.b / bottom.weight,
            saturationFactor: 1.45,
            lightnessRange: 0.10...0.24
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

    private static func downsample(_ image: UIImage, to size: Int) -> CGImage? {
        let target = CGSize(width: size, height: size)
        let renderer = UIGraphicsImageRenderer(size: target)
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return scaled.cgImage
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
