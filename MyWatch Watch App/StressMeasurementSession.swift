import Foundation
import HealthKit
import Combine
import WatchKit

/// Runs a real 60-second on-demand stress measurement.
///
/// Flow:
///   1. Start a `.mindAndBody` `HKWorkoutSession` (elevates HR sampling rate
///      and makes the watch record beat-to-beat data).
///   2. Stream live HR via `HKAnchoredObjectQuery` for the countdown UI.
///   3. After 60 s, save the workout (required so we can query its
///      `HKHeartbeatSeriesSample`s), pull every beat time, compute a real
///      **SDNN (HRV)** from the R-R intervals, then delete the workout so the
///      user's Health app stays clean.
///   4. Final score is `HealthManager.stressScore(hrvSDNN:restingHR:)` — same
///      function used for the 12-hour timeline, so all stress numbers in the
///      app are derived from HRV.
///   5. If no heartbeat series was recorded (e.g. simulator), gracefully
///      degrade to a heart-rate-only estimate so the UI never gets stuck.
@MainActor
final class StressMeasurementSession: ObservableObject {
    enum Phase: Equatable { case idle, measuring, finished }

    @Published var phase: Phase = .idle
    @Published var elapsed: TimeInterval = 0
    @Published var currentHR: Double?
    @Published var result: StressReading?

    let duration: TimeInterval = 60

    private let healthManager = HealthManager.shared
    private var healthStore: HKHealthStore { healthManager.store }
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var query: HKAnchoredObjectQuery?
    private var hrSamples: [Double] = []
    private var startDate: Date?
    private var ticker: Task<Void, Never>?

    /// Belt-and-braces companion to the HKWorkoutSession. The workout session is
    /// what we *want* to keep the app alive (it also gives us beat-to-beat data),
    /// but if it fails to start for any reason — denied workout-write permission,
    /// `.mindAndBody` not getting always-on treatment on this watch, etc. — the
    /// app gets suspended ~15 s after the wrist drops and the timer freezes
    /// until the next tap. A `.mindfulSession` extended-runtime session is
    /// documented to keep the screen on and the app running for up to an hour,
    /// and only requires the `self-care` background mode we already have.
    private var runtimeSession: WKExtendedRuntimeSession?
    private var runtimeDelegate: RuntimeDelegate?

    var progress: Double {
        guard duration > 0 else { return 0 }
        return clamp(elapsed / duration, 0, 1)
    }

    func start() {
        guard phase != .measuring else { return }
        phase = .measuring
        elapsed = 0
        currentHR = nil
        result = nil
        hrSamples.removeAll()

        let start = Date()
        startDate = start

        startRuntimeSession()
        startWorkoutSession(at: start)
        startHRQuery(from: start)
        startTicker()
    }

    func cancel() {
        guard phase == .measuring else { return }
        tearDownQuery()
        endRuntimeSession()
        Task { await discardWorkout() }
        phase = .idle
    }

    // MARK: - Extended runtime session (keeps screen + app alive)

    private func startRuntimeSession() {
        let s = WKExtendedRuntimeSession()
        let delegate = RuntimeDelegate()
        s.delegate = delegate
        runtimeDelegate = delegate
        runtimeSession = s
        s.start()   // immediate start — runs from now for up to 1 hour
        NSLog("[MyWatch] stress runtime session started (state=\(s.state.rawValue))")
    }

    private func endRuntimeSession() {
        if let s = runtimeSession, s.state == .running {
            s.invalidate()
            NSLog("[MyWatch] stress runtime session invalidated")
        }
        runtimeSession = nil
        runtimeDelegate = nil
    }

    // MARK: - Workout session

