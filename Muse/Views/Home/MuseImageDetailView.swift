import SwiftUI
import SwiftData

/// Detail overlay for real `LocalMuseImage` content — same motion system as
/// `ImageDetailView` but renders actual photos and persists notes via SwiftData.
struct MuseImageDetailView: View {
    let images: [LocalMuseImage]
    let sourceFrame: CGRect
    @Binding var displayedTileID: Int?
    @Binding var isExpanded: Bool
    let modelContext: ModelContext

    static let glassForeground = Color(red: 1, green: 0.965, blue: 0.918)
    static let transition = Animation.timingCurve(0.33, 0, 0.2, 1, duration: 0.42)
    private static let snapBack = Animation.spring(response: 0.32, dampingFraction: 0.84)
    private static let ambientFade = Animation.easeInOut(duration: 0.5)
    private static let cellRadius: CGFloat = 10
    private static let heroRadius: CGFloat = 18
    private static let motionBlurPeakMin: CGFloat = 1.5
    private static let motionBlurPeakMax: CGFloat = 6
    /// Gentle fixed blur for the photo-to-photo slide.
    private static let pageBlurPeak: CGFloat = 2.5
    // Parallax + frost chrome choreography for the photo-to-photo swipe.
    private static let frostIn = Animation.easeIn(duration: 0.16)
    private static let chromeClear = Animation.easeOut(duration: 0.34)
    private static let cardFrostBlur: CGFloat = 4

    @State private var ambientA = AmbientGradientColors.fallback
    @State private var ambientB = AmbientGradientColors.fallback
    @State private var showAmbientA = true
    @State private var motionBlur: CGFloat = 0
    @State private var blurPeak: CGFloat = MuseImageDetailView.motionBlurPeakMin
    @State private var zoomScale: CGFloat = 1
    @State private var zoomOffset: CGSize = .zero
    @State private var dismissDrag: CGSize = .zero
    @GestureState private var magnifyBy: CGFloat = 1
    @State private var noteSaveTask: Task<Void, Never>?
    @State private var loadedImages: [Int: UIImage] = [:]

    // Filmstrip pager state: one slide motion shared by drag, fling, and chevrons.
    @State private var slideOffset: CGFloat = 0
    @State private var slideDirection = 1
    @State private var incomingImage: LocalMuseImage?
    @State private var isSliding = false
    // Parallax + frost: the card and top bar trail the photo at half speed while
    // frosting over; their content swaps under peak frost and fades back in.
    @State private var chromeFrost: CGFloat = 0
    @State private var cardContentID: Int?
    @State private var incomingAmbient: AmbientGradientColors?
    @State private var ambientProgress: Double = 0
    /// Locked once at gesture start so a single drag stays horizontal or vertical
    /// instead of flickering between page-swipe and dismiss near the diagonal.
    @State private var dragAxis: Axis?

    private var currentImage: LocalMuseImage? {
        guard let id = displayedTileID else { return nil }
        return images.first { $0.intID == id }
    }

    private var currentIndex: Int? {
        guard let id = displayedTileID else { return nil }
        return images.firstIndex { $0.intID == id }
    }

    /// The image whose metadata the card and counter show. During a swipe this
    /// flips to the incoming image at the frost peak, so the new content fades
    /// in as the chrome clears instead of popping on landing.
    private var cardImage: LocalMuseImage? {
        guard let id = cardContentID,
              let match = images.first(where: { $0.intID == id }) else { return currentImage }
        return match
    }

    /// 0 at rest → 1 at a full dismiss pull. Drives the shrink, dim and chrome exit.
    private var dismissProgress: CGFloat {
        min(abs(dismissDrag.height) / 320, 1)
    }

    /// Ambient background dims as the sheet is pulled away.
    private var dragOpacity: Double {
        1 - Double(dismissProgress) * 0.5
    }

    /// Whole sheet shrinks slightly as you pull — the iOS Photos "let go" feel.
    private var dismissScale: CGFloat {
        1 - dismissProgress * 0.12
    }

    /// Chrome (top bar + info card) rides the pull out fully, rather than a flat fade.
    private var chromeOpacity: Double {
        isExpanded ? Double(1 - dismissProgress) : 0
    }

