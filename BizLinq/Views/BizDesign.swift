import MapKit
import SwiftUI
import UIKit

/// Shared BizLinq style tokens. Teal carries primary action/selection;
/// category color is used sparingly (cover art, badges).
enum BizStyle {
    static let teal = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.20, green: 0.72, blue: 0.68, alpha: 1.0) // ~#33B8AD
            : UIColor(red: 0.04, green: 0.52, blue: 0.50, alpha: 1.0) // ~#0A857F
    })
    static let tealSoft = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.20, green: 0.72, blue: 0.68, alpha: 0.18)
            : UIColor(red: 0.04, green: 0.52, blue: 0.50, alpha: 0.10)
    })
    /// Near-black in light mode, near-white in dark mode.
    static let ink = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.96, alpha: 1.0)
            : UIColor(red: 0.09, green: 0.13, blue: 0.17, alpha: 1.0) // ~#17212B
    })
    static let canvas = Color(.systemBackground)
    /// Soft fill for search fields, inactive tiles, and secondary buttons.
    static let field = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1.0, alpha: 0.08)
            : UIColor(red: 0.953, green: 0.961, blue: 0.965, alpha: 1.0) // ~#F3F5F6
    })
    static let hairline = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1.0, alpha: 0.14)
            : UIColor(red: 0.878, green: 0.902, blue: 0.918, alpha: 1.0) // ~#E0E6EA
    })
    static let cardRadius: CGFloat = 16
    static let controlRadius: CGFloat = 12
    static let gutter: CGFloat = 16

    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.82)
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.86)
}

// MARK: - Surfaces & motion

extension View {
    /// White card with hairline border and a soft lift.
    func bizCard(radius: CGFloat = BizStyle.cardRadius, padding: CGFloat? = nil) -> some View {
        self
            .padding(padding ?? 0)
            .background(BizStyle.canvas, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(BizStyle.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 4)
    }

    /// Fade-and-rise entrance, staggered by list position.
    func bizAppear(index: Int = 0) -> some View {
        modifier(BizAppearModifier(delay: Double(min(index, 8)) * 0.05))
    }

    /// Source side of the iOS 18 zoom navigation transition.
    @ViewBuilder
    func bizZoomSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// Destination side of the iOS 18 zoom navigation transition.
    @ViewBuilder
    func bizZoomTransition(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}

private struct BizAppearModifier: ViewModifier {
    let delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                guard !shown else { return }
                withAnimation(BizStyle.spring.delay(delay)) { shown = true }
            }
    }
}

/// Gentle press-down scale for tappable cards and tiles.
struct BizPressStyle: ButtonStyle {
    var scale: CGFloat = 0.975

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(BizStyle.snappy, value: configuration.isPressed)
    }
}

// MARK: - Buttons

private struct BizFilledButtonStyle: ButtonStyle {
    let enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(enabled ? Color.white : Color.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: BizStyle.controlRadius, style: .continuous)
                    .fill(enabled ? BizStyle.teal : BizStyle.field)
            )
            .opacity(configuration.isPressed ? 0.88 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(BizStyle.snappy, value: configuration.isPressed)
    }
}

private struct BizOutlineButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: BizStyle.controlRadius, style: .continuous)
                    .fill(configuration.isPressed ? BizStyle.field : BizStyle.canvas)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BizStyle.controlRadius, style: .continuous)
                    .stroke(BizStyle.hairline, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(BizStyle.snappy, value: configuration.isPressed)
    }
}

/// Primary teal action button, 52pt tall, full width.
struct BizPrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var isBusy: Bool = false
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView().tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .contentTransition(.interpolate)
            }
        }
        .buttonStyle(BizFilledButtonStyle(enabled: enabled && !isBusy))
        .disabled(!enabled || isBusy)
        .accessibilityLabel(title)
    }
}

/// Secondary outlined button.
struct BizSecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
        }
        .buttonStyle(BizOutlineButtonStyle(tint: role == .destructive ? .red : BizStyle.teal))
        .accessibilityLabel(title)
    }
}

/// Outlined label styled like `BizSecondaryButton`, for ShareLink/Link.
struct BizSecondaryLabel: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title)
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(BizStyle.teal)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: BizStyle.controlRadius, style: .continuous)
                .fill(BizStyle.field)
        )
    }
}

