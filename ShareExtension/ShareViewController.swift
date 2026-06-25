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
            for image in await loadImages(from: provider) {
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

    /// Resolve one attachment into the image(s) it represents.
    ///
    /// Photos hands over raw pixels. X, Chrome and Safari hand over a *link*
    /// instead — and that link usually points at a web page, not an image. So
    /// when we get a link we figure out what kind of page it is and dig the real
    /// picture out (a tweet can carry several), rather than trying to download
    /// the page itself.
    private func loadImages(from provider: NSItemProvider) async -> [UIImage] {
        // Raw image data (Photos, Files, some apps).
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
           let image = await resolveImage(provider, typeID: UTType.image.identifier) {
            return [image]
        }
        // A link — to an image directly, to a tweet, or to some other web page.
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = await resolveURL(provider, typeID: UTType.url.identifier) {
            return await images(forSharedURL: url)
        }
        return []
    }

    private func resolveImage(_ provider: NSItemProvider, typeID: String) async -> UIImage? {
        let item: NSSecureCoding? = await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeID, options: nil) { item, _ in
                continuation.resume(returning: item)
            }
        }
        switch item {
        case let image as UIImage: return image
        case let data as Data: return UIImage(data: data)
        case let url as URL: return await download(url)
        default: return nil
        }
    }

    private func resolveURL(_ provider: NSItemProvider, typeID: String) async -> URL? {
        let item: NSSecureCoding? = await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeID, options: nil) { item, _ in
                continuation.resume(returning: item)
            }
        }
        if let url = item as? URL { return url }
        if let data = item as? Data, let str = String(data: data, encoding: .utf8) {
            return URL(string: str.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    /// Turn a shared link into the picture(s) it stands for, trying the most
    /// reliable source first and quietly falling back if one comes up empty.
    private func images(forSharedURL url: URL) async -> [UIImage] {
        // 1. A tweet/X link: ask X's own embed feed for the post's real media.
        if let id = TweetMedia.tweetID(in: url) {
            let mediaURLs = await TweetMedia.imageURLs(forTweetID: id)
            let images = await download(mediaURLs)
            if !images.isEmpty { return images }
        }
        // 2. An Instagram post: read the photo from its public embed page.
        if let code = InstagramMedia.shortcode(in: url) {
            let mediaURLs = await InstagramMedia.imageURLs(forShortcode: code)
            let images = await download(mediaURLs)
            if !images.isEmpty { return images }
        }
        // 3. A direct link to an image file (some browsers, "copy image address").
        if let image = await download(url) { return [image] }
        // 4. Any other web page: use its social-preview image, if it has one.
        if let preview = await OpenGraph.imageURL(forPage: url),
           let image = await download(preview) {
            return [image]
        }
        return []
    }

    // MARK: - Downloading

    /// Fetch a URL into an image: read local files directly, download remote
    /// ones. Returns nil for anything that isn't actually a decodable image
    /// (e.g. an HTML page), which surfaces as "No image found".
    private func download(_ url: URL) async -> UIImage? {
        if url.isFileURL {
            return (try? Data(contentsOf: url)).flatMap(UIImage.init)
        }
        guard let (data, _) = try? await URLSession.shared.data(for: Self.request(url)) else { return nil }
        return UIImage(data: data)
    }

    private func download(_ urls: [URL]) async -> [UIImage] {
        var images: [UIImage] = []
        for url in urls {
            if let image = await download(url) { images.append(image) }
        }
        return images
    }

    /// Some hosts (X's CDN among them) refuse requests without a browser-like
    /// User-Agent, so we always present one.
    static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
            + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent")
        return request
    }
}

/// Pulls a tweet's real media out of X's public embed feed — the same data
/// source that powers "embedded tweet" widgets across the web. No developer API,
/// no keys, no login.
///
/// This is an undocumented endpoint, so it can change without notice; callers
/// always have a fallback. When we add video, its download links live in this
/// same payload under each item's `video_info.variants`.
enum TweetMedia {

