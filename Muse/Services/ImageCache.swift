import UIKit
import ImageIO

/// Decoded-image cache so views never decode JPEGs inside their body.
/// Thumbnails and screen-sized display images are cached separately by path.
enum ImageCache {

    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 200 * 1024 * 1024
        return cache
    }()

    /// Grid thumbnail, decoded once and force-prepared for display.
    static func thumbnail(for path: String) -> UIImage? {
        let key = "thumb:\(path)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = UIImage(contentsOfFile: LocalImageStore.url(for: path).path) else { return nil }
        let prepared = image.preparingForDisplay() ?? image
        cache.setObject(prepared, forKey: key, cost: prepared.byteCost)
        return prepared
    }

    /// Full image downsampled to at most `maxDimension` pixels — the hero never
    /// needs more pixels than the screen.
    static func display(for path: String, maxDimension: CGFloat) -> UIImage? {
        let key = "display:\(path):\(Int(maxDimension))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let url = LocalImageStore.url(for: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: key, cost: image.byteCost)
        return image
    }

    /// Screen-sized pixel budget for hero/display images.
    static var screenMaxDimension: CGFloat {
        let bounds = UIScreen.main.bounds
        return max(bounds.width, bounds.height) * UIScreen.main.scale
    }
}

private extension UIImage {
    var byteCost: Int {
        guard let cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}
