import UIKit
import UniformTypeIdentifiers

/// The little panel that appears when you tap Share → Muse.
///
/// It does the bare minimum on purpose: pull the shared image(s) out, hand them
/// to the shared inbox, and dismiss. The AI description and cloud sync happen
/// later, in the full app, where there's memory and a signed-in session.
final class ShareViewController: UIViewController {

    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.0)

        label.text = "Saving to Muse…"
        label.font = .systemFont(ofSize: 17, weight: .medium)
        label.textColor = .label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await handleSharedItems() }
    }

    private func handleSharedItems() async {
        let attachments = (extensionContext?.inputItems as? [NSExtensionItem])?
            .flatMap { $0.attachments ?? [] } ?? []

        var savedCount = 0
        for provider in attachments {
            if let image = await loadImage(from: provider) {
                if SharedInbox.write(image: image) { savedCount += 1 }
            }
        }

        await MainActor.run {
            label.text = savedCount > 0 ? "Saved to Muse" : "No image found"
        }
        // Brief beat so the confirmation is readable, then dismiss.
        try? await Task.sleep(nanoseconds: 500_000_000)
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    /// Resolve an attachment into a UIImage. Photos hands over raw pixels; X,
    /// Chrome and Safari usually hand over a link to the image instead, so we
    /// also accept URLs and download the image behind them.
    private func loadImage(from provider: NSItemProvider) async -> UIImage? {
        // Raw image data (Photos, Files, some apps).
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
           let image = await resolve(provider, typeID: UTType.image.identifier) {
            return image
        }
        // A link — either directly to an image, or to a page (browsers, X).
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let image = await resolve(provider, typeID: UTType.url.identifier) {
            return image
        }
        return nil
    }

    private func resolve(_ provider: NSItemProvider, typeID: String) async -> UIImage? {
        let item: NSSecureCoding? = await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeID, options: nil) { item, _ in
                continuation.resume(returning: item)
            }
        }
        switch item {
        case let image as UIImage:
            return image
        case let data as Data:
            return UIImage(data: data)
        case let url as URL:
            return await image(from: url)
        default:
            return nil
        }
    }

    /// Turn a URL into an image: read local file URLs directly, download remote
    /// ones. A plain web page (e.g. a tweet link) won't decode to an image and
    /// returns nil, which surfaces as "No image found".
    private func image(from url: URL) async -> UIImage? {
        if url.isFileURL {
            return (try? Data(contentsOf: url)).flatMap(UIImage.init)
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }
}
