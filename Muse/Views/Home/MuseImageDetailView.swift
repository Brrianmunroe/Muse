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
    private static let cellRadius: CGFloat = 5
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
    @State private var confirmDelete = false
    @FocusState private var notesFocused: Bool
    // Tap toggles an immersive black backdrop (photo front-and-center, chrome gone).
    @State private var immersed = false
    // 0 = info card hidden (photo is the star), 1 = card fully revealed. A small
    // drag up reveals it; drag down collapses it, then dismisses.
    @State private var cardReveal: CGFloat = 0
    /// Live vertical-drag delta while revealing/collapsing the card (≠ 0 only mid-drag).
    @State private var revealDrag: CGFloat = 0
    private static let revealDistance: CGFloat = 180

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

    /// Live 0→1 reveal of the info card. Folds the in-progress drag into the settled
    /// `cardReveal` so the photo and card track the thumb, then settle on release.
    private var revealProgress: CGFloat {
        // During a horizontal page swipe (or its settle) the reveal must not move,
        // or the photo's band would shift and it would drift vertically mid-swipe.
        if dragAxis == .horizontal || isSliding { return cardReveal }
        if cardReveal == 0 {
            return min(max(-revealDrag / Self.revealDistance, 0), 1)
        }
        return min(max(1 - revealDrag / Self.revealDistance, 0), 1)
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
                // `geo.safeAreaInsets` reads as zero here because the whole layout
                // uses `.ignoresSafeArea()`, so measure against the real window insets.
                let safe = Self.windowSafeArea
                let dest = heroDestination(
                    in: geo.size,
                    safeTop: safe.top,
                    safeBottom: safe.bottom,
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

                    // Tap-to-immerse fades the ambient gradient to black so the photo
                    // sits front and centre, Apple-Photos style.
                    Color.black
                        .ignoresSafeArea()
                        .opacity(immersed ? 1 : 0)

                    // Top-aligned so the chrome anchors to the top of the screen.
                    // Every child is positioned with `.offset` (a render-time shift,
                    // not layout) so none can inflate this stack's measured height —
                    // otherwise the `.frame` below would re-center the whole stack by
                    // an amount that depends on the photo's height, dragging the top
                    // bar and photo up/down as you swipe between differently-sized photos.
                    ZStack(alignment: .top) {
                        heroPager(current: image, dest: dest, geo: geo)

                        // Chrome sits above the pager so its buttons stay tappable;
                        // it's transparent to touches elsewhere, so the photo's
                        // pan/zoom and page-swipe still read through it.
                        topBar(image: cardImage ?? image, width: geo.size.width, safeTop: safe.top)
                            .frame(maxWidth: .infinity)
                            // Chrome hides in immersive mode.
                            .opacity(immersed ? 0 : chromeOpacity)
                            // Static during swipes — only moves on open/dismiss.
                            .offset(y: (isExpanded ? 0 : -52) - dismissProgress * 36)

                        // Card is hidden until revealed by a small drag up; it then
                        // rides up 32pt below the photo's (retreating) bottom. Placed
                        // from the top purely by offset so its distance-from-top can't
                        // grow the stack and re-center everything mid-swipe.
                        glassCard(image: cardImage ?? image)
                            .padding(.horizontal, 16)
                            .opacity(chromeOpacity * Double(revealProgress))
                            .offset(y: cardTop(in: geo.size, safe: safe, current: image)
                                + (isExpanded ? 0 : 52) + dismissProgress * 36)
                            .allowsHitTesting(revealProgress > 0.6)
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                    // Dismiss shrink/offset only ever applies to a vertical pull —
                    // never during a horizontal swipe, so the photo can't drift down.
                    .scaleEffect(dragAxis == .horizontal || isSliding ? 1 : dismissScale)
                    .offset(y: dragAxis == .horizontal || isSliding ? 0 : dismissDrag.height)
                }
                .onAppear {
                    open(image: image, dest: dest, screenHeight: geo.size.height)
                }
            }
            .ignoresSafeArea()
            .preferredColorScheme(.dark)
            .confirmationDialog("Delete this image?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { performDelete(image) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes it from your gallery for good.")
            }
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
                let safe = Self.windowSafeArea
                let incomingDest = heroDestination(
                    in: geo.size,
                    safeTop: safe.top,
                    safeBottom: safe.bottom,
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
            .onTapGesture { toggleImmerse() }
            .gesture(combinedImageGesture(image: image, width: width))
    }

    /// Real window safe-area insets. Needed because `geo.safeAreaInsets` reads as
    /// zero inside this `.ignoresSafeArea()` layout, which would push the back button
    /// up under the status bar.
    static var windowSafeArea: UIEdgeInsets {
        let insets = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.safeAreaInsets ?? .zero
        // The lookup can miss (returns zero) in this overlay context, which would
        // jam the back button into the status bar. Floor it to a notch device.
        return UIEdgeInsets(
            top: max(insets.top, 47),
            left: insets.left,
            bottom: max(insets.bottom, 20),
            right: insets.right
        )
    }

    /// Constant gap between the photo's bottom and the info card.
    private static let cardGap: CGFloat = 32
    /// Vertical room kept for the glass card so a tall portrait can't push it
    /// off-screen. Matched to the compact card's real height — must stay ≥ it or the
    /// card's bottom ("Saved …") clips. Re-tune if the card's height changes.
    private static let cardReserve: CGFloat = 230

    /// Y for the top of the info card: 32pt below the photo's bottom. During a
    /// swipe it interpolates between the current and incoming photo's positions by
    /// slide progress, so a height change between photos glides instead of snapping.
    private func cardTop(in size: CGSize, safe: UIEdgeInsets, current: LocalMuseImage) -> CGFloat {
        let currentBottom = heroDestination(
            in: size, safeTop: safe.top, safeBottom: safe.bottom, aspect: current.aspectRatio
        ).maxY
        guard let incoming = incomingImage else { return currentBottom + Self.cardGap }
        let incomingBottom = heroDestination(
            in: size, safeTop: safe.top, safeBottom: safe.bottom, aspect: incoming.aspectRatio
        ).maxY
        let p = min(abs(slideOffset) / max(size.width, 1), 1)
        return currentBottom * (1 - p) + incomingBottom * p + Self.cardGap
    }

    private func heroDestination(in size: CGSize, safeTop: CGFloat, safeBottom: CGFloat, aspect: CGFloat) -> CGRect {
        let reveal = revealProgress
        // Immersed: photo fills the whole screen over black. Otherwise it's centered
        // in a band whose bottom retreats as the card is revealed, so the photo eases
        // up to make room — and grows back to fill the band when the card is hidden.
        let hInset: CGFloat = immersed ? 0 : 10
        let top: CGFloat = immersed ? 0 : safeTop + 58
        let bottomFull: CGFloat = immersed ? size.height : size.height - safeBottom
        let bottom = bottomFull - reveal * (Self.cardReserve + Self.cardGap)
        let availableWidth = size.width - hInset * 2
        let availableHeight = max(160, bottom - top)

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

    private func topBar(image: LocalMuseImage, width: CGFloat, safeTop: CGFloat) -> some View {
        HStack(spacing: 10) {
            // Back button — returns to the gallery, same as the swipe-down.
            glassIconButton(systemName: "chevron.left") { dismiss() }
            Spacer()
            // Favorite toggle, persisted on the image.
            glassIconButton(systemName: image.isFavorite ? "heart.fill" : "heart") {
                toggleFavorite(image)
            }
            // Overflow: share the file or delete the image.
            Menu {
                ShareLink(item: LocalImageStore.url(for: image.localPath)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                glassIconCircle(systemName: "ellipsis")
            }
        }
        .padding(.horizontal, 20)
        // Sit clearly below the status bar / dynamic island, on every device.
        .padding(.top, safeTop + 12)
        .padding(.bottom, 8)
    }

    /// The glass circle shared by the icon buttons and the overflow menu label.
    private func glassIconCircle(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Self.glassForeground)
            .frame(width: 34, height: 34)
            .background(.white.opacity(0.16), in: Circle())
    }

    private func glassIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            glassIconCircle(systemName: systemName)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Glass card

    private func glassCard(image: LocalMuseImage) -> some View {
        // Deliberate per-section rhythm: a single uniform gap read as uneven across
        // blocks of different density, so each section sets its own top gap instead.
        VStack(alignment: .leading, spacing: 0) {
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
                .padding(.bottom, 16)
            }

            // No label — the serif description is the card's editorial voice.
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

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Your notes")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(Self.glassForeground.opacity(0.65))
                    Spacer()
                    if notesFocused {
                        Button("Done") { notesFocused = false }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Self.glassForeground.opacity(0.8))
                            .buttonStyle(.plain)
                    }
                }

                // Tap-to-edit: reads as plain text at rest with a quiet placeholder
                // when empty; the dark field only appears once focused.
                ZStack(alignment: .topLeading) {
                    if image.notes.isEmpty {
                        Text("Add a note")
                            .font(.system(size: 15))
                            .foregroundStyle(Self.glassForeground.opacity(0.4))
                            .padding(.horizontal, notesFocused ? 13 : 0)
                            .padding(.vertical, notesFocused ? 11 : 2)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: notesBinding(for: image))
                        .font(.system(size: 15))
                        .foregroundStyle(Self.glassForeground)
                        .scrollContentBackground(.hidden)
                        .focused($notesFocused)
                        .frame(minHeight: notesFocused ? 60 : 24, maxHeight: 120)
                        .padding(.horizontal, notesFocused ? 13 : 0)
                        .padding(.vertical, notesFocused ? 11 : 0)
                        .background(notesFocused ? Color.black.opacity(0.28) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.top, 20)
            .animation(.easeInOut(duration: 0.2), value: notesFocused)

            Text("Saved \(image.createdAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.system(size: 12))
                .foregroundStyle(Self.glassForeground.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
                // Smaller, distinct gap for the footnote.
                .padding(.top, 14)
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

    // MARK: - Top bar actions

    private func toggleFavorite(_ image: LocalMuseImage) {
        image.isFavorite.toggle()
        try? modelContext.save()
    }

    /// Removes the image's files and record, then closes back to the gallery.
    private func performDelete(_ image: LocalMuseImage) {
        LocalImageStore.delete(localPath: image.localPath, thumbnailPath: image.thumbnailPath)
        modelContext.delete(image)
        try? modelContext.save()
        dismiss()
    }

    // MARK: - Gestures

    /// Locks the drag to one axis on the first movement so a single gesture can't
    /// flicker between the page swipe and the dismiss swipe near the diagonal.
    private func lockAxis(_ translation: CGSize) {
        guard dragAxis == nil else { return }
        let dx = abs(translation.width), dy = abs(translation.height)
        // Wait for a clear direction before committing, so a slightly diagonal
        // horizontal swipe can't mis-lock to vertical and trigger reveal/dismiss
        // (which made the photo shrink and swoop down mid-swipe).
        guard max(dx, dy) > 12 else { return }
        // The filmstrip swipe is the primary gesture, so a side-flick wins any
        // ambiguous/diagonal drag. Only commit to vertical (reveal/dismiss) when
        // the drag is clearly vertical — otherwise a thumb-flick's small vertical
        // component would mis-lock and make the photo and top bar bob up/down.
        dragAxis = dy > dx * 1.6 ? .vertical : .horizontal
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
        // One vertical gesture, three jobs by direction + state:
        //   • card hidden, drag up   → reveal the info card
        //   • card shown, drag down  → collapse it
        //   • card hidden, drag down → dismiss (the original behaviour)
        let verticalSwipe = DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                guard zoomScale <= 1.05, !isSliding, !immersed else { return }
                lockAxis(value.translation)
                guard dragAxis == .vertical else { return }
                let ty = value.translation.height
                if cardReveal == 0 {
                    if ty < 0 { revealDrag = ty; dismissDrag = .zero }
                    else { revealDrag = 0; dismissDrag = value.translation }
                } else {
                    if ty > 0 { revealDrag = ty; dismissDrag = .zero }
                    else { revealDrag = 0 }
                }
            }
            .onEnded { value in
                defer { resetDragAxis() }
                let ty = value.translation.height
                let v = value.velocity.height
                // Immersive: a downward flick drops back to the gradient view.
                if immersed {
                    if ty > 70 || v > 600 { toggleImmerse() }
                    return
                }
                guard zoomScale <= 1.05, dragAxis == .vertical else {
                    dismissDrag = .zero; revealDrag = 0; return
                }
                if dismissDrag != .zero {
                    if ty > 120 || v > 700 { dismiss() } else { springDismissBack(velocity: v) }
                    return
                }
                // Reveal/collapse: settle to whichever end the drag + flick favour.
                let target: CGFloat
                if cardReveal == 0 {
                    target = (-ty > Self.revealDistance * 0.3 || v < -500) ? 1 : 0
                } else {
                    target = (ty > Self.revealDistance * 0.3 || v > 500) ? 0 : 1
                }
                settleReveal(to: target)
            }

        return magnification.simultaneously(with: verticalSwipe)
    }

    /// Tap toggles the immersive black backdrop; entering it folds the card away.
    private func toggleImmerse() {
        withAnimation(Self.transition) {
            immersed.toggle()
            if immersed { cardReveal = 0; revealDrag = 0 }
        }
    }

    /// Springs the info card to fully shown or hidden after a reveal/collapse drag.
    private func settleReveal(to target: CGFloat) {
        withAnimation(.interpolatingSpring(stiffness: 240, damping: 28)) {
            cardReveal = target
            revealDrag = 0
        }
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
        immersed = false
        cardReveal = 0
        revealDrag = 0
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
