import Foundation
import SwiftUI

/// Single source of truth for the whole app. Holds all state, persists it to
/// `UserDefaults`, and coordinates HealthKit + notifications. Views observe this
/// and call its mutating methods.
@MainActor
final class AppStore: ObservableObject {
    // Published state
    @Published var stress: StressReading?
    @Published var stressHistory: [StressReading] = []
    @Published var stressTimeline: [StressPoint] = []   // last 12h, for the chart
    @Published var hydration = HydrationState()
    @Published var medications: [Medication] = []
    @Published var meals: [MealReminder] = []
    @Published var hydrationRemindersPerDay: Int = 5
    @Published var measurement = StressMeasurementSession()

    private let defaults = UserDefaults.standard
    private let highStressThreshold = 70

    // MARK: - Lifecycle

    func bootstrap() async {
        load()
        resetDailyCountersIfNeeded()
        let demoData = ProcessInfo.processInfo.arguments.contains("-DemoData")
        // Under -DemoData (screenshot/preview mode) skip the system permission
        // prompts so captures aren't blocked by the Health/Notifications dialogs.
        if !demoData {
            _ = await NotificationManager.shared.requestAuthorization()
            _ = await HealthManager.shared.requestAuthorization()
            await refreshStress()
        }
        rescheduleAllReminders()

        // Subscribe to passive HealthKit updates: every time the watch records a
        // new HRV sample, refresh the reading/chart/widget — no user action.
        // (Skipped under -DemoData so seeded preview values aren't overwritten.)
        if !demoData {
            HealthManager.shared.enablePassiveUpdates { [weak self] in
                Task { @MainActor in await self?.passiveRefresh() }
            }
        }

        #if DEBUG
        // `-DemoAlert` on the scheme/launch fires the reminder a couple seconds in,
        // so the wake-and-buzz alert can be captured without manual tapping.
        if ProcessInfo.processInfo.arguments.contains("-DemoAlert") {
            HydrationReminderSession.shared.scheduleTest(in: 2)
        }
        // `-DemoData` fills the 12h trend with natural-looking random samples so
        // the chart can be previewed without waiting for real HRV to accumulate.
        if ProcessInfo.processInfo.arguments.contains("-DemoData") {
            seedDemoTimeline()
            hydration.consumedML = 1150   // partial fill so the ring reads well
        }
        #endif
    }

    #if DEBUG
    /// Fill `stressHistory` with ~12h of gently-varying random readings (a smooth
    /// random walk, not white noise, so it looks like a real day) and refresh the
    /// timeline. Debug/preview only — gated behind the `-DemoData` launch arg.
    func seedDemoTimeline() {
        let now = Date()
        let count = 26
        let step = (12.0 * 3600.0) / Double(count)
        let phase = Double.random(in: 0...0.5)
        var readings: [StressReading] = []
        for i in stride(from: count, through: 0, by: -1) {
            // A gentle hump that rises through the zones and settles, plus noise —
            // so the trend crosses calm→balanced→high and shows off the gradient.
            let t = Double(count - i) / Double(count)          // 0 (oldest) … 1 (now)
            let base = 36 + 40 * sin((t + phase) * .pi)
            let score = clamp(base + Double.random(in: -7...7), 8, 96)
            readings.append(StressReading(date: now.addingTimeInterval(-Double(i) * step),
                                          score: Int(score.rounded()),
                                          hrvSDNN: Double.random(in: 38...58),
                                          restingHR: Double.random(in: 58...70)))
        }
        stressHistory = readings
        stress = readings.last
        Task { await refreshStressTimeline() }
    }
    #endif

    /// Lightweight refresh triggered by a background HRV sample. Updates the
    /// current reading, the 12-hour chart (read straight from HealthKit) and the
    /// widget snapshot — without appending to history or re-firing alerts.
    func passiveRefresh() async {
        adoptIfFresher(await HealthManager.shared.latestStress())
        await refreshStressTimeline()
        save()
    }

    /// Replace `stress` only when `candidate` is at least as fresh as what we're
    /// already showing. Stops a stale HealthKit sample (e.g. last night's sleep
    /// HRV) from overwriting a freshly-taken manual measurement on the dial.
    private func adoptIfFresher(_ candidate: StressReading) {
        let currentDate = stress?.date ?? .distantPast
        if candidate.date >= currentDate {
            stress = candidate
        }
    }

    // MARK: - Stress

    func refreshStress() async {
        let reading = await HealthManager.shared.latestStress()
        adoptIfFresher(reading)
        stressHistory.append(reading)
        if stressHistory.count > 48 { stressHistory.removeFirst(stressHistory.count - 48) }
        if reading.score >= highStressThreshold {
            NotificationManager.shared.fireHighStressAlert(score: reading.score)
        }
        await refreshStressTimeline()
        save()
    }

    /// Pulls a 12-hour rolling timeline from HealthKit (HRV samples + HR fallback)
    /// and merges in every locally captured manual measurement, so the chart on
    /// the Stress tab always shows the freshest values the user just took.
    func refreshStressTimeline() async {
        var points = await HealthManager.shared.stressTimeline(hours: 12)
        let cutoff = Date().addingTimeInterval(-12 * 3600)
        let manual = stressHistory.filter { $0.date >= cutoff }.map {
            StressPoint(date: $0.date, score: $0.score, source: .measurement)
        }
        points.append(contentsOf: manual)
        stressTimeline = points.sorted { $0.date < $1.date }
    }

    /// Run a real 60-second on-device measurement, then persist its result.
    func startMeasurement() {
        measurement.start()
    }

