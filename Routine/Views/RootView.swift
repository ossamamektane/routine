import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PrefKey.welcomeDone) private var welcomeDone = false

    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.selectedTab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(AppTab.today)
                .badge(store.agenda.actionableCount)
            RoutinesView()
                .tabItem { Label("Tasks", systemImage: "checklist") }
                .tag(AppTab.routines)
            MoneyView()
                .tabItem { Label("Bills", systemImage: "creditcard") }
                .tag(AppTab.money)
        }
        // Always show the iPhone status bar (time, Wi-Fi, battery).
        .statusBarHidden(false)
        .sheet(isPresented: Binding(get: { !welcomeDone }, set: { shown in if !shown { welcomeDone = true } })) {
            WelcomeView { welcomeDone = true }
                .interactiveDismissDisabled()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.becameActive() }
        }
    }
}
