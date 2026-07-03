import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Snapshot of the few pieces of app state the Smart Stack widget needs. Lives
/// in `UserDefaults(suiteName:)` backed by the shared App Group so the widget
/// extension can read what the main app wrote, with no other IPC.
struct WellnessSnapshot: Codable {
    var stressScore: Int
    var stressLevel: String
    var stressDate: Date
    var hrvSDNN: Double?
    var hydrationConsumed: Int
    var hydrationGoal: Int
    var nextHydrationReminder: Date?
    var updatedAt: Date

    static let placeholder = WellnessSnapshot(
        stressScore: 42, stressLevel: "Balanced", stressDate: Date(),
        hrvSDNN: 48, hydrationConsumed: 1200, hydrationGoal: 2000,
        nextHydrationReminder: nil, updatedAt: Date())
}

enum SharedStore {
    static let appGroupID = "group.com.lichaochen.mywatch.qf8c3873ku"
    private static let key = "mywatch.snapshot.v1"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func save(_ snapshot: WellnessSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    static func load() -> WellnessSnapshot? {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(WellnessSnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }
}
