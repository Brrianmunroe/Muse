import SwiftUI

/// Half-height dial kit for tuning the mode-switch morphs live. Pick a
/// direction, drag the sliders, toggle modes behind the sheet to feel it,
/// then "Copy specs" to hand the numbers off.
struct MorphTuningPanel: View {
    @ObservedObject var tuning: MorphTuning
    @State private var from: GalleryLayoutMode = .vast
    @State private var to: GalleryLayoutMode = .feed
    @State private var copied = false

    private var key: String { MorphTuning.key(from, to) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Transition") {
                    Picker("From", selection: $from) {
                        ForEach(GalleryLayoutMode.allCases) { mode in
                            Text(mode.rawValue.capitalized).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("To", selection: $to) {
                        ForEach(GalleryLayoutMode.allCases) { mode in
                            Text(mode.rawValue.capitalized).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if from == to {
                    Text("Pick two different modes")
                        .foregroundStyle(.secondary)
                } else {
                    let spec = tuning.binding(for: key)
                    Section {
                        BezierCurveEditor(spec: spec)
                    } header: {
                        Text("Curve")
                    } footer: {
                        Text(spec.wrappedValue.wiggle > 0.001
                             ? "Curve applies when Wiggle is 0 — currently using a spring."
                             : String(format: "cubic-bezier(%.2f, %.2f, %.2f, %.2f)",
                                      spec.wrappedValue.c1x, spec.wrappedValue.c1y,
                                      spec.wrappedValue.c2x, spec.wrappedValue.c2y))
                    }

                    Section("Dials") {
                        dial("Duration", spec.duration, in: 0.2...2.5, format: "%.2fs")
                        dial("Speed range", spec.range, in: 0...0.5, format: "%.2fs")
                        dial("Wiggle", spec.wiggle, in: 0...0.5, format: "%.2f")
                        dial("Motion blur", spec.blurPeak, in: 0...14, format: "%.1f")
                        dial("Stagger", spec.stagger, in: 0...0.4, format: "%.2fs")
                    }

                    Section {
                        Button("Reset this transition") {
                            tuning.reset(key)
                        }
                        Button(copied ? "Copied ✓" : "Copy specs for Claude") {
                            UIPasteboard.general.string = tuning.exportText
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                copied = false
                            }
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .navigationTitle("Motion dials")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func dial(_ label: String, _ value: Binding<Double>, in bounds: ClosedRange<Double>, format: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 14))
            Slider(value: value, in: bounds)
        }
    }
}

/// Draggable cubic-bezier editor: progress (x = time, y = position) with two
/// control handles, like a CSS/After Effects curve editor. Y is allowed to
/// overshoot a little beyond 0–1 for anticipation/overshoot curves.
private struct BezierCurveEditor: View {
    @Binding var spec: MorphSpec

    private static let height: CGFloat = 220
    private static let yOvershoot: Double = 0.3

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                grid(in: size)
                curve(in: size)
                handleLine(from: CGPoint(x: 0, y: yPos(0, in: size)),
                           to: point(spec.c1x, spec.c1y, in: size))
                handleLine(from: CGPoint(x: size.width, y: yPos(1, in: size)),
                           to: point(spec.c2x, spec.c2y, in: size))
                handle(at: point(spec.c1x, spec.c1y, in: size), color: .orange) { p in
                    spec.c1x = xValue(p.x, in: size)
                    spec.c1y = yValue(p.y, in: size)
                }
                handle(at: point(spec.c2x, spec.c2y, in: size), color: .blue) { p in
                    spec.c2x = xValue(p.x, in: size)
                    spec.c2y = yValue(p.y, in: size)
                }
            }
            .coordinateSpace(name: "bezierEditor")
        }
        .frame(height: Self.height)
        .padding(.vertical, 6)
    }

    // MARK: Coordinate mapping (y flipped; overshoot margin top and bottom)

    private func point(_ x: Double, _ y: Double, in size: CGSize) -> CGPoint {
        CGPoint(x: CGFloat(x) * size.width, y: yPos(y, in: size))
    }

    private func yPos(_ y: Double, in size: CGSize) -> CGFloat {
        let span = 1 + 2 * Self.yOvershoot
        return size.height * CGFloat(1 - (y + Self.yOvershoot) / span)
    }

    private func xValue(_ px: CGFloat, in size: CGSize) -> Double {
        min(max(Double(px / size.width), 0), 1)
    }

    private func yValue(_ py: CGFloat, in size: CGSize) -> Double {
        let span = 1 + 2 * Self.yOvershoot
        let y = Double(1 - py / size.height) * span - Self.yOvershoot
        return min(max(y, -Self.yOvershoot), 1 + Self.yOvershoot)
    }

    // MARK: Pieces

    private func grid(in size: CGSize) -> some View {
        Path { path in
            // Unit-square frame (the 0 and 1 position lines).
            for y in [yPos(0, in: size), yPos(1, in: size)] {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            for fraction in [0.25, 0.5, 0.75] {
                let x = size.width * fraction
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
        }
        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
    }

    private func curve(in size: CGSize) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: yPos(0, in: size)))
            path.addCurve(
                to: CGPoint(x: size.width, y: yPos(1, in: size)),
                control1: point(spec.c1x, spec.c1y, in: size),
                control2: point(spec.c2x, spec.c2y, in: size)
            )
        }
        .stroke(Color.primary, lineWidth: 2.5)
    }

    private func handleLine(from: CGPoint, to: CGPoint) -> some View {
        Path { path in
            path.move(to: from)
            path.addLine(to: to)
        }
        .stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
    }

    private func handle(at position: CGPoint, color: Color, onDrag: @escaping (CGPoint) -> Void) -> some View {
        Circle()
            .fill(color)
            .frame(width: 18, height: 18)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            // Generous hit area, but scoped to this dot — applied before
            // .position so the two handles never steal each other's touches.
            .padding(13)
            .contentShape(Circle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("bezierEditor"))
                    .onChanged { value in onDrag(value.location) }
            )
            .position(position)
    }
}
