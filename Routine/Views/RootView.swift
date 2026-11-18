import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PrefKey.welcomeDone) private var welcomeDone = false
    @AppStorage(PrefKey.appearance) private var appearance: Appearance = .system

    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.selectedTab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(AppTab.today)
                // Only what's blue ("Now", a bill due today) or red (late) on Today.
                .badge(store.agenda.attentionCount(now: store.clock.now, today: store.clock.day))
            RoutinesView()
                .tabItem { Label("Tasks", systemImage: "checklist") }
                .tag(AppTab.routines)
            MoneyView()
                .tabItem { Label("Bills", systemImage: "creditcard") }
                .tag(AppTab.money)
        }
        // Only blue and red in the app: switches are blue too, not green.
        .tint(Color.accentColor)
        // Always show the iPhone status bar (time, Wi-Fi, battery).
        .statusBarHidden(false)
        .sheet(isPresented: Binding(get: { !welcomeDone }, set: { shown in if !shown { welcomeDone = true } })) {
            WelcomeView { welcomeDone = true }
                .interactiveDismissDisabled()
        }
        .onAppear {
            appearance.apply()
        }
        .onChange(of: appearance) { _, value in
            // Applied to the windows themselves, so open sheets switch at the same moment.
            value.apply()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                appearance.apply()
                store.becameActive()
            } else if phase == .background {
                store.enteredBackground()
            }
        }
    }
}
