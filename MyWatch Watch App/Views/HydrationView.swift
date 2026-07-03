import SwiftUI

/// Hydration module — two full-screen pages you swipe between horizontally:
///   1. **Today** — the animated fill ring plus quick-add buttons.
///   2. **Reminders** — count-per-day + a shortcut into the schedule editor.
/// Each page fills the face on its own; no vertical scrolling.
struct HydrationView: View {
    @EnvironmentObject var store: AppStore
    @State private var celebrate = false
    @State private var showSchedule = false
    @State private var page: Int

    init(initialPage: Int = 0) { _page = State(initialValue: initialPage) }

    private var h: HydrationState { store.hydration }

    var body: some View {
        TabView(selection: $page) {
            todayPage.tag(0)
            remindersPage.tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Theme.bg)
        .sheet(isPresented: $showSchedule) {
            HydrationScheduleView()
                .environmentObject(store)
        }
    }

    // MARK: Page 1 — today's intake

    private var todayPage: some View {
        ModuleScreen(title: "Hydration", symbol: "drop.fill",
                     gradient: Theme.waterGradient, pageCount: 2, pageIndex: page) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                RingView(progress: h.progress, gradient: Theme.waterGradient, lineWidth: Metrics.x(13)) {
                    VStack(spacing: 0) {
                        Text("\(h.consumedML)")
                            .font(.system(size: Metrics.x(28), weight: .semibold, design: .rounded))
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text("/ \(h.goalML) ml")
                            .font(.system(size: Metrics.x(11), weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(.horizontal, Metrics.x(6))
                }
                .frame(width: Metrics.ringSize, height: Metrics.ringSize)
                .overlay(alignment: .top) {
                    if h.progress >= 1 {
                        Text("🎉 Goal reached!")
                            .font(.caption2).bold()
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Theme.waterGradient, in: Capsule())
                            .foregroundStyle(.black)
                            .offset(y: -6)
                            .scaleEffect(celebrate ? 1.0 : 0.6)
                    }
                }

                // Fixed safe gap so the ring's progress arc never touches the
                // quick-add buttons (fixes the overlap on rapid tapping).
                Spacer(minLength: Metrics.x(10))

                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        PillButton(title: "200", systemImage: "drop",
                                   gradient: Theme.waterGradient, compact: true) { add(200) }
                        PillButton(title: "350", systemImage: "cup.and.saucer",
                                   gradient: Theme.waterGradient, compact: true) { add(350) }
                    }
                    HStack(spacing: 6) {
                        PillButton(title: "500", systemImage: "waterbottle",
                                   gradient: Theme.waterGradient, compact: true) { add(500) }
                        PillButton(title: "Undo", systemImage: "arrow.uturn.backward",
                                   gradient: LinearGradient(colors: [.gray, .gray.opacity(0.7)],
                                                            startPoint: .top, endPoint: .bottom),
                                   compact: true) { store.addWater(-350) }
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Page 2 — reminders

    private var remindersPage: some View {
        ModuleScreen(title: "Reminders", symbol: "bell.badge.fill",
                     gradient: Theme.waterGradient, pageCount: 2, pageIndex: page) {
            VStack(spacing: 12) {
                Spacer(minLength: 0)

                VStack(spacing: 2) {
                    Text("\(store.hydrationRemindersPerDay)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .foregroundStyle(Theme.waterGradient)
                    Text("reminders / day")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Stepper("", value: Binding(
                    get: { store.hydrationRemindersPerDay },
                    set: { store.setHydrationReminders($0) }), in: 0...16)
                    .labelsHidden()

                Spacer(minLength: 0)

                if store.hydrationRemindersPerDay > 0 {
                    Button {
                        showSchedule = true
                    } label: {
                        Label("Edit times", systemImage: "clock")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity)
                            .background(.white.opacity(0.10), in: Capsule())
                            .overlay(Capsule().stroke(Theme.waterGradient.asColor.opacity(0.35), lineWidth: 0.8))
                    }
                    .buttonStyle(PressableStyle())
                } else {
                    Text("Turn on reminders to schedule sip times.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private func add(_ ml: Int) {
        store.addWater(ml)
        if store.hydration.progress >= 1 {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) { celebrate = true }
        }
    }
}

// MARK: - Schedule editor

/// Per-reminder time editor. Each row is a wheel-style watch DatePicker; saving
/// reschedules the daily local notifications so the watch actually fires at the
/// chosen times. Includes a "Test wake + buzz in 5s" affordance that fires the
/// real mechanism (time-sensitive notification + wake-the-app session) on demand.
struct HydrationScheduleView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var nextFire: Date?

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Hydration schedule")
                    .font(.headline)

                if let next = nextFire {
                    Text("Next at \(next.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                ForEach(Array(store.hydration.reminderTimes.enumerated()), id: \.offset) { idx, time in
                    HydrationTimeRow(index: idx, time: time)
                }

                BurstPatternEditor { rescheduleAndRefresh() }

                Button {
                    dismiss()
                    NotificationManager.shared.fireTestReminder(in: 5)
                } label: {
                    Label("Test reminder in 5s", systemImage: "bell.and.waves.left.and.right.fill")
                        .font(.caption2).fontWeight(.semibold)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Theme.waterGradient, in: Capsule())
                        .foregroundStyle(.black)
                }
                .buttonStyle(PressableStyle())

                Text("Closes the sheet, then in 5s sends the configured burst. Tap any one to wake the app and play the full reminder.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button { dismiss() } label: {
                    Text("Done")
                        .font(.caption2).fontWeight(.semibold)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(.white.opacity(0.14), in: Capsule())
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.horizontal, 6)
        }
        .task { nextFire = await NotificationManager.shared.nextHydrationFireDate() }
    }

    /// Re-emit the daily-repeating burst with the latest burst settings, then
    /// refresh the "Next at …" preview so the user sees the change land.
    private func rescheduleAndRefresh() {
        NotificationManager.shared.scheduleHydrationReminders(times: store.hydration.reminderTimes)
        Task { nextFire = await NotificationManager.shared.nextHydrationFireDate() }
    }
}

/// One editable row in the hydration schedule list — opens an inline time
/// picker that writes back through `AppStore.setHydrationReminderTime`.
struct HydrationTimeRow: View {
    @EnvironmentObject var store: AppStore
    var index: Int
    var time: DateComponents

    @State private var editing = false

    private var date: Date {
        Calendar.current.date(bySettingHour: time.hour ?? 9,
                              minute: time.minute ?? 0,
                              second: 0, of: Date()) ?? Date()
    }

    var body: some View {
        Button {
            editing = true
        } label: {
            HStack {
                Image(systemName: "drop.fill").foregroundStyle(Theme.waterGradient.asColor)
                Text("#\(index + 1)").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(time.hmLabel)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .cardBackground(cornerRadius: 12)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $editing) {
            TimePickerSheet(initial: date) { picked in
                let cal = Calendar.current
                let comps = cal.dateComponents([.hour, .minute], from: picked)
                store.setHydrationReminderTime(at: index, to: comps)
                editing = false
            }
        }
    }
}

/// Two sliders that drive the actual wrist haptics: how many notifications go
/// out per reminder time, and how many seconds between them. Changes write
/// straight to UserDefaults; `onChange` re-schedules the daily-repeating burst
/// so the next reminder uses the new pattern.
struct BurstPatternEditor: View {
    var onChange: () -> Void

    @State private var count: Int = NotificationManager.shared.burstCount
    @State private var spacing: Int = NotificationManager.shared.burstSpacingSec

    private var totalSeconds: Int { max(0, (count - 1) * spacing) }

    var body: some View {
        let countLo = Double(NotificationManager.burstCountRange.lowerBound)
        let countHi = Double(NotificationManager.burstCountRange.upperBound)
        let spacingLo = Double(NotificationManager.burstSpacingRange.lowerBound)
        let spacingHi = Double(NotificationManager.burstSpacingRange.upperBound)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Reminder burst")
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(Theme.waterGradient.asColor)

            sliderRow(
                label: "通知条数",
                value: "\(count) 条",
                binding: Binding(
                    get: { Double(count) },
                    set: { newValue in
                        let clamped = clamp(Int(newValue.rounded()),
                                            NotificationManager.burstCountRange)
                        guard clamped != count else { return }
                        count = clamped
                        UserDefaults.standard.set(clamped,
                                                  forKey: NotificationManager.burstCountKey)
                        onChange()
                    }),
                range: countLo...countHi,
                step: 1)

            sliderRow(
                label: "条间间隔",
                value: "\(spacing) s",
                binding: Binding(
                    get: { Double(spacing) },
                    set: { newValue in
                        let clamped = clamp(Int(newValue.rounded()),
                                            NotificationManager.burstSpacingRange)
                        guard clamped != spacing else { return }
                        spacing = clamped
                        UserDefaults.standard.set(clamped,
                                                  forKey: NotificationManager.burstSpacingKey)
                        onChange()
                    }),
                range: spacingLo...spacingHi,
                step: 1)

            Text("到点连发 \(count) 条通知，每条间隔 \(spacing) s（共 ~\(totalSeconds) s 震动）")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .cardBackground()
    }

    private func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    @ViewBuilder
    private func sliderRow(label: String, value: String,
                           binding: Binding<Double>,
                           range: ClosedRange<Double>, step: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Text(value).font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            Slider(value: binding, in: range, step: step)
                .tint(Theme.waterGradient.asColor)
        }
    }
}

/// Tiny modal that wraps a wheel-style time picker — watchOS DatePicker uses
/// the crown for hour/minute selection.
struct TimePickerSheet: View {
    var initial: Date
    var onPick: (Date) -> Void
    @State private var value: Date

    init(initial: Date, onPick: @escaping (Date) -> Void) {
        self.initial = initial
        self.onPick = onPick
        _value = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 8) {
            DatePicker("", selection: $value, displayedComponents: .hourAndMinute)
                .labelsHidden()
            Button("Save") { onPick(value) }
                .buttonStyle(.borderedProminent)
                .tint(Theme.waterGradient.asColor)
        }
        .padding(.horizontal, 6)
    }
}

// MARK: - Full-screen reminder alert

/// The screen that takes over when a hydration reminder fires through the
/// extended-runtime session: a glass filling with water, a clear prompt, and two
/// big actions. Shown over everything while `HydrationReminderSession.isAlerting`.
struct HydrationAlertOverlay: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var session = HydrationReminderSession.shared

    @State private var fill: CGFloat = 0.28
    @State private var pulse = false

    var body: some View {
        ZStack {
            // Opaque takeover so it reads as a dedicated wake-up screen, washed
            // with the water gradient toward the bottom.
            Theme.bg.ignoresSafeArea()
            LinearGradient(colors: [.clear, Color(red: 0.20, green: 0.45, blue: 0.95).opacity(0.35)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                FillingGlass(fill: fill)
                    .frame(width: 64, height: 78)
                    .scaleEffect(pulse ? 1.06 : 0.94)

                Text("💧 Time to hydrate")
                    .font(.headline)
                Text("Take a few sips now.")
                    .font(.caption2).foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button {
                        store.addWater(250)
                        session.dismissAlert()
                    } label: {
                        Label("Drank", systemImage: "checkmark")
                            .font(.caption2).fontWeight(.semibold)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity)
                            .background(Theme.waterGradient, in: Capsule())
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(PressableStyle())

                    Button {
                        session.snooze(minutes: 10)
                    } label: {
                        Label("10m", systemImage: "clock")
                            .font(.caption2).fontWeight(.semibold)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity)
                            .background(.white.opacity(0.16), in: Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal, 10)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                fill = 1
            }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

/// A simple glass outline that fills bottom-up with the water gradient — the
/// little animation that plays while the reminder is buzzing.
private struct FillingGlass: View {
    var fill: CGFloat   // 0…1

    var body: some View {
        GeometryReader { geo in
            let shape = TrapezoidGlass()
            ZStack(alignment: .bottom) {
                shape.fill(.white.opacity(0.10))
                Theme.waterGradient
                    .frame(height: geo.size.height * fill)
                    .mask(alignment: .bottom) { shape }
                shape.stroke(.white.opacity(0.7), lineWidth: 2.5)
            }
        }
    }
}

/// Tumbler outline — slightly narrower at the base than the rim.
private struct TrapezoidGlass: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.width * 0.12
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

#Preview {
    HydrationView().environmentObject(AppStore())
}