    var body: some View {
        if let image = currentImage {
            GeometryReader { geo in
                let dest = heroDestination(
                    in: geo.size,
                    safeTop: geo.safeAreaInsets.top,
                    safeBottom: geo.safeAreaInsets.bottom,
                    aspect: image.aspectRatio
                )

                ZStack {
                    Group {
                        ambientLayer(colors: ambientA, visible: showAmbientA)
                        ambientLayer(colors: ambientB, visible: !showAmbientA)
                        // Incoming photo's glow, dissolving in under the thumb.
                        if let incoming = incomingAmbient {
                            LinearGradient(
                                colors: [incoming.top, incoming.bottom],
                                startPoint: UnitPoint(x: 0.35, y: 0),
                                endPoint: UnitPoint(x: 0.65, y: 1)
                            )
                            .ignoresSafeArea()
                            .opacity(ambientProgress)
                        }
                    }
                    .opacity(isExpanded ? dragOpacity : 0)

                    ZStack {
                        VStack(spacing: 0) {
                            topBar(width: geo.size.width)
                                .opacity(chromeOpacity)
                                // Static during swipes — only moves on open/dismiss.
                                .offset(y: (isExpanded ? 0 : -52) - dismissProgress * 36)
                            Spacer(minLength: 0)
                        }

                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            glassCard(image: cardImage ?? image)
                                .padding(.horizontal, 16)
                                .padding(.bottom, max(16, geo.safeAreaInsets.bottom + 8))
                                .opacity(chromeOpacity)
                                // Container stays put; only its content frosts/fades.
                                .offset(y: (isExpanded ? 0 : 52) + dismissProgress * 36)
                        }

                        heroPager(current: image, dest: dest, geo: geo)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(dismissScale)
                    .offset(y: dismissDrag.height)
                }
                .onAppear {
                    open(image: image, dest: dest, screenHeight: geo.size.height)
                }
            }
            .ignoresSafeArea()
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Hero image

    /// Current photo plus, mid-swipe, the neighbor sliding in beside it.
    /// Both move on the same offset so the swap reads as one filmstrip.
    private func heroPager(current: LocalMuseImage, dest: CGRect, geo: GeometryProxy) -> some View {
        ZStack {
            heroImage(image: current, dest: dest, width: geo.size.width)
                .offset(x: slideOffset)

            if let incoming = incomingImage {
                let incomingDest = heroDestination(
                    in: geo.size,
                    safeTop: geo.safeAreaInsets.top,
                    safeBottom: geo.safeAreaInsets.bottom,
                    aspect: incoming.aspectRatio
                )
                let side = CGFloat(slideDirection)
                heroCard(image: incoming, frame: incomingDest, radius: Self.heroRadius)
                    .shadow(color: .black.opacity(0.4), radius: 22, y: 12)
                    .position(x: incomingDest.midX, y: incomingDest.midY)
                    .offset(x: slideOffset + side * geo.size.width)
            }
        }
        .blur(radius: motionBlur)
        // Page swipe lives on the stationary pager (not the moving photo) so the
        // gesture reads translation in a fixed coordinate space — no jitter.
        // simultaneousGesture so it co-exists with the photo's zoom/dismiss.
        .contentShape(Rectangle())
        .simultaneousGesture(pageSwipeGesture(width: geo.size.width))
    }

    private func heroCard(image: LocalMuseImage, frame: CGRect, radius: CGFloat) -> some View {
        Group {
            if let uiImage = loadedImages[image.intID] {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: frame.width, height: frame.height)
                    .clipped()
            } else {
                Color(white: 0.18)
                    .frame(width: frame.width, height: frame.height)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    private func heroImage(image: LocalMuseImage, dest: CGRect, width: CGFloat) -> some View {
        let frame = isExpanded ? dest : sourceFrame
        let radius = isExpanded ? Self.heroRadius : Self.cellRadius
        let effectiveScale = zoomScale * magnifyBy

        return heroCard(image: image, frame: frame, radius: radius)
            .shadow(color: .black.opacity(isExpanded ? 0.4 : 0), radius: isExpanded ? 22 : 0, y: 12)
            .scaleEffect(effectiveScale)
            .offset(x: zoomOffset.width, y: zoomOffset.height)
            .position(x: frame.midX, y: frame.midY)
            .gesture(combinedImageGesture(image: image, width: width))
    }

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

    // MARK: - Ambient

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

    private func ambientColors(for image: LocalMuseImage) -> AmbientGradientColors {
        let thumbImage = image.thumbnailPath.flatMap {
            ImageCache.thumbnail(for: $0)
        } ?? UIImage(contentsOfFile: LocalImageStore.url(for: image.localPath).path)
        return thumbImage.flatMap { AmbientGradientEngine.colors(from: $0) } ?? .fallback
    }

    private func crossfadeAmbient(to image: LocalMuseImage, animated: Bool = true) {
        let colors = ambientColors(for: image)

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

    private func topBar(width: CGFloat) -> some View {
        HStack {
            // Single back button — returns to the gallery, same as the swipe-down.
            glassIconButton(systemName: "chevron.left") { dismiss() }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
        .padding(.bottom, 8)
    }

    private func glassIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Self.glassForeground)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.16), in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Glass card

    private func glassCard(image: LocalMuseImage) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            if !image.tagLabels.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(image.tagLabels, id: \.self) { label in
                            Text(label)
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.16))
                                .foregroundStyle(Self.glassForeground)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Description")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(Self.glassForeground.opacity(0.65))

                if let description = image.aiDescription {
                    Text(description)
                        .font(MuseTheme.serif(18))
                        .lineSpacing(3)
                        .foregroundStyle(Self.glassForeground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Analyzing…")
                        .font(MuseTheme.serif(18))
                        .foregroundStyle(Self.glassForeground.opacity(0.45))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Your notes")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(Self.glassForeground.opacity(0.65))

                TextEditor(text: notesBinding(for: image))
                    .font(.system(size: 14))
                    .foregroundStyle(Self.glassForeground)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 44, maxHeight: 72)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .background(Color.black.opacity(0.28))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Text("Saved \(image.createdAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.system(size: 12))
                .foregroundStyle(Self.glassForeground.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Content frosts and fades to near-zero at the swipe midpoint, swaps,
        // then sharpens back in — the glass container behind it stays put.
        .blur(radius: chromeFrost * Self.cardFrostBlur)
        .opacity(1 - Double(chromeFrost) * 0.95)
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

    private func notesBinding(for image: LocalMuseImage) -> Binding<String> {
        Binding(
            get: { image.notes },
            set: { newValue in
                image.notes = newValue
                noteSaveTask?.cancel()
                noteSaveTask = Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    guard !Task.isCancelled else { return }
                    try? modelContext.save()
                }
            }
        )
    }

    // MARK: - Gestures

    /// Locks the drag to one axis on the first movement so a single gesture can't
    /// flicker between the page swipe and the dismiss swipe near the diagonal.
    private func lockAxis(_ translation: CGSize) {
        guard dragAxis == nil else { return }
        dragAxis = abs(translation.width) > abs(translation.height) ? .horizontal : .vertical
    }

    /// Zoom + swipe-to-dismiss; stays on the photo itself.
    private func combinedImageGesture(image: LocalMuseImage, width: CGFloat) -> some Gesture {
        let magnification = MagnificationGesture()
            .updating($magnifyBy) { value, state, _ in state = value }
            .onEnded { value in
                zoomScale = min(max(zoomScale * value, 1), 4)
                if zoomScale <= 1.05 { zoomScale = 1; zoomOffset = .zero }
            }

        // Global coordinate space: translation is measured against the screen, not
        // the sheet that's moving under the thumb — that feedback was the jitter.
        let dismissSwipe = DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                guard zoomScale <= 1.05, !isSliding else { return }
                lockAxis(value.translation)
                guard dragAxis == .vertical else { return }
                dismissDrag = value.translation
            }
            .onEnded { value in
                defer { resetDragAxis() }
                guard zoomScale <= 1.05, dragAxis == .vertical else { dismissDrag = .zero; return }
                let v = value.velocity.height
                if value.translation.height > 120 || v > 700 {
                    dismiss()
                } else {
                    springDismissBack(velocity: v)
                }
            }

        return magnification.simultaneously(with: dismissSwipe)
    }

    /// Cancelled dismiss: spring the sheet back to rest carrying the release speed.
    private func springDismissBack(velocity: CGFloat) {
        let remaining = -dismissDrag.height
        let initialV = remaining == 0 ? 0 : Double(velocity / remaining)
        withAnimation(.interpolatingSpring(stiffness: 300, damping: 30, initialVelocity: initialV)) {
            dismissDrag = .zero
        }
    }

    /// Clears the locked axis *after* the current run-loop turn, so the page and
    /// dismiss gestures (which both fire `onEnded` for one drag) each still read
    /// the locked axis regardless of which handler runs first.
    private func resetDragAxis() {
        DispatchQueue.main.async { dragAxis = nil }
    }

    /// Interactive filmstrip pan: tracks the thumb 1:1 and hands the release
    /// velocity to `finishSlide` so the spring continues at the flick's speed.
    private func pageSwipeGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                guard zoomScale <= 1.05, !isSliding else { return }
                lockAxis(value.translation)
                guard dragAxis == .horizontal else { return }
                updateSlide(translation: value.translation.width, width: width)
            }
            .onEnded { value in
                defer { resetDragAxis() }
                guard zoomScale <= 1.05, !isSliding, dragAxis == .horizontal else { return }
                finishSlide(
                    translation: value.translation.width,
                    velocity: value.velocity.width,
                    width: width
                )
            }
    }

    // MARK: - Page slide

    private func neighbor(inDirection direction: Int) -> LocalMuseImage? {
        guard let index = currentIndex else { return nil }
        let next = index + direction
        guard images.indices.contains(next) else { return nil }
        return images[next]
    }

    private func setIncoming(_ image: LocalMuseImage, direction: Int) {
        incomingImage = image
        slideDirection = direction
        incomingAmbient = ambientColors(for: image)
        loadHeroImage(for: image)
    }

    private func updateSlide(translation: CGFloat, width: CGFloat) {
        let direction = translation < 0 ? 1 : -1
        if let next = neighbor(inDirection: direction) {
            if incomingImage?.intID != next.intID {
                setIncoming(next, direction: direction)
            }
            slideOffset = translation
            let p = min(abs(translation) / max(width, 1), 1)
            chromeFrost = min(2 * min(p, 1 - p), 1)
            ambientProgress = Double(p)
            // The card's content swaps to the incoming photo under peak frost, so
            // the new tags/notes fade in as the frost clears.
            cardContentID = p <= 0.5 ? currentImage?.intID : next.intID
        } else {
            incomingImage = nil
            incomingAmbient = nil
            slideOffset = translation * 0.25
            let p = min(abs(slideOffset) / max(width, 1), 1)
            chromeFrost = min(2 * min(p, 1 - p), 1)
        }
    }

    /// Decides commit-vs-cancel from how far the thumb travelled *and* how fast it
    /// was moving at release, then springs to the chosen target carrying that
    /// velocity so the motion feels continuous with the flick.
    private func finishSlide(translation: CGFloat, velocity: CGFloat, width: CGFloat) {
        let direction = translation < 0 ? 1 : -1
        let flungEnough = abs(translation) > width * 0.3 || abs(velocity) > 500
        guard let target = incomingImage,
              neighbor(inDirection: direction)?.intID == target.intID,
              flungEnough else {
            // Cancel: spring back to the current photo, inheriting release velocity.
            cardContentID = currentImage?.intID
            springSlide(to: 0, velocity: velocity) {
                incomingImage = nil
                incomingAmbient = nil
            }
            withAnimation(Self.chromeClear) {
                chromeFrost = 0
                ambientProgress = 0
            }
            return
        }
        commitSlide(to: target, direction: direction, width: width, velocity: velocity)
    }

    /// Springs `slideOffset` to `target` launching at the thumb's release speed.
    /// `interpolatingSpring`'s `initialVelocity` is a fraction of the remaining
    /// distance per second, so we normalise the point/sec velocity by the distance.
    private func springSlide(to target: CGFloat, velocity: CGFloat, completion: @escaping () -> Void) {
        let remaining = target - slideOffset
        let initialV = remaining == 0 ? 0 : Double(velocity / remaining)
        // Soft, just-over-critically-damped glide — no overshoot, no snap.
        withAnimation(.interpolatingSpring(stiffness: 110, damping: 22, initialVelocity: initialV)) {
            slideOffset = target
        } completion: {
            completion()
        }
    }

    /// Completes the filmstrip move: both photos spring together at the release
    /// velocity, the ambient glow finishes its thumb-driven dissolve, and the
    /// chrome frosts to a peak, swaps content underneath, then trails in from
    /// the incoming side and fades clear — shared by drag-flings and chevrons.
    private func commitSlide(to target: LocalMuseImage, direction: Int, width: CGFloat, velocity: CGFloat = 0) {
        isSliding = true
        // Only fast flings streak; gentle swipes stay crisp.
        let blurPeak = min(Self.pageBlurPeak, abs(velocity) / 600 * Self.pageBlurPeak)
        if blurPeak > 0.05 { runMotionBlurParabola(peak: blurPeak) }

        springSlide(to: CGFloat(-direction) * width, velocity: velocity) {
            displayedTileID = target.intID
            slideOffset = 0
            incomingImage = nil
            if let colors = incomingAmbient {
                ambientA = colors
                showAmbientA = true
            } else {
                crossfadeAmbient(to: target, animated: false)
            }
            incomingAmbient = nil
            ambientProgress = 0
            resetZoom()
            isSliding = false
        }
        withAnimation(.easeOut(duration: 0.4)) { ambientProgress = 1 }

        // Skip the frost-in when the drag already crossed the midpoint — the
        // content swapped under the finger's own frost.
        if cardContentID != target.intID {
            withAnimation(Self.frostIn) {
                chromeFrost = 1
            } completion: {
                cardContentID = target.intID
                withAnimation(Self.chromeClear) { chromeFrost = 0 }
            }
        } else {
            withAnimation(Self.chromeClear) { chromeFrost = 0 }
        }
    }

    // MARK: - Lifecycle

    /// Show the (already-decoded) grid thumbnail immediately so motion starts
    /// on time, then swap in the screen-sized image once it's ready.
    private func loadHeroImage(for image: LocalMuseImage) {
        let imageID = image.intID
        if loadedImages[imageID] == nil {
            loadedImages[imageID] = image.thumbnailPath.flatMap { ImageCache.thumbnail(for: $0) }
        }
        let path = image.localPath
        let maxDimension = ImageCache.screenMaxDimension
        Task.detached(priority: .userInitiated) {
            let display = ImageCache.display(for: path, maxDimension: maxDimension)
            await MainActor.run {
                guard let display else { return }
                loadedImages[imageID] = display
            }
        }
    }

    private func open(image: LocalMuseImage, dest: CGRect, screenHeight: CGFloat) {
        loadHeroImage(for: image)
        // Analyze images that haven't been described yet (failed earlier, or
        // predate the feature) when they're first opened.
        ImageAnalysisService.analyzeIfNeeded(image, context: modelContext)
        crossfadeAmbient(to: image, animated: false)
        isExpanded = false
        motionBlur = 0
        blurPeak = Self.blurPeak(from: sourceFrame, to: dest, screenHeight: screenHeight)
        withAnimation(Self.transition) { isExpanded = true }
        runMotionBlurParabola(peak: blurPeak)
    }

    private static func blurPeak(from source: CGRect, to dest: CGRect, screenHeight: CGFloat) -> CGFloat {
        let travel = hypot(dest.midX - source.midX, dest.midY - source.midY)
        let growth = abs(dest.width - source.width)
        let progress = min((travel + growth) / max(screenHeight, 1), 1)
        return motionBlurPeakMin + (motionBlurPeakMax - motionBlurPeakMin) * progress
    }

    private func runMotionBlurParabola(peak: CGFloat) {
        let half = 0.42 / 2
        withAnimation(.easeIn(duration: half)) {
            motionBlur = peak
        } completion: {
            withAnimation(.easeOut(duration: half)) { motionBlur = 0 }
        }
    }

    private func dismiss() {
        noteSaveTask?.cancel()
        try? modelContext.save()
        withAnimation(Self.transition) {
            isExpanded = false
            dismissDrag = .zero
        } completion: {
            displayedTileID = nil
        }
        runMotionBlurParabola(peak: blurPeak)
    }

    private func resetZoom() {
        zoomScale = 1; zoomOffset = .zero; dismissDrag = .zero
    }
}
