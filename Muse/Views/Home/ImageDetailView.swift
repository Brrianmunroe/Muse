import SwiftUI

/// Glass detail screen with an Airbnb-style shared-element transition.
///
/// The hero is a single floating image whose frame, center and corner radius are
/// interpolated directly from the tapped cell's exact on-screen rect (`sourceFrame`)
/// to a computed destination — no `matchedGeometryEffect`, which can't resolve a
/// correct origin from the gallery's transformed/clipped canvas. One `easeInOut(0.3)`
/// curve drives the whole thing: the image scales up from where it sat, and the
/// ambient background + metadata card settle on the same motion. Closing runs the
/// exact inverse, flying the image back to the cell it came from.
struct ImageDetailView: View {
    let tiles: [SampleTile]
    /// Exact global rect of the tapped cell — the hero's start (and end) frame.
    let sourceFrame: CGRect
    @Binding var displayedTileID: Int?
    /// Shared open/close flag, owned by HomeView. Flipping it inside one
    /// `withAnimation` moves the hero, the gallery blur and the scrim together.
    @Binding var isExpanded: Bool
    @State private var tileNotes: [Int: String] = [:]

    static let glassForeground = Color(red: 1, green: 0.965, blue: 0.918)
    /// The one curve everything rides: a soft, slightly long ease — gentle out of
    /// the start, gentle into the destination — both opening and closing.
    static let transition = Animation.timingCurve(0.33, 0, 0.2, 1, duration: 0.42)
    /// Snap-back for cancelled drags (dismiss pull released, page swipe settle).
    private static let snapBack = Animation.spring(response: 0.32, dampingFraction: 0.84)
    private static let ambientFade = Animation.easeInOut(duration: 0.5)

    // Resting corner radii for the cell and the expanded hero.
    private static let cellRadius: CGFloat = 10
    private static let heroRadius: CGFloat = 18
    /// Motion blur rides a parabola: zero at rest, peaking at the midpoint of the
    /// move, back to zero as it settles — both opening and closing. The peak scales
    /// with how far the hero actually travels: a tile flying in from a far corner
    /// blurs up to the max, while one that's already large and centered (feed view)
    /// barely blurs at all.
    private static let motionBlurPeakMin: CGFloat = 1.5
    private static let motionBlurPeakMax: CGFloat = 6

    @State private var ambientA = AmbientGradientColors.fallback
    @State private var ambientB = AmbientGradientColors.fallback
    @State private var showAmbientA = true
    @State private var motionBlur: CGFloat = 0
    /// Distance-scaled blur peak, computed on open from the source→destination trip.
    /// The trip is symmetric, so the close reuses the same peak.
    @State private var blurPeak: CGFloat = ImageDetailView.motionBlurPeakMin
    @State private var zoomScale: CGFloat = 1
    @State private var zoomOffset: CGSize = .zero
    @State private var dismissDrag: CGSize = .zero
    @State private var pageDrag: CGSize = .zero
    @GestureState private var magnifyBy: CGFloat = 1

    private var currentTile: SampleTile? {
        guard let id = displayedTileID else { return nil }
        return tiles.first { $0.id == id }
    }

    private var currentIndex: Int? {
        guard let id = displayedTileID else { return nil }
        return tiles.firstIndex { $0.id == id }
    }

    /// Drag-to-dismiss progress softens the whole sheet as the user pulls down.
    private var dragOpacity: Double {
        let progress = min(abs(dismissDrag.height) / 320, 1)
        return 1 - progress * 0.5
    }

    var body: some View {
        if let tile = currentTile {
            GeometryReader { geo in
                let dest = heroDestination(
                    in: geo.size,
                    safeTop: geo.safeAreaInsets.top,
                    safeBottom: geo.safeAreaInsets.bottom,
                    aspect: tile.aspectRatio
                )

                ZStack {
                    Group {
                        ambientLayer(colors: ambientA, visible: showAmbientA)
                        ambientLayer(colors: ambientB, visible: !showAmbientA)
                    }
                    .opacity(isExpanded ? dragOpacity : 0)

                    // Chrome + hero shift together while the user drags to dismiss.
                    ZStack {
                        VStack(spacing: 0) {
                            topBar
                                .opacity(isExpanded ? dragOpacity : 0)
                            Spacer(minLength: 0)
                        }

                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            glassCard(tile: tile)
                                .padding(.horizontal, 16)
                                .padding(.bottom, max(16, geo.safeAreaInsets.bottom + 8))
                                .opacity(isExpanded ? dragOpacity : 0)
                                .offset(y: isExpanded ? 0 : 24)
                        }

                        heroImage(tile: tile, dest: dest)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .offset(y: dismissDrag.height)
                }
                .onAppear {
                    open(tile: tile, dest: dest, screenHeight: geo.size.height)
                }
            }
            .ignoresSafeArea()
            .preferredColorScheme(.dark)
            .onChange(of: displayedTileID) { oldID, newID in
                // Browsing to a sibling image while open (next/prev, swipe).
                guard isExpanded, let newID, oldID != nil,
                      let newTile = tiles.first(where: { $0.id == newID }) else { return }
                resetZoom()
                crossfadeAmbient(to: newTile)
            }
        }
    }

