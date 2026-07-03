import SwiftUI
import Charts

/// Stress module — two full-screen pages you swipe between horizontally:
///   1. **Score** — the big ring, current level, one-line advice, "Measure now".
///   2. **Last 12h** — the HRV/Rest/Avg signals and the zoned trend chart.
/// Each page is complete on its own and fills the face without scrolling.
struct StressView: View {
    @EnvironmentObject var store: AppStore
    @State private var showMeasure = false
    @State private var page: Int

    init(initialPage: Int = 0) { _page = State(initialValue: initialPage) }

    private var reading: StressReading? { store.stress }
    private var score: Int { reading?.score ?? 0 }

    var body: some View {
        TabView(selection: $page) {
            scorePage.tag(0)
            trendPage.tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Theme.bg)
        .sheet(isPresented: $showMeasure) {
            MeasureSheet(session: store.measurement) { reading in
                Task { await store.recordMeasurement(reading) }
            }
        }
        .task {
            await store.refreshStressTimeline()
        }
    }

    // MARK: Page 1 — score

    private var scorePage: some View {
        ModuleScreen(title: "Stress", symbol: "waveform.path.ecg",
                     gradient: Theme.stressGradient, pageCount: 2, pageIndex: page) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                RingView(progress: Double(score) / 100,
                         gradient: LinearGradient(colors: [Theme.stressColor(score),
                                                           Theme.stressColor(score).opacity(0.6)],
                                                  startPoint: .top, endPoint: .bottom),
                         lineWidth: Metrics.x(13)) {
                    VStack(spacing: 0) {
                        Text("\(score)")
                            .font(.system(size: Metrics.x(38), weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text(reading?.level.rawValue ?? "—")
                            .font(.system(size: Metrics.x(11)))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: Metrics.ringSize, height: Metrics.ringSize)

                if let level = reading?.level {
                    Label(level.advice, systemImage: level.symbol)
                        .font(.system(size: Metrics.x(11)))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Metrics.x(7)).padding(.horizontal, Metrics.x(8))
                        .cardBackground(cornerRadius: 12)
                        .padding(.top, Metrics.x(10))
                } else {
                    Text("0–100 stress score · from HRV")
                        .font(.system(size: Metrics.x(10)))
                        .foregroundStyle(.secondary)
                        .padding(.top, Metrics.x(10))
                }

                Spacer(minLength: 0)

                Button {
                    showMeasure = true
                    store.startMeasurement()
                } label: {
                    StressMeasureButton(score: score)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Page 2 — 12h trend

    private var trendPage: some View {
        ModuleScreen(title: "Last 12h", symbol: "chart.xyaxis.line",
                     gradient: Theme.stressGradient, pageCount: 2, pageIndex: page) {
            StressInsightPanel(reading: reading, points: store.stressTimeline)
        }
    }
}

// MARK: - Stress insight panel

/// The 12-hour stress card: header status, three signal tiles, the zoned trend
/// chart, and a trend footer — laid out to match the provided design.
struct StressInsightPanel: View {
    var reading: StressReading?
    var points: [StressPoint]

    private var cutoff: Date { Date().addingTimeInterval(-12 * 3600) }
    private var recent: [StressPoint] {
        points.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
    }
    private var latestScore: Int { recent.last?.score ?? reading?.score ?? 0 }
    private var statusText: String {
        switch latestScore { case ..<34: "Calm"; case 34..<67: "Balanced"; default: "High" }
    }
    private var statusColor: Color { Theme.stressColor(latestScore) }
    private var averageScore: Int? {
        guard !recent.isEmpty else { return nil }
        return Int((Double(recent.reduce(0) { $0 + $1.score }) / Double(recent.count)).rounded())
    }
    /// Change vs the sample closest to 3 hours ago — drives the delta pill + footer.
    private var delta: Int? {
        guard let last = recent.last?.score else { return nil }
        let target = Date().addingTimeInterval(-3 * 3600)
        guard let then = recent.min(by: {
            abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target))
        })?.score else { return nil }
        return last - then
    }
    private var deltaText: String { guard let d = delta else { return "" }; return "\(d > 0 ? "+" : "")\(d)" }
    private var trendWord: String {
        guard let d = delta else { return "—" }
        return abs(d) < 5 ? "Steady" : (d > 0 ? "Rising" : "Easing")
    }
    private var trendArrow: String {
        guard let d = delta else { return "arrow.right" }
        return d >= 5 ? "arrow.up.right" : (d <= -5 ? "arrow.down.right" : "arrow.right")
    }

    var body: some View {
        VStack(spacing: Metrics.x(6)) {
            // Status + trend + delta pill (title lives in the screen header).
            HStack(spacing: 6) {
                Text(statusText).font(.system(size: 15, weight: .bold)).foregroundStyle(statusColor)
                Image(systemName: trendArrow)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(statusColor)
                Text(trendWord).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if delta != nil {
                    Text(deltaText)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(statusColor.opacity(0.16), in: Capsule())
                }
            }
            .frame(height: Metrics.x(20))

            // Signal tiles
            HStack(spacing: 5) {
                StressStatTile(icon: "heart.fill", tint: StressPalette.calm, label: "HRV",
                               value: reading?.hrvSDNN.map { "\(Int($0))" } ?? "—", unit: "ms")
                StressStatTile(icon: "heart", tint: StressPalette.balanced, label: "Rest",
                               value: reading?.restingHR.map { "\(Int($0))" } ?? "—", unit: "bpm")
                StressStatTile(icon: "waveform.path.ecg", tint: StressPalette.avg, label: "Avg",
                               value: averageScore.map { "\($0)" } ?? "—", unit: "")
            }
            .frame(height: Metrics.x(42))

            if recent.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "sparkline")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(statusColor.opacity(0.75))
                    Text("No 12h samples yet").font(.system(size: 12, weight: .semibold))
                    Text("Wear overnight or measure now")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                StressTrendChart(recent: recent, cutoff: cutoff)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Shared stress palette — the three zone hues plus the blue used for "Avg".
/// Mirrors `Theme.stressColor` thresholds so the chart, tiles and ring agree.
enum StressPalette {
    static let calm = Color(red: 0.36, green: 0.86, blue: 0.55)
    static let balanced = Color(red: 0.99, green: 0.78, blue: 0.30)
    static let high = Color(red: 0.98, green: 0.42, blue: 0.42)
    static let avg = Color(red: 0.33, green: 0.70, blue: 0.96)
}

/// One signal tile: colored icon + label + big value + unit.
struct StressStatTile: View {
    var icon: String
    var tint: Color
    var label: String
    var value: String
    var unit: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(value).font(.system(size: 13, weight: .bold, design: .rounded))
                    if !unit.isEmpty {
                        Text(unit).font(.system(size: 7, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

struct StressTrendChart: View {
    var recent: [StressPoint]
    var cutoff: Date

    private struct Zone { var value: Double; var title: String; var range: String; var color: Color }
    private static let zones = [
        Zone(value: 88, title: "High", range: "70+", color: StressPalette.high),
        Zone(value: 50, title: "Balanced", range: "30–70", color: Color.white.opacity(0.5)),
        Zone(value: 12, title: "Calm", range: "0–30", color: StressPalette.calm),
    ]

    /// Vertical green→amber→red gradient mapped to the plot's 0–100 height, so
    /// the line/area take their color from how high (stressed) each point sits.
    private func valueGradient(_ opacity: Double, _ topOpacity: Double? = nil) -> LinearGradient {
        let t = topOpacity ?? opacity
        return LinearGradient(stops: [
            .init(color: StressPalette.calm.opacity(opacity), location: 0.0),
            .init(color: StressPalette.calm.opacity(opacity), location: 0.26),
            .init(color: StressPalette.balanced.opacity(opacity), location: 0.5),
            .init(color: StressPalette.high.opacity(t), location: 0.74),
            .init(color: StressPalette.high.opacity(t), location: 1.0),
        ], startPoint: .bottom, endPoint: .top)
    }

    var body: some View {
        Chart {
            // Threshold references at the zone boundaries (70 and 30).
            RuleMark(y: .value("high", 70))
                .foregroundStyle(StressPalette.high.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 0.6, dash: [3, 3]))
            RuleMark(y: .value("calm", 30))
                .foregroundStyle(StressPalette.calm.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 0.6, dash: [3, 3]))

            ForEach(recent) { p in
                AreaMark(x: .value("t", p.date), y: .value("stress", p.score))
                    .interpolationMethod(.catmullRom)
            }
            .foregroundStyle(valueGradient(0.28))

            ForEach(recent) { p in
                LineMark(x: .value("t", p.date), y: .value("stress", p.score))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            .foregroundStyle(valueGradient(1))

            // "Now" marker: a dashed drop line to the axis + a white dot.
            if let last = recent.last {
                RuleMark(x: .value("t", last.date), yStart: .value("s", 0), yEnd: .value("s", last.score))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [2, 2]))
                PointMark(x: .value("t", last.date), y: .value("stress", last.score))
                    .symbolSize(95).foregroundStyle(.white)
                PointMark(x: .value("t", last.date), y: .value("stress", last.score))
                    .symbolSize(36).foregroundStyle(Theme.stressColor(last.score))
            }
        }
        .chartXScale(domain: cutoff...Date())
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 4)) { _ in
                AxisValueLabel(format: .dateTime.hour())
                    .font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }
        .chartYAxis(.hidden)
        .chartPlotStyle { plot in
            plot
                .background(
                    LinearGradient(stops: [
                        .init(color: StressPalette.calm.opacity(0.10), location: 0.0),
                        .init(color: .clear, location: 0.42),
                        .init(color: .clear, location: 0.60),
                        .init(color: StressPalette.high.opacity(0.13), location: 1.0),
                    ], startPoint: .bottom, endPoint: .top)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let anchor = proxy.plotFrame {
                    let plot = geo[anchor]
                    ForEach(Array(Self.zones.enumerated()), id: \.offset) { _, z in
                        let y = proxy.position(forY: z.value) ?? 0
                        Text(z.title)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(z.color)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.black.opacity(0.35), in: Capsule())
                            .fixedSize()
                            .position(x: plot.minX + 20, y: plot.minY + y)
                    }
                }
            }
        }
    }
}

struct StressMeasureButton: View {
    var score: Int

    // Fixed calm-green accent — reads as a clean "start" affordance regardless of
    // the current score (which would otherwise tint it amber/red).
    private let accent = StressPalette.calm

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.18))
                    .frame(width: 26, height: 26)
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
            }
            Text("Measure now")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.08), in: Capsule())
        .overlay(
            Capsule()
                .stroke(accent.opacity(0.30), lineWidth: 0.8)
        )
    }
}

