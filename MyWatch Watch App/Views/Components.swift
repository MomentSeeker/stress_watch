import SwiftUI
import WatchKit

/// Device-adaptive sizing. Everything scales off the *actual* watch screen so
/// the layout looks right on every case size (40 / 41 / 42 / 44 / 45 / 46 / 49mm)
/// — never hard-coded point values.
///
/// We use the 176pt-wide 45mm screen as the reference and derive a single
/// `scale` factor from the current device width; all fonts, rings and spacings
/// are expressed as `Metrics.x(...)` of that reference.
enum Metrics {
    /// Physical screen size in points for the current watch.
    static var screen: CGSize { WKInterfaceDevice.current().screenBounds.size }

    /// Reference width (Series 45mm). Scale is clamped so tiny/huge cases stay sane.
    static var scale: CGFloat {
        let s = screen.width / 176.0
        return min(max(s, 0.82), 1.22)
    }

    /// Scale an arbitrary reference value to the current device.
    static func x(_ referenceValue: CGFloat) -> CGFloat { (referenceValue * scale).rounded() }

    /// A ring diameter that fills a comfortable share of the face — bounded by
    /// *both* width and height so it never crowds out the advice card / action
    /// button below it on shorter cases. Height is the tighter constraint on a
    /// watch, so we cap the ring at ~38% of the screen height as well.
    static var ringSize: CGFloat {
        min(screen.width * 0.56, screen.height * 0.4).rounded()
    }

    /// Standard horizontal screen inset.
    static var hInset: CGFloat { x(7) }
}

/// A circular progress ring with a gradient stroke — the signature element used
/// for both the stress score and the hydration goal.
struct RingView<Center: View>: View {
    var progress: Double            // 0…1
    var gradient: LinearGradient
    var lineWidth: CGFloat = 12
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: progress)
            center()
        }
    }
}

/// Button style that makes a tap unmistakable: a crisp haptic the instant your
/// finger lands, plus a springy shrink-and-dim so you *see* the press register —
/// instead of waiting to find out whether it took.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.9

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.55), value: configuration.isPressed)
            .sensoryFeedback(trigger: configuration.isPressed) { _, pressed in
                pressed ? .impact(weight: .medium, intensity: 0.9) : nil
            }
    }
}

/// Small rounded pill button used for quick actions (e.g. +250 ml).
struct PillButton: View {
    var title: String
    var systemImage: String?
    var gradient: LinearGradient
    var compact: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).fontWeight(.semibold)
            }
            .font(compact ? .system(size: 13, weight: .semibold) : .footnote)
            .padding(.vertical, compact ? 6 : 8)
            .frame(maxWidth: .infinity)
            .background(gradient, in: Capsule())
            .foregroundStyle(.black)
        }
        .buttonStyle(PressableStyle())
    }
}

/// Header row with an SF Symbol badge and a title, reused at the top of each tab.
struct ModuleHeader: View {
    var title: String
    var symbol: String
    var gradient: LinearGradient

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 30, height: 30)
                .background(gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(title)
                .font(.headline)
            Spacer()
        }
    }
}

/// Compact one-line header for a full-screen module page: a small gradient
/// badge and the screen title. Deliberately short so the screen body gets the
/// vertical space it needs to fill the face. The page indicator lives at the
/// bottom of `ModuleScreen`, not here, so it can't collide with the clock.
struct ScreenHeader: View {
    var title: String
    var symbol: String
    var gradient: LinearGradient

    var body: some View {
        HStack(spacing: Metrics.x(6)) {
            Image(systemName: symbol)
                .font(.system(size: Metrics.x(11), weight: .bold))
                .foregroundStyle(.black)
                .frame(width: Metrics.x(20), height: Metrics.x(20))
                .background(gradient, in: RoundedRectangle(cornerRadius: Metrics.x(6), style: .continuous))
            Text(title)
                .font(.system(size: Metrics.x(15), weight: .bold))
            Spacer(minLength: 4)
        }
    }
}

/// Tiny horizontal page indicator — shows which screen of a module you're on.
struct PageDots: View {
    var count: Int
    var index: Int
    var tint: Color

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? tint : Color.white.opacity(0.25))
                    .frame(width: i == index ? 9 : 5, height: 5)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: index)
    }
}

/// A single, self-contained module screen that fills exactly one watch face.
///
/// This is the *single source of truth* for per-screen geometry: every screen —
/// Stress, Hydration, Medication and their sibling pages — is wrapped in this
/// same scaffold, so they all share an identical header position and an
/// identical flexible content area. That uniformity is what keeps vertical
/// paging from feeling like the screen jumps taller/shorter between modules.
///
/// The header is pinned to the top (below the system clock's safe area); the
/// rest of the height is one flexible content region. Content is expected to
/// distribute itself with `Spacer()`s so it always *fills* the region without
/// overflowing — no scrolling, no dead space.
struct ModuleScreen<Content: View>: View {
    var title: String
    var symbol: String
    var gradient: LinearGradient
    var pageCount: Int = 0
    var pageIndex: Int = 0
    @ViewBuilder var content: () -> Content

    @State private var appeared = false

    var body: some View {
        // Layout-driven scaffold: a fixed-height header pinned to the top
        // (identical on all six screens) plus a flexible content region that
        // fills everything below it. Content distributes itself with Spacers so
        // it fills the face top-to-bottom without a hard-coded height. We respect
        // the safe area (no ignoresSafeArea) so the header sits just under the
        // clock and is never clipped by the rounded corners. Everything scales
        // via Metrics so it adapts to every watch case size.
        VStack(spacing: Metrics.x(6)) {
            ScreenHeader(title: title, symbol: symbol, gradient: gradient)
                .frame(height: Metrics.x(24))

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if pageCount > 1 {
                PageDots(count: pageCount, index: pageIndex, tint: gradient.asColor)
                    .frame(height: Metrics.x(10))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, Metrics.hInset)
        .padding(.bottom, Metrics.x(3))
        .background(Theme.bg)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.28)) { appeared = true }
        }
        .onDisappear { appeared = false }
    }
}
