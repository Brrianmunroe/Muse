import SwiftUI
import SwiftData
import UIKit

struct HomeView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \LocalMuseImage.createdAt, order: .reverse) private var images: [LocalMuseImage]

    @State private var layoutMode: GalleryLayoutMode = .vast
    /// Whether the nav bar's view-mode picker is open (owned here so the shared
    /// search icon can be hidden while it is).
    @State private var viewModeExpanded = false
    @State private var displayedTileID: Int?
    @State private var isExpanded = false
    @State private var sourceFrame: CGRect = .zero
    @StateObject private var tuning = MorphTuning()
    @State private var showImagePicker = false

    // Filtering / search state.
    @State private var activeFacets: Set<String> = []
    @State private var sortOrder: GallerySortOrder = .recency
    @State private var searchText: String = ""
    @State private var showSearch = false
    @State private var keyboardHeight: CGFloat = 0
    @FocusState private var searchFieldFocused: Bool
    /// Shared so the nav bar morphs into the search field and back.
    @Namespace private var navMorph

    /// The full, unfiltered tile set — the canvas keeps all tiles so filtered-out
    /// ones can fade in place rather than vanish.
    private var tiles: [MuseTile] { images.map(\.asTile) }

    private var hasActiveFilters: Bool { !activeFacets.isEmpty || !searchText.isEmpty }

    /// IDs that pass the current filter in sort/rank order, or `nil` when nothing
    /// is filtering.
    private var orderedVisibleIDs: [Int]? {
        guard hasActiveFilters else { return nil }
        return filteredImages.map(\.intID)
    }

    /// Pipeline: locked-tag filter (smart) → free-text fuzzy rank → sort.
    private var filteredImages: [LocalMuseImage] {
        var result = images

        // Facet filter — OR within a category, AND across categories.
        if !activeFacets.isEmpty {
            let byCategory = Dictionary(grouping: activeFacets) { Taxonomy.parse($0)?.category }
            result = result.filter { image in
                byCategory.allSatisfy { category, tokens in
                    category == nil || tokens.contains { image.facetTags.contains($0) }
                }
            }
        }

        // Free text: when present it both filters and ranks by overlap;
        // otherwise honor the chosen sort order.
        let words = searchText.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !words.isEmpty else { return sortedImages(result) }
        return result
            .map { (image: $0, score: overlap($0, words)) }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .map(\.image)
    }

    /// Count of query words that match a card's tags, description, or notes.
    private func overlap(_ image: LocalMuseImage, _ words: [String]) -> Int {
        let haystack = (image.tagLabels + image.facetTags.map { Taxonomy.value(of: $0) }).map { $0.lowercased() }
        let text = ((image.aiDescription ?? "") + " " + image.notes).lowercased()
        return words.reduce(0) { acc, w in
            let hit = haystack.contains { $0.contains(w) || w.contains($0) } || text.contains(w)
            return acc + (hit ? 1 : 0)
        }
    }

    private func sortedImages(_ arr: [LocalMuseImage]) -> [LocalMuseImage] {
        switch sortOrder {
        case .recency: return arr.sorted { $0.createdAt > $1.createdAt }
        case .oldest:  return arr.sorted { $0.createdAt < $1.createdAt }
        case .discipline, .color:
            guard let cat = sortOrder.groupingCategory else { return arr }
            return arr.sorted {
                let a = facetValue($0, cat) ?? "~"
                let b = facetValue($1, cat) ?? "~"
                return a == b ? $0.createdAt > $1.createdAt : a < b
            }
        }
    }

    private func facetValue(_ image: LocalMuseImage, _ category: FacetCategory) -> String? {
        image.facetTags.lazy.compactMap { Taxonomy.parse($0) }.first { $0.category == category }?.value
    }

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
            .ignoresSafeArea(.container, edges: [.top, .bottom])
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
                importImage(image)
            }
        }
        .onAppear {
            importPendingShares()
            backfillFacets()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                importPendingShares()
                backfillFacets()
            }
        }
    }

    /// Backfill controlled facet tags onto images saved before tagging existed.
    /// `analyzeIfNeeded` dedupes in-flight work; we cap each pass to a handful so
    /// a large library doesn't fire a burst of edge-function calls at once.
    private func backfillFacets() {
        guard SupabaseService.shared.isConfigured else {
            #if DEBUG
            seedDemoFacets()  // simulator without keys → fake tags so filters work
            #endif
            return
        }
        let pending = images.filter { $0.facetsAnalyzedAt == nil }
        for image in pending.prefix(4) {
            ImageAnalysisService.analyzeIfNeeded(image, context: modelContext)
        }
    }

    #if DEBUG
    /// Assigns deterministic placeholder facets to untagged images so the filter
    /// can be exercised in the simulator. Never runs in release.
    private func seedDemoFacets() {
        let untagged = images.filter { $0.facetTags.isEmpty }
        guard !untagged.isEmpty else { return }
        for image in untagged {
            image.facetTags = Taxonomy.demoTags(seed: image.intID)
            image.facetsAnalyzedAt = .now
        }
        try? modelContext.save()
    }
    #endif

    /// Save an image into the gallery and start its AI description, exactly the
    /// same path whether it came from the picker or the share extension.
    private func importImage(_ image: UIImage, sourceApp: String? = nil) {
        guard let paths = try? LocalImageStore.save(image: image) else { return }
        let record = LocalMuseImage(
            localPath: paths.localPath,
            thumbnailPath: paths.thumbnailPath,
            width: paths.width,
            height: paths.height,
            sourceApp: sourceApp
        )
        modelContext.insert(record)
        // Kick off the AI design description + tags in the background.
        ImageAnalysisService.analyzeIfNeeded(record, context: modelContext)
        try? modelContext.save()
    }

    /// Drain any images dropped in by the share extension. Runs on open and
    /// whenever the app returns to the foreground.
    private func importPendingShares() {
        for url in SharedInbox.pendingFiles() {
            if let image = UIImage(contentsOfFile: url.path) {
                importImage(image, sourceApp: "Shared")
            }
            SharedInbox.remove(url)
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
                orderedVisibleIDs: orderedVisibleIDs,
                onSelectTile: openTile,
                onSelectedTileFrame: { sourceFrame = $0 },
                tuning: tuning
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if hasActiveFilters && filteredImages.isEmpty {
                    VStack(spacing: 8) {
                        Text("No matches")
                            .font(MuseTheme.serif(22))
                            .foregroundStyle(MuseTheme.Semantic.textHeading)
                        Text("Try removing a filter")
                            .font(.subheadline)
                            .foregroundStyle(MuseTheme.Semantic.textSecondary)
                    }
                    .transition(.opacity)
                }
            }

            // Subtle scrim while searching; tap it to dismiss.
            if showSearch {
                Color.black.opacity(0.12)
                    .ignoresSafeArea()
                    .onTapGesture { searchFieldFocused = false }
                    .transition(.opacity)
            }

            // The bottom bar. At rest it's the consolidated nav pill; tapping
            // search morphs it (shared namespace) into the keyboard-docked search
            // field + suggestions card. One bottom-anchored stack the keyboard
            // lifts (manual offset) so the rise and stretch ride a single clock.
            VStack(spacing: 10) {
                    // The search bar stays as long as it's being typed in OR holds
                    // active filters — so dismissing the keyboard while populated drops
                    // it to rest (keyboard down → offset 0) instead of collapsing. It
                    // only returns to the compact nav bar once it's empty.
                    if showSearch || hasActiveFilters {
                        // Suggestions only while actively typing.
                        if showSearch {
                            SearchFilterView(searchText: $searchText, activeFacets: $activeFacets)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                        searchBar
                            // Fade the search bar's content out fast on collapse so the
                            // trailing ✕/chips vanish while the bar is still wide.
                            .transition(.asymmetric(
                                insertion: .opacity,
                                removal: .opacity.animation(.easeOut(duration: 0.14))
                            ))
                    } else {
                        MuseNavBar(
                            layoutMode: $layoutMode,
                            viewModeExpanded: $viewModeExpanded,
                            namespace: navMorph,
                            onAdd: { showImagePicker = true },
                            onSearch: { openSearch() }
                        )
                        // Appear with NO fade so the frosted fill stays solid the whole
                        // time it shrinks into place (its icons fade in after, via the
                        // bar's iconsVisible delay). Fade out normally when opening search.
                        .transition(.asymmetric(insertion: .identity, removal: .opacity))
                    }
                }
                .overlay(alignment: .topLeading) {
                    // THE search icon — ONE persistent view that follows the active
                    // form's anchor, so it's on screen the whole time and only glides
                    // position (never fades/inserts). It's never removed — only its
                    // opacity changes — so closing the view-mode picker just fades it
                    // back IN PLACE (no scaling in from a corner). Taps pass through.
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(MuseTheme.Semantic.accentSelected)
                        .frame(width: 24, height: 24)
                        .matchedGeometryEffect(id: "searchSlot", in: navMorph, isSource: false)
                        .allowsHitTesting(false)
                        .opacity(viewModeExpanded ? 0 : 1)
                        .animation(.easeInOut(duration: 0.2), value: viewModeExpanded)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
                .offset(y: -keyboardOverlap)
                .allowsHitTesting(displayedTileID == nil)
        }
        // Opt the whole gallery out of keyboard avoidance so the bar never moves
        // and the search bar rises only by its single manual offset (no double rise).
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            handleKeyboard(note, showing: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { note in
            handleKeyboard(note, showing: false)
        }
        // A light tick as the search field opens / closes.
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: showSearch)
    }

    /// How far the search bar lifts to sit 16pt above the keyboard. (The bar
    /// already has 12pt bottom padding, so add 4 to reach a 16pt gap.)
    private var keyboardOverlap: CGFloat {
        keyboardHeight <= 0 ? 0 : max(0, keyboardHeight - bottomSafeInset + 4)
    }

    private var bottomSafeInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.safeAreaInsets.bottom ?? 0
    }

    /// Open search from the nav bar. The search field only exists while
    /// `showSearch` is true, so render it first, then focus on the next runloop
    /// tick (the field must be in the tree for focus to attach and raise the
    /// keyboard). The keyboard's own animation then lifts the bar — see `handleKeyboard`.
    private func openSearch() {
        withAnimation(.museBar) { showSearch = true }
        DispatchQueue.main.async { searchFieldFocused = true }
    }

    /// Drives the bar's rise + stretch off the keyboard's own show/hide — its
    /// duration (so they're in lockstep) but our view-switch easing curve.
    private func handleKeyboard(_ note: Notification, showing: Bool) {
        let info = note.userInfo
        let height: CGFloat = showing
            ? (info?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height ?? keyboardHeight
            : 0
        // Rise + dismiss ride the shared bar spring so the search morph feels like
        // the same physical object as the rest of the bar.
        withAnimation(.museBar) {
            keyboardHeight = height
            showSearch = showing
        }
    }

    private func clearAllFilters() {
        withAnimation(.museBar) {
            activeFacets.removeAll()
            searchText = ""
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

    /// The resting search + filter capsule. Shows a placeholder when idle, or the
    /// active filter pills + a clear-all ✕ when filtering. Tapping it (anywhere but
    /// a pill or the ✕) lifts into the keyboard-docked typing bar.
    private var sortedActiveFacets: [String] {
        activeFacets.sorted { Taxonomy.value(of: $0) < Taxonomy.value(of: $1) }
    }

    /// A removable filter pill — lives *inside* the search bar so it rides the
    /// bar's morph as part of the same element.
    private func facetChip(_ token: String) -> some View {
        Button { withAnimation(.museBar) { _ = activeFacets.remove(token) } } label: {
            HStack(spacing: 4) {
                Text(Taxonomy.value(of: token)).font(.system(size: 13, weight: .medium))
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).opacity(0.55)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(MuseTheme.Alias.fillTintNeutral, in: Capsule())
            .foregroundStyle(MuseTheme.Alias.textOnTintNeutral)
        }
        .buttonStyle(.plain)
    }

    /// The single search bar — one capsule that morphs between resting and active.
    /// Active-filter pills live inside it (a token field) so they travel with the
    /// bar through the transition; the field placeholder stays "Search inspiration".
    private var searchBar: some View {
        // The morphing capsule is the CONTAINER; the content lives in its overlay and
        // is clipped to it. So when the bar collapses (the matched background shrinks to
        // the compact pill), the trailing ✕ and chips move inward and clip with it —
        // they stay part of the bar instead of floating outside as it shrinks.
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(Capsule().fill(MuseTheme.Semantic.navBarSurface.opacity(0.8)))
            .overlay(Capsule().stroke(MuseTheme.Semantic.navBarStroke, lineWidth: 0.5))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .matchedGeometryEffect(id: "barBG", in: navMorph)
            .overlay {
                HStack(spacing: 8) {
                    // Invisible anchor — the visible search icon is a persistent overlay
                    // (see the bottom bar's `.overlay`) so it never fades when forms swap.
                    Color.clear
                        .frame(width: 24, height: 24)
                        .matchedGeometryEffect(id: "searchSlot", in: navMorph, isSource: true)

                    // One stable token field: pills (a ForEach) then a persistent field.
                    // Keeping the field in the same structural slot means adding a chip
                    // doesn't rebuild it, so focus (and the keyboard) is never lost.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(sortedActiveFacets, id: \.self) { token in
                                facetChip(token)
                            }
                            searchField(placeholder: activeFacets.isEmpty ? "Search inspiration" : "")
                                .frame(minWidth: 160)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    // Stable trailing slot — chevron when active, clear-✕ when resting
                    // with filters, cross-faded in place.
                    ZStack {
                        Button { searchFieldFocused = false } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(MuseTheme.Semantic.iconDefault)
                                .frame(width: 28, height: 28)
                        }
                        .opacity(showSearch ? 1 : 0)
                        .allowsHitTesting(showSearch)

                        Button { clearAllFilters() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(MuseTheme.Semantic.textSecondary)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .opacity((!showSearch && hasActiveFilters) ? 1 : 0)
                        .allowsHitTesting(!showSearch && hasActiveFilters)
                    }
                    .frame(width: 28, height: 28)
                    .opacity(showSearch || hasActiveFilters ? 1 : 0)
                }
                .padding(.horizontal, 16)
            }
            .clipShape(Capsule())
            .shadow(color: Color(red: 0.5, green: 0.5, blue: 0.5).opacity(0.2), radius: 1, x: 2, y: 2)
            .shadow(color: Color(red: 0.5, green: 0.5, blue: 0.5).opacity(0.15), radius: 2, x: 4, y: 4)
            .contentShape(Capsule())
            .onTapGesture { if !showSearch { searchFieldFocused = true } }
    }

    private func searchField(placeholder: String) -> some View {
        TextField(placeholder, text: $searchText)
            .font(.system(size: 16))
            .foregroundStyle(MuseTheme.Semantic.textBody)
            .focused($searchFieldFocused)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
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