// MARK: - Live measurement sheet

/// Shown while the 60-second measurement runs. Pulses a heart, counts down,
/// shows live HR, and on completion hands the reading back to the store.
struct MeasureSheet: View {
    @ObservedObject var session: StressMeasurementSession
    var onFinish: (StressReading) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "heart.fill")
                .font(.system(size: 36))
                .foregroundStyle(Theme.stressColor(session.result?.score ?? 50))
                .scaleEffect(pulse ? 1.15 : 0.95)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulse)

            switch session.phase {
            case .idle, .measuring:
                Text(session.currentHR.map { "\(Int($0)) bpm" } ?? "— bpm")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                ProgressView(value: session.progress)
                    .tint(Theme.stressColor(50))
                Text("Hold still · \(Int(max(0, session.duration - session.elapsed)))s")
                    .font(.caption2).foregroundStyle(.secondary)
                Button("Cancel") {
                    session.cancel()
                    dismiss()
                }
                .font(.caption2)
                .buttonStyle(.bordered)
            case .finished:
                if let r = session.result {
                    Text("\(r.score)")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.stressColor(r.score))
                    Text(r.level.rawValue)
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Text(r.hrvSDNN.map { "HRV \(Int($0)) ms" } ?? "HRV —")
                        if let hr = r.restingHR { Text("· \(Int(hr)) bpm") }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
                Button("Done") { dismiss() }
                    .font(.caption2)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.stressColor(session.result?.score ?? 50))
            }
        }
        .padding(.horizontal, 6)
        .onAppear { pulse = true }
        .onChange(of: session.phase) { _, new in
            if new == .finished, let r = session.result { onFinish(r) }
        }
    }
}

#Preview {
    StressView().environmentObject(AppStore())
}
