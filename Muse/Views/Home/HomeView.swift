import SwiftUI

struct HomeView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var layoutMode: GalleryLayoutMode = .vast
    /// Which tile the detail overlay owns: drives the mount and hides that cell in
    /// the canvas. Set on open, cleared only once the hero finishes flying home.
    @State private var displayedTileID: Int?
    /// The visual open/close state. Everything — hero, gallery blur, scrim — reads
    /// this single flag inside one `withAnimation`, so they move as one motion.
    @State private var isExpanded = false
    /// Exact on-screen rect of the tapped cell — the hero scales up from here.
    @State private var sourceFrame: CGRect = .zero
    @State private var tileNotes: [Int: String] = [:]
    @StateObject private var tuning = MorphTuning()
    @State private var showTuningPanel = false

    var body: some View {
        NavigationStack {
            Group {
                if authViewModel.isPreviewMode {
                    galleryContent
                } else {
                    emptyState
                }
            }
            .blur(radius: isExpanded ? 18 : 0)
            .scaleEffect(isExpanded ? 0.96 : 1)
            .animation(ImageDetailView.transition, value: isExpanded)
            .background(MuseTheme.Semantic.surfacePage.ignoresSafeArea())
            // No top chrome: the gallery owns the full screen, and the nav bar
            // can't reappear mid-dismiss and shove the layout down.
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
            if displayedTileID != nil {
                ImageDetailView(
                    tiles: SampleTile.samples,
                    sourceFrame: sourceFrame,
                    displayedTileID: $displayedTileID,
                    isExpanded: $isExpanded,
                    tileNotes: $tileNotes
                )
            }
        }
    }

    /// Commit a tap: remember the cell's exact rect and mount the overlay. The
    /// detail view flips `isExpanded` true on appear, so the hero scales up and
    /// the gallery blur/scrim fade in on that one shared transaction.
    private func openTile(_ id: Int, _ frame: CGRect) {
        sourceFrame = frame
        displayedTileID = id
    }

    private var galleryContent: some View {
        ZStack(alignment: .bottom) {
            GalleryCanvasView(
                mode: $layoutMode,
                // Bound to displayedTileID: the cell stays hidden until the hero
                // finishes flying home, then reappears with no flicker.
                selectedTileID: $displayedTileID,
                tiles: SampleTile.samples,
                onSelectTile: openTile,
                tuning: tuning
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The header is an overlay, never a safe-area inset: it must not
            // resize the canvas when modes change, or the in-flight morph gets
            // re-laid-out mid-animation and every tile snaps and re-targets.
            // The bento layout reserves top space for it in the layout engine.
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
                HStack(spacing: 10) {
                    GalleryModeToggle(mode: $layoutMode)

                    Button {
                        showTuningPanel = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(MuseTheme.Semantic.iconDefault)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showTuningPanel) {
            MorphTuningPanel(tuning: tuning)
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
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
