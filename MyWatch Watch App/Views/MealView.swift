import SwiftUI

/// Regular-eating coach: each meal has a scheduled reminder you can toggle, and a
/// one-tap log so you can see what you've eaten today and keep a steady rhythm.
struct MealView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ModuleHeader(title: "Meals", symbol: "fork.knife",
                             gradient: Theme.mealGradient)

                ForEach(store.meals) { meal in
                    MealRow(meal: meal)
                }

                Text("Steady meal times help keep energy and stress balanced.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 6)
        }
        .background(Theme.bg)
    }
}

private struct MealRow: View {
    @EnvironmentObject var store: AppStore
    var meal: MealReminder

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(meal.name).font(.headline)
                    Text(meal.time.hmLabel).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { meal.enabled },
                    set: { _ in store.toggleMeal(meal) }))
                    .labelsHidden()
                    .tint(Color(red: 0.4, green: 0.8, blue: 0.5))
            }

            PillButton(title: meal.loggedToday() ? "Eaten ✓" : "Log meal",
                       systemImage: meal.loggedToday() ? "checkmark" : "fork.knife",
                       gradient: Theme.mealGradient) {
                store.logMeal(meal)
            }
        }
        .padding(10)
        .cardBackground()
        .opacity(meal.enabled ? 1 : 0.55)
    }
}

#Preview {
    MealView().environmentObject(AppStore())
}
