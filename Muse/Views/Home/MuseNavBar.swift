import SwiftUI

/// The "Vast" glyph — a bento-style cluster of six rounded rectangles, traced
/// from the Figma SVG (24×24 viewBox). Strokes sit inside the bounds so the
/// outline reads crisp at small sizes.
struct VastGridShape: Shape {
    /// (x, y, width, height) in the 24×24 design space.
    private static let rects: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (3, 3, 8, 12),
        (17, 3, 4, 5),
        (12, 3, 4, 5),
        (12, 9, 9, 6),
        (3, 16, 5, 5),
        (9, 16, 12, 5)
    ]
    /// Visible stroke width in the design space (3pt stroke, masked to the inside → 1.5pt shows).
    static let strokeWidth: CGFloat = 1.5

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let inset = Self.strokeWidth / 2
        var path = Path()
        for (x, y, w, h) in Self.rects {
            let r = CGRect(x: x * scale, y: y * scale, width: w * scale, height: h * scale)
                .insetBy(dx: inset * scale, dy: inset * scale)
            path.addRoundedRect(in: r, cornerSize: CGSize(width: scale, height: scale))
        }
        return path
    }
}

extension Animation {
    /// The one spring every nav-bar movement shares — expand/collapse, the
    /// traveling glyph, the selection pill, and the search-bar morph all ride this,
    /// so the whole bar feels like a single physical object. Fluid & springy.
    static let museBar = Animation.spring(duration: 0.5, bounce: 0.3)
}

/// The single consolidated bottom bar: `🔍  ＋  ▦`.
///
/// Two of its three controls hand their action back to the host (`onSearch`,
/// `onAdd`); the View control is self-contained — tapping it stretches the bar
/// in place into a layout-mode picker.
///
/// Motion: one fluid spring drives everything so the bar behaves like a single
/// physical object. The frosted background stretches/contracts as the continuity;
/// the current-mode glyph and its purple pill travel between rest and picker via
/// `matchedGeometryEffect`; the other icons scale + settle in (entering) or clear
/// quickly out of the traveller's path (leaving). Selecting a mode slides the pill
/// and keeps the picker open; only ✕ closes it. Taps carry haptics.
///
/// The search morph (pill → keyboard-docked field) is owned by the host: it
/// shares `namespace` so the frosted background and the magnifying-glass icon
/// animate from this bar into the host's search field and back.
struct MuseNavBar: View {
    @Binding var layoutMode: GalleryLayoutMode
    /// Lifted to the host so it can hide the shared search icon while the picker is open.
    @Binding var viewModeExpanded: Bool
    /// Shared with the host's search field so the bar morphs into it.
    var namespace: Namespace.ID
    var onAdd: () -> Void
    var onSearch: () -> Void

    /// Set true (delayed) once the bar has settled into place, so the icons fade in
    /// *after* the background lands — used when returning from search.
    @State private var iconsVisible = false
    /// Connects the traveling current-mode glyph across rest ⇄ expanded.
    @Namespace private var morph

    private let corner: CGFloat = 28
    private let stretch = Animation.museBar

    // Mode-picker geometry — used to position the single sliding pill.
    private let glyphSize: CGFloat = 44        // 24pt icon + 10pt padding each side
    private let itemSpacing: CGFloat = 32      // matches the HStack spacing
    private let pillWidth: CGFloat = 58

    /// Leading-edge x of the selection pill for the current mode. The pill is a
    /// single persistent view — only this value changes — so its slide is governed
    /// by exactly one spring and is identical every time.
    private var pillX: CGFloat {
        let index = GalleryLayoutMode.allCases.firstIndex(of: layoutMode) ?? 0
        return CGFloat(index) * (glyphSize + itemSpacing) + glyphSize / 2 - pillWidth / 2
    }

    /// Side icons (search, ＋, non-selected modes, ✕) scale + fade.
    private var pop: AnyTransition {
        .scale(scale: 0.5).combined(with: .opacity)
    }

    var body: some View {
        ZStack {
            if viewModeExpanded {
                modePicker
            } else {
                restContent
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 16)
        .opacity(iconsVisible ? 1 : 0)   // icons only — background stays visible as it lands
        .background(barBackground)
        .fixedSize(horizontal: true, vertical: false)
        .onAppear {
            // The bar slides/shrinks into place first; its contents fade in after.
            withAnimation(.easeOut(duration: 0.22).delay(0.18)) { iconsVisible = true }
        }
        // Haptics: a soft tap when the picker opens/closes, a selection tick per mode.
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: viewModeExpanded)
        .sensoryFeedback(.selection, trigger: layoutMode)
    }

    // MARK: Resting state — 🔍 ＋ ▦

