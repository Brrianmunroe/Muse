import SwiftUI

/// One transition direction's dialed values. All five knobs map onto the morph
/// math in `GalleryCanvasView.transition(from:to:)`.
struct MorphSpec: Codable, Equatable {
    /// Base spring response in seconds — the floor every tile starts from.
    var duration: Double
    /// Extra response added for the longest trips (per-tile scaling range).
    var range: Double
    /// Spring overshoot, 0 = dead stop. Damping fraction is `1 - wiggle`.
    var wiggle: Double
    /// Cap on per-tile motion blur radius.
    var blurPeak: Double
    /// Max extra delay for the farthest-travelling tile.
    var stagger: Double
    /// Cubic-bezier control points used when wiggle is 0 (curve mode).
    /// Defaults to a symmetric easy-ease.
    var c1x: Double = 0.45
    var c1y: Double = 0
    var c2x: Double = 0.55
    var c2y: Double = 1

    init(duration: Double, range: Double, wiggle: Double, blurPeak: Double, stagger: Double,
         c1x: Double = 0.45, c1y: Double = 0, c2x: Double = 0.55, c2y: Double = 1) {
        self.duration = duration
        self.range = range
        self.wiggle = wiggle
        self.blurPeak = blurPeak
        self.stagger = stagger
        self.c1x = c1x
        self.c1y = c1y
        self.c2x = c2x
        self.c2y = c2y
    }

    // Older saved specs predate the bezier fields — decode them with the
    // easy-ease defaults instead of failing.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        duration = try c.decode(Double.self, forKey: .duration)
        range = try c.decode(Double.self, forKey: .range)
        wiggle = try c.decode(Double.self, forKey: .wiggle)
        blurPeak = try c.decode(Double.self, forKey: .blurPeak)
        stagger = try c.decode(Double.self, forKey: .stagger)
        c1x = try c.decodeIfPresent(Double.self, forKey: .c1x) ?? 0.45
        c1y = try c.decodeIfPresent(Double.self, forKey: .c1y) ?? 0
        c2x = try c.decodeIfPresent(Double.self, forKey: .c2x) ?? 0.55
        c2y = try c.decodeIfPresent(Double.self, forKey: .c2y) ?? 1
    }
}

/// Live-tunable animation specs for the six mode-switch directions, persisted
/// across launches. The dial panel edits these; the canvas reads them on every
/// transition, so changes apply instantly. "Copy specs" exports `exportText`
/// for handing the final numbers back to be baked in as defaults.
final class MorphTuning: ObservableObject {
    @Published var specs: [String: MorphSpec] {
        didSet { persist() }
    }

    private static let storageKey = "morphTuningSpecs.v4"

    /// One calm motion system for every direction (2026-06-11): no springs, so
    /// nothing overshoots or rebounds. Every tile rides the same decelerating
    /// ease (cubic-bezier 0.4, 0, 0.2, 1) — smooth start, soft landing, settles
    /// once. Wiggle is 0 everywhere (curve mode); durations scale with trip and
    /// the big vast↔feed blow-up gets the longest, most deliberate curve. Blur
    /// and stagger kept low so the busy scatters read clean, not chaotic.
    private static let ease = (c1x: 0.4, c1y: 0.0, c2x: 0.2, c2y: 1.0)

    static func defaults() -> [String: MorphSpec] {
        func spec(_ duration: Double, range: Double, blur: Double, stagger: Double) -> MorphSpec {
            MorphSpec(duration: duration, range: range, wiggle: 0, blurPeak: blur, stagger: stagger,
                      c1x: ease.c1x, c1y: ease.c1y, c2x: ease.c2x, c2y: ease.c2y)
        }
        return [
            "vast→bento": spec(0.50, range: 0.25, blur: 1.0, stagger: 0.10),
            "vast→feed":  spec(0.80, range: 0.40, blur: 1.5, stagger: 0.10),
            "bento→vast": spec(0.50, range: 0.25, blur: 1.0, stagger: 0.10),
            "bento→feed": spec(0.50, range: 0.25, blur: 1.0, stagger: 0.10),
            "feed→vast":  spec(0.70, range: 0.30, blur: 1.5, stagger: 0.08),
            "feed→bento": spec(0.30, range: 0.25, blur: 1.0, stagger: 0.12)
        ]
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([String: MorphSpec].self, from: data) {
            // Merge over defaults so new directions/fields pick up baseline values.
            specs = Self.defaults().merging(saved) { _, dialed in dialed }
        } else {
            specs = Self.defaults()
        }
    }

    static func key(_ from: GalleryLayoutMode, _ to: GalleryLayoutMode) -> String {
        "\(from.rawValue)→\(to.rawValue)"
    }

    func spec(from: GalleryLayoutMode, to: GalleryLayoutMode) -> MorphSpec {
        // Same-mode "transitions" happen on viewport resizes — fall back to the
        // baseline values rather than force-unwrapping a key that never exists.
        specs[Self.key(from, to)]
            ?? MorphSpec(duration: 0.7, range: 0.25, wiggle: 0.06, blurPeak: 6, stagger: 0.18)
    }

    func binding(for key: String) -> Binding<MorphSpec> {
        Binding(
            get: { self.specs[key] ?? MorphTuning.defaults()[key]! },
            set: { self.specs[key] = $0 }
        )
    }

    func reset(_ key: String) {
        specs[key] = Self.defaults()[key]
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(specs) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    /// Human-readable dump of every direction, for pasting back to Claude.
    var exportText: String {
        var lines = ["Muse morph specs:"]
        for from in GalleryLayoutMode.allCases {
            for to in GalleryLayoutMode.allCases where from != to {
                let s = spec(from: from, to: to)
                lines.append(String(
                    format: "%@ → %@: duration %.2fs, range %.2fs, wiggle %.2f, blur %.1f, stagger %.2fs, bezier(%.2f, %.2f, %.2f, %.2f)",
                    from.rawValue, to.rawValue, s.duration, s.range, s.wiggle, s.blurPeak, s.stagger,
                    s.c1x, s.c1y, s.c2x, s.c2y
                ))
            }
        }
        return lines.joined(separator: "\n")
    }
}
