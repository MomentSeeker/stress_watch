import Foundation
import SwiftUI
import WatchKit

/// The "wake the app + buzz hard + show an animation" layer that sits on top of
/// the plain local notification.
///
/// Mechanism: a `WKExtendedRuntimeSession` of the self-care kind. We schedule it
/// for the next reminder time; when it fires, watchOS brings MyWatch to the
/// foreground and calls `extendedRuntimeSessionDidStart`. That callback is our
/// stage — we run a sustained custom haptic pattern and flip `isAlerting` so the
/// UI shows the full-screen hydration alert. A plain notification can do neither.
/// When the user dismisses, we chain-schedule the next session.
@MainActor
final class HydrationReminderSession: NSObject, ObservableObject {
    static let shared = HydrationReminderSession()

    /// When true, the app shows the full-screen "time to hydrate" alert overlay.
    @Published var isAlerting = false

    /// Human-readable trace of the last extended-runtime-session event, persisted
    /// so it survives relaunch — lets us see on the wrist whether a scheduled
    /// wake actually fired or was rejected. Shown on the hydration schedule sheet.
    @Published var lastSessionLog: String =
        UserDefaults.standard.string(forKey: "hydration.session.log") ?? "—"

    private var session: WKExtendedRuntimeSession?
    private var hapticTimer: Timer?
    private var hapticsRemaining = 0
    private var testTimer: Timer?

    private func note(_ message: String) {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        let line = "\(f.string(from: Date())) · \(message)"
        lastSessionLog = line
        UserDefaults.standard.set(line, forKey: "hydration.session.log")
        NSLog("[MyWatch] \(message)")
    }

    // MARK: - In-app buzz pattern (fixed)
    //
    // The wake-and-buzz overlay only runs when the user taps a notification, so
    // we no longer expose these as user-tunable knobs. They're tuned to a sane
    // "hard to miss but not obnoxious" default; the user-facing reminder
    // intensity is now controlled by `NotificationManager.burstCount` /
    // `burstSpacingSec`, which actually drives the wrist haptics.

    private let tapsPerBuzz: Int = 2
    private let buzzInterval: TimeInterval = 1.5
    private let buzzCount: Int = 5
    private let tapSpacing: TimeInterval = 0.18

    override init() {
        super.init()
    }

    // MARK: - Scheduling

    /// Schedule the wake-and-buzz alert for a future date. Replaces any session
    /// already scheduled. No-ops for a past date (a session can't start in the
    /// past). Must be called while the app is alive — the notification is the
    /// fallback for when it isn't.
    func schedule(at date: Date) {
        guard date > Date() else { return }
        invalidateSession()
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        s.start(at: date)
        session = s
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        note("scheduled for \(f.string(from: date))")
    }

    /// Start a session right now. Unlike `schedule(at:)`, an immediate session
    /// needs no scheduling permission, so it works everywhere — including the
    /// simulator. The chain uses `schedule(at:)` for real future reminders; this
    /// is the "fire it now" path used by the test button and snooze.
    func startNow() {
        invalidateSession()
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        s.start()
        session = s
        note("immediate start()")
    }

    /// Fire the alert `seconds` from now — used by the in-app test button so the
    /// whole mechanism (wake → animation → sustained buzzing) can be verified on
    /// demand. Uses a timer + immediate session so it's reliable in the simulator
    /// too (scheduled-ahead sessions are a device-only capability).
    func scheduleTest(in seconds: TimeInterval = 5) {
        testTimer?.invalidate()
        testTimer = Timer.scheduledTimer(withTimeInterval: max(1, seconds), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.startNow() }
        }
    }

    // MARK: - Alert lifecycle

    /// User tapped "I drank it" or "Snooze", or the buzzing ran its course.
    func dismissAlert() {
        stopHaptics()
        isAlerting = false
        invalidateSession()
    }

    /// Push the next alert out by `minutes` and clear the current one.
    func snooze(minutes: Int = 10) {
        let next = Date().addingTimeInterval(Double(minutes) * 60)
        dismissAlert()
        schedule(at: next)
    }

    // MARK: - Sustained haptics

    /// Once the session starts, buzz on a steady cadence for ~30s so the reminder
    /// is genuinely hard to miss — the whole point of the feature.
    private func beginAlert() {
        isAlerting = true
        note("WOKE — alert started ✓")
        playBuzz()
        hapticsRemaining = max(0, buzzCount - 1)
        hapticTimer?.invalidate()
        guard hapticsRemaining > 0 else { return }
        hapticTimer = Timer.scheduledTimer(withTimeInterval: max(0.2, buzzInterval), repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.hapticsRemaining > 0 else {
                    self?.stopHaptics()
                    return
                }
                self.playBuzz()
                self.hapticsRemaining -= 1
            }
        }
    }

    /// One "buzz" = `tapsPerBuzz` quick `.notification` taps spaced `tapSpacing` apart.
    private func playBuzz() {
        let taps = max(1, tapsPerBuzz)
        for i in 0..<taps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * tapSpacing) {
                WKInterfaceDevice.current().play(.notification)
            }
        }
    }

    private func stopHaptics() {
        hapticTimer?.invalidate()
        hapticTimer = nil
        hapticsRemaining = 0
    }

    private func invalidateSession() {
        session?.invalidate()
        session = nil
    }
}

// MARK: - WKExtendedRuntimeSessionDelegate

extension HydrationReminderSession: WKExtendedRuntimeSessionDelegate {
    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in self.beginAlert() }
    }

    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in self.stopHaptics() }
    }

    nonisolated func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
                                            didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                            error: Error?) {
        Task { @MainActor in
            // Only surface *failures* — a normal user-dismissed session also
            // invalidates, and we don't want that to overwrite "WOKE ✓".
            if let error {
                self.note("FAILED: \(error.localizedDescription)")
            } else if reason != .none {
                self.note("ended (reason \(reason.rawValue))")
            }
            self.stopHaptics()
            if self.session === extendedRuntimeSession { self.session = nil }
        }
    }
}
