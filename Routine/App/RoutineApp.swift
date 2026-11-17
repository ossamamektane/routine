import SwiftUI

@main
struct RoutineApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
    }
}
