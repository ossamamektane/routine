import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(PrefKey.reminders) private var remindersOn = true
    @AppStorage(PrefKey.badge) private var badgeOn = true
    @AppStorage(PrefKey.appearance) private var appearance: Appearance = .standard

    var body: some View {
        NavigationStack {
            Form {
                syncSection
                remindersSection
                moneySection
                displaySection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Changes are saved as you make them, so this just closes, like Apple's Home app.
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton { dismiss() }
                }
            }
            .onAppear { store.refreshNotificationStatus() }
            .onChange(of: appearance) { _, value in
                // Switches this sheet and the screen behind it right away.
                value.apply()
            }
        }
        // Switches in blue, like the rest of the app.
        .tint(Color.accentColor)
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
        case .available: return Color.accentColor
        case .noAccount: return Color.secondary
        case .full: return Color.red
        }
    }

    private var cloudTitle: LocalizedStringKey {
        switch store.cloudState {
        case .available: return "Synced with iCloud"
        case .noAccount: return "iCloud Is Off"
        case .full: return "iCloud Sync Is Full"
        }
    }

    private var cloudDetail: LocalizedStringKey {
        switch store.cloudState {
        case .available:
            return "Changes appear on your other devices signed in to the same Apple Account."
        case .noAccount:
            return "Everything still works and is saved on this iPhone. To sync, sign in to iCloud in the Settings app."
        case .full:
            return "Routine’s sync space is full, so new changes stay on this iPhone. Deleting old tasks and bills frees up space."
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
                    Label("Turn On Notifications in Settings", systemImage: "bell.badge")
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
            Toggle(isOn: Binding(
                get: { remindersOn },
                set: { on in
                    remindersOn = on
                    store.setRemindersEnabled(on)
                }
            )) {
                Label("Reminders", systemImage: "bell")
            }
            Toggle(isOn: Binding(
                get: { badgeOn },
                set: { on in
                    badgeOn = on
                    store.setBadgeEnabled(on)
                }
            )) {
                Label("Badges", systemImage: "app.badge")
            }
        } header: {
            Text("Reminders")
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
                LabeledContent {
                    Text(verbatim: store.settings.currency)
                } label: {
                    Label("Currency", systemImage: "banknote")
                }
            }
        } header: {
            Text("Bills")
        }
    }

    // MARK: Display

    private var displaySection: some View {
        Section {
            Picker(selection: $appearance) {
                ForEach(Appearance.allCases) { option in
                    Text(option.title).tag(option)
                }
            } label: {
                Label("Appearance", systemImage: "circle.lefthalf.filled")
            }
            Button {
                open(UIApplication.openSettingsURLString)
            } label: {
                LabeledContent {
                    Text(verbatim: languageName)
                        .foregroundStyle(Color.secondary)
                } label: {
                    Label {
                        Text("Language")
                            .foregroundStyle(Color.primary)
                    } icon: {
                        Image(systemName: "globe")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
        } header: {
            Text("General")
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section {
            NavigationLink {
                PrivacyView()
            } label: {
                Label("Privacy", systemImage: "hand.raised")
            }
        }
    }

    /// The language Routine is shown in, in its own name, like "English" or "Français".
    private var languageName: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        let locale = Locale(identifier: code)
        let name = locale.localizedString(forLanguageCode: code) ?? code
        return name.capitalized(with: locale)
    }

    private func open(_ string: String) {
        if let url = URL(string: string) {
            openURL(url)
        }
    }
}

// MARK: - Currency

/// Tap a currency to pick it and go back. It's applied as the list closes, so the list never
/// changes under your finger.
struct CurrencyPicker: View {
    var onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var chosen: String
    private let original: String
    private let suggestedCodes: [String]
    private let allCodes: [String]

    private struct Row: Identifiable {
        var id: String
        var code: String
    }

    private static let suggested = ["USD", "EUR", "GBP", "MAD", "CAD", "CHF", "AED", "SAR", "DZD", "TND", "EGP", "QAR", "KWD", "TRY", "AUD", "JPY", "INR"]

    /// Sorted once: there are a few hundred currencies. Each code only once, so no two rows share an ID.
    private static let sortedCodes: [String] = Array(Set(Locale.commonISOCurrencyCodes)).sorted { (a: String, b: String) -> Bool in
        Format.currencyName(a).localizedStandardCompare(Format.currencyName(b)) == .orderedAscending
    }

    init(selection: String, onSelect: @escaping (String) -> Void) {
        self.onSelect = onSelect
        original = selection
        _chosen = State(initialValue: selection)
        var codes = [selection]
        if let local = Locale.current.currency?.identifier { codes.append(local) }
        codes += Self.suggested
        var seen = Set<String>()
        suggestedCodes = codes.filter { seen.insert($0).inserted }
        allCodes = Self.sortedCodes.contains(selection) ? Self.sortedCodes : [selection] + Self.sortedCodes
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
                    ForEach(suggestedCodes.map { Row(id: "s." + $0, code: $0) }) { entry in
                        row(entry.code)
                    }
                } header: {
                    Text("Suggested")
                }
            }
            Section {
                ForEach(results.map { Row(id: "a." + $0, code: $0) }) { entry in
                    row(entry.code)
                }
            } header: {
                if search.isEmpty {
                    Text("All Currencies")
                } else {
                    Text("Results")
                }
            }
        }
        // Always showing, so it never appears under your finger as you scroll.
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search"))
        .navigationTitle("Currency")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            if chosen != original { onSelect(chosen) }
        }
    }

    private func row(_ code: String) -> some View {
        Button {
            // Like Apple's Settings: pick one and you're back.
            chosen = code
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: Format.currencyName(code))
                        .foregroundStyle(Color.primary)
                    Text(verbatim: "\(code) · \(Format.currencySymbol(code))")
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
                if code == chosen {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(code == chosen ? .isSelected : [])
    }
}

// MARK: - Privacy

struct PrivacyView: View {
    var body: some View {
        List {
            Section {
                FeatureRow(symbol: "hand.raised.fill", color: .accentColor, title: "Data Not Collected",
                           text: "Routine doesn’t collect, sell, or share anything about you. There are no ads, no analytics, and no trackers.")
                FeatureRow(symbol: "person.crop.circle.badge.xmark", color: .accentColor, title: "No Account",
                           text: "You never sign up or log in. Your iCloud keeps your devices in sync.")
                FeatureRow(symbol: "lock.icloud.fill", color: .accentColor, title: "Your iCloud, Not Our Servers",
                           text: "Your tasks and bills are saved on your devices and in your private iCloud storage. Only you can see them.")
                FeatureRow(symbol: "bell.badge.fill", color: .accentColor, title: "Reminders Stay on Your iPhone",
                           text: "Reminders are scheduled by your iPhone itself. Nothing is sent anywhere.")
            }
            .listRowSeparator(.hidden)
            .padding(.vertical, 6)
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
