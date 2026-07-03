#if DEBUG
import SwiftUI

/// Debug-only mirror of the Smart Stack rectangular widget, rendered inline in
/// the main app so we can screenshot and iterate without adding/removing the
/// widget from the Smart Stack every time. Show with `-DemoWidget` launch arg.
///
/// This is a paste-not-shared copy of the widget's rectangular layout — the
/// widget view itself lives in the widget extension target and depends on
/// WidgetKit, so it can't be imported here. Keep them in sync by hand while
/// iterating; once the design is locked, this file gets deleted.
struct WidgetPreviewView: View {
    var snapshot: WellnessSnapshot

    private var pct: Double {
        guard snapshot.hydrationGoal > 0 else { return 0 }
        return min(1, Double(snapshot.hydrationConsumed) / Double(snapshot.hydrationGoal))
    }
    private var hrv: String { snapshot.hrvSDNN.map { "\(Int($0))" } ?? "—" }
    private var nextWater: String {
        guard let d = snapshot.nextHydrationReminder else { return "—" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    var body: some View {
        // Smart Stack rectangular widget on 46mm watch is ~196 × 84 pt.
        ZStack {
            Color.black.ignoresSafeArea()
            VStack {
                Text("Widget preview · 196 × 84").font(.system(size: 9)).foregroundStyle(.secondary)
                widgetCard
                    .frame(width: 196, height: 84)
                Spacer()
            }
            .padding(.top, 4)
        }
    }

    private var widgetCard: some View {
        ZStack {
            content
        }
    }

    private var content: some View {
        GeometryReader { geo in
            let sx = geo.size.width / 196
            let sy = geo.size.height / 84
            let scale = min(sx, sy)

            ZStack(alignment: .topLeading) {
                cardBackground

                stressIcon
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

                Text(stressLabel)
                    .font(.system(size: 11.5 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(stressColor)
                    .position(x: 80 * sx, y: 50 * sy)

                segmentBar
                    .frame(width: 93 * sx, height: 8 * sy)
                    .position(x: 52.5 * sx, y: 70 * sy)

                Rectangle()
                    .fill(.white.opacity(0.16))
                    .frame(width: max(0.6, 0.7 * sx), height: 56 * sy)
                    .position(x: 119 * sx, y: 42 * sy)

                Image(systemName: "drop.fill")
                    .font(.system(size: 18 * scale, weight: .bold))
                    .foregroundStyle(waterBlue)
                    .position(x: 134 * sx, y: 20 * sy)

                HStack(alignment: .firstTextBaseline, spacing: 1 * scale) {
                    Text("\(Int(pct * 100))")
                        .font(.system(size: 34 * scale, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("%")
                        .font(.system(size: 13.5 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.68))
                }
                .frame(width: 53 * sx, alignment: .leading)
                .position(x: 149 * sx, y: 48 * sy)

                waterTube
                    .frame(width: 12 * sx, height: 59 * sy)
                    .position(x: 187 * sx, y: 42 * sy)
            }
        }
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [
                    Color(red: 0.082, green: 0.098, blue: 0.133),
                    Color(red: 0.051, green: 0.063, blue: 0.090),
                    Color(red: 0.090, green: 0.075, blue: 0.149)
                ], startPoint: .topLeading, endPoint: .bottomTrailing))
            LinearGradient(colors: [
                calmGreen.opacity(0.09),
                .clear,
                highRed.opacity(0.06)
            ], startPoint: .leading, endPoint: .trailing)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var stressIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                .fill(LinearGradient(colors: [
                    Color(red: 0.44, green: 0.88, blue: 0.82),
                    Color(red: 0.55, green: 0.49, blue: 1.0)
                ], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Color(red: 0.02, green: 0.03, blue: 0.04))
        }
    }

    private var segmentBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                HStack(spacing: 1.5) {
                    Capsule().fill(calmGreen)
                    Capsule().fill(balAmber)
                    Capsule().fill(highRed)
                }
                Circle()
                    .fill(.white)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(.black.opacity(0.3), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.5), radius: 1, y: 0.5)
                    .offset(x: max(0, min(geo.size.width - 7,
                                          geo.size.width * CGFloat(snapshot.stressScore) / 100 - 3.5)))
            }
        }
    }

    private var waterTube: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(red: 0.09, green: 0.10, blue: 0.13))
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(.white.opacity(0.45), lineWidth: 1)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(LinearGradient(colors: [
                        Color(red: 0.435, green: 0.878, blue: 1.0),
                        Color(red: 0.18, green: 0.55, blue: 1.0)
                    ], startPoint: .top, endPoint: .bottom))
                    .frame(height: max(2, geo.size.height * CGFloat(pct) - 3))
                    .padding(1.5)
                Capsule()
                    .fill(Color(red: 0.53, green: 0.93, blue: 1.0).opacity(0.9))
                    .frame(height: 1.5)
                    .padding(.horizontal, 1.5)
                    .offset(y: -max(2, geo.size.height * CGFloat(pct) - 3) + 3)
                VStack(spacing: 0) {
                    ForEach(0..<3) { i in
                        Rectangle().fill(.white.opacity(0.25))
                            .frame(height: 0.5).padding(.horizontal, 3.5)
                        if i < 2 { Spacer(minLength: 0) }
                    }
                }
                .padding(.vertical, 5)
            }
        }
    }

    private var stressLabel: String {
        switch snapshot.stressScore {
        case ..<34: return "Calm"
        case 34..<67: return "Balanced"
        default: return "High"
        }
    }
    private var stressColor: Color {
        switch snapshot.stressScore {
        case ..<34: return calmGreen
        case 34..<67: return balAmber
        default: return highRed
        }
    }
    private var calmGreen: Color { Color(red: 0.30, green: 0.89, blue: 0.54) }
    private var balAmber: Color { Color(red: 1.00, green: 0.78, blue: 0.28) }
    private var highRed: Color { Color(red: 1.00, green: 0.42, blue: 0.48) }
    private var waterBlue: Color { Color(red: 0.23, green: 0.74, blue: 0.97) }
}
#endif
