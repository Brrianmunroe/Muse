import SwiftUI

struct RootView: View {
    @EnvironmentObject var authViewModel: AuthViewModel

    var body: some View {
        Group {
            switch authViewModel.state {
            case .loading:
                ProgressView("Loading…")
            case .signedOut:
                SignInView()
            case .signedIn:
                HomeView()
            }
        }
        .animation(.easeInOut, value: authViewModel.state)
    }
}
