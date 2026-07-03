import SwiftUI

/// Root of the app: a two-dimensional page navigation.
///
/// - **Vertical swipe** moves between wellness *modules* (Stress → Hydration →
///   Medication) — the top-level dashboard rhythm.
/// - **Horizontal swipe** moves between the *screens inside a module*. Every
///   screen is a complete, self-contained function that fills exactly one watch
///   face — no scrolling. One screen, one job; a swipe crossfades to the next.
struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var reminderSession = HydrationReminderSession.shared
    @State private var module = 0

    #if DEBUG
    /// Debug launch route "-Screen m.p": jump straight to module m, inner page p
    /// (used for capturing per-screen screenshots).
    private static var route: (module: Int, page: Int)? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-Screen"), i + 1 < args.count else { return nil }
        let parts = args[i + 1].split(separator: ".").compactMap { Int($0) }
        guard let m = parts.first else { return nil }
        return (m, parts.count > 1 ? parts[1] : 0)
    }
    #endif

    var body: some View {
        Group {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-DemoWidget") {
                WidgetPreviewView(snapshot: WellnessSnapshot(
                    stressScore: 36, stressLevel: "Balanced", stressDate: Date(),
                    hrvSDNN: 47, hydrationConsumed: 840, hydrationGoal: 2000,
                    nextHydrationReminder: Calendar.current.date(bySettingHour: 14, minute: 30, second: 0, of: Date()),
                    updatedAt: Date()))
            } else {
                normalTabs
            }
            #else
            normalTabs
            #endif
        }
    }

    private var normalTabs: some View {
        #if DEBUG
        let route = Self.route
        #endif
        return TabView(selection: $module) {
            #if DEBUG
            StressView(initialPage: route?.module == 0 ? (route?.page ?? 0) : 0).tag(0)
            HydrationView(initialPage: route?.module == 1 ? (route?.page ?? 0) : 0).tag(1)
            MedicationView(initialPage: route?.module == 2 ? (route?.page ?? 0) : 0).tag(2)
            #else
            StressView().tag(0)
            HydrationView().tag(1)
            MedicationView().tag(2)
            #endif
        }
        .tabViewStyle(.verticalPage)
        .background(Theme.bg)
        .overlay {
            if reminderSession.isAlerting {
                HydrationAlertOverlay()
                    .environmentObject(store)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: reminderSession.isAlerting)
        #if DEBUG
        .onAppear { if let r = Self.route { module = r.module } }
        #endif
    }
}

#Preview {
    ContentView().environmentObject(AppStore())
}
