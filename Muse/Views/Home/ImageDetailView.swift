import SwiftUI

/// Glass detail screen: full-bleed photo, tone-matched ambient gradient,
/// frosted metadata card, hero zoom, pinch-to-zoom, swipe dismiss, browse next/prev.
struct ImageDetailView: View {
    let tiles: [SampleTile]
    @Binding var selectedTileID: Int?
    @Binding var tileNotes: [Int: String]
    var namespace: Namespace.ID

    static let glassForeground = Color(red: 1, green: 0.965, blue: 0.918)
    static let heroSpring = Animation.spring(response: 0.5, dampingFraction: 0.86)

    private static let panelSpring = Animation.spring(response: 0.4, dampingFraction: 0.9)
    private static let ambientSpring = Animation.easeInOut(duration: 0.8)
    private static let glassDelay: Double = 0.35
    private static let panelDismissLead: Double = 0.15

    @State private var expanded = false
    @State private var showGlass = false
    @State private var ambientA = AmbientGradientColors.fallback
    @State private var ambientB = AmbientGradientColors.fallback
    @State private var showAmbientA = true
    @State private var zoomScale: CGFloat = 1
    @State private var zoomOffset: CGSize = .zero
    @State private var dismissDrag: CGSize = .zero
    @State private var pageDrag: CGSize = .zero
    @GestureState private var magnifyBy: CGFloat = 1

    private var currentTile: SampleTile? {
        guard let id = selectedTileID else { return nil }
        return tiles.first { $0.id == id }
    }

    private var currentIndex: Int? {
        guard let id = selectedTileID else { return nil }
        return tiles.firstIndex { $0.id == id }
    }

    var body: some View {
        if let tile = currentTile {
            GeometryReader { geo in
                let safeBottom = geo.safeAreaInsets.bottom

                ZStack {
                    ambientLayer(colors: ambientA, visible: showAmbientA)
                    ambientLayer(colors: ambientB, visible: !showAmbientA)

                    VStack(spacing: 0) {
                        topBar

                        photoStage(tile: tile)
                            .layoutPriority(1)
                            .frame(minHeight: 0, maxHeight: .infinity)

                        glassCard(tile: tile)
                            .padding(.horizontal, 16)
                            .padding(.bottom, max(16, safeBottom + 8))
                            .opacity(showGlass ? 1 : 0)
                            .offset(y: showGlass ? 0 : 16)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .offset(y: dismissDrag.height)
                    .opacity(dismissOpacity)
                }
            }
            .ignoresSafeArea()
            .preferredColorScheme(.dark)
            .onAppear { openDetail(tile: tile) }
            .onChange(of: selectedTileID) { _, newID in
                guard let newID, let newTile = tiles.first(where: { $0.id == newID }) else { return }
                resetZoom()
                crossfadeAmbient(to: newTile)
                reopenGlass()
            }
        }
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
        .animation(Self.ambientSpring, value: visible)
    }

    private func crossfadeAmbient(to tile: SampleTile, animated: Bool = true) {
        let colors = AmbientGradientEngine.colors(for: tile)
        if animated {
            if showAmbientA {
                ambientB = colors
                withAnimation(Self.ambientSpring) { showAmbientA = false }
            } else {
                ambientA = colors
                withAnimation(Self.ambientSpring) { showAmbientA = true }
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

    // MARK: - Photo

    private func photoStage(tile: SampleTile) -> some View {
        let effectiveScale = zoomScale * magnifyBy
        let cornerRadius: CGFloat = expanded ? 18 : 10

        return GeometryReader { geo in
            tileImage(tile)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .matchedGeometryEffect(id: tile.id, in: namespace)
                .scaleEffect(effectiveScale)
                .offset(x: zoomOffset.width + pageDrag.width, y: zoomOffset.height)
                .shadow(color: .black.opacity(0.45), radius: expanded ? 24 : 6, y: 10)
                .gesture(combinedImageGesture(tile: tile))
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(.horizontal, 22)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .animation(Self.heroSpring, value: expanded)
    }

    private func tileImage(_ tile: SampleTile) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(tile.gradient)
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
        .animation(Self.panelSpring, value: showGlass)
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
                    withAnimation(Self.heroSpring) { dismissDrag = .zero }
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
                withAnimation(Self.heroSpring) { pageDrag = .zero }
            }

        return magnification.simultaneously(with: dismissSwipe).simultaneously(with: pageSwipe)
    }

    // MARK: - Navigation

    private func navigate(by delta: Int) {
        guard let index = currentIndex else { return }
        let next = index + delta
        guard tiles.indices.contains(next) else { return }

        withAnimation(Self.panelSpring) { showGlass = false }
        resetZoom()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            selectedTileID = tiles[next].id
        }
    }

    private func dismiss() {
        withAnimation(Self.panelSpring) { showGlass = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.panelDismissLead) {
            withAnimation(Self.heroSpring) {
                expanded = false
                dismissDrag = .zero
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                selectedTileID = nil
            }
        }
    }

    private func openDetail(tile: SampleTile) {
        expanded = false
        showGlass = false
        crossfadeAmbient(to: tile, animated: false)

        withAnimation(Self.heroSpring) {
            expanded = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.glassDelay) {
            withAnimation(Self.panelSpring) {
                showGlass = true
            }
        }
    }

    private func reopenGlass() {
        showGlass = false
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.glassDelay) {
            withAnimation(Self.panelSpring) {
                showGlass = true
            }
        }
    }

    private func resetZoom() {
        zoomScale = 1
        zoomOffset = .zero
        dismissDrag = .zero
        pageDrag = .zero
    }

    private var dismissOpacity: Double {
        let progress = min(abs(dismissDrag.height) / 300, 1)
        return 1 - progress * 0.35
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
