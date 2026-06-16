import SwiftUI
import SwiftData

struct HomeView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LocalMuseImage.createdAt, order: .reverse) private var images: [LocalMuseImage]

    @State private var layoutMode: GalleryLayoutMode = .vast
    @State private var displayedTileID: Int?
    @State private var isExpanded = false
    @State private var sourceFrame: CGRect = .zero
    @StateObject private var tuning = MorphTuning()
    @State private var showImagePicker = false

    private var tiles: [MuseTile] { images.map(\.asTile) }

    var body: some View {
        NavigationStack {
            Group {
                if images.isEmpty {
                    emptyState
                } else {
                    galleryContent
                }
            }
            .blur(radius: isExpanded ? 18 : 0)
            .scaleEffect(isExpanded ? 0.96 : 1)
            .animation(ImageDetailView.transition, value: isExpanded)
            .background(MuseTheme.Semantic.surfacePage.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .overlay {
            Color.black
                .opacity(isExpanded ? 0.5 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(displayedTileID != nil)
                .animation(ImageDetailView.transition, value: isExpanded)
        }
        .overlay {
            if let id = displayedTileID {
                if images.contains(where: { $0.intID == id }) {
                    MuseImageDetailView(
                        images: images,
                        sourceFrame: sourceFrame,
                        displayedTileID: $displayedTileID,
                        isExpanded: $isExpanded,
                        modelContext: modelContext
                    )
                } else {
                    ImageDetailView(
                        tiles: SampleTile.samples,
                        sourceFrame: sourceFrame,
                        displayedTileID: $displayedTileID,
                        isExpanded: $isExpanded
                    )
                }
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker { image in
                guard let paths = try? LocalImageStore.save(image: image) else { return }
                let record = LocalMuseImage(
                    localPath: paths.localPath,
                    thumbnailPath: paths.thumbnailPath,
                    width: paths.width,
                    height: paths.height
                )
                modelContext.insert(record)
                // Kick off the AI design description + tags in the background.
                ImageAnalysisService.analyzeIfNeeded(record, context: modelContext)
                try? modelContext.save()
            }
        }
    }

    private func openTile(_ id: Int, _ frame: CGRect) {
        sourceFrame = frame
        displayedTileID = id
    }

    private var galleryContent: some View {
        liveGallery(tiles: tiles)
    }

    private var sampleGallery: some View {
        liveCanvas(tiles: SampleTile.samples, showAddButton: false)
    }

    private func liveGallery(tiles: [MuseTile]) -> some View {
        ZStack(alignment: .bottom) {
            MuseGalleryCanvasView(
                mode: $layoutMode,
                selectedTileID: $displayedTileID,
                tiles: tiles,
                onSelectTile: openTile,
                onSelectedTileFrame: { sourceFrame = $0 },
                tuning: tuning
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if displayedTileID == nil {
                ZStack {
                    GalleryModeToggle(mode: $layoutMode)

                    HStack {
                        Spacer()
                        addButton
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func liveCanvas(tiles: [SampleTile], showAddButton: Bool) -> some View {
        ZStack(alignment: .bottom) {
            GalleryCanvasView(
                mode: $layoutMode,
                selectedTileID: $displayedTileID,
                tiles: tiles,
                onSelectTile: openTile,
                tuning: tuning
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
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
                .opacity(layoutMode == .bento ? 1 : 0)
                .allowsHitTesting(layoutMode == .bento)
                .animation(.easeInOut(duration: 0.3), value: layoutMode)
            }

            if displayedTileID == nil {
                GalleryModeToggle(mode: $layoutMode)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var addButton: some View {
        Button { showImagePicker = true } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(MuseTheme.Semantic.iconDefault)
                .frame(width: 56, height: 56)
                .background(MuseTheme.Semantic.surfaceCard, in: Circle())
                .overlay(Circle().stroke(MuseTheme.Semantic.dividerDefault, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Your canvas is empty")
                .font(MuseTheme.serif(24))

            Text("Add your first image to begin\nbuilding your inspiration board.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(MuseTheme.Semantic.textSecondary)

            Button { showImagePicker = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Add images")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(MuseTheme.Semantic.surfacePage)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(MuseTheme.Semantic.textHeading, in: Capsule())
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
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
