import Foundation
import HealthKit

/// Wraps HealthKit access. Provides:
///   • the most recent passive stress reading (from sleep-time HRV samples)
///   • a 12-hour rolling stress series for the trend chart
///   • permission to start workout sessions used by `StressMeasurementSession`
///
/// On the Simulator or before HealthKit grants access, `latestStress()` falls
/// back to a synthesized reading so the UI always looks alive. Real devices use
/// genuine HealthKit samples.
final class HealthManager {
    static let shared = HealthManager()
    let store = HKHealthStore()

    let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
    let restingHRType = HKQuantityType(.restingHeartRate)
    let heartRateType = HKQuantityType(.heartRate)
    let heartbeatSeriesType = HKSeriesType.heartbeat()

    var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Request read + workout-write authorization. Workout share is needed so the
    /// live measurement session can start/stop a workout to elevate HR sampling.
    func requestAuthorization() async -> Bool {
        guard isHealthDataAvailable else { return false }
        let toRead: Set<HKObjectType> = [hrvType, restingHRType, heartRateType, heartbeatSeriesType]
        let toShare: Set<HKSampleType> = [HKObjectType.workoutType()]
        do {
            try await store.requestAuthorization(toShare: toShare, read: toRead)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Passive background updates

    private var hrvObserver: HKObserverQuery?

    /// Wake the app whenever the watch records a new HRV (or resting-HR) sample
    /// so the current reading, the 12-hour chart, and the Smart Stack widget all
    /// stay fresh *without* the user opening the app or tapping "Measure". This
    /// is the mechanism that lets real data accumulate gradually through the day.
    func enablePassiveUpdates(_ handler: @escaping @Sendable () -> Void) {
        guard isHealthDataAvailable, hrvObserver == nil else { return }
        let query = HKObserverQuery(sampleType: hrvType, predicate: nil) { _, completion, _ in
            handler()
            completion()   // tell HealthKit we've handled this background wake-up
        }
        store.execute(query)
        hrvObserver = query
        // Ask the system to deliver new HRV samples in the background.
        store.enableBackgroundDelivery(for: hrvType, frequency: .immediate) { _, _ in }
    }

    // MARK: - Passive reading

    /// Most recent passive stress reading from stored HRV+RHR samples. The
    /// returned reading's `date` is the **HRV sample's own end date**, not
    /// "now" — so callers can detect when this is just a stale sleep sample
    /// (e.g. 8 hours old) and refuse to overwrite a fresher manual measurement.
    func latestStress() async -> StressReading {
        let hrvSample = await mostRecentSample(for: hrvType)
        let rhr = await mostRecentValue(for: restingHRType, unit: HKUnit.count().unitDivided(by: .minute()))

        if let hrvSample {
            let hrv = hrvSample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
            let score = Self.stressScore(hrvSDNN: hrv, restingHR: rhr)
            return StressReading(date: hrvSample.endDate, score: score, hrvSDNN: hrv, restingHR: rhr)
        } else {
            return StressReading(date: Date(), score: Self.simulatedScore(), hrvSDNN: nil, restingHR: rhr)
        }
    }

    // MARK: - 12h trend

    /// Build a 12-hour rolling stress timeline from every HRV sample in the
    /// window. HRV-only by design — heart rate alone isn't a stress signal, so
    /// when HRV is sparse the chart should look empty rather than fake values.
    /// Manual measurements are added on top by `AppStore.refreshStressTimeline`.
    func stressTimeline(hours: Int = 12) async -> [StressPoint] {
        let end = Date()
        let start = end.addingTimeInterval(-Double(hours) * 3600)
        let rhr = await mostRecentValue(for: restingHRType,
                                        unit: HKUnit.count().unitDivided(by: .minute()))

        let hrvSamples = await samples(of: hrvType, from: start, to: end)
        let hrvUnit = HKUnit.secondUnit(with: .milli)
        return hrvSamples.map { s in
            let hrv = s.quantity.doubleValue(for: hrvUnit)
            return StressPoint(date: s.endDate,
                               score: Self.stressScore(hrvSDNN: hrv, restingHR: rhr),
                               source: .hrvSample)
        }
    }

    // MARK: - Scoring

    /// Lower HRV → higher stress. Elevated resting HR nudges the score up.
    static func stressScore(hrvSDNN: Double, restingHR: Double?) -> Int {
        let hrvNorm = clamp((hrvSDNN - 20) / (90 - 20), 0, 1)
        var stress = (1 - hrvNorm) * 100
        if let rhr = restingHR {
            let rhrPenalty = clamp((rhr - 60) / 40, 0, 1) * 18
            stress = stress * 0.82 + rhrPenalty
        }
        return Int(clamp(stress, 0, 100).rounded())
    }

    /// Rough fallback when only mean HR is available.
    static func stressScoreFromHR(_ hr: Double) -> Int {
        let n = clamp((hr - 55) / (110 - 55), 0, 1)
        return Int((n * 100).rounded())
    }

    /// Time-of-day shaped pseudo value used when HealthKit has no data.
    private static func simulatedScore() -> Int {
        let hour = Calendar.current.component(.hour, from: Date())
        let base: Double
        switch hour {
        case 6..<10:  base = 28
        case 10..<14: base = 52
        case 14..<18: base = 60
        case 18..<22: base = 38
        default:      base = 22
        }
        let jitter = Double((Calendar.current.component(.minute, from: Date()) % 17)) - 8
        return Int(clamp(base + jitter, 0, 100))
    }

    // MARK: - Beat-to-beat HRV (used by live measurement)

    /// Pull every heartbeat series sample associated with `workout`, flatten it
    /// into a list of beat times, and turn that into a real SDNN (the same
    /// measure HealthKit uses for `heartRateVariabilitySDNN`).
    func computeHRV(for workout: HKWorkout) async -> Double? {
        let predicate = HKQuery.predicateForObjects(from: workout)
        let series: [HKHeartbeatSeriesSample] = await withCheckedContinuation { c in
            let q = HKSampleQuery(sampleType: heartbeatSeriesType, predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                c.resume(returning: (samples as? [HKHeartbeatSeriesSample]) ?? [])
            }
            store.execute(q)
        }
        var beats: [TimeInterval] = []
        for s in series {
            beats.append(contentsOf: await beatTimes(in: s))
        }
        return Self.sdnnMs(beatTimes: beats)
    }

    private func beatTimes(in series: HKHeartbeatSeriesSample) async -> [TimeInterval] {
        await withCheckedContinuation { continuation in
            var times: [TimeInterval] = []
            let query = HKHeartbeatSeriesQuery(heartbeatSeries: series) { _, t, _, done, _ in
                times.append(t)
                if done { continuation.resume(returning: times) }
            }
            store.execute(query)
        }
    }

    /// SDNN in milliseconds from raw beat timestamps. Filters out implausible
    /// R-R intervals (<300 ms or >2000 ms) so noisy beats don't blow up stdev.
    static func sdnnMs(beatTimes: [TimeInterval]) -> Double? {
        guard beatTimes.count > 2 else { return nil }
        let sorted = beatTimes.sorted()
        var rr: [Double] = []
        for i in 1..<sorted.count {
            let ms = (sorted[i] - sorted[i - 1]) * 1000
            if ms > 300 && ms < 2000 { rr.append(ms) }
        }
        guard rr.count > 1 else { return nil }
        let mean = rr.reduce(0, +) / Double(rr.count)
        let variance = rr.map { pow($0 - mean, 2) }.reduce(0, +) / Double(rr.count - 1)
        return sqrt(variance)
    }

    // MARK: - Queries

    private func mostRecentValue(for type: HKQuantityType, unit: HKUnit) async -> Double? {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func mostRecentSample(for type: HKQuantityType) async -> HKQuantitySample? {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: samples?.first as? HKQuantitySample)
            }
            store.execute(query)
        }
    }

    private func samples(of type: HKQuantityType, from start: Date, to end: Date) async -> [HKQuantitySample] {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }
    }
}

func clamp<T: Comparable>(_ value: T, _ low: T, _ high: T) -> T {
    min(max(value, low), high)
}
