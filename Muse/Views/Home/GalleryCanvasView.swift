import SwiftUI

/// A single canvas that holds every tile and morphs them between the three
/// layout modes. Each tile is absolutely positioned from the layout engine's
/// output, so switching modes animates every tile from its old frame to its
/// new one — the same trick in every direction, which is what makes the
/// explosion/collapse feel seamless and reversible.
struct GalleryCanvasView: View {
    @Binding var mode: GalleryLayoutMode
    /// The tile currently owned by the detail overlay. While non-nil the canvas
    /// hides that cell (the hero is flying it) and ignores input.
    @Binding var selectedTileID: Int?
    let tiles: [SampleTile]
    /// Reports the tapped tile's id together with its exact on-screen rect in
    /// global coordinates. The detail hero starts from that precise rect, so the
    /// image scales up from where it actually sits — no matched-geometry guessing.
    var onSelectTile: (Int, CGRect) -> Void
    /// Live-dialed morph specs per transition direction (see MorphTuningPanel).
    @ObservedObject var tuning: MorphTuning

    @State private var placements: [Int: TilePlacement] = [:]
    @State private var contentSize: CGSize = .zero
    @State private var contentOffset: CGPoint = .zero
    @State private var blurAmounts: [Int: CGFloat] = [:]
    /// The lead tile of the current mode morph (longest trip — e.g. the one
    /// blowing up to fullscreen). Drawn on top so neighbors slide behind it.
    @State private var leadTileID: Int?
    @State private var viewport: CGSize = .zero
    @State private var currentPage: Int = 0
    @State private var zoomScale: CGFloat = 1
    @State private var canvasPanActive = false
    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var magnifyBy: CGFloat = 1

    private static let settleSpring = Animation.spring(response: 0.45, dampingFraction: 1.0)
    /// Minimum drag before canvas pan activates — keeps taps on tiles distinct.
    private static let panMinimumDistance: CGFloat = 18
    private static let minZoom: CGFloat = 1
    private static let maxZoom: CGFloat = 4

    private var effectiveZoom: CGFloat {
        min(max(zoomScale * magnifyBy, Self.minZoom), Self.maxZoom)
    }

