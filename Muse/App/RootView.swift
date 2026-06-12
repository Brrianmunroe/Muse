import SwiftUI

struct RootView: View {
    @EnvironmentObject var authViewModel: AuthViewModel

    var body: some View {
        HomeView()
            .environmentObject(authViewModel)
    }
}
