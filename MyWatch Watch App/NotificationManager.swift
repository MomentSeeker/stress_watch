import Foundation
import UserNotifications

/// Schedules the local reminders that power hydration / medication / meal
/// nudges. All reminders are repeating daily local notifications, so they keep
/// firing on the watch even when the app isn't open.
///
/// Also acts as the `UNUserNotificationCenterDelegate` so that test reminders
/// and any reminder that happens to fire while the app is in the foreground
/// actually display on the wrist — watchOS suppresses them by default.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show banner + sound even when MyWatch itself is in the foreground. If a
    /// reminder session is already alerting (user tapped a burst sibling and the
    /// app is now in the wake-and-buzz overlay), silently swallow the remaining
    /// pulses so the user isn't pelted with duplicate notifications.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let info = notification.request.content.userInfo
        let isHydration = (info["kind"] as? String) == "hydration"
        Task { @MainActor in
            if isHydration, HydrationReminderSession.shared.isAlerting {
                completionHandler([])
            } else {
                completionHandler([.banner, .sound, .list])
            }
        }
    }

    /// User tapped a hydration burst notification → wake the app into the full
    /// alert overlay (immediate session — the only Session variant free Apple
    /// accounts can use) and clear the rest of the burst from the notification
    /// center so they don't sit there pretending to be unread.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let isHydration = (info["kind"] as? String) == "hydration"
        let slot = info["slot"] as? Int ?? -1
        if isHydration {
            Task { @MainActor in
                HydrationReminderSession.shared.startNow()
                let delivered = await center.deliveredNotifications()
                let siblings: [String] = delivered.compactMap {
                    let u = $0.request.content.userInfo
                    guard (u["kind"] as? String) == "hydration",
                          (u["slot"] as? Int) == slot else { return nil }
                    return $0.request.identifier
                }
                center.removeDeliveredNotifications(withIdentifiers: siblings)
                completionHandler()
            }
        } else {
            completionHandler()
        }
    }

    // MARK: - Hydration

    /// One reminder slot = a **burst of N notifications, K s apart** instead of
    /// a single ping. Both N and K are user-configurable from the Hydration
    /// schedule sheet (persisted to UserDefaults). Defaults give ~10 s of buzz.
    /// Tap any one → the app launches and the wake-and-buzz overlay takes over
    /// (see `didReceive` above).
    static let burstCountDefault = 5
    static let burstSpacingDefault = 2
    static let burstCountRange: ClosedRange<Int> = 1...5
    static let burstSpacingRange: ClosedRange<Int> = 1...5
    /// Schema upper bound used when computing stale notification IDs so that a
    /// burst that *used to* be larger still gets cleaned up after the user
    /// dials the count down. Don't shrink this — it must cover every value
    /// `burstCount` could have taken on disk.
    private static let burstCountSchemaMax = 8
    static let burstCountKey = "hydration.burstCount"
    static let burstSpacingKey = "hydration.burstSpacingSec"
    static let medicationBurstCountKey = "medication.burstCount"
    static let medicationBurstSpacingKey = "medication.burstSpacingSec"

    var burstCount: Int {
        let raw = UserDefaults.standard.object(forKey: Self.burstCountKey) as? Int
            ?? Self.burstCountDefault
        return min(max(raw, Self.burstCountRange.lowerBound), Self.burstCountRange.upperBound)
    }

    var burstSpacingSec: Int {
        let raw = UserDefaults.standard.object(forKey: Self.burstSpacingKey) as? Int
            ?? Self.burstSpacingDefault
        return min(max(raw, Self.burstSpacingRange.lowerBound), Self.burstSpacingRange.upperBound)
    }

    var medicationBurstCount: Int {
        let raw = UserDefaults.standard.object(forKey: Self.medicationBurstCountKey) as? Int
            ?? Self.burstCountDefault
        return min(max(raw, Self.burstCountRange.lowerBound), Self.burstCountRange.upperBound)
    }

    var medicationBurstSpacingSec: Int {
        let raw = UserDefaults.standard.object(forKey: Self.medicationBurstSpacingKey) as? Int
            ?? Self.burstSpacingDefault
        return min(max(raw, Self.burstSpacingRange.lowerBound), Self.burstSpacingRange.upperBound)
    }

    /// Schedule the daily-repeating burst for every time in `times`.
    func scheduleHydrationReminders(times: [DateComponents]) {
        // Remove old burst IDs SYNCHRONOUSLY by enumerating the schema — we
        // can't use the async `removePending(prefix:)` here because its callback
        // can fire *after* the new adds below and wipe them out. (That's the bug
        // that made the "save reminder time" flow silently re-schedule nothing.)
        var staleIds: [String] = []
        for slot in 0..<24 {  // slot count is clamped to 12, this is a margin
            for burst in 0..<Self.burstCountSchemaMax {
                staleIds.append("hydration-\(slot)-\(burst)")
            }
        }
        center.removePendingNotificationRequests(withIdentifiers: staleIds)
        // iOS caps a single app at 64 pending notifications. With burst ≤ 5 and
        // 12 slots that's ≤ 60 — plenty for hydration, and we leave room for
        // meds/meals.
        let count = burstCount
        let spacing = burstSpacingSec
        for (slot, t) in times.prefix(12).enumerated() {
            for burst in 0..<count {
                schedule(id: "hydration-\(slot)-\(burst)",
                         title: "💧 Time to hydrate",
                         body: "Tap to open the reminder.",
                         hour: t.hour ?? 9,
                         minute: t.minute ?? 0,
                         second: burst * spacing,
                         userInfo: ["kind": "hydration", "slot": slot, "burst": burst])
            }
        }
    }

    /// Evenly-spaced default reminder times across waking hours.
    static func defaultHydrationTimes(count: Int) -> [DateComponents] {
        guard count > 0 else { return [] }
        // Preferred preset for the common "5 reminders/day" case.
        if count == 5 {
            return [(9, 30), (11, 30), (14, 30), (16, 0), (17, 30)]
                .map { DateComponents(hour: $0.0, minute: $0.1) }
        }
        let startHour = 8, endHour = 22
        let span = endHour - startHour
        return (0..<count).map { i in
            let hour = startHour + Int(round(Double(span) * Double(i) / Double(max(count - 1, 1))))
            return DateComponents(hour: hour, minute: 0)
        }
    }

    /// Fire the **full N-pulse burst** as a test, starting `seconds` from now,
    /// with the user-configured spacing. Tapping any one wakes the app exactly
    /// like a real reminder does — so this also exercises the tap-to-wake flow.
    func fireTestReminder(in seconds: TimeInterval = 5) {
        let base = max(2, seconds)
        let token = UUID().uuidString
        let count = burstCount
        let spacing = burstSpacingSec
        for burst in 0..<count {
            let content = UNMutableNotificationContent()
            content.title = "💧 Test reminder"
            content.body = "Tap to wake the app."
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            content.userInfo = ["kind": "hydration", "slot": -1, "burst": burst]
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: base + Double(burst * spacing), repeats: false)
            center.add(UNNotificationRequest(identifier: "hydration-test-\(token)-\(burst)",
                                             content: content, trigger: trigger))
        }
    }

    /// Soonest upcoming hydration reminder, or nil if none scheduled. Only the
    /// first pulse of each burst counts as "the reminder time" — the trailing
    /// pulses are an implementation detail.
    func nextHydrationFireDate() async -> Date? {
        let requests = await center.pendingNotificationRequests()
        let dates: [Date] = requests
            .filter { $0.identifier.hasPrefix("hydration-")
                   && !$0.identifier.hasPrefix("hydration-test")
                   && $0.identifier.hasSuffix("-0") }
            .compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() }
        return dates.min()
    }

    // MARK: - Medication

    func scheduleMedication(_ med: Medication) {
        let base = "med-\(med.id.uuidString)"
        var staleIds: [String] = []
        for slot in 0..<24 {
            staleIds.append("\(base)-\(slot)")
            for burst in 0..<Self.burstCountSchemaMax {
                staleIds.append("\(base)-\(slot)-\(burst)")
            }
        }
        center.removePendingNotificationRequests(withIdentifiers: staleIds)

        let count = medicationBurstCount
        let spacing = medicationBurstSpacingSec
        for (slot, time) in med.times.prefix(12).enumerated() {
            for burst in 0..<count {
                schedule(id: "\(base)-\(slot)-\(burst)",
                         title: "💊 \(med.name)",
                         body: "Take \(med.dose).",
                         hour: time.hour ?? 9,
                         minute: time.minute ?? 0,
                         second: burst * spacing,
                         userInfo: ["kind": "medication",
                                    "medicationID": med.id.uuidString,
                                    "slot": slot,
                                    "burst": burst])
            }
        }
    }

    func cancelMedication(_ med: Medication) {
        removePending(prefix: "med-\(med.id.uuidString)")
    }

    func fireTestMedicationReminder(in seconds: TimeInterval = 5) {
        let base = max(2, seconds)
        let token = UUID().uuidString
        let count = medicationBurstCount
        let spacing = medicationBurstSpacingSec
        for burst in 0..<count {
            let content = UNMutableNotificationContent()
            content.title = "💊 Test medication"
            content.body = "Tap to open MyWatch."
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            content.userInfo = ["kind": "medication", "slot": -1, "burst": burst]
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: base + Double(burst * spacing), repeats: false)
            center.add(UNNotificationRequest(identifier: "med-test-\(token)-\(burst)",
                                             content: content, trigger: trigger))
        }
    }

    // MARK: - Meals

    func scheduleMeal(_ meal: MealReminder) {
        let id = "meal-\(meal.id.uuidString)"
        removePending(prefix: id)
        guard meal.enabled else { return }
        schedule(id: id,
                 title: "🍽️ \(meal.name)",
                 body: "Time for \(meal.name.lowercased()). Fuel up well.",
                 hour: meal.time.hour ?? 12, minute: meal.time.minute ?? 0)
    }

    func cancelAllMealReminders() {
        removePending(prefix: "meal-")
    }

    // MARK: - Stress alert

    /// Fired immediately when a high-stress reading is detected.
    func fireHighStressAlert(score: Int) {
        let content = UNMutableNotificationContent()
        content.title = "🫀 Stress is high (\(score))"
        content.body = "Pause for a 1-minute breathe to reset."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "stress-alert-\(UUID().uuidString)",
                                            content: content, trigger: nil)
        center.add(request)
    }

    // MARK: - Internals

    private func schedule(id: String, title: String, body: String,
                          hour: Int, minute: Int, second: Int = 0,
                          userInfo: [String: Any] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive   // punch through Focus / wrist-down
        content.userInfo = userInfo

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        comps.second = second
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    private func removePending(prefix: String) {
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            self.center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
}
