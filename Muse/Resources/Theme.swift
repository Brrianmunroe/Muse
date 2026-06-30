import SwiftUI

enum MuseTheme {

    // MARK: - Tier 1: Primitives (raw hex values — the single source of truth)

    enum Primitive {
        static let red900 = Color(hex: "6B2625")
        static let red500 = Color(hex: "C4706E")
        static let red200 = Color(hex: "E8C5C4")

        static let blue900 = Color(hex: "2A3A58")
        static let blue500 = Color(hex: "6B80A3")
        static let blue200 = Color(hex: "C9D4E6")

        static let ochre900 = Color(hex: "5C4A1A")
        static let ochre500 = Color(hex: "D4B872")
        static let ochre200 = Color(hex: "EDDAAE")

        static let neutral900 = Color(hex: "2C2B28")
        static let neutral700 = Color(hex: "3E3D38")
        static let neutral500 = Color(hex: "8A877E")
        static let neutral300 = Color(hex: "D3D1C7")
        static let neutral200 = Color(hex: "DDD9CF")
        static let neutral100 = Color(hex: "F1EFE8")
        static let neutral50 = Color(hex: "F5F2EC")

        // Purple accent — introduced with the consolidated nav bar.
        static let purple700 = Color(hex: "7744FF")                      // accent / selected icon
        static let purple500 = Color(red: 0.58, green: 0.42, blue: 1)    // FAB gradient end (Figma)
        static let purple300 = Color(red: 0.73, green: 0.64, blue: 0.97) // FAB border (Figma)
        static let purple200 = Color(red: 0.81, green: 0.74, blue: 1)    // FAB gradient start (Figma)
        static let purple100 = Color(hex: "D4C5FF")                      // mode-selection pill

        // Near-white frosted surfaces for the nav bar.
        static let frost = Color(hex: "FCFCFC")
        static let frostStroke = Color(hex: "E4E4E4")
    }

    // MARK: - Tier 2: Aliases (purpose-based names → reference Primitives)

    enum Alias {
        static let brandPrimary = Primitive.neutral900
        static let brandAccentRed = Primitive.red500
        static let brandAccentBlue = Primitive.blue500
        static let brandAccentOchre = Primitive.ochre500

        static let textStrong = Primitive.neutral900
        static let textMuted = Primitive.neutral500

        static let fillCanvas = Primitive.neutral50
        static let fillSurface = Primitive.neutral100
        static let strokeDefault = Primitive.neutral300

        static let fillTintRed = Primitive.red200
        static let fillTintBlue = Primitive.blue200
        static let fillTintOchre = Primitive.ochre200
        static let fillTintNeutral = Primitive.neutral200

        static let textOnTintRed = Primitive.red900
        static let textOnTintBlue = Primitive.blue900
        static let textOnTintOchre = Primitive.ochre900
        static let textOnTintNeutral = Primitive.neutral700
    }

    // MARK: - Tier 3: Semantic (element-specific names → reference Aliases)

    enum Semantic {
        static let surfacePage = Color(hex: "F9F9F9")
        static let surfaceCard = Alias.fillSurface
        static let surfaceNavBar = Alias.fillCanvas

        static let textHeading = Alias.textStrong
        static let textBody = Alias.textStrong
        static let textSecondary = Alias.textMuted

        static let buttonPrimaryBg = Alias.brandPrimary
        static let buttonPrimaryFg = Alias.fillCanvas

        static let iconDefault = Alias.textMuted
        static let dividerDefault = Alias.strokeDefault

        // Consolidated nav bar.
        static let navBarSurface = Primitive.frost            // frosted fill tint (used ~0.8 opacity over a material)
        static let navBarStroke = Primitive.frostStroke
        static let accentSelected = Primitive.purple700        // selected mode / view icon
        static let accentSelectionFill = Primitive.purple100   // sliding pill behind the selected mode
        static let fabStroke = Primitive.purple300
        static let fabGradient = LinearGradient(
            colors: [Primitive.purple200, Primitive.purple500],
            startPoint: .top,
            endPoint: .bottom
        )

        static let tagTypographyBg = Alias.fillTintBlue
        static let tagTypographyFg = Alias.textOnTintBlue
        static let tagColorBg = Alias.fillTintOchre
        static let tagColorFg = Alias.textOnTintOchre
        static let tagLayoutBg = Alias.fillTintRed
        static let tagLayoutFg = Alias.textOnTintRed
        static let tagStyleBg = Alias.fillTintNeutral
        static let tagStyleFg = Alias.textOnTintNeutral

        static func tagBackground(for category: TagCategory) -> Color {
            switch category {
            case .typography: return tagTypographyBg
            case .color: return tagColorBg
            case .layout: return tagLayoutBg
            case .style: return tagStyleBg
            }
        }

        static func tagForeground(for category: TagCategory) -> Color {
            switch category {
            case .typography: return tagTypographyFg
            case .color: return tagColorFg
            case .layout: return tagLayoutFg
            case .style: return tagStyleFg
            }
        }
    }

    // MARK: - Typography

    static let serifFont = "InstrumentSerif-Regular"

    static func serif(_ size: CGFloat) -> Font {
        .custom(serifFont, size: size)
    }
}

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)

        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
