import Foundation

// MARK: - Stress

/// A single stress reading derived from heart-rate variability and resting HR.
struct StressReading: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var score: Int          // 0 (calm) … 100 (very stressed)
    var hrvSDNN: Double?     // ms, if available
    var restingHR: Double?   // bpm, if available

    var level: StressLevel { StressLevel(score: score) }
}

enum StressLevel: String, Codable {
    case calm = "Calm"
    case balanced = "Balanced"
    case stressed = "Stressed"

    init(score: Int) {
        switch score {
        case ..<34:   self = .calm
        case 34..<67: self = .balanced
        default:      self = .stressed
        }
    }

    var advice: String {
        switch self {
        case .calm:     return "Nicely recovered. Keep it up."
        case .balanced: return "Steady. A few slow breaths help."
        case .stressed: return "Take a breather — try a 1-min breathe."
        }
    }

    var symbol: String {
        switch self {
        case .calm:     return "leaf.fill"
        case .balanced: return "wind"
        case .stressed: return "bolt.heart.fill"
        }
    }
}

// MARK: - Hydration

struct HydrationState: Codable {
    var goalML: Int = 2000
    var consumedML: Int = 0
    var lastResetDay: Int = 0   // day-of-year used to auto-reset daily
    /// Per-reminder times. Empty means "auto-spread evenly between 8:00 and 22:00".
    var reminderTimes: [DateComponents] = []

    var progress: Double {
        guard goalML > 0 else { return 0 }
        return min(1.0, Double(consumedML) / Double(goalML))
    }
}

// MARK: - Stress timeline

/// One point on the rolling stress chart — either a real HRV-derived score, a
/// completed measurement, or just a heart-rate snapshot.
struct StressPoint: Identifiable, Codable {
    enum Source: String, Codable { case hrvSample, measurement, restingHR }
    var id = UUID()
    var date: Date
    var score: Int
    var source: Source
}

// MARK: - Medication

struct Medication: Codable, Identifiable {
    var id = UUID()
    var name: String
    var dose: String            // e.g. "1 pill", "500 mg"
    var times: [DateComponents]  // hour/minute reminders each day
    var takenDates: [Date] = []  // log of when it was taken

    /// Whether a dose has already been logged today.
    func takenToday(now: Date = Date()) -> Bool {
        let cal = Calendar.current
        return takenDates.contains { cal.isDate($0, inSameDayAs: now) }
    }
}

// MARK: - Meals

struct MealReminder: Codable, Identifiable {
    var id = UUID()
    var name: String            // Breakfast / Lunch / Dinner / Snack
    var time: DateComponents
    var enabled: Bool = true
    var loggedDates: [Date] = []

    func loggedToday(now: Date = Date()) -> Bool {
        let cal = Calendar.current
        return loggedDates.contains { cal.isDate($0, inSameDayAs: now) }
    }
}

// MARK: - Helpers

extension DateComponents {
    static func hm(_ hour: Int, _ minute: Int) -> DateComponents {
        DateComponents(hour: hour, minute: minute)
    }

    /// "07:30" style label.
    var hmLabel: String {
        let h = hour ?? 0, m = minute ?? 0
        return String(format: "%02d:%02d", h, m)
    }
}
