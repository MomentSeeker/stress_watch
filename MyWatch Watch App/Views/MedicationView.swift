import SwiftUI

/// Medication module — two full-screen pages you swipe between horizontally:
///   1. **Today** — an adherence summary plus one-tap "Taken" for each med.
///   2. **Manage** — reminder burst settings and add/remove medications.
/// The Today page fills the face; a short med list needs no scrolling, and a
/// long one stays contained on its own page.
struct MedicationView: View {
    @EnvironmentObject var store: AppStore
    @State private var showingAdd = false
    @State private var showingReminderSettings = false
    @State private var page: Int

    init(initialPage: Int = 0) { _page = State(initialValue: initialPage) }

    private var takenCount: Int { store.medications.filter { $0.takenToday() }.count }
    private var totalCount: Int { store.medications.count }

    var body: some View {
        TabView(selection: $page) {
            todayPage.tag(0)
            managePage.tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Theme.bg)
        .sheet(isPresented: $showingAdd) {
            AddMedicationView()
        }
        .sheet(isPresented: $showingReminderSettings) {
            MedicationReminderSettingsView()
                .environmentObject(store)
        }
    }

    // MARK: Page 1 — today's doses

    private var todayPage: some View {
        ModuleScreen(title: "Medication", symbol: "pills.fill",
                     gradient: Theme.medGradient, pageCount: 2, pageIndex: page) {
            if store.medications.isEmpty {
                VStack(spacing: 10) {
                    Spacer(minLength: 0)
                    Image(systemName: "pills")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Theme.medGradient)
                    Text("No medications yet")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Swipe left to add one")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 6) {
                    // Adherence header
                    HStack(spacing: 6) {
                        Text("\(takenCount)/\(totalCount)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.medGradient)
                        Text("taken today")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        if takenCount == totalCount {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(Color(red: 0.45, green: 0.85, blue: 0.5))
                        }
                    }

                    // A plain VStack (not a ScrollView) so watchOS keeps the
                    // compact clock bar and the header stays pinned right under
                    // the clock — identical to the Stress/Hydration screens. A
                    // short med list fits the face; overflow is handled on the
                    // Manage page rather than by making this page scroll.
                    VStack(spacing: 5) {
                        ForEach(store.medications) { med in
                            MedicationRow(med: med)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        }
    }

    // MARK: Page 2 — manage

    private var managePage: some View {
        ModuleScreen(title: "Manage", symbol: "slider.horizontal.3",
                     gradient: Theme.medGradient, pageCount: 2, pageIndex: page) {
            VStack(spacing: 12) {
                Spacer(minLength: 0)

                Button {
                    showingReminderSettings = true
                } label: {
                    HStack {
                        Image(systemName: "bell.and.waves.left.and.right.fill")
                            .foregroundStyle(Theme.medGradient.asColor)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Reminder burst")
                                .font(.caption).fontWeight(.semibold)
                            Text("\(NotificationManager.shared.medicationBurstCount) alerts · \(NotificationManager.shared.medicationBurstSpacingSec)s apart")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .cardBackground()
                }
                .buttonStyle(.plain)

                Button {
                    showingAdd = true
                } label: {
                    Label("Add medication", systemImage: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Theme.medGradient, in: Capsule())
                        .foregroundStyle(.black)
                }
                .buttonStyle(PressableStyle())

                Spacer(minLength: 0)

                Text("\(totalCount) medication\(totalCount == 1 ? "" : "s") tracked")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}

private struct MedicationRow: View {
    @EnvironmentObject var store: AppStore
    var med: Medication

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(med.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text("\(med.dose) · \(med.times.map(\.hmLabel).joined(separator: " · "))")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 4)
            Button {
                store.logMedicationTaken(med)
            } label: {
                Image(systemName: med.takenToday() ? "checkmark.seal.fill" : "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 32, height: 26)
                    .background(med.takenToday()
                                ? AnyShapeStyle(Color.white.opacity(0.12))
                                : AnyShapeStyle(Theme.medGradient),
                                in: Capsule())
                    .foregroundStyle(med.takenToday() ? Color(red: 0.55, green: 0.9, blue: 0.6) : .black)
            }
            .buttonStyle(PressableStyle())

            Button(role: .destructive) {
                store.removeMedication(med)
            } label: {
                Image(systemName: "trash").font(.system(size: 10))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .background(Color.white.opacity(0.08), in: Circle())
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .cardBackground()
    }
}

/// Simple form to create a medication with one daily reminder time.
private struct AddMedicationView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var dose = "1 pill"
    @State private var time = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                TextField("Name", text: $name)
                    .padding(8).cardBackground()
                TextField("Dose", text: $dose)
                    .padding(8).cardBackground()
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .padding(8).cardBackground()

                Button("Save") {
                    let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
                    let med = Medication(name: name.isEmpty ? "Medication" : name,
                                         dose: dose, times: [comps])
                    store.addMedication(med)
                    dismiss()
                }
                .tint(Color(red: 1.0, green: 0.5, blue: 0.45))
                .disabled(name.isEmpty)
            }
            .padding(.horizontal, 6)
        }
        .background(Theme.bg)
    }
}

private struct MedicationReminderSettingsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("Medication reminders")
                    .font(.headline)

                MedicationBurstPatternEditor {
                    store.rescheduleMedicationReminders()
                }

                Button {
                    dismiss()
                    NotificationManager.shared.fireTestMedicationReminder(in: 5)
                } label: {
                    Label("Test reminder in 5s", systemImage: "bell.and.waves.left.and.right.fill")
                        .font(.caption2).fontWeight(.semibold)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Theme.medGradient, in: Capsule())
                        .foregroundStyle(.black)
                }
                .buttonStyle(PressableStyle())

                Text("Applies to every medication time. At each time, MyWatch sends the configured burst.")
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
        .background(Theme.bg)
    }
}

private struct MedicationBurstPatternEditor: View {
    var onChange: () -> Void

    @State private var count: Int = NotificationManager.shared.medicationBurstCount
    @State private var spacing: Int = NotificationManager.shared.medicationBurstSpacingSec

    private var totalSeconds: Int { max(0, (count - 1) * spacing) }

    var body: some View {
        let countLo = Double(NotificationManager.burstCountRange.lowerBound)
        let countHi = Double(NotificationManager.burstCountRange.upperBound)
        let spacingLo = Double(NotificationManager.burstSpacingRange.lowerBound)
        let spacingHi = Double(NotificationManager.burstSpacingRange.upperBound)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Reminder burst")
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(Theme.medGradient.asColor)

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
                                                  forKey: NotificationManager.medicationBurstCountKey)
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
                                                  forKey: NotificationManager.medicationBurstSpacingKey)
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
                .tint(Theme.medGradient.asColor)
        }
    }
}

#Preview {
    MedicationView().environmentObject(AppStore())
}
