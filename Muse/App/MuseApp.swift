import SwiftUI
import SwiftData

@main
struct MuseApp: App {
    @StateObject private var authViewModel = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authViewModel)
        }
        .modelContainer(for: LocalMuseImage.self)
    }
}
