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
        static let surfacePage = Alias.fillCanvas
        static let surfaceCard = Alias.fillSurface
        static let surfaceNavBar = Alias.fillCanvas

        static let textHeading = Alias.textStrong
        static let textBody = Alias.textStrong
        static let textSecondary = Alias.textMuted

        static let buttonPrimaryBg = Alias.brandPrimary
        static let buttonPrimaryFg = Alias.fillCanvas

        static let iconDefault = Alias.textMuted
        static let dividerDefault = Alias.strokeDefault

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