    // MARK: - Hero image

    /// The shared element. Its frame, center and corner radius interpolate between
    /// `sourceFrame` (the cell) and `dest` (the expanded slot) as `isExpanded` flips,
    /// so it scales up from exactly where the user tapped.
    private func heroImage(tile: SampleTile, dest: CGRect) -> some View {
        let frame = isExpanded ? dest : sourceFrame
        let radius = isExpanded ? Self.heroRadius : Self.cellRadius
        let effectiveScale = zoomScale * magnifyBy

        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(tile.gradient)
            .frame(width: frame.width, height: frame.height)
            .shadow(color: .black.opacity(isExpanded ? 0.4 : 0), radius: isExpanded ? 22 : 0, y: 12)
            .scaleEffect(effectiveScale)
            .blur(radius: motionBlur)
            .offset(x: zoomOffset.width + pageDrag.width, y: zoomOffset.height)
            .position(x: frame.midX, y: frame.midY)
            .gesture(combinedImageGesture(tile: tile))
    }

    /// Fit the tile's aspect ratio into the area between the top bar and the
    /// metadata card, centered — the hero's resting frame on screen.
    private func heroDestination(in size: CGSize, safeTop: CGFloat, safeBottom: CGFloat, aspect: CGFloat) -> CGRect {
        let hInset: CGFloat = 22
        let top = safeTop + 104
        let glassReserve: CGFloat = 296 + safeBottom
        let bottom = max(top + 160, size.height - glassReserve)
        let availableWidth = size.width - hInset * 2
        let availableHeight = bottom - top

        var width = availableWidth
        var height = width / aspect
        if height > availableHeight {
            height = availableHeight
            width = height * aspect
        }

        let centerX = size.width / 2
        let centerY = (top + bottom) / 2
        return CGRect(x: centerX - width / 2, y: centerY - height / 2, width: width, height: height)
    }

    // MARK: - Ambient background

    private func ambientLayer(colors: AmbientGradientColors, visible: Bool) -> some View {
        LinearGradient(
            colors: [colors.top, colors.bottom],
            startPoint: UnitPoint(x: 0.35, y: 0),
            endPoint: UnitPoint(x: 0.65, y: 1)
        )
        .ignoresSafeArea()
        .opacity(visible ? 1 : 0)
        .animation(Self.ambientFade, value: visible)
    }

    private func crossfadeAmbient(to tile: SampleTile, animated: Bool = true) {
        let colors = AmbientGradientEngine.colors(for: tile)
        if animated {
            if showAmbientA {
                ambientB = colors
                withAnimation(Self.ambientFade) { showAmbientA = false }
            } else {
                ambientA = colors
                withAnimation(Self.ambientFade) { showAmbientA = true }
            }
        } else {
            ambientA = colors
            showAmbientA = true
        }
    }

    // MARK: - Top bar

    private static let topBarPadding: CGFloat = 60

    private var topBar: some View {
        HStack {
            glassIconButton(systemName: "chevron.left") {
                navigate(by: -1)
            }
            .opacity(canNavigateBackward ? 1 : 0.35)
            .disabled(!canNavigateBackward)

            Spacer()

            if let index = currentIndex {
                Text("\(index + 1) of \(tiles.count)")
                    .font(.system(size: 13, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(Self.glassForeground.opacity(0.75))
            }

            Spacer()

            glassIconButton(systemName: "xmark") {
                dismiss()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, Self.topBarPadding)
        .padding(.bottom, 8)
    }

    private var canNavigateBackward: Bool {
        guard let index = currentIndex else { return false }
        return index > 0
    }

    private func glassIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: systemName == "xmark" ? 12 : 14, weight: .semibold))
                .foregroundStyle(Self.glassForeground)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.16), in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Glass card

