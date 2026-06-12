import SwiftUI

/// Gallery canvas for real `MuseTile` images — identical logic to `GalleryCanvasView`
/// but renders actual photos from local storage instead of gradient placeholders.
struct MuseGalleryCanvasView: View {
    @Binding var mode: GalleryLayoutMode
    @Binding var selectedTileID: Int?
    let tiles: [MuseTile]
    var onSelectTile: (Int, CGRect) -> Void
    /// Reports where the currently-selected tile sits, so the detail overlay
    /// can dismiss back to the right spot after swiping to another photo.
    var onSelectedTileFrame: ((CGRect) -> Void)? = nil
    @ObservedObject var tuning: MorphTuning

    @State private var placements: [Int: TilePlacement] = [:]
    @State private var contentSize: CGSize = .zero
    @State private var contentOffset: CGPoint = .zero
    @State private var blurAmounts: [Int: CGFloat] = [:]
    @State private var leadTileID: Int?
    @State private var viewport: CGSize = .zero
    @State private var currentPage: Int = 0
    @State private var zoomScale: CGFloat = 1
    @State private var canvasPanActive = false
    /// Canvas global frame captured at tap time, before the gallery is
    /// scaled/blurred behind the detail overlay.
    @State private var frozenCanvasFrame: CGRect = .zero
    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var magnifyBy: CGFloat = 1

