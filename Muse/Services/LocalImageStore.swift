import UIKit

enum LocalImageStore {

    struct SavedPaths {
        let localPath: String
        let thumbnailPath: String
        let width: Int
        let height: Int
    }

    private static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("muse-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func save(image: UIImage) throws -> SavedPaths {
        let name = UUID().uuidString
        let fullName = "\(name).jpg"
        let thumbName = "\(name)_thumb.jpg"

        // Normalize orientation before saving
        let normalized = image.normalized()

        guard let fullData = normalized.jpegData(compressionQuality: 0.85) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try fullData.write(to: directory.appendingPathComponent(fullName))

        let thumb = thumbnail(from: normalized, maxDimension: 400)
        guard let thumbData = thumb.jpegData(compressionQuality: 0.75) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try thumbData.write(to: directory.appendingPathComponent(thumbName))

        let width = Int(normalized.size.width * normalized.scale)
        let height = Int(normalized.size.height * normalized.scale)

        return SavedPaths(localPath: fullName, thumbnailPath: thumbName, width: width, height: height)
    }

    static func url(for path: String) -> URL {
        directory.appendingPathComponent(path)
    }

    static func delete(localPath: String, thumbnailPath: String?) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(localPath))
        if let t = thumbnailPath {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(t))
        }
    }

    private static func thumbnail(from image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1)
        guard scale < 1 else { return image }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}

private extension UIImage {
    /// Returns a copy with orientation set to .up (fixes rotated camera photos).
    func normalized() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}
