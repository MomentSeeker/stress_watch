import WidgetKit
import SwiftUI

/// One widget, three sizes:
///   • `.accessoryRectangular` — the Smart Stack card. A compact two-metric
///     layout: stress gets the primary score, label and 3-zone bar; water gets a
///     large percent and vertical fill tube. Text stays minimal so the card is
///     readable at the real 196×84pt Smart Stack size.
///   • `.accessoryCircular` — the stress gauge alone (watch-face slot).
///   • `.accessoryInline` — a single tinted text line (system constraint).
///
/// Data comes from the App-Group-shared `WellnessSnapshot` the main app writes
/// on every state change; the timeline also refreshes every 30 min as a
/// fallback in case the app hasn't been opened.
struct WellnessEntry: TimelineEntry {
    let date: Date
    let snapshot: WellnessSnapshot
}

struct WellnessProvider: TimelineProvider {
    func placeholder(in context: Context) -> WellnessEntry {
        WellnessEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (WellnessEntry) -> Void) {
        completion(WellnessEntry(date: Date(),
                                 snapshot: SharedStore.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WellnessEntry>) -> Void) {
        let snap = SharedStore.load() ?? .placeholder
        let entry = WellnessEntry(date: Date(), snapshot: snap)
        let next = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct WellnessWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MyWatchWellnessWidget",
                            provider: WellnessProvider()) { entry in
            WellnessWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) {
                    ZStack {
                        Color(hex: 0x0A0C12)
                        LinearGradient(colors: [.white.opacity(0.04), .clear],
                                       startPoint: .top, endPoint: .center)
                    }
                }
        }
        .configurationDisplayName("Wellness")
        .description("Stress + hydration at a glance.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

// MARK: - Palette

private enum Palette {
    static let calmGreen  = Color(hex: 0x4DE38A)
    static let balAmber   = Color(hex: 0xFFC847)
    static let highRed    = Color(hex: 0xFF6B7A)
    static let waterBlue  = Color(hex: 0x3BAFFF)
    static let waterFill  = [Color(hex: 0x6FE0FF), Color(hex: 0x2E8BFF)]
    static let stressIcon = [Color(hex: 0x6FE0FF), Color(hex: 0x7B4FE0)]
    static let rim        = [Color(hex: 0x6FE0FF), Color(hex: 0x9B6BFF)]

    static func stressLabelColor(_ score: Int) -> Color {
        switch score {
        case ..<34:   return calmGreen
        case 34..<67: return balAmber
        default:      return highRed
        }
    }
    static func stressLabelText(_ score: Int) -> String {
        switch score { case ..<34: "Calm"; case 34..<67: "Balanced"; default: "High" }
    }
}

// MARK: - View

struct WellnessWidgetView: View {
    @Environment(\.widgetFamily) var family
    var snapshot: WellnessSnapshot

    private var hydrationPct: Double {
        guard snapshot.hydrationGoal > 0 else { return 0 }
        return min(1, Double(snapshot.hydrationConsumed) / Double(snapshot.hydrationGoal))
    }

    private var hrvText: String { snapshot.hrvSDNN.map { "\(Int($0))" } ?? "—" }

    private var nextWaterText: String {
        guard let d = snapshot.nextHydrationReminder else { return "—" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    var body: some View {
        switch family {
        case .accessoryRectangular: rectangular
        case .accessoryCircular:    StressGauge(score: snapshot.stressScore, lineWidth: 5)
        case .accessoryInline:      Text("🫀 \(snapshot.stressScore)  💧 \(Int(hydrationPct * 100))%")
        default:                    rectangular
        }
    }

    // MARK: Rectangular — fixed-ratio Smart Stack card

    private var rectangular: some View {
        GeometryReader { geo in
            let sx = geo.size.width / 196
            let sy = geo.size.height / 84
            let scale = min(sx, sy)

            ZStack(alignment: .topLeading) {
                cardBackground

                StressIcon()
                    .frame(width: 19 * scale, height: 19 * scale)
                    .position(x: 17 * sx, y: 20 * sy)

                Text("Stress")
                    .font(.system(size: 13.5 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .position(x: 49 * sx, y: 20 * sy)

                Text("\(snapshot.stressScore)")
                    .font(.system(size: 34 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .position(x: 31 * sx, y: 47 * sy)

                Text(Palette.stressLabelText(snapshot.stressScore))
                    .font(.system(size: 11.5 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.stressLabelColor(snapshot.stressScore))
                    .position(x: 80 * sx, y: 50 * sy)

                SegmentBar(score: snapshot.stressScore)
                    .frame(width: 93 * sx, height: 8 * sy)
                    .position(x: 52.5 * sx, y: 70 * sy)

                Rectangle()
                    .fill(.white.opacity(0.16))
                    .frame(width: max(0.6, 0.7 * sx), height: 56 * sy)
                    .position(x: 119 * sx, y: 42 * sy)

                Image(systemName: "drop.fill")
                    .font(.system(size: 18 * scale, weight: .bold))
                    .foregroundStyle(Palette.waterBlue)
                    .position(x: 134 * sx, y: 20 * sy)

                HStack(alignment: .firstTextBaseline, spacing: 1 * scale) {
                    Text("\(Int(hydrationPct * 100))")
                        .font(.system(size: 34 * scale, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("%")
                        .font(.system(size: 13.5 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.68))
                }
                .frame(width: 53 * sx, alignment: .leading)
                .position(x: 149 * sx, y: 48 * sy)

                WaterTube(level: hydrationPct)
                    .frame(width: 12 * sx, height: 59 * sy)
                    .position(x: 187 * sx, y: 42 * sy)
            }
        }
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(colors: [
                        Color(hex: 0x151922),
                        Color(hex: 0x0D1017),
                        Color(hex: 0x171326)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            LinearGradient(colors: [
                Palette.calmGreen.opacity(0.09),
                .clear,
                Palette.highRed.opacity(0.06)
            ], startPoint: .leading, endPoint: .trailing)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct StressIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                .fill(LinearGradient(colors: Palette.stressIcon,
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Color(hex: 0x05070A))
        }
    }
}

// MARK: - 3-zone stress bar

/// Three colored capsule segments (calm/balanced/high) with a white indicator
/// dot positioned by score — the signature element of the new card.
struct SegmentBar: View {
    var score: Int

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                HStack(spacing: 1.5) {
                    Capsule().fill(Palette.calmGreen)
                    Capsule().fill(Palette.balAmber)
                    Capsule().fill(Palette.highRed)
                }
                Circle()
                    .fill(.white)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(.black.opacity(0.3), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.5), radius: 1, y: 0.5)
                    .offset(x: max(0, min(geo.size.width - 7,
                                          geo.size.width * CGFloat(score) / 100 - 3.5)))
            }
        }
    }
}

// MARK: - Vertical water tube

/// Stylized water tube on the right edge of the water pane.
struct WaterTube: View {
    var level: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(hex: 0x171920))
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(.white.opacity(0.40), lineWidth: 1)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(LinearGradient(colors: Palette.waterFill,
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: max(2, geo.size.height * CGFloat(level) - 3))
                    .padding(1.5)
                Capsule()
                    .fill(Color(hex: 0x88EDFF).opacity(0.9))
                    .frame(height: 1.5)
                    .padding(.horizontal, 1.5)
                    .offset(y: -max(2, geo.size.height * CGFloat(level) - 3) + 3)
                VStack(spacing: 0) {
                    ForEach(0..<3) { i in
                        Rectangle()
                            .fill(.white.opacity(0.22))
                            .frame(height: 0.5)
                        .padding(.horizontal, 3)
                        if i < 2 { Spacer(minLength: 0) }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - Stress gauge (kept for accessoryCircular)

struct StressGauge: View {
    var score: Int
    var lineWidth: CGFloat

    var body: some View {
        let color = Palette.stressLabelColor(score)
        ZStack {
            Circle().stroke(.white.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, Double(score) / 100))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: -1) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color)
                Text("\(score)")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
            }
        }
        .widgetAccentable()
    }
}

// MARK: - Color hex helper

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

#Preview(as: .accessoryRectangular) {
    WellnessWidget()
} timeline: {
    WellnessEntry(date: .now, snapshot: WellnessSnapshot(
        stressScore: 36, stressLevel: "Balanced", stressDate: .now,
        hrvSDNN: 47, hydrationConsumed: 840, hydrationGoal: 2000,
        nextHydrationReminder: Calendar.current.date(bySettingHour: 14, minute: 30, second: 0, of: .now),
        updatedAt: .now))
    WellnessEntry(date: .now, snapshot: WellnessSnapshot(
        stressScore: 78, stressLevel: "Stressed", stressDate: .now,
        hrvSDNN: 28, hydrationConsumed: 1700, hydrationGoal: 2000,
        nextHydrationReminder: nil, updatedAt: .now))
}