    /// The numeric id from a tweet link, e.g. .../status/1771234567890 → "1771234567890".
    static func tweetID(in url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              host == "x.com" || host == "twitter.com"
                || host.hasSuffix(".x.com") || host.hasSuffix(".twitter.com")
        else { return nil }
        let parts = url.pathComponents
        guard let i = parts.firstIndex(of: "status"), i + 1 < parts.count else { return nil }
        let id = parts[i + 1].prefix { $0.isNumber }
        return id.isEmpty ? nil : String(id)
    }

    /// Full-resolution image URLs for every photo attached to the tweet.
    static func imageURLs(forTweetID id: String) async -> [URL] {
        let endpoint = "https://cdn.syndication.twimg.com/tweet-result?id=\(id)&token=\(token(for: id))&lang=en"
        guard let url = URL(string: endpoint),
              let (data, _) = try? await URLSession.shared.data(for: ShareViewController.request(url)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }

        // Preferred shape: "mediaDetails" lists every attachment with its type.
        if let media = json["mediaDetails"] as? [[String: Any]] {
            let photos = media
                .filter { ($0["type"] as? String) == "photo" }
                .compactMap { $0["media_url_https"] as? String }
                .compactMap { largeVariant(of: $0) }
            if !photos.isEmpty { return photos }
        }
        // Fallback shape: a plain "photos" array.
        if let photos = json["photos"] as? [[String: Any]] {
            return photos
                .compactMap { $0["url"] as? String }
                .compactMap { largeVariant(of: $0) }
        }
        return []
    }

    /// Ask X's image CDN for the large rendition rather than a thumbnail.
    private static func largeVariant(of urlString: String) -> URL? {
        guard var components = URLComponents(string: urlString) else { return nil }
        components.queryItems = [URLQueryItem(name: "name", value: "large")]
        return components.url
    }

    /// X's embed feed requires a token derived from the tweet id. This mirrors
    /// the exact arithmetic X's own embed library uses:
    /// `((id / 1e15) * π)` rendered in base‑36 with zeros and the dot stripped.
    static func token(for id: String) -> String {
        guard let n = Double(id) else { return "0" }
        let value = (n / 1e15) * Double.pi
        return base36(value)
            .replacingOccurrences(of: "0", with: "")
            .replacingOccurrences(of: ".", with: "")
    }

    /// Render a Double in base‑36 the same way JavaScript's `Number.toString(36)`
    /// does, including the fractional part — needed so the token matches exactly.
    private static func base36(_ input: Double) -> String {
        let radix = 36.0
        let digits = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        var integer = input.rounded(.down)
        var fraction = input - integer

        var fractionChars: [Character] = []
        var delta = max(Double.leastNonzeroMagnitude, 0.5 * (input.nextUp - input))
        if fraction >= delta {
            while true {
                fraction *= radix
                delta *= radix
                let digit = Int(fraction)
                fractionChars.append(digits[digit])
                fraction -= Double(digit)
                if fraction > 0.5 || (fraction == 0.5 && digit & 1 == 1) {
                    if fraction + delta > 1 {
                        // Round up, propagating any carry back through the digits.
                        while true {
                            guard let last = fractionChars.popLast() else {
                                integer += 1
                                break
                            }
                            let d = last > "9"
                                ? Int(last.asciiValue! - Character("a").asciiValue!) + 10
                                : Int(last.asciiValue! - Character("0").asciiValue!)
                            if Double(d + 1) < radix {
                                fractionChars.append(digits[d + 1])
                                break
                            }
                        }
                        break
                    }
                }
                if fraction < delta { break }
            }
        }

        var integerChars: [Character] = []
        if integer == 0 {
            integerChars.append("0")
        } else {
            while integer > 0 {
                let remainder = integer.truncatingRemainder(dividingBy: radix)
                integerChars.append(digits[Int(remainder)])
                integer = (integer - remainder) / radix
            }
            integerChars.reverse()
        }

        var result = String(integerChars)
        if !fractionChars.isEmpty { result += "." + String(fractionChars) }
        return result
    }
}

