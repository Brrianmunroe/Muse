import SwiftUI

enum TagChipStyle {
    case standard
    case glass
}

struct TagChip: View {
    let label: String
    let category: TagCategory
    var style: TagChipStyle = .standard

    init(tag: Tag, style: TagChipStyle = .standard) {
        label = tag.label
        category = tag.category
        self.style = style
    }

    init(preview: TagPreview, style: TagChipStyle = .standard) {
        label = preview.label
        category = preview.category
        self.style = style
    }

    var body: some View {
        switch style {
        case .standard:
            Text(label)
                .font(.system(size: 12))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(MuseTheme.Semantic.tagBackground(for: category))
                .foregroundStyle(MuseTheme.Semantic.tagForeground(for: category))
                .clipShape(Capsule())
        case .glass:
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.2))
                .foregroundStyle(ImageDetailView.glassForeground)
                .clipShape(Capsule())
        }
    }
}