    private var restContent: some View {
        HStack(spacing: 32) {
            // Invisible anchor for the search icon. The *visible* icon is a single
            // persistent overlay owned by the host (so it never fades when the bar
            // morphs — it just glides to whichever form's anchor, like the pill).
            Button(action: onSearch) {
                Color.clear
                    .frame(width: 24, height: 24)
                    .matchedGeometryEffect(id: "searchSlot", in: namespace, isSource: true)
                    .padding(10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .transition(pop)

            fab
                .transition(pop)

            // Current-mode glyph — the shared traveller. `.identity` so it slides
            // (via matchedGeometry) into its picker slot without fading.
            Button {
                withAnimation(stretch) { viewModeExpanded = true }
            } label: {
                modeGlyph(layoutMode)
            }
            .buttonStyle(PressableStyle())
            // Matches the expanded glyph for the current mode, so on expand this
            // resting icon travels into that slot (and back on collapse).
            .matchedGeometryEffect(id: "mode-\(layoutMode.rawValue)", in: morph)
            .transition(.identity)
        }
    }

    private var fab: some View {
        Button(action: onAdd) {
            plusGlyph
                .frame(width: 44, height: 44)
                .background(MuseTheme.Semantic.fabGradient, in: Circle())
                // 1pt stroke sitting 0.5pt outside the edge (Figma `inset(by: -0.5)`).
                .overlay(Circle().inset(by: -0.5).stroke(MuseTheme.Semantic.fabStroke, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }

    /// The Figma plus: a chunky, fully-rounded "+" (two 2.52pt-thick rounded bars in
    /// a 16pt box) with a faint light-lavender inner highlight along the top edge.
    private var plusGlyph: some View {
        ZStack {
            Capsule().frame(width: 16, height: 2.52)
            Capsule().frame(width: 2.52, height: 16)
        }
        .frame(width: 16, height: 16)
        .foregroundStyle(
            .white.shadow(.inner(color: Color(red: 0.873, green: 0.825, blue: 1), radius: 0.1, y: 0.25))
        )
    }

    // MARK: Expanded state — Vast · Bento · Feed · ✕

    private var modePicker: some View {
        HStack(spacing: itemSpacing) {
            ForEach(GalleryLayoutMode.allCases) { mode in
                let isSelected = mode == layoutMode
                Button {
                    // Keep the picker open and cross-fade the icon tints on the shared
                    // spring. The pill animates itself (scoped below), so it stays the
                    // single, deterministic driver of the slide.
                    withAnimation(stretch) { layoutMode = mode }
                } label: {
                    modeGlyph(mode)
                }
                // Plain (no press dip): the icons stay put, only the pill moves.
                .buttonStyle(.plain)
                // STABLE per-mode id — never changes with selection, so picking a
                // mode never slides an icon. It exists only so the current mode's
                // glyph can travel on expand/collapse (matches the resting glyph).
                .matchedGeometryEffect(id: "mode-\(mode.rawValue)", in: morph)
                .transition(isSelected ? .identity : pop)
            }

            iconButton("xmark", tint: MuseTheme.Semantic.textHeading, weight: .semibold, size: 14) {
                withAnimation(stretch) { viewModeExpanded = false }
            }
            .transition(pop)
        }
        // THE selection animation: one persistent pill, one position, one spring.
        // Nothing else drives it — so every mode-to-mode move is the same springy slide.
        .background(alignment: .leading) {
            Capsule()
                .fill(MuseTheme.Semantic.accentSelectionFill)
                .frame(width: pillWidth, height: 40)
                .offset(x: pillX)
                .animation(.museBar, value: layoutMode)
        }
        // Keep the (hidden) search-icon anchor alive at the leading edge while the
        // picker is open, so the host's persistent icon stays anchored here instead of
        // jumping to a corner — it just fades back in place on close.
        .overlay(alignment: .leading) {
            Color.clear
                .frame(width: 24, height: 24)
                .matchedGeometryEffect(id: "searchSlot", in: namespace, isSource: true)
        }
    }

    /// A layout-mode icon. Just the glyph — the selection pill is a separate single
    /// sliding view in `modePicker`, so it can be governed by one spring.
    private func modeGlyph(_ mode: GalleryLayoutMode) -> some View {
        let tint = mode == layoutMode
            ? MuseTheme.Semantic.accentSelected
            : MuseTheme.Semantic.textHeading
        return Group {
            if mode == .vast {
                VastGridShape()
                    .stroke(tint, lineWidth: VastGridShape.strokeWidth)
            } else {
                Image(systemName: mode.outlineIconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: 24, height: 24)
        .padding(10)
    }

    // MARK: Building blocks

    private func iconButton(
        _ systemName: String,
        tint: Color,
        weight: Font.Weight = .medium,
        size: CGFloat = 18,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .padding(10)
        }
        .buttonStyle(PressableStyle())
    }

    /// Frosted near-white pill with a hairline stroke and soft drop shadow. Shares
    /// `namespace` so it morphs into the host's search field.
    private var barBackground: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(MuseTheme.Semantic.navBarSurface.opacity(0.8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(MuseTheme.Semantic.navBarStroke, lineWidth: 0.5)
            )
            .matchedGeometryEffect(id: "barBG", in: namespace)
            .shadow(color: Color(red: 0.5, green: 0.5, blue: 0.5).opacity(0.2), radius: 1, x: 2, y: 2)
            .shadow(color: Color(red: 0.5, green: 0.5, blue: 0.5).opacity(0.15), radius: 2, x: 4, y: 4)
    }
}

/// Tactile press feedback — the control dips and springs back, so every tap feels
/// physical. Replaces `.plain` (keeps the same flat look, adds the press response).
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(duration: 0.3, bounce: 0.45), value: configuration.isPressed)
    }
}
