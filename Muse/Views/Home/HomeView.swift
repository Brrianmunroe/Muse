import SwiftUI
import SwiftData
import UIKit

struct HomeView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \LocalMuseImage.createdAt, order: .reverse) private var images: [LocalMuseImage]

    @State private var layoutMode: GalleryLayoutMode = .vast
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
    @State private var showViewPopover = false
    @State private var keyboardHeight: CGFloat = 0
    @FocusState private var searchFieldFocused: Bool

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
            // Let the gallery draw up under the status bar so photos can pass beneath
            // it. Applied once here (not on the canvas) so it can't feed the canvas's
            // own size measurement into a layout loop.
            .ignoresSafeArea(.container, edges: .top)
        }
        .overlay(alignment: .top) {
            // Opaque page color at the very top edge fading to transparent, so photos
            // appear to slide underneath the status bar / battery. Lives at the screen
            // root (never on the canvas) and ignores touches, so it can't affect canvas
            // sizing or gestures.
            if displayedTileID == nil {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [MuseTheme.Semantic.surfacePage, MuseTheme.Semantic.surfacePage.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: proxy.safeAreaInsets.top + 16)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .ignoresSafeArea(.container, edges: .top)
                .allowsHitTesting(false)
            }
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

            // Fixed buttons — Add (leading) and View (trailing). They never move or
            // fade; the keyboard simply covers and reveals them.
            if displayedTileID == nil {
                HStack {
                    addButton
                    Spacer()
                    viewButton
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }

            // The single search bar + its suggestions card. One bottom-anchored
            // stack the keyboard lifts (manual offset) so the bar's rise and
            // stretch ride a single clock and land at the right size/place.
            if displayedTileID == nil {
                VStack(spacing: 10) {
                    if showSearch {
                        SearchFilterView(searchText: $searchText, activeFacets: $activeFacets)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    searchBar
                        .padding(.horizontal, showSearch ? 0 : 72)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .offset(y: -keyboardOverlap)
            }
        }
        // Opt the whole gallery out of keyboard avoidance so the buttons never move
        // and the search bar rises only by its single manual offset (no double rise).
        .ignoresSafeArea(.keyboard, edges: .bottom)
        // Tap-catcher that dismisses the view popover.
        .overlay {
            if showViewPopover && displayedTileID == nil {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showViewPopover = false } }
            }
        }
        // View-mode popover rising out of the View button.
        .overlay(alignment: .bottomTrailing) {
            if showViewPopover && displayedTileID == nil && !showSearch {
                viewPopover
                    .padding(.trailing, 20)
                    .padding(.bottom, 80)
                    .transition(.scale(scale: 0.85, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            handleKeyboard(note, showing: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { note in
            handleKeyboard(note, showing: false)
        }
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

    /// Drives the bar's rise + stretch off the keyboard's own show/hide — its
    /// duration (so they're in lockstep) but our view-switch easing curve.
    private func handleKeyboard(_ note: Notification, showing: Bool) {
        let info = note.userInfo
        let height: CGFloat = showing
            ? (info?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height ?? keyboardHeight
            : 0
        // Rise on a soft spring so the bar glides up alongside the keyboard and
        // eases into its spot without a hard stop. Dismiss runs a gentle ease-out.
        let animation: Animation = showing
            ? .spring(response: 0.36, dampingFraction: 0.86)
            : .easeOut(duration: 0.25)
        withAnimation(animation) {
            keyboardHeight = height
            showSearch = showing
            if showing { showViewPopover = false }
        }
    }

    private func clearAllFilters() {
        withAnimation(.easeInOut(duration: 0.25)) {
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

    /// The resting search + filter capsule. Shows a placeholder when idle, or the
    /// active filter pills + a clear-all ✕ when filtering. Tapping it (anywhere but
    /// a pill or the ✕) lifts into the keyboard-docked typing bar.
    private var sortedActiveFacets: [String] {
        activeFacets.sorted { Taxonomy.value(of: $0) < Taxonomy.value(of: $1) }
    }

    /// A removable filter pill — lives *inside* the search bar so it rides the
    /// bar's morph as part of the same element.
    private func facetChip(_ token: String) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.2)) { _ = activeFacets.remove(token) } } label: {
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
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(MuseTheme.Semantic.iconDefault)

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
            // Hug content height so it stays vertically centered (otherwise the
            // scroll view fills the bar and the trailing button looks like it floats low).
            .fixedSize(horizontal: false, vertical: true)

            // Stable trailing slot — always present so it rides the bar's offset
            // (never pops to the bottom). Chevron when active, clear-✕ when resting
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
                        .background(MuseTheme.Semantic.surfacePage, in: Circle())
                }
                .buttonStyle(.plain)
                .opacity((!showSearch && hasActiveFilters) ? 1 : 0)
                .allowsHitTesting(!showSearch && hasActiveFilters)
            }
            .frame(width: 28, height: 28)
            .opacity(showSearch || hasActiveFilters ? 1 : 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
        .frame(maxWidth: .infinity)
        .background(MuseTheme.Semantic.surfaceCard, in: Capsule())
        .overlay(Capsule().stroke(MuseTheme.Semantic.dividerDefault, lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
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

    /// Solo floating View button → opens the mode popover. Shows the current mode.
    private var viewButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { showViewPopover.toggle() }
        } label: {
            Image(systemName: layoutMode.iconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(showViewPopover ? MuseTheme.Semantic.surfacePage : MuseTheme.Semantic.iconDefault)
                .frame(width: 56, height: 56)
                .background(
                    showViewPopover ? MuseTheme.Semantic.textHeading : MuseTheme.Semantic.surfaceCard,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(MuseTheme.Semantic.dividerDefault, lineWidth: showViewPopover ? 0 : 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        }
    }

    /// The little window that pops up out of the View button.
    private var viewPopover: some View {
        VStack(spacing: 2) {
            ForEach(GalleryLayoutMode.allCases) { m in
                Button {
                    layoutMode = m
                    withAnimation(.easeInOut(duration: 0.2)) { showViewPopover = false }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: m.iconName).font(.system(size: 15)).frame(width: 20)
                        Text(m.label).font(.system(size: 15, weight: m == layoutMode ? .semibold : .regular))
                        Spacer()
                        if m == layoutMode {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .foregroundStyle(m == layoutMode ? MuseTheme.Semantic.textHeading : MuseTheme.Semantic.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity)
                    .background(
                        m == layoutMode ? MuseTheme.Semantic.surfacePage : Color.clear,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .frame(width: 188)
        .background(MuseTheme.Semantic.surfaceCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(MuseTheme.Semantic.dividerDefault, lineWidth: 1))
        .shadow(color: .black.opacity(0.16), radius: 22, y: 8)
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
