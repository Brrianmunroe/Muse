import SwiftUI

/// Floating capsule control for switching between the three gallery modes.
struct GalleryModeToggle: View {
    @Binding var mode: GalleryLayoutMode
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(GalleryLayoutMode.allCases) { candidate in
                Button {
                    guard candidate != mode else { return }
                    mode = candidate
                } label: {
                    Image(systemName: candidate.iconName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(
                            mode == candidate
                                ? MuseTheme.Semantic.buttonPrimaryFg
                                : MuseTheme.Semantic.iconDefault
                        )
                        .frame(width: 44, height: 34)
                        .background {
                            if mode == candidate {
                                Capsule()
                                    .fill(MuseTheme.Semantic.buttonPrimaryBg)
                                    .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(candidate.label)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: mode)
        .padding(4)
        .background(
            Capsule()
                .fill(MuseTheme.Semantic.surfaceCard)
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        )
        .overlay(
            Capsule()
                .stroke(MuseTheme.Semantic.dividerDefault, lineWidth: 1)
        )
    }
}