    private func glassCard(tile: SampleTile) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            FlowLayout(spacing: 6) {
                ForEach(tile.tags) { tag in
                    TagChip(preview: tag, style: .glass)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(tile.aiDescription)
                .font(MuseTheme.serif(18))
                .foregroundStyle(Self.glassForeground)
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 5) {
                Text("Your notes")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(Self.glassForeground.opacity(0.65))

                TextEditor(text: notesBinding(for: tile))
                    .font(.system(size: 14))
                    .foregroundStyle(Self.glassForeground)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 44, maxHeight: 72)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .background(Color.black.opacity(0.28))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if let source = tile.sourceApp {
                Text("Saved from \(source) · \(tile.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 12))
                    .foregroundStyle(Self.glassForeground.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
        )
    }

    private func notesBinding(for tile: SampleTile) -> Binding<String> {
        Binding(
            get: { tileNotes[tile.id] ?? tile.notes },
            set: { tileNotes[tile.id] = $0 }
        )
    }

    // MARK: - Gestures

    private func combinedImageGesture(tile: SampleTile) -> some Gesture {
        let magnification = MagnificationGesture()
            .updating($magnifyBy) { value, state, _ in
                state = value
            }
            .onEnded { value in
                zoomScale = min(max(zoomScale * value, 1), 4)
                if zoomScale <= 1.05 {
                    zoomScale = 1
                    zoomOffset = .zero
                }
            }

        let dismissSwipe = DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard zoomScale <= 1.05, abs(value.translation.height) > abs(value.translation.width) else { return }
                dismissDrag = value.translation
            }
            .onEnded { value in
                guard zoomScale <= 1.05 else {
                    dismissDrag = .zero
                    return
                }
                if value.translation.height > 100 || value.predictedEndTranslation.height > 200 {
                    dismiss()
                } else {
                    withAnimation(Self.snapBack) { dismissDrag = .zero }
                }
            }

        let pageSwipe = DragGesture(minimumDistance: 30)
            .onChanged { value in
                guard zoomScale <= 1.05, abs(value.translation.width) > abs(value.translation.height) else { return }
                pageDrag = value.translation
            }
            .onEnded { value in
                guard zoomScale <= 1.05 else {
                    pageDrag = .zero
                    return
                }
                let threshold: CGFloat = 60
                if value.translation.width < -threshold {
                    navigate(by: 1)
                } else if value.translation.width > threshold {
                    navigate(by: -1)
                }
                withAnimation(Self.snapBack) { pageDrag = .zero }
            }

        return magnification.simultaneously(with: dismissSwipe).simultaneously(with: pageSwipe)
    }

    // MARK: - Lifecycle

    /// Open: render one frame at the source rect, then ease `isExpanded` true so the
    /// image scales up into the destination while the chrome and gallery blur settle
    /// on one shared curve. Motion blur runs its parabola over the same window.
    private func open(tile: SampleTile, dest: CGRect, screenHeight: CGFloat) {
        crossfadeAmbient(to: tile, animated: false)
        isExpanded = false
        motionBlur = 0
        blurPeak = Self.blurPeak(from: sourceFrame, to: dest, screenHeight: screenHeight)
        withAnimation(Self.transition) {
            isExpanded = true
        }
        runMotionBlurParabola()
    }

    /// How hard the blur should peak for this trip: center travel plus growth,
    /// normalized against the screen height and mapped into the min–max range.
    private static func blurPeak(from source: CGRect, to dest: CGRect, screenHeight: CGFloat) -> CGFloat {
        let travel = hypot(dest.midX - source.midX, dest.midY - source.midY)
        let growth = abs(dest.width - source.width)
        let progress = min((travel + growth) / max(screenHeight, 1), 1)
        return motionBlurPeakMin + (motionBlurPeakMax - motionBlurPeakMin) * progress
    }

    /// Drive the hero's blur up to its peak over the first half of the transition,
    /// then back to zero over the second half — a parabola centered on the moment
    /// the hero is moving fastest.
    private func runMotionBlurParabola() {
        let half = 0.42 / 2
        withAnimation(.easeIn(duration: half)) {
            motionBlur = blurPeak
        } completion: {
            withAnimation(.easeOut(duration: half)) {
                motionBlur = 0
            }
        }
    }

    /// Close: the exact inverse. The image eases back to the source cell while the
    /// chrome and blur clear on the same curve; the completion handler unmounts only
    /// once it lands, which is also when the canvas reveals the cell — no flicker.
    private func dismiss() {
        withAnimation(Self.transition) {
            isExpanded = false
            dismissDrag = .zero
        } completion: {
            displayedTileID = nil
        }
        runMotionBlurParabola()
    }

    private func navigate(by delta: Int) {
        guard let index = currentIndex else { return }
        let next = index + delta
        guard tiles.indices.contains(next) else { return }

        resetZoom()
        withAnimation(Self.transition) {
            displayedTileID = tiles[next].id
        }
    }

    private func resetZoom() {
        zoomScale = 1
        zoomOffset = .zero
        dismissDrag = .zero
        pageDrag = .zero
    }
}

// MARK: - Flow layout for tags

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