    private static let settleSpring = Animation.spring(response: 0.45, dampingFraction: 1.0)
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
            .onChange(of: tiles.count) { _, _ in configure(viewport: viewport, animated: false) }
            .onChange(of: selectedTileID) { _, newID in
                guard let newID else { return }
                publishSelectedTileFrame(for: newID)
            }
        }
        .clipped()
        .onChange(of: mode) { oldMode, newMode in
            if newMode != .vast { zoomScale = 1 }
            transition(from: oldMode, to: newMode)
        }
    }

    // MARK: - Tile rendering

    private func tileView(_ tile: MuseTile, _ placement: TilePlacement, offset: CGPoint, zoom: CGFloat, canvasFrame: CGRect) -> some View {
        let isSelected = selectedTileID == tile.id
        let width = placement.frame.width * zoom
        let height = placement.frame.height * zoom
        let localCenterX = (placement.frame.midX - offset.x) * zoom
        let localCenterY = (placement.frame.midY - offset.y) * zoom
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
                        frozenCanvasFrame = canvasFrame
                        onSelectTile(tile.id, globalRect)
                    }
            } else {
                Color.clear.frame(width: width, height: height)
            }
        }
        .position(x: localCenterX, y: localCenterY)
        .zIndex(leadTileID == tile.id ? 1 : 0)
    }

    private func tileContent(_ tile: MuseTile, _ placement: TilePlacement, zoom: CGFloat) -> some View {
        let w = placement.frame.width * zoom
        let h = placement.frame.height * zoom

        return Group {
            if let thumbPath = tile.thumbnailPath,
               let uiImage = ImageCache.thumbnail(for: thumbPath) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: w, height: h)
                    .clipped()
            } else {
                Color(white: 0.18)
                    .frame(width: w, height: h)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .rotationEffect(placement.rotation)
        .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
        .blur(radius: blurAmounts[tile.id] ?? 0)
    }

    /// Recomputes the selected tile's global frame from layout state — same math
    /// as the tap handler — so a swipe in the detail view retargets the dismiss.
    private func publishSelectedTileFrame(for id: Int) {
        guard let placement = placements[id], frozenCanvasFrame != .zero else { return }
        let zoom = effectiveZoom
        let offset = displayedOffset
        let width = placement.frame.width * zoom
        let height = placement.frame.height * zoom
        let localCenterX = (placement.frame.midX - offset.x) * zoom
        let localCenterY = (placement.frame.midY - offset.y) * zoom
        let rect = CGRect(
            x: frozenCanvasFrame.minX + localCenterX - width / 2,
            y: frozenCanvasFrame.minY + localCenterY - height / 2,
            width: width,
            height: height
        )
        onSelectedTileFrame?(rect)
    }

    // MARK: - Mode transitions

    private func transition(from oldMode: GalleryLayoutMode, to newMode: GalleryLayoutMode) {
        guard viewport.width > 50, viewport.height > 50 else { return }
        let spec = tuning.spec(from: oldMode, to: newMode)
        let layout = GalleryLayoutEngine.layout(mode: newMode, tiles: tiles, viewport: viewport)

        let anchorID = currentAnchorTile(oldMode: oldMode)
        let newOffset = anchoredOffset(for: newMode, layout: layout, anchorID: anchorID)

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
            let delay = Double(trip / maxTrip) * spec.stagger
            let response = tileResponse(forTrip: trip)

            withAnimation(morphAnimation(response: response).delay(delay)) {
                placements[tile.id] = layout.placements[tile.id] ?? .zero
            }

            let peakBlur = min(CGFloat(spec.blurPeak), (distances[tile.id] ?? 0) / 110)
            if peakBlur > 0.5 {
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

    private func anchoredOffset(for newMode: GalleryLayoutMode, layout: GalleryLayout, anchorID: Int?) -> CGPoint {
        guard let anchorID, let frame = layout.placements[anchorID]?.frame else {
            return layout.initialOffset
        }
        switch newMode {
        case .feed:
            guard let index = tiles.firstIndex(where: { $0.id == anchorID }) else { return layout.initialOffset }
            return CGPoint(x: 0, y: CGFloat(index) * viewport.height)
        case .vast:
            let raw = CGPoint(x: frame.midX - viewport.width / 2, y: frame.midY - viewport.height / 2)
            return clampToContent(raw, contentSize: layout.contentSize)
        case .bento:
            let raw = CGPoint(x: 0, y: frame.midY - viewport.height / 2)
            return clampToContent(raw, contentSize: layout.contentSize)
        }
    }

    private func clampToContent(_ point: CGPoint, contentSize: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), max(0, contentSize.width - viewport.width)),
            y: min(max(point.y, 0), max(0, contentSize.height - viewport.height))
        )
    }

    private func configure(viewport newViewport: CGSize, animated: Bool) {
        guard newViewport.width > 50, newViewport.height > 50 else { return }
        guard newViewport != viewport || placements.isEmpty else { return }

        let hadLayout = viewport.width > 50 && !placements.isEmpty
        viewport = newViewport

        let layout = GalleryLayoutEngine.layout(mode: mode, tiles: tiles, viewport: newViewport)
        if animated && hadLayout {
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { canvasPanActive = false }
            }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .updating($magnifyBy) { value, state, _ in state = value }
            .onEnded { value in zoomScale = min(max(zoomScale * value, Self.minZoom), Self.maxZoom) }
    }

    private var displayedOffset: CGPoint {
        let zoom = effectiveZoom
        let translation = restrictedTranslation(dragTranslation)
        let raw = CGPoint(
            x: contentOffset.x - translation.width / zoom,
            y: contentOffset.y - translation.height / zoom
        )
        return rubberClamped(raw, zoom: zoom)
    }

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
            withAnimation(Self.settleSpring) { contentOffset = target }

        case .feed:
            let pageHeight = viewport.height
            guard pageHeight > 0 else { return }
            let flick = -(predicted.height)
            var newPage = currentPage
            if flick > pageHeight * 0.18 { newPage += 1 }
            else if flick < -pageHeight * 0.18 { newPage -= 1 }
            newPage = max(0, min(tiles.count - 1, newPage))
            currentPage = newPage
            withAnimation(Self.settleSpring) {
                contentOffset = CGPoint(x: 0, y: CGFloat(newPage) * pageHeight)
            }
        }
    }

    private func maxOffset(zoom: CGFloat) -> CGPoint {
        CGPoint(
            x: max(0, contentSize.width - viewport.width / zoom),
            y: max(0, contentSize.height - viewport.height / zoom)
        )
    }

    private func hardClamped(_ point: CGPoint, zoom: CGFloat) -> CGPoint {
        let bounds = maxOffset(zoom: zoom)
        return CGPoint(x: min(max(point.x, 0), bounds.x), y: min(max(point.y, 0), bounds.y))
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
