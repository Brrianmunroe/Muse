import SwiftUI

struct HomeView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var layoutMode: GalleryLayoutMode = .vast
    @State private var selectedTileID: Int?
    @State private var tileNotes: [Int: String] = [:]
    @Namespace private var detailNamespace

    var body: some View {
        NavigationStack {
            Group {
                if authViewModel.isPreviewMode {
                    galleryContent
                } else {
                    emptyState
                }
            }
            .background(MuseTheme.Semantic.surfacePage.ignoresSafeArea())
            .toolbarBackground(MuseTheme.Semantic.surfacePage, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar(selectedTileID == nil ? .visible : .hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Muse")
                        .font(MuseTheme.serif(22))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await authViewModel.signOut() }
                    } label: {
                        Image(systemName: "person.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(MuseTheme.Semantic.iconDefault)
                    }
                }
            }
        }
        .overlay {
            if selectedTileID != nil {
                ImageDetailView(
                    tiles: SampleTile.samples,
                    selectedTileID: $selectedTileID,
                    tileNotes: $tileNotes,
                    namespace: detailNamespace
                )
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selectedTileID)
    }

    private var galleryContent: some View {
        ZStack(alignment: .bottom) {
            GalleryCanvasView(
                mode: $layoutMode,
                selectedTileID: $selectedTileID,
                tiles: SampleTile.samples,
                detailNamespace: detailNamespace
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                if layoutMode != .vast {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Your inspiration")
                            .font(MuseTheme.serif(28))
                            .padding(.horizontal, 20)

                        sampleTagRow
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MuseTheme.Semantic.surfacePage)
                }
            }

            if selectedTileID == nil {
                GalleryModeToggle(mode: $layoutMode)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 12) {
                Spacer().frame(height: 60)
                Text("No inspiration yet")
                    .font(MuseTheme.serif(20))
                Text("Start by sharing screenshots\nfrom any app into Muse")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(MuseTheme.Semantic.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var sampleTagRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                sampleTag("serif heading", .typography)
                sampleTag("warm palette", .color)
                sampleTag("asymmetric grid", .layout)
                sampleTag("editorial", .style)
                sampleTag("high contrast", .typography)
                sampleTag("earth tones", .color)
            }
            .padding(.horizontal, 20)
        }
    }

    private func sampleTag(_ label: String, _ category: TagCategory) -> some View {
        Text(label)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(MuseTheme.Semantic.tagBackground(for: category))
            .foregroundStyle(MuseTheme.Semantic.tagForeground(for: category))
            .clipShape(Capsule())
    }
}