    private func startWorkoutSession(at start: Date) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .mindAndBody
        config.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore,
                                                         workoutConfiguration: config)
            session.startActivity(with: start)
            builder.beginCollection(withStart: start) { _, _ in }
            self.session = session
            self.builder = builder
            NSLog("[MyWatch] stress workout session started")
        } catch {
            // Live HR query + the runtime session will still keep the timer
            // running; we just won't get beat-to-beat HRV.
            NSLog("[MyWatch] stress workout session FAILED to start: \(error.localizedDescription)")
        }
    }

    // MARK: - Live HR

    private func startHRQuery(from start: Date) {
        let type = healthManager.heartRateType
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil,
                                                    options: .strictStartDate)
        let handler: (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void = { [weak self] _, samples, _, _, _ in
            self?.ingest(samples)
        }
        let query = HKAnchoredObjectQuery(type: type, predicate: predicate,
                                          anchor: nil, limit: HKObjectQueryNoLimit,
                                          resultsHandler: handler)
        query.updateHandler = handler
        healthStore.execute(query)
        self.query = query
    }

    private nonisolated func ingest(_ samples: [HKSample]?) {
        guard let quantities = samples as? [HKQuantitySample], !quantities.isEmpty else { return }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let values = quantities.map { $0.quantity.doubleValue(for: unit) }
        Task { @MainActor in
            self.hrSamples.append(contentsOf: values)
            if let last = values.last { self.currentHR = last }
        }
    }

    // MARK: - Timer

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self else { return }
                await MainActor.run {
                    guard self.phase == .measuring, let s = self.startDate else { return }
                    self.elapsed = Date().timeIntervalSince(s)
                    if self.elapsed >= self.duration {
                        Task { await self.finish() }
                    }
                }
            }
        }
    }

    // MARK: - Finish

    @discardableResult
    func finish() async -> StressReading {
        guard phase == .measuring else { return result ?? StressReading(date: Date(), score: 0, hrvSDNN: nil, restingHR: nil) }
        tearDownQuery()
        endRuntimeSession()
        let samples = hrSamples
        let meanHR: Double? = samples.isEmpty ? nil : samples.reduce(0, +) / Double(samples.count)

        // End + save the workout. We need the saved workout in order to query
        // its associated heartbeat-series samples (HRV source). Cleaned up
        // immediately after extraction so Health stays tidy.
        let workout = await endAndSaveWorkout()
        let hrv: Double? = await {
            guard let workout else { return nil }
            return await healthManager.computeHRV(for: workout)
        }()
        if let workout {
            try? await healthStore.delete(workout)
        }

        let reading: StressReading
        if let hrv {
            let score = HealthManager.stressScore(hrvSDNN: hrv, restingHR: meanHR)
            reading = StressReading(date: Date(), score: score, hrvSDNN: hrv, restingHR: meanHR)
        } else if let meanHR {
            // No beat-to-beat data (simulator, or too short a window) — be honest
            // and use a HR-only estimate. The card will show "HRV: —".
            let stdev = Self.stdev(samples)
            let score = Self.scoreFromHRStats(meanHR: meanHR, hrStdev: stdev)
            reading = StressReading(date: Date(), score: score, hrvSDNN: nil, restingHR: meanHR)
        } else {
            reading = await healthManager.latestStress()
        }

        result = reading
        phase = .finished
        return reading
    }

    private func endAndSaveWorkout() async -> HKWorkout? {
        guard let session, let builder else { return nil }
        let end = Date()
        session.end()
        return await withCheckedContinuation { continuation in
            builder.endCollection(withEnd: end) { _, _ in
                builder.finishWorkout { workout, _ in
                    continuation.resume(returning: workout)
                }
            }
        }
    }

    private func discardWorkout() async {
        guard let session, let builder else { return }
        session.end()
        builder.endCollection(withEnd: Date()) { _, _ in builder.discardWorkout() }
        self.session = nil
        self.builder = nil
    }

    private func tearDownQuery() {
        ticker?.cancel(); ticker = nil
        if let q = query {
            healthStore.stop(q)
            query = nil
        }
    }

    // MARK: - HR-only fallback (simulator / no beat data)

    private static func stdev(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let v = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count - 1)
        return sqrt(v)
    }

    static func scoreFromHRStats(meanHR: Double, hrStdev: Double) -> Int {
        var stress = 50.0
        stress += clamp((meanHR - 70) / 30, -1, 1) * 28
        let varNorm = clamp((hrStdev - 1) / (8 - 1), 0, 1)
        stress += (1 - 2 * varNorm) * 12
        return Int(clamp(stress, 0, 100).rounded())
    }
}

/// Minimal delegate for the measurement's extended-runtime session — we just
/// want the lifecycle callbacks in the log so a future "still freezing" report
/// can be triaged from console output. The session is driven by start/invalidate
/// on `StressMeasurementSession`, so the delegate doesn't need to do any work.
private final class RuntimeDelegate: NSObject, WKExtendedRuntimeSessionDelegate {
    func extendedRuntimeSessionDidStart(_ s: WKExtendedRuntimeSession) {
        NSLog("[MyWatch] runtime session did start")
    }
    func extendedRuntimeSessionWillExpire(_ s: WKExtendedRuntimeSession) {
        NSLog("[MyWatch] runtime session WILL expire (1h cap reached)")
    }
    func extendedRuntimeSession(_ s: WKExtendedRuntimeSession,
                                didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                error: Error?) {
        NSLog("[MyWatch] runtime session invalidated reason=\(reason.rawValue) err=\(error?.localizedDescription ?? "nil")")
    }
}