/// Pulls a public Instagram post's photo out of the same embed page that powers
/// "embed this post" widgets across the web — no login, no API keys, no Meta
/// developer app. We read the post's *embed* page rather than the normal post
/// page on purpose: the normal page now often throws a login wall at anyone
/// signed out, while the embed page stays public by design.
///
/// Limits we accept for now: this reaches only *public* posts, and only their
/// still image. Private accounts, stories and login-walled posts have nothing
/// here; a multi-photo carousel gives up just its first picture. A reel resolves
/// to its cover frame, which is fine as a photo tile. The video file itself
/// lives on this same page — wiring it up later is "read one more field", not a
/// rebuild — but we deliberately ignore it for now.
enum InstagramMedia {

    /// The shortcode from a post link, e.g. .../p/Cx1Ab2Cd3/ → "Cx1Ab2Cd3".
    /// Recognises the post, reel and IGTV link shapes — all expose the same embed.
    static func shortcode(in url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              host == "instagram.com" || host.hasSuffix(".instagram.com")
        else { return nil }
        let parts = url.pathComponents
        for marker in ["p", "reel", "reels", "tv"] {
            if let i = parts.firstIndex(of: marker), i + 1 < parts.count,
               !parts[i + 1].isEmpty {
                return parts[i + 1]
            }
        }
        return nil
    }

    /// The post's full-resolution photo, read from its public embed page.
    static func imageURLs(forShortcode code: String) async -> [URL] {
        let endpoint = "https://www.instagram.com/p/\(code)/embed/captioned/"
        guard let url = URL(string: endpoint),
              let (data, _) = try? await URLSession.shared.data(for: ShareViewController.request(url)),
              let html = String(data: data, encoding: .utf8)
        else { return [] }

        // Preferred: the original image URL embedded in the page's JSON payload.
        if let raw = firstMatch(#""display_url":"([^"]+)""#, in: html),
           let imageURL = URL(string: unescape(raw)) {
            return [imageURL]
        }
        // Fallback: the <img> the embed actually renders on screen.
        if let raw = firstMatch(#"class="EmbeddedMediaImage"[^>]+src="([^"]+)""#, in: html),
           let imageURL = URL(string: unescape(raw)) {
            return [imageURL]
        }
        return []
    }

    /// Undo the escaping Instagram applies inside its embedded JSON: `\/` for
    /// slashes and `&`/`&amp;` for the ampersands between query parameters.
    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\/", with: "/")
         .replacingOccurrences(of: "\\u0026", with: "&")
         .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func firstMatch(_ pattern: String, in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let r = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[r])
    }
}

/// Last-ditch way to get a picture out of an arbitrary web page: read its
/// Open Graph / Twitter "card" preview image from the page's `<head>`.
enum OpenGraph {
    static func imageURL(forPage url: URL) async -> URL? {
        guard let (data, _) = try? await URLSession.shared.data(for: ShareViewController.request(url)),
              let html = String(data: data, encoding: .utf8) else { return nil }

        for property in ["og:image", "twitter:image", "twitter:image:src"] {
            if let value = metaContent(property: property, in: html),
               let imageURL = URL(string: value) {
                return imageURL
            }
        }
        return nil
    }

    /// Find `<meta property="og:image" content="…">` (in either attribute order)
    /// without pulling in an HTML parser.
    private static func metaContent(property: String, in html: String) -> String? {
        let patterns = [
            "<meta[^>]+(?:property|name)=[\"']\(property)[\"'][^>]+content=[\"']([^\"']+)[\"']",
            "<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+(?:property|name)=[\"']\(property)[\"']"
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(html.startIndex..., in: html)
            if let match = regex.firstMatch(in: html, range: range),
               let r = Range(match.range(at: 1), in: html) {
                return String(html[r])
            }
        }
        return nil
    }
}