    var body: some View {
        GeometryReader { geo in
            let offset = displayedOffset
            let zoom = effectiveZoom
            // The canvas's own origin in global space. Combined with each tile's
            // local position below, this gives an exact global rect at tap time —
            // synchronously, so the very first tap in a view is never wrong.
            let canvasFrame = geo.frame(in: .global)

            ZStack(alignment: .topLeading) {
                ForEach(tiles) { tile in
                    if let placement = placements[tile.id] {
                        tileView(tile, placement, offset: offset, zoom: zoom, canvasFrame: canvasFrame)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(selectedTileID == nil ? canvasGesture : nil)
            .simultaneousGesture(selectedTileID == nil && mode == .vast ? zoomGesture : nil)
            .onAppear { configure(viewport: geo.size, animated: false) }
            .onChange(of: geo.size) { _, newSize in configure(viewport: newSize, animated: true) }
        }
        .clipped()
        .onChange(of: mode) { oldMode, newMode in
            if newMode != .vast {
                zoomScale = 1
            }
            transition(from: oldMode, to: newMode)
        }
    }

    // MARK: - Tile rendering

    private func tileView(_ tile: SampleTile, _ placement: TilePlacement, offset: CGPoint, zoom: CGFloat, canvasFrame: CGRect) -> some View {
        let isSelected = selectedTileID == tile.id
        let width = placement.frame.width * zoom
        let height = placement.frame.height * zoom
        let localCenterX = (placement.frame.midX - offset.x) * zoom
        let localCenterY = (placement.frame.midY - offset.y) * zoom
        // The cell's rect in global space, derived from the canvas origin — the
        // exact frame the detail hero launches from and returns to.
        let globalRect = CGRect(
            x: canvasFrame.minX + localCenterX - width / 2,
            y: canvasFrame.minY + localCenterY - height / 2,
            width: width,
            height: height
        )

        return Group {
            if !isSelected {
                tileContent(tile, placement, zoom: zoom)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard selectedTileID == nil, !canvasPanActive else { return }
                        onSelectTile(tile.id, globalRect)
                    }
            } else {
                Color.clear
                    .frame(width: width, height: height)
            }
        }
        .position(x: localCenterX, y: localCenterY)
        .zIndex(leadTileID == tile.id ? 1 : 0)
    }

    private func tileContent(_ tile: SampleTile, _ placement: TilePlacement, zoom: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(tile.gradient)
            .frame(width: placement.frame.width * zoom, height: placement.frame.height * zoom)
            .rotationEffect(placement.rotation)
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            .blur(radius: blurAmounts[tile.id] ?? 0)
    }

    // MARK: - Mode transitions

    private func transition(from oldMode: GalleryLayoutMode, to newMode: GalleryLayoutMode) {
        guard viewport.width > 50, viewport.height > 50 else { return }
        let spec = tuning.spec(from: oldMode, to: newMode)

        let layout = GalleryLayoutEngine.layout(mode: newMode, tiles: tiles, viewport: viewport)

        // Location continuity: the tile in front of the user becomes the focus
        // of the new mode — feed opens on its page, vast/bento arrive scrolled
        // to it.
        let anchorID = currentAnchorTile(oldMode: oldMode)
        let newOffset = anchoredOffset(for: newMode, layout: layout, anchorID: anchorID)

        // Rebase: snap the offset to its destination and shift every current
        // placement to compensate — on-screen nothing moves. From here only the
        // placements animate, so each tile travels a dead-straight line to its
        // final spot instead of arcing on the composite of two curves.
        let delta = CGPoint(x: newOffset.x - contentOffset.x, y: newOffset.y - contentOffset.y)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            contentOffset = newOffset
            for (id, placement) in placements {
                var shifted = placement
                shifted.frame = placement.frame.offsetBy(dx: delta.x, dy: delta.y)
                placements[id] = shifted
            }
        }

        // Each tile's trip counts both how far it travels and how much it resizes —
        // the lead tile blowing up to fullscreen is a long trip even though its
        // center barely moves.
        var trips: [Int: CGFloat] = [:]
        var distances: [Int: CGFloat] = [:]
        var maxTrip: CGFloat = 1
        var leadID: Int?
        for tile in tiles {
            let oldFrame = placements[tile.id]?.frame ?? .zero
            let newFrame = layout.placements[tile.id]?.frame ?? .zero
            let distance = hypot(newFrame.midX - oldFrame.midX, newFrame.midY - oldFrame.midY)
            distances[tile.id] = distance
            trips[tile.id] = distance + abs(newFrame.width - oldFrame.width)
            if trips[tile.id] ?? 0 > maxTrip {
                maxTrip = trips[tile.id] ?? 0
                leadID = tile.id
            }
        }
        leadTileID = leadID

        contentSize = layout.contentSize
        if newMode == .feed, let anchorID, let index = tiles.firstIndex(where: { $0.id == anchorID }) {
            currentPage = index
        } else {
            currentPage = 0
        }

        // Each tile rides its own curve sized to its own trip: small hops stay
        // snappy while the fullscreen blow-up spreads across the whole transition
        // instead of slamming in early. All knobs come from this direction's spec.
        // Wiggle > 0 uses a spring (fast start, bouncy settle); wiggle 0 swaps to
        // a symmetric easy-ease that starts as smoothly as it ends.
        func tileResponse(forTrip trip: CGFloat) -> Double {
            let progress = Double(min(trip / max(viewport.height, 1), 1))
            return spec.duration + spec.range * progress
        }
        func morphAnimation(response: Double) -> Animation {
            if spec.wiggle > 0.001 {
                return .spring(response: response, dampingFraction: 1 - spec.wiggle)
            }
            return .timingCurve(spec.c1x, spec.c1y, spec.c2x, spec.c2y, duration: response)
        }

        for tile in tiles {
            let trip = trips[tile.id] ?? 0
            // Stagger by trip, so the gallery parts first and the lead tile —
            // the longest trip — rises into place last.
            let delay = Double(trip / maxTrip) * spec.stagger
            let response = tileResponse(forTrip: trip)

            withAnimation(morphAnimation(response: response).delay(delay)) {
                placements[tile.id] = layout.placements[tile.id] ?? .zero
            }

            let peakBlur = min(CGFloat(spec.blurPeak), (distances[tile.id] ?? 0) / 110)
            if peakBlur > 0.5 {
                // Blur parabola scaled to this tile's own travel time.
                withAnimation(.easeIn(duration: response * 0.3).delay(delay)) {
                    blurAmounts[tile.id] = peakBlur
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + delay + response * 0.55) {
                    withAnimation(.easeOut(duration: response * 0.7)) {
                        blurAmounts[tile.id] = 0
                    }
                }
            }
        }
    }

    /// The tile the user is visually focused on in the outgoing mode: feed's
    /// current page, or whichever tile sits nearest the viewport center.
    private func currentAnchorTile(oldMode: GalleryLayoutMode) -> Int? {
        if oldMode == .feed, tiles.indices.contains(currentPage) {
            return tiles[currentPage].id
        }
        let zoom = effectiveZoom
        let center = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        var best: (id: Int, distance: CGFloat)?
        for tile in tiles {
            guard let frame = placements[tile.id]?.frame else { continue }
            let x = (frame.midX - contentOffset.x) * zoom
            let y = (frame.midY - contentOffset.y) * zoom
            let distance = hypot(x - center.x, y - center.y)
            if best == nil || distance < best!.distance {
                best = (tile.id, distance)
            }
        }
        return best?.id
    }

    /// Where the new layout should land so the anchor tile ends up in front of
    /// the user: feed opens on its page, vast/bento arrive scrolled to it.
    private func anchoredOffset(for newMode: GalleryLayoutMode, layout: GalleryLayout, anchorID: Int?) -> CGPoint {
        guard let anchorID, let frame = layout.placements[anchorID]?.frame else {
            return layout.initialOffset
        }
        switch newMode {
        case .feed:
            guard let index = tiles.firstIndex(where: { $0.id == anchorID }) else {
                return layout.initialOffset
            }
            return CGPoint(x: 0, y: CGFloat(index) * viewport.height)
        case .vast:
            let raw = CGPoint(x: frame.midX - viewport.width / 2, y: frame.midY - viewport.height / 2)
            return clampToContent(raw, contentSize: layout.contentSize)
        case .bento:
            let raw = CGPoint(x: 0, y: frame.midY - viewport.height / 2)
            return clampToContent(raw, contentSize: layout.contentSize)
        }
    }

    /// Clamp against an explicit content size (the incoming layout's, which may
    /// not be committed to state yet when this runs).
    private func clampToContent(_ point: CGPoint, contentSize: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), max(0, contentSize.width - viewport.width)),
            y: min(max(point.y, 0), max(0, contentSize.height - viewport.height))
        )
    }

    private func configure(viewport newViewport: CGSize, animated: Bool) {
        guard newViewport.width > 50, newViewport.height > 50 else { return }
        guard newViewport != viewport else { return }

        let hadLayout = viewport.width > 50 && !placements.isEmpty
        viewport = newViewport

        let layout = GalleryLayoutEngine.layout(mode: mode, tiles: tiles, viewport: newViewport)
        if animated && hadLayout {
            // Gentle uniform reflow — never the staggered transition choreography,
            // whose offset rebase snaps any animation already in flight.
            contentSize = layout.contentSize
            let target = clampToContent(contentOffset, contentSize: layout.contentSize)
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.45)) {
                placements = layout.placements
                contentOffset = target
            }
        } else {
            placements = layout.placements
            contentSize = layout.contentSize
            contentOffset = layout.initialOffset
            currentPage = 0
        }
    }

    // MARK: - Gestures

    private var canvasGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($dragTranslation) { value, state, _ in
                let distance = hypot(value.translation.width, value.translation.height)
                if distance >= Self.panMinimumDistance {
                    canvasPanActive = true
                    state = value.translation
                }
            }
            .onEnded { value in
                let distance = hypot(value.translation.width, value.translation.height)
                if distance >= Self.panMinimumDistance {
                    endDrag(translation: value.translation, predicted: value.predictedEndTranslation)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    canvasPanActive = false
                }
            }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .updating($magnifyBy) { value, state, _ in
                state = value
            }
            .onEnded { value in
                zoomScale = min(max(zoomScale * value, Self.minZoom), Self.maxZoom)
            }
    }

    // MARK: - Scrolling / panning / paging

    private var displayedOffset: CGPoint {
        let zoom = effectiveZoom
        let translation = restrictedTranslation(dragTranslation)
        let raw = CGPoint(
            x: contentOffset.x - translation.width / zoom,
            y: contentOffset.y - translation.height / zoom
        )
        return rubberClamped(raw, zoom: zoom)
    }

    /// Vast pans freely in both axes; bento and feed move vertically only.
    private func restrictedTranslation(_ translation: CGSize) -> CGSize {
        switch mode {
        case .vast: return translation
        case .bento, .feed: return CGSize(width: 0, height: translation.height)
        }
    }

    private func endDrag(translation: CGSize, predicted: CGSize) {
        let zoom = effectiveZoom
        let dragged = restrictedTranslation(translation)
        let committed = rubberClamped(CGPoint(
            x: contentOffset.x - dragged.width / zoom,
            y: contentOffset.y - dragged.height / zoom
        ), zoom: zoom)
        contentOffset = committed

        switch mode {
        case .vast, .bento:
            let momentum = restrictedTranslation(CGSize(
                width: predicted.width - translation.width,
                height: predicted.height - translation.height
            ))
            let target = hardClamped(CGPoint(
                x: committed.x - momentum.width / zoom,
                y: committed.y - momentum.height / zoom
            ), zoom: zoom)
            withAnimation(Self.settleSpring) {
                contentOffset = target
            }

        case .feed:
            let pageHeight = viewport.height
            guard pageHeight > 0 else { return }
            let flick = -(predicted.height)
            var newPage = currentPage
            if flick > pageHeight * 0.18 {
                newPage += 1
            } else if flick < -pageHeight * 0.18 {
                newPage -= 1
            }
            newPage = max(0, min(tiles.count - 1, newPage))
            currentPage = newPage
            withAnimation(Self.settleSpring) {
                contentOffset = CGPoint(x: 0, y: CGFloat(newPage) * pageHeight)
            }
        }
    }

    // MARK: - Bounds

    private func maxOffset(zoom: CGFloat) -> CGPoint {
        CGPoint(
            x: max(0, contentSize.width - viewport.width / zoom),
            y: max(0, contentSize.height - viewport.height / zoom)
        )
    }

    private func hardClamped(_ point: CGPoint, zoom: CGFloat) -> CGPoint {
        let bounds = maxOffset(zoom: zoom)
        return CGPoint(
            x: min(max(point.x, 0), bounds.x),
            y: min(max(point.y, 0), bounds.y)
        )
    }

    private func rubberClamped(_ point: CGPoint, zoom: CGFloat) -> CGPoint {
        let bounds = maxOffset(zoom: zoom)
        return CGPoint(
            x: rubber(point.x, min: 0, max: bounds.x),
            y: rubber(point.y, min: 0, max: bounds.y)
        )
    }

    private func rubber(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        if value < lower { return lower + (value - lower) * 0.25 }
        if value > upper { return upper + (value - upper) * 0.25 }
        return value
    }
}
