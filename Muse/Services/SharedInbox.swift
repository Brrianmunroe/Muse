import UIKit

/// A shared "drop box" both the main app and the share extension can reach.
///
/// The share extension can't safely do the heavy lifting (limited memory, no
/// sign-in), so it just writes incoming images here. The main app drains this
/// folder on launch/foreground, importing each image the normal way.
enum SharedInbox {

    /// Must match the App Group enabled on both targets' entitlements.
    static let appGroupID = "group.com.brianmunroe.Muse"

    /// Folder inside the shared App Group container where pending images land.
    static var directory: URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return nil }
        let dir = container.appendingPathComponent("inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Write a shared image as JPEG into the inbox. Called from the extension.
    @discardableResult
    static func write(image: UIImage) -> Bool {
        guard let directory,
              let data = image.jpegData(compressionQuality: 0.9) else { return false }
        let url = directory.appendingPathComponent("\(UUID().uuidString).jpg")
        return (try? data.write(to: url)) != nil
    }

    /// Image files waiting to be imported, oldest first. Called from the app.
    static func pendingFiles() -> [URL] {
        guard let directory else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "jpg" }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                return l < r
            }
    }

    /// Remove an inbox file once it's been imported.
    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
