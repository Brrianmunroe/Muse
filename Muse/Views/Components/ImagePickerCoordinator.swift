import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ImageIO

struct ImagePicker: UIViewControllerRepresentable {
    /// Called once per picked image, in selection order, as each finishes loading.
    /// Delivering one at a time (rather than a full batch) keeps only a single
    /// downsampled image in memory at once.
    var onPick: (UIImage) -> Void

    /// Cap the longest edge of imported photos. Originals can be 12–48 MP, which
    /// decode to ~50 MB+ each — far more than a moodboard ever displays. Bounding
    /// here keeps memory in check on import; the screen never shows more pixels.
    private let maxPixelSize: CGFloat = 4096

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 10
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, maxPixelSize: maxPixelSize) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (UIImage) -> Void
        let maxPixelSize: CGFloat

        init(onPick: @escaping (UIImage) -> Void, maxPixelSize: CGFloat) {
            self.onPick = onPick
            self.maxPixelSize = maxPixelSize
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            let providers = results.map(\.itemProvider)
            guard !providers.isEmpty else { return }

            let onPick = self.onPick
            let maxPixelSize = self.maxPixelSize
            // Process sequentially off the main thread: load each photo's data,
            // downsample it via ImageIO (never fully decoding the original giant
            // bitmap), hand it back, then release it before the next one.
            Task.detached(priority: .userInitiated) {
                for provider in providers {
                    guard let data = await Self.loadData(from: provider),
                          let image = Self.downsample(data, maxPixelSize: maxPixelSize)
                    else { continue }
                    await MainActor.run { onPick(image) }
                }
            }
        }

        /// Reads the raw file bytes without decoding into a bitmap.
        private static func loadData(from provider: NSItemProvider) async -> Data? {
            await withCheckedContinuation { continuation in
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    continuation.resume(returning: data)
                }
            }
        }

        /// Decodes straight to a thumbnail at most `maxPixelSize` on its longest
        /// edge, applying the EXIF orientation transform so the result is upright.
        private static func downsample(_ data: Data, maxPixelSize: CGFloat) -> UIImage? {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return UIImage(cgImage: cgImage)
        }
    }
}