    /// Called when the live session finishes — fold the reading into history.
    func recordMeasurement(_ reading: StressReading) async {
        stress = reading
        stressHistory.append(reading)
        if stressHistory.count > 48 { stressHistory.removeFirst(stressHistory.count - 48) }
        if reading.score >= highStressThreshold {
            NotificationManager.shared.fireHighStressAlert(score: reading.score)
        }
        await refreshStressTimeline()
        save()
    }

    // MARK: - Hydration

    func addWater(_ ml: Int) {
        resetDailyCountersIfNeeded()
        let next = hydration.consumedML + ml
        hydration.consumedML = clamp(next, 0, hydration.goalML * 2)
        save()
    }

    func setHydrationGoal(_ ml: Int) {
        hydration.goalML = max(250, ml)
        save()
    }

    /// Change the number of reminders. Resets `reminderTimes` to an evenly-spread
    /// default for the new count so the user has somewhere to edit from.
    func setHydrationReminders(_ count: Int) {
        let clamped = clamp(count, 0, 16)
        hydrationRemindersPerDay = clamped
        hydration.reminderTimes = NotificationManager.defaultHydrationTimes(count: clamped)
        NotificationManager.shared.scheduleHydrationReminders(times: hydration.reminderTimes)
        save()
    }

    /// Update one reminder's time (used by the per-row time picker).
    func setHydrationReminderTime(at index: Int, to time: DateComponents) {
        guard hydration.reminderTimes.indices.contains(index) else { return }
        hydration.reminderTimes[index] = time
        NotificationManager.shared.scheduleHydrationReminders(times: hydration.reminderTimes)
        save()
    }

    // MARK: - Medication

    func addMedication(_ med: Medication) {
        medications.append(med)
        NotificationManager.shared.scheduleMedication(med)
        save()
    }

    func rescheduleMedicationReminders() {
        medications.forEach { NotificationManager.shared.scheduleMedication($0) }
        save()
    }

    func removeMedication(_ med: Medication) {
        NotificationManager.shared.cancelMedication(med)
        medications.removeAll { $0.id == med.id }
        save()
    }

    func logMedicationTaken(_ med: Medication) {
        guard let idx = medications.firstIndex(where: { $0.id == med.id }) else { return }
        medications[idx].takenDates.append(Date())
        save()
    }

    // MARK: - Meals

    func toggleMeal(_ meal: MealReminder) {
        guard let idx = meals.firstIndex(where: { $0.id == meal.id }) else { return }
        meals[idx].enabled.toggle()
        NotificationManager.shared.scheduleMeal(meals[idx])
        save()
    }

    func logMeal(_ meal: MealReminder) {
        guard let idx = meals.firstIndex(where: { $0.id == meal.id }) else { return }
        meals[idx].loggedDates.append(Date())
        save()
    }

    // MARK: - Scheduling

    private func rescheduleAllReminders() {
        if hydration.reminderTimes.isEmpty {
            hydration.reminderTimes = NotificationManager.defaultHydrationTimes(count: hydrationRemindersPerDay)
        }
        NotificationManager.shared.scheduleHydrationReminders(times: hydration.reminderTimes)
        medications.forEach { NotificationManager.shared.scheduleMedication($0) }
        NotificationManager.shared.cancelAllMealReminders()
        // (Note: we used to also schedule a WKExtendedRuntimeSession at the next
        //  reminder time so watchOS would auto-wake the app. That path requires a
        //  paid Apple Developer entitlement and silently fails on free accounts.
        //  The reminder is now a 5-pulse notification burst with tap-to-wake; the
        //  immediate-session path still works and runs on tap.)
    }

    // MARK: - Daily reset

    private func resetDailyCountersIfNeeded() {
        let today = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        if hydration.lastResetDay != today {
            hydration.consumedML = 0
            hydration.lastResetDay = today
            save()
        }
    }

    // MARK: - Persistence

    private struct Persisted: Codable {
        var stressHistory: [StressReading]
        var hydration: HydrationState
        var medications: [Medication]
        var meals: [MealReminder]
        var hydrationRemindersPerDay: Int
    }

    private let key = "mywatch.state.v1"

    private func save() {
        let snapshot = Persisted(stressHistory: stressHistory,
                                 hydration: hydration,
                                 medications: medications,
                                 meals: meals,
                                 hydrationRemindersPerDay: hydrationRemindersPerDay)
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: key)
        }
        publishWidgetSnapshot()
    }

    /// Publish a widget-friendly snapshot to the shared App Group so the Smart
    /// Stack card reflects whatever just changed.
    private func publishWidgetSnapshot() {
        Task {
            let next = await NotificationManager.shared.nextHydrationFireDate()
            let snap = WellnessSnapshot(
                stressScore: stress?.score ?? 0,
                stressLevel: stress?.level.rawValue ?? "—",
                stressDate: stress?.date ?? Date(),
                hrvSDNN: stress?.hrvSDNN,
                hydrationConsumed: hydration.consumedML,
                hydrationGoal: hydration.goalML,
                nextHydrationReminder: next,
                updatedAt: Date())
            SharedStore.save(snap)
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(Persisted.self, from: data) else {
            seedDefaults()
            return
        }
        stressHistory = snapshot.stressHistory
        hydration = snapshot.hydration
        medications = snapshot.medications
        meals = []
        hydrationRemindersPerDay = snapshot.hydrationRemindersPerDay
    }

    /// First-launch sample data so the app is immediately useful and pretty.
    private func seedDefaults() {
        meals = []
        medications = [
            Medication(name: "Vitamin D", dose: "1 capsule", times: [.hm(9, 0)]),
            Medication(name: "Omega-3", dose: "2 softgels", times: [.hm(13, 0)]),
            Medication(name: "Magnesium", dose: "1 tablet", times: [.hm(21, 0)])
        ]
        hydration.consumedML = 900
        save()
    }
}
