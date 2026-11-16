import SwiftUI

/// Shown once, the first time Routine opens.
struct WelcomeView: View {
    @Environment(AppStore.self) private var store
    var onFinish: () -> Void
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    Image("AppMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 92, height: 92)
                        .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                        .padding(.top, 44)
                        .accessibilityHidden(true)

                    Text("Welcome to Routine")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 24) {
                        FeatureRow(symbol: "sun.max.fill", color: .orange, title: "Today at a glance",
                                   text: "Everything that needs doing today in one calm list. Check things off with a tap.")
                        FeatureRow(symbol: "repeat", color: .green, title: "Routines that fit real life",
                                   text: "Every morning, every other week, 6 weeks after the last haircut, or 3 times a week.")
                        FeatureRow(symbol: "creditcard.fill", color: .blue, title: "Bills in the same place",
                                   text: "Add an amount to anything to see what’s paid and what’s left this month.")
                        FeatureRow(symbol: "lock.icloud.fill", color: .cyan, title: "Private and synced",
                                   text: "No account and no ads. Your iCloud keeps your devices in sync.")
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 10) {
                Text("Next, Routine asks if it can send you reminders. You can change this anytime.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    busy = true
                    store.requestNotifications { _ in
                        onFinish()
                    }
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(busy)
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
    }
}