// MARK: - Chips

/// Selectable pill. Selected pills fill teal; others are outlined.
struct BizChip: View {
    let title: String
    var count: Int? = nil
    let selected: Bool
    var showsCheck: Bool = false
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            withAnimation(BizStyle.snappy) { action() }
        } label: {
            HStack(spacing: 5) {
                if showsCheck && selected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .transition(.scale.combined(with: .opacity))
                } else if let systemImage {
                    Image(systemName: systemImage).font(.caption)
                }
                Text(title)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                if let count {
                    Text("\(count)")
                        .font(.caption)
                        .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
                }
            }
            .lineLimit(1)
            .foregroundStyle(selected ? Color.white : BizStyle.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(Capsule().fill(selected ? BizStyle.teal : BizStyle.canvas))
            .overlay(Capsule().stroke(selected ? Color.clear : BizStyle.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(BizPressStyle(scale: 0.95))
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Wrapping row layout for chips.
struct BizFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Large two-option tile (e.g. In person / Online, Free / Paid).
struct BizChoiceTile: View {
    let title: String
    var systemImage: String? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            withAnimation(BizStyle.snappy) { action() }
        } label: {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.subheadline.weight(selected ? .semibold : .regular))
            .foregroundStyle(selected ? BizStyle.teal : BizStyle.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? BizStyle.tealSoft : BizStyle.canvas)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? BizStyle.teal : BizStyle.hairline, lineWidth: selected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(BizPressStyle(scale: 0.97))
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Badges & tags

/// Cost badge. Unknown/unspecified costs read as "Fee varies" — never "Free".
struct BizCostBadge: View {
    let meeting: Meeting

    var body: some View {
        Text(meeting.costBadgeText)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(BizStyle.tealSoft)
            .foregroundStyle(BizStyle.teal)
            .clipShape(Capsule())
            .accessibilityLabel(meeting.isFreeEntry ? "Free entry" : "Cost: \(meeting.costBadgeText)")
    }
}

/// Soft teal pill with an icon, e.g. "Free to attend".
struct BizTag: View {
    let text: String
    var systemImage: String = "tag"

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.footnote.weight(.medium))
            .foregroundStyle(BizStyle.teal)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(BizStyle.tealSoft, in: Capsule())
    }
}

/// Icon in a soft teal circle.
struct BizIconBadge: View {
    let systemImage: String
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(BizStyle.teal)
            .frame(width: size, height: size)
            .background(BizStyle.tealSoft, in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - Saved meetings

/// Locally saved ("hearted") meetings. Device-only; no account needed.
enum SavedMeetings {
    static let key = "bizlinq.savedMeetingIDs"

    static func ids(_ raw: String) -> Set<String> {
        Set(raw.split(separator: ",").map(String.init))
    }

    static func toggled(_ raw: String, id: UUID) -> String {
        var set = ids(raw)
        let value = id.uuidString
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
        return set.sorted().joined(separator: ",")
    }
}

/// Heart toggle. `onImage` draws a translucent disc for use over cover art.
struct BizSaveButton: View {
    let meetingID: UUID
    var onImage: Bool = true
    @AppStorage(SavedMeetings.key) private var savedRaw = ""

    private var saved: Bool { SavedMeetings.ids(savedRaw).contains(meetingID.uuidString) }

    var body: some View {
        Button {
            withAnimation(BizStyle.snappy) {
                savedRaw = SavedMeetings.toggled(savedRaw, id: meetingID)
            }
        } label: {
            Image(systemName: saved ? "heart.fill" : "heart")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(saved ? Color(red: 0.95, green: 0.29, blue: 0.40) : (onImage ? .white : BizStyle.teal))
                .symbolEffect(.bounce, value: saved)
                .frame(width: 36, height: 36)
                .background {
                    if onImage { Circle().fill(.black.opacity(0.28)) }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: saved)
        .accessibilityLabel(saved ? "Remove from saved" : "Save meeting")
    }
}

// MARK: - Cover art

/// Procedural skyline illustration, seeded by group name so a group's
/// cards, detail hero, and profile always match. Tinted by category.
struct BizCover: View {
    let seed: String
    var category: MeetingCategory = .businessNetworking

    var body: some View {
        Canvas { ctx, size in
            BizCoverPainter(seed: seed, palette: .for(category)).paint(ctx, size: size)
        }
        .accessibilityHidden(true)
    }
}

private struct BizCoverPalette {
    var skyTop: Color
    var skyBottom: Color
    var far: Color
    var near: Color
    var window: Color
    var water: Color
    var foliage: Color

    static func `for`(_ category: MeetingCategory) -> BizCoverPalette {
        switch category {
        case .businessNetworking:
            return BizCoverPalette(
                skyTop: Color(red: 0.42, green: 0.71, blue: 0.86), skyBottom: Color(red: 0.86, green: 0.94, blue: 0.96),
                far: Color(red: 0.62, green: 0.74, blue: 0.82), near: Color(red: 0.16, green: 0.35, blue: 0.47),
                window: Color(red: 0.70, green: 0.88, blue: 0.95), water: Color(red: 0.13, green: 0.46, blue: 0.60),
                foliage: Color(red: 0.13, green: 0.38, blue: 0.28)
            )
        case .realEstate:
            return BizCoverPalette(
                skyTop: Color(red: 0.95, green: 0.66, blue: 0.47), skyBottom: Color(red: 0.99, green: 0.90, blue: 0.79),
                far: Color(red: 0.82, green: 0.66, blue: 0.60), near: Color(red: 0.33, green: 0.25, blue: 0.27),
                window: Color(red: 1.0, green: 0.85, blue: 0.60), water: Color(red: 0.36, green: 0.42, blue: 0.55),
                foliage: Color(red: 0.22, green: 0.33, blue: 0.22)
            )
        case .technology:
            return BizCoverPalette(
                skyTop: Color(red: 0.20, green: 0.24, blue: 0.52), skyBottom: Color(red: 0.55, green: 0.60, blue: 0.86),
                far: Color(red: 0.36, green: 0.40, blue: 0.66), near: Color(red: 0.10, green: 0.12, blue: 0.27),
                window: Color(red: 0.55, green: 0.90, blue: 1.0), water: Color(red: 0.14, green: 0.18, blue: 0.40),
                foliage: Color(red: 0.08, green: 0.20, blue: 0.22)
            )
        case .specialEvents:
            return BizCoverPalette(
                skyTop: Color(red: 0.58, green: 0.40, blue: 0.75), skyBottom: Color(red: 0.98, green: 0.80, blue: 0.82),
                far: Color(red: 0.70, green: 0.56, blue: 0.74), near: Color(red: 0.28, green: 0.18, blue: 0.38),
                window: Color(red: 1.0, green: 0.86, blue: 0.70), water: Color(red: 0.34, green: 0.27, blue: 0.52),
                foliage: Color(red: 0.18, green: 0.24, blue: 0.24)
            )
        }
    }
}

/// Deterministic PRNG (SplitMix64) so art is stable across launches.
private struct SeededGenerator {
    private var state: UInt64

    init(_ string: String) {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325 // FNV-1a
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        state = hash
    }

    mutating func next() -> Double {
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }

    mutating func range(_ lower: Double, _ upper: Double) -> Double {
        lower + (upper - lower) * next()
    }
}

private struct BizCoverPainter {
    let seed: String
    let palette: BizCoverPalette

    private struct Building {
        var rect: CGRect
        var spire: Bool
        var slant: Bool
    }

    func paint(_ ctx: GraphicsContext, size: CGSize) {
        var rng = SeededGenerator(seed)
        let w = size.width, h = size.height
        let horizon = h * 0.70
        let full = CGRect(origin: .zero, size: size)

        ctx.fill(Path(full), with: .linearGradient(
            Gradient(colors: [palette.skyTop, palette.skyBottom]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)
        ))

        // Sun glow
        let sun = CGPoint(x: w * rng.range(0.55, 0.85), y: h * rng.range(0.18, 0.32))
        let glowRadius = h * 0.42
        ctx.fill(
            Path(ellipseIn: CGRect(x: sun.x - glowRadius, y: sun.y - glowRadius, width: glowRadius * 2, height: glowRadius * 2)),
            with: .radialGradient(
                Gradient(colors: [.white.opacity(0.55), .white.opacity(0)]),
                center: sun, startRadius: 0, endRadius: glowRadius
            )
        )

        // Far skyline
        var x: CGFloat = -w * 0.02
        while x < w {
            let bw = w * rng.range(0.035, 0.08)
            let bh = h * rng.range(0.10, 0.30)
            ctx.fill(Path(CGRect(x: x, y: horizon - bh, width: bw, height: bh)), with: .color(palette.far.opacity(0.75)))
            x += bw + w * rng.range(0.0, 0.02)
        }

        // Near skyline, clustered toward the middle like a downtown core
        var buildings: [Building] = []
        x = w * rng.range(0.0, 0.08)
        while x < w * 0.98 {
            let bw = w * rng.range(0.045, 0.10)
            let center = abs((x + bw / 2) / w - 0.5) * 2 // 0 at middle, 1 at edges
            let maxHeight = 0.58 - 0.30 * center
            let bh = h * rng.range(0.12, max(0.16, maxHeight))
            buildings.append(Building(
                rect: CGRect(x: x, y: horizon - bh, width: bw, height: bh),
                spire: rng.next() < 0.18,
                slant: rng.next() < 0.15
            ))
            x += bw + w * rng.range(0.004, 0.05)
        }

        var skyline = Path()
        for b in buildings {
            skyline.addPath(shape(for: b))
        }
        ctx.fill(skyline, with: .linearGradient(
            Gradient(colors: [palette.near.opacity(0.92), palette.near]),
            startPoint: CGPoint(x: 0, y: horizon - h * 0.5), endPoint: CGPoint(x: 0, y: horizon)
        ))

        // Lit windows
        var windows = Path()
        for b in buildings where b.rect.width > w * 0.05 {
            let cols = 3
            let gap = b.rect.width / CGFloat(cols * 2 + 1)
            var wy = b.rect.minY + gap * 1.5
            while wy < horizon - gap * 2 {
                for c in 0..<cols where rng.next() < 0.55 {
                    let wx = b.rect.minX + gap * (CGFloat(c) * 2 + 1)
                    windows.addRect(CGRect(x: wx, y: wy, width: gap, height: gap * 0.9))
                }
                wy += gap * 2.2
            }
        }
        ctx.fill(windows, with: .color(palette.window.opacity(0.45)))

        // Water + reflection
        let waterRect = CGRect(x: 0, y: horizon, width: w, height: h - horizon)
        ctx.fill(Path(waterRect), with: .linearGradient(
            Gradient(colors: [palette.water.opacity(0.85), palette.water]),
            startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: h)
        ))
        var mirrored = ctx
        mirrored.clip(to: Path(waterRect))
        mirrored.translateBy(x: 0, y: horizon * 2)
        mirrored.scaleBy(x: 1, y: -1)
        mirrored.fill(skyline, with: .color(palette.near.opacity(0.35)))

        var shimmer = Path()
        for _ in 0..<10 {
            let sy = horizon + (h - horizon) * rng.range(0.1, 0.95)
            let sx = w * rng.range(0, 0.9)
            shimmer.addRoundedRect(
                in: CGRect(x: sx, y: sy, width: w * rng.range(0.04, 0.14), height: 1.4),
                cornerSize: CGSize(width: 0.7, height: 0.7)
            )
        }
        ctx.fill(shimmer, with: .color(.white.opacity(0.35)))

        // Palms framing the skyline
        var trunks = Path()
        var fronds = Path()
        let palmCount = 1 + Int(rng.next() * 3)
        for i in 0..<palmCount {
            let leftSide = i % 2 == 0
            let baseX = leftSide ? w * rng.range(0.02, 0.18) : w * rng.range(0.80, 0.97)
            let height = min(h * rng.range(0.30, 0.50), w * rng.range(0.16, 0.24))
            let lean = (leftSide ? 1 : -1) * w * rng.range(0.01, 0.035)
            let top = CGPoint(x: baseX + lean, y: horizon + h * 0.04 - height)
            trunks.move(to: CGPoint(x: baseX, y: horizon + h * 0.04))
            trunks.addQuadCurve(to: top, control: CGPoint(x: baseX + lean * 1.8, y: horizon - height * 0.5))
            let span = min(height * 0.42, w * 0.12)
            for f in 0..<9 {
                let angle = Double.pi * (0.92 + Double(f) * 0.145) // fan left → right
                let droop = abs(cos(angle)) * span * 0.45
                let tip = CGPoint(x: top.x + cos(angle) * span, y: top.y + sin(angle) * span * 0.5 + droop)
                let mid = CGPoint(x: (top.x + tip.x) / 2, y: (top.y + tip.y) / 2 - span * 0.12)
                let dx = tip.x - top.x, dy = tip.y - top.y
                let len = max(1, sqrt(dx * dx + dy * dy))
                let nx = -dy / len * span * 0.11, ny = dx / len * span * 0.11
                fronds.move(to: top)
                fronds.addQuadCurve(to: tip, control: CGPoint(x: mid.x + nx, y: mid.y + ny))
                fronds.addQuadCurve(to: top, control: CGPoint(x: mid.x - nx, y: mid.y - ny))
            }
        }
        ctx.stroke(trunks, with: .color(palette.foliage.opacity(0.9)), style: StrokeStyle(lineWidth: max(2, w * 0.007), lineCap: .round))
        ctx.fill(fronds, with: .color(palette.foliage))
    }

    private func shape(for b: Building) -> Path {
        var p = Path()
        let r = b.rect
        if b.slant {
            p.move(to: CGPoint(x: r.minX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY + r.width * 0.5))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.closeSubpath()
        } else {
            p.addRect(r)
        }
        if b.spire {
            p.addRect(CGRect(x: r.midX - 0.75, y: r.minY - r.height * 0.18, width: 1.5, height: r.height * 0.18))
        }
        return p
    }
}

// MARK: - People

/// Initials avatar with a teal gradient.
struct BizAvatar: View {
    let name: String
    var size: CGFloat = 44

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [BizStyle.teal, BizStyle.teal.opacity(0.7)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: Circle()
            )
            .accessibilityHidden(true)
    }
}

/// "Hosted by" row used on detail and group screens.
struct BizHostRow: View {
    let hostName: String
    var subtitle: String? = nil
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            BizAvatar(name: hostName, size: 48)
            VStack(alignment: .leading, spacing: 1) {
                Text("Hosted by")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(hostName)
                    .font(.headline)
                    .foregroundStyle(BizStyle.ink)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Meeting card

/// One tappable meeting card for Discover lists: cover art, title,
/// audience, date, and distance/cost.
struct BizMeetingCard: View {
    let ranked: RankedMeeting
    var showsSave: Bool = true
    @EnvironmentObject private var store: MeetingStore

    private var meeting: Meeting { ranked.meeting }

    private var placeLine: String {
        var bits: [String] = []
        if meeting.isVirtual {
            bits.append("Online")
        } else if let miles = ranked.distanceMiles {
            bits.append(miles < 1 ? "< 1 mi" : String(format: "%.1f mi", miles))
        } else {
            bits.append(meeting.city.isEmpty ? meeting.locationLine : meeting.city)
        }
        bits.append(meeting.costBadgeText)
        return bits.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BizCover(seed: meeting.groupName, category: meeting.category)
                .frame(height: 124)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(alignment: .topTrailing) {
                    if showsSave {
                        BizSaveButton(meetingID: meeting.id).padding(10)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if meeting.isVirtual {
                        Label("Online", systemImage: "video.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.35), in: Capsule())
                            .padding(10)
                    }
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(meeting.title)
                    .font(.headline)
                    .foregroundStyle(BizStyle.ink)
                    .lineLimit(2)
                if !meeting.audienceLine.isEmpty {
                    Text(meeting.audienceLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 5) {
                        cardLine(icon: "calendar", text: Formatters.dateLine(for: meeting.startsAt))
                        cardLine(icon: meeting.isVirtual ? "video" : "mappin.and.ellipse", text: placeLine)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 4)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: BizStyle.cardRadius, style: .continuous))
        .bizCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(meeting.title), \(Formatters.dateLine(for: meeting.startsAt)), \(placeLine)")
    }

    private func cardLine(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.footnote)
                .frame(width: 16)
                .foregroundStyle(BizStyle.ink.opacity(0.75))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(BizStyle.ink.opacity(0.85))
                .lineLimit(1)
        }
    }
}

// MARK: - Rows & headers

/// Icon + two-line metadata row with a fixed icon column.
struct BizMetaRow: View {
    let icon: String
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(BizStyle.ink.opacity(0.7))
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(BizStyle.ink)
                if let detail, !detail.isEmpty {
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Section title with an optional trailing text action.
struct BizSectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .foregroundStyle(BizStyle.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.medium))
                    .tint(BizStyle.teal)
            }
        }
    }
}

/// Group header: cover-filled avatar, name, tagline.
struct BizGroupHeader: View {
    let groupName: String
    let tagline: String
    let hostName: String?

    var body: some View {
        HStack(spacing: 12) {
            BizAvatar(name: groupName, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(groupName).font(.headline).foregroundStyle(BizStyle.ink)
                if !tagline.isEmpty {
                    Text(tagline).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                if let hostName, !hostName.isEmpty {
                    Text("Hosted by \(hostName)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Group \(groupName)")
    }
}

/// Compact meeting row with a calendar tile (group upcoming lists, host).
struct BizDateRow: View {
    let meeting: Meeting

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.body)
                .foregroundStyle(BizStyle.teal)
                .frame(width: 40, height: 40)
                .background(BizStyle.tealSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(Formatters.dateLine(for: meeting.startsAt))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BizStyle.ink)
                Text(meeting.isVirtual ? "Online" : meeting.venue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

// MARK: - Metrics

/// Small summary tile for host metrics.
struct BizMetricTile: View {
    let value: String
    let label: String
    var footnote: String? = nil
    var systemImage: String? = nil

    var body: some View {
        VStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .foregroundStyle(BizStyle.teal)
            }
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(BizStyle.ink)
                .contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(.secondary)
            if let footnote {
                Text(footnote).font(.caption2).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .background(BizStyle.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// Honest placeholder when a metric has no backing data yet.
struct BizMetricUnavailable: View {
    let label: String
    let reason: String
    var systemImage: String? = nil

    var body: some View {
        BizMetricTile(value: "—", label: label, footnote: reason, systemImage: systemImage)
            .accessibilityLabel("\(label): \(reason)")
    }
}

// MARK: - Map

/// Non-interactive map preview; tapping opens Apple Maps.
struct BizMapCard: View {
    let title: String
    let coordinate: CLLocationCoordinate2D

    var body: some View {
        Button {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
            item.name = title
            item.openInMaps()
        } label: {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
            )), interactionModes: []) {
                Marker(title, coordinate: coordinate)
                    .tint(.red)
            }
            .allowsHitTesting(false)
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(BizStyle.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(BizPressStyle())
        .accessibilityLabel("Map showing \(title). Opens in Maps.")
    }
}

// MARK: - States & forms

/// Shared empty / error / loading states.
struct BizStateView: View {
    enum Kind { case empty, error, loading }
    let kind: Kind
    let title: String
    let message: String
    var systemImage: String? = nil
    var actionTitle: String? = nil
    var secondaryTitle: String? = nil
    var action: (() -> Void)? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            if kind == .loading {
                ProgressView().controlSize(.large)
            } else {
                BizIconBadge(
                    systemImage: systemImage ?? (kind == .error ? "wifi.exclamationmark" : "magnifyingglass"),
                    size: 72
                )
                .symbolEffect(.bounce, value: title)
            }
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(BizStyle.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                BizPrimaryButton(title: actionTitle, action: action)
                    .padding(.top, 8)
            }
            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .font(.subheadline.weight(.semibold))
                    .tint(BizStyle.teal)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
    }
}

/// Full-screen centered intro used for signed-out and first-run states.
struct BizIntroView: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            BizIconBadge(systemImage: systemImage, size: 96)
                .bizAppear(index: 0)
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(BizStyle.ink)
                .multilineTextAlignment(.center)
                .bizAppear(index: 1)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .bizAppear(index: 2)
            BizPrimaryButton(title: actionTitle, action: action)
                .padding(.top, 8)
                .bizAppear(index: 3)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
    }
}

/// Form section wrapper with consistent spacing.
struct BizFormSection<Content: View>: View {
    let title: String
    var footnote: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        Section {
            content
            if let footnote {
                Text(footnote).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BizStyle.ink)
                .textCase(nil)
        }
    }
}
