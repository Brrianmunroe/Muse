import SwiftUI

/// A single canvas that holds every tile and morphs them between the three
/// layout modes. Each tile is absolutely positioned from the layout engine's
/// output, so switching modes animates every tile from its old frame to its
/// new one — the same trick in every direction, which is what makes the
/// explosion/collapse feel seamless and reversible.
struct GalleryCanvasView: View {
    @Binding var mode: GalleryLayoutMode
    @Binding var selectedTileID: Int?
    let tiles: [SampleTile]
    var detailNamespace: Namespace.ID

    @State private var placements: [Int: TilePlacement] = [:]
    @State private var contentSize: CGSize = .zero
    @State private var contentOffset: CGPoint = .zero
    @State private var blurAmounts: [Int: CGFloat] = [:]
    @State private var viewport: CGSize = .zero
    @State private var currentPage: Int = 0
    @State private var zoomScale: CGFloat = 1
    @State private var canvasPanActive = false
    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var magnifyBy: CGFloat = 1

    private static let morphSpring = Animation.spring(response: 0.55, dampingFraction: 0.82)
    private static let settleSpring = Animation.spring(response: 0.45, dampingFraction: 1.0)
    /// Max extra delay applied to the farthest-travelling tile, selling the
    /// outward-ripple of the big bang and the inward collapse into the grid.
    private static let maxStagger: Double = 0.14
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

            ZStack(alignment: .topLeading) {
                ForEach(tiles) { tile in
                    if let placement = placements[tile.id] {
                        tileView(tile, placement, offset: offset, zoom: zoom)
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
        .onChange(of: mode) { _, newMode in
            if newMode != .vast {
                zoomScale = 1
            }
            transition(to: newMode)
        }
    }

    // MARK: - Tile rendering

    private func tileView(_ tile: SampleTile, _ placement: TilePlacement, offset: CGPoint, zoom: CGFloat) -> some View {
        let isSelected = selectedTileID == tile.id
        let width = placement.frame.width * zoom
        let height = placement.frame.height * zoom

        return Group {
            if !isSelected {
                tileContent(tile, placement, zoom: zoom)
                    .matchedGeometryEffect(id: tile.id, in: detailNamespace)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard selectedTileID == nil, !canvasPanActive else { return }
                        withAnimation(ImageDetailView.heroSpring) {
                            selectedTileID = tile.id
                        }
                    }
            } else {
                Color.clear
                    .frame(width: width, height: height)
            }
        }
        .position(
            x: (placement.frame.midX - offset.x) * zoom,
            y: (placement.frame.midY - offset.y) * zoom
        )
    }

    private func tileContent(_ tile: SampleTile, _ placement: TilePlacement, zoom: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(tile.gradient)
            .frame(width: placement.frame.width * zoom, height: placement.frame.height * zoom)
            .rotationEffect(placement.rotation)
            .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
            .blur(radius: blurAmounts[tile.id] ?? 0)
    }

    // MARK: - Mode transitions

    private func transition(to newMode: GalleryLayoutMode) {
        guard viewport.width > 50, viewport.height > 50 else { return }

        let layout = GalleryLayoutEngine.layout(mode: newMode, tiles: tiles, viewport: viewport)
        let oldOffset = contentOffset
        let newOffset = layout.initialOffset

        var distances: [Int: CGFloat] = [:]
        var maxDistance: CGFloat = 1
        for tile in tiles {
            let oldFrame = placements[tile.id]?.frame ?? .zero
            let newFrame = layout.placements[tile.id]?.frame ?? .zero
            let dx = (newFrame.midX - newOffset.x) - (oldFrame.midX - oldOffset.x)
            let dy = (newFrame.midY - newOffset.y) - (oldFrame.midY - oldOffset.y)
            let distance = sqrt(dx * dx + dy * dy)
            distances[tile.id] = distance
            maxDistance = max(maxDistance, distance)
        }

        contentSize = layout.contentSize
        currentPage = 0

        withAnimation(Self.morphSpring) {
            contentOffset = newOffset
        }

        for tile in tiles {
            let distance = distances[tile.id] ?? 0
            let delay = Double(distance / maxDistance) * Self.maxStagger

            withAnimation(Self.morphSpring.delay(delay)) {
                placements[tile.id] = layout.placements[tile.id] ?? .zero
            }

            let peakBlur = min(6, distance / 110)
            if peakBlur > 0.5 {
                withAnimation(.easeIn(duration: 0.14).delay(delay)) {
                    blurAmounts[tile.id] = peakBlur
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.26) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        blurAmounts[tile.id] = 0
                    }
                }
            }
        }
    }

    private func configure(viewport newViewport: CGSize, animated: Bool) {
        guard newViewport.width > 50, newViewport.height > 50 else { return }
        guard newViewport != viewport else { return }

        let hadLayout = viewport.width > 50 && !placements.isEmpty
        viewport = newViewport

        if animated && hadLayout {
            transition(to: mode)
        } else {
            let layout = GalleryLayoutEngine.layout(mode: mode, tiles: tiles, viewport: newViewport)
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
