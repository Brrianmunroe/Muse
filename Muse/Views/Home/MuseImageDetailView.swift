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
    @State private var infoOpacity: Double = 1

    private var currentImage: LocalMuseImage? {
        guard let id = displayedTileID else { return nil }
        return images.first { $0.intID == id }
    }

    private var currentIndex: Int? {
        guard let id = displayedTileID else { return nil }
        return images.firstIndex { $0.intID == id }
    }

    private var dragOpacity: Double {
        let progress = min(abs(dismissDrag.height) / 320, 1)
        return 1 - progress * 0.5
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
                    }
                    .opacity(isExpanded ? dragOpacity : 0)

                    ZStack {
                        VStack(spacing: 0) {
                            topBar(width: geo.size.width)
                                .opacity(isExpanded ? dragOpacity * infoOpacity : 0)
                            Spacer(minLength: 0)
                        }

                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            glassCard(image: image)
                                .padding(.horizontal, 16)
                                .padding(.bottom, max(16, geo.safeAreaInsets.bottom + 8))
                                .opacity(isExpanded ? dragOpacity * infoOpacity : 0)
                                .offset(y: isExpanded ? 0 : 24)
                        }

                        heroPager(current: image, dest: dest, geo: geo)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
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

    private func crossfadeAmbient(to image: LocalMuseImage, animated: Bool = true) {
        let thumbImage = image.thumbnailPath.flatMap {
            ImageCache.thumbnail(for: $0)
        } ?? UIImage(contentsOfFile: LocalImageStore.url(for: image.localPath).path)

        let colors = thumbImage.flatMap { AmbientGradientEngine.colors(from: $0) } ?? .fallback

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
            glassIconButton(systemName: "chevron.left") { navigate(by: -1, width: width) }
                .opacity(canNavigateBackward ? 1 : 0.35)
                .disabled(!canNavigateBackward)

            Spacer()

            if let index = currentIndex {
                Text("\(index + 1) of \(images.count)")
                    .font(.system(size: 13, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(Self.glassForeground.opacity(0.75))
            }

            Spacer()

            glassIconButton(systemName: "xmark") { dismiss() }
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
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

    private func combinedImageGesture(image: LocalMuseImage, width: CGFloat) -> some Gesture {
        let magnification = MagnificationGesture()
            .updating($magnifyBy) { value, state, _ in state = value }
            .onEnded { value in
                zoomScale = min(max(zoomScale * value, 1), 4)
                if zoomScale <= 1.05 { zoomScale = 1; zoomOffset = .zero }
            }

        let dismissSwipe = DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard zoomScale <= 1.05, !isSliding,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                dismissDrag = value.translation
            }
            .onEnded { value in
                guard zoomScale <= 1.05 else { dismissDrag = .zero; return }
                if value.translation.height > 100 || value.predictedEndTranslation.height > 200 {
                    dismiss()
                } else {
                    withAnimation(Self.snapBack) { dismissDrag = .zero }
                }
            }

        let pageSwipe = DragGesture(minimumDistance: 30)
            .onChanged { value in
                guard zoomScale <= 1.05, !isSliding,
                      abs(value.translation.width) > abs(value.translation.height) else { return }
                updateSlide(translation: value.translation.width, width: width)
            }
            .onEnded { value in
                guard zoomScale <= 1.05, !isSliding else { return }
                finishSlide(
                    translation: value.translation.width,
                    predicted: value.predictedEndTranslation.width,
                    width: width
                )
            }

        return magnification.simultaneously(with: dismissSwipe).simultaneously(with: pageSwipe)
    }

    // MARK: - Page slide

    private func neighbor(inDirection direction: Int) -> LocalMuseImage? {
        guard let index = currentIndex else { return nil }
        let next = index + direction
        guard images.indices.contains(next) else { return nil }
        return images[next]
    }

    private func updateSlide(translation: CGFloat, width: CGFloat) {
        let direction = translation < 0 ? 1 : -1
        if let next = neighbor(inDirection: direction) {
            if incomingImage?.intID != next.intID {
                incomingImage = next
                slideDirection = direction
                loadHeroImage(for: next)
            }
            slideOffset = translation
            infoOpacity = max(0.35, 1 - Double(abs(translation) / max(width, 1)) * 0.65)
        } else {
            incomingImage = nil
            slideOffset = translation * 0.25
        }
    }

    private func finishSlide(translation: CGFloat, predicted: CGFloat, width: CGFloat) {
        let direction = translation < 0 ? 1 : -1
        guard let target = incomingImage,
              neighbor(inDirection: direction)?.intID == target.intID,
              abs(translation) > 60 || abs(predicted) > 160 else {
            withAnimation(Self.snapBack) {
                slideOffset = 0
                infoOpacity = 1
            } completion: {
                incomingImage = nil
            }
            return
        }
        commitSlide(to: target, direction: direction, width: width)
    }

    /// Completes the filmstrip move: both photos slide together, motion blur
    /// pulses, the ambient gradient crossfades, and the info card dips out and
    /// back in — one motion shared by drag-flings and chevron taps.
    private func commitSlide(to target: LocalMuseImage, direction: Int, width: CGFloat) {
        isSliding = true
        crossfadeAmbient(to: target)
        runMotionBlurParabola(peak: Self.pageBlurPeak)
        withAnimation(.easeOut(duration: 0.15)) { infoOpacity = 0 }
        withAnimation(Self.transition) {
            slideOffset = CGFloat(-direction) * width
        } completion: {
            displayedTileID = target.intID
            slideOffset = 0
            incomingImage = nil
            resetZoom()
            isSliding = false
            withAnimation(.easeOut(duration: 0.25)) { infoOpacity = 1 }
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

    private func navigate(by delta: Int, width: CGFloat) {
        guard !isSliding, let target = neighbor(inDirection: delta) else { return }
        incomingImage = target
        slideDirection = delta
        loadHeroImage(for: target)
        commitSlide(to: target, direction: delta, width: width)
    }

    private func resetZoom() {
        zoomScale = 1; zoomOffset = .zero; dismissDrag = .zero
    }
}
