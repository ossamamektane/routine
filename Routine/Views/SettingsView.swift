import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(PrefKey.reminders) private var remindersOn = true
    @AppStorage(PrefKey.badge) private var badgeOn = true
    @AppStorage(PrefKey.appearance) private var appearance: Appearance = .system

    var body: some View {
        NavigationStack {
            Form {
                syncSection
                remindersSection
                wakeSection
                moneySection
                displaySection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { store.refreshNotificationStatus() }
        }
    }

    // MARK: iCloud

    private var syncSection: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: cloudSymbol)
                    .font(.title2)
                    .foregroundStyle(cloudTint)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(cloudTitle)
                        .font(.headline)
                    Text(cloudDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        } header: {
            Text("iCloud")
        } footer: {
            Text("No account needed. Your routines sync privately through your own iCloud, and nothing is stored on anyone else’s servers.")
        }
    }

    private var cloudSymbol: String {
        switch store.cloudState {
        case .available: return "checkmark.icloud.fill"
        case .noAccount: return "icloud.slash"
        case .full: return "exclamationmark.icloud.fill"
        }
    }

    private var cloudTint: Color {
        switch store.cloudState {
        case .available: return .green
        case .noAccount: return .secondary
        case .full: return .orange
        }
    }

    private var cloudTitle: LocalizedStringKey {
        switch store.cloudState {
        case .available: return "Synced with iCloud"
        case .noAccount: return "iCloud is off"
        case .full: return "iCloud sync is full"
        }
    }

    private var cloudDetail: LocalizedStringKey {
        switch store.cloudState {
        case .available:
            return "Changes appear on your other devices signed in to the same Apple Account."
        case .noAccount:
            return "Everything still works and is saved on this iPhone. To sync, sign in to iCloud in the Settings app."
        case .full:
            return "Routine’s sync space is full, so new changes stay on this iPhone. Deleting old routines frees up space."
        }
    }

    // MARK: Reminders

    private var remindersSection: some View {
        Section {
            switch store.notificationStatus {
            case .denied:
                Button {
                    open(UIApplication.openNotificationSettingsURLString)
                } label: {
                    Label("Turn On Notifications in Settings", systemImage: "bell.slash")
                }
            case .notDetermined:
                Button {
                    store.requestNotifications()
                } label: {
                    Label("Allow Notifications", systemImage: "bell.badge")
                }
            default:
                EmptyView()
            }
            Toggle("Reminders", isOn: Binding(
                get: { remindersOn },
                set: { on in
                    remindersOn = on
                    store.setRemindersEnabled(on)
                }
            ))
            Toggle("Badge on App Icon", isOn: Binding(
                get: { badgeOn },
                set: { on in
                    badgeOn = on
                    store.setBadgeEnabled(on)
                }
            ))
        } header: {
            Text("Reminders")
        } footer: {
            Text("Reminders are scheduled by your iPhone, so they work offline. The badge shows what’s left to do today.")
        }
    }

    // MARK: Waking up

    private var wakeSection: some View {
        Section {
            Toggle("Morning Check-In", isOn: Binding(
                get: { store.settings.morningCheckIn },
                set: { on in store.updateSettings { $0.morningCheckIn = on } }
            ))
            if store.settings.morningCheckIn {
                DatePicker("Ask At", selection: Binding(
                    get: { Day.today.date(minutes: store.settings.morningMinute) },
                    set: { date in store.updateSettings { $0.morningMinute = date.minutesOfDay } }
                ), displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Waking Up")
        } footer: {
            Text("For routines that start when you wake up. If you haven’t tapped “I’m up” by this time, Routine asks once.")
        }
    }

    // MARK: Money

    private var moneySection: some View {
        Section {
            NavigationLink {
                CurrencyPicker(selection: store.settings.currency) { code in
                    store.updateSettings { $0.currency = code }
                }
            } label: {
                LabeledContent("Currency") {
                    Text(store.settings.currency)
                }
            }
        } header: {
            Text("Money")
        }
    }

    // MARK: Display

    private var displaySection: some View {
        Section {
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            Button("Language") {
                open(UIApplication.openSettingsURLString)
            }
        } header: {
            Text("Display")
        } footer: {
            Text("Routine speaks English, French and Arabic. Language opens the Settings app, where you can pick one just for Routine.")
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section {
            NavigationLink {
                PrivacyView()
            } label: {
                Label("Privacy", systemImage: "hand.raised.fill")
            }
            LabeledContent("Version", value: versionText)
        } header: {
            Text("About")
        }
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func open(_ string: String) {
        if let url = URL(string: string) {
            openURL(url)
        }
    }
}

// MARK: - Currency

struct CurrencyPicker: View {
    var selection: String
    var onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private static let suggested = ["USD", "EUR", "GBP", "MAD", "CAD", "CHF", "AED", "SAR", "DZD", "TND", "EGP", "QAR", "KWD", "TRY", "AUD", "JPY", "INR"]

    private var allCodes: [String] {
        var codes = Set(Locale.commonISOCurrencyCodes)
        codes.insert(selection)
        return codes.sorted { Format.currencyName($0).localizedStandardCompare(Format.currencyName($1)) == .orderedAscending }
    }

    private var suggestedCodes: [String] {
        var codes = [selection]
        if let local = Locale.current.currency?.identifier { codes.append(local) }
        codes += Self.suggested
        var seen = Set<String>()
        return codes.filter { seen.insert($0).inserted }
    }

    private var results: [String] {
        let text = search.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return allCodes }
        return allCodes.filter {
            $0.localizedStandardContains(text) || Format.currencyName($0).localizedStandardContains(text)
        }
    }

    var body: some View {
        List {
            if search.isEmpty {
                Section {
                    ForEach(suggestedCodes, id: \.self) { code in
                        row(code)
                    }
                } header: {
                    Text("Suggested")
                }
            }
            Section {
                ForEach(results, id: \.self) { code in
                    row(code)
                }
            } header: {
                if search.isEmpty {
                    Text("All Currencies")
                } else {
                    Text("Results")
                }
            }
        }
        .searchable(text: $search)
        .navigationTitle("Currency")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ code: String) -> some View {
        Button {
            onSelect(code)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Format.currencyName(code))
                        .foregroundStyle(Color.primary)
                    Text(verbatim: "\(code) · \(Format.currencySymbol(code))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if code == selection {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(code == selection ? .isSelected : [])
    }
}

// MARK: - Privacy

struct PrivacyView: View {
    var body: some View {
        List {
            Section {
                FeatureRow(symbol: "hand.raised.fill", color: .blue, title: "No data collected",
                           text: "Routine doesn’t collect, sell or share anything about you. There are no ads, no analytics and no trackers.")
                FeatureRow(symbol: "person.crop.circle.badge.xmark", color: .orange, title: "No account",
                           text: "You never sign up or log in. Your iCloud keeps your devices in sync.")
                FeatureRow(symbol: "lock.icloud.fill", color: .cyan, title: "Your iCloud, not our servers",
                           text: "Your routines are saved on your devices and in your private iCloud storage. Only you can see them.")
                FeatureRow(symbol: "bell.badge.fill", color: .red, title: "Reminders stay on your iPhone",
                           text: "Reminders are scheduled by your iPhone itself. Nothing is sent anywhere.")
            }
            .listRowSeparator(.hidden)
            .padding(.vertical, 6)
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
