import SwiftUI

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @State private var editor: EditorRequest?
    @State private var showSettings = false
    @State private var showWakeTime = false
    @State private var laterEntry: AgendaEntry?

    var body: some View {
        let agenda = store.agenda
        let items = store.itemsByID
        let today = Day(store.now)
        let currency = store.settings.currency
        let isEmpty = store.visibleItems.isEmpty

        NavigationStack {
            List {
                if !isEmpty {
                    Section {
                        TodayHeader(date: store.now, remaining: agenda.remainingCount, done: agenda.doneCount)
                    }
                }

                if agenda.hasWakeItems && agenda.overdue.count + agenda.today.count + agenda.waiting.count + agenda.done.count > 0 {
                    Section {
                        if let wake = store.todayWake {
                            HStack {
                                Label {
                                    Text("Up since \(Format.time(wake))")
                                } icon: {
                                    Image(systemName: "sunrise.fill").foregroundStyle(.orange)
                                }
                                Spacer()
                                Button("Change") { showWakeTime = true }
                                    .buttonStyle(.borderless)
                            }
                        } else {
                            WakeCard(onUp: {
                                withAnimation(.snappy) { store.wakeUp(at: Date()) }
                            }, onEarlier: {
                                showWakeTime = true
                            })
                        }
                    }
                }

                entrySection("Overdue", agenda.overdue, items: items, today: today, currency: currency)
                entrySection("After you wake up", agenda.waiting, items: items, today: today, currency: currency)
                entrySection("Today", agenda.today, items: items, today: today, currency: currency)
                entrySection("Goals", agenda.goals, items: items, today: today, currency: currency)

                if !agenda.upcoming.isEmpty {
                    Section("Coming up") {
                        ForEach(agenda.upcoming.flatMap { $0.entries }) { entry in
                            if let item = items[entry.itemID] {
                                UpcomingRow(entry: entry, item: item, today: today, currency: currency)
                                    .contentShape(Rectangle())
                                    .onTapGesture { editor = .edit(item) }
                            }
                        }
                    }
                }

                entrySection("Done", agenda.done, items: items, today: today, currency: currency)

                if isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Nothing here yet").font(.headline)
                            Text("Add routines, bills and goals. Today shows what's due, so you don't have to remember.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        Button {
                            editor = .new()
                        } label: {
                            Label("Add your own", systemImage: "plus.circle.fill")
                        }
                    }
                    Section("Ideas to start with") {
                        ForEach(Templates.all(today: today)) { template in
                            TemplateRow(template: template)
                                .contentShape(Rectangle())
                                .onTapGesture { editor = .new(template.item) }
                        }
                    }
                } else if agenda.overdue.isEmpty && agenda.today.isEmpty && agenda.waiting.isEmpty && agenda.goals.isEmpty {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title2)
                                .foregroundStyle(.tint)
                            Text("Nothing else due today.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(Text("Settings"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editor = .new()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("Add"))
                }
            }
            .sheet(item: $editor) { request in
                EditorView(request: request)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showWakeTime) {
                WakeTimeSheet()
            }
            .confirmationDialog("Remind me again", isPresented: Binding(get: { laterEntry != nil }, set: { shown in if !shown { laterEntry = nil } }),
                                titleVisibility: .visible, presenting: laterEntry) { entry in
                ForEach(store.laterOptions(for: entry)) { option in
                    Button(option.label) {
                        withAnimation(.snappy) {
                            store.snooze(entry.itemID, day: entry.day, slot: entry.slot, until: option.date)
                        }
                    }
                }
            }
            .sensoryFeedback(.success, trigger: store.completions)
        }
    }

    @ViewBuilder
    private func entrySection(_ title: LocalizedStringKey, _ entries: [AgendaEntry], items: [UUID: Item], today: Day, currency: String) -> some View {
        if !entries.isEmpty {
            Section {
                ForEach(entries) { entry in
                    if let item = items[entry.itemID] {
                        row(entry, item: item, today: today, currency: currency)
                    }
                }
            } header: {
                Text(title)
            }
        }
    }

    private func row(_ entry: AgendaEntry, item: Item, today: Day, currency: String) -> some View {
        let canComplete = !entry.isFinished && entry.state != .info && !(entry.goal && entry.state == .done)
        let canSkip = canComplete && !entry.goal
        let canUndo = entry.isFinished || ((entry.goal || entry.hourly) && entry.progress > 0)
        let hasLater = canComplete && !store.laterOptions(for: entry).isEmpty

        return AgendaRow(entry: entry, item: item, today: today, currency: currency) {
            toggle(entry)
        }
        .contentShape(Rectangle())
        .onTapGesture { editor = .edit(item) }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if canComplete {
                Button {
                    withAnimation(.snappy) { store.complete(entry) }
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .tint(.green)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canUndo {
                Button {
                    withAnimation(.snappy) { store.undo(entry) }
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .tint(.gray)
            }
            if canSkip {
                Button {
                    withAnimation(.snappy) { store.complete(entry, skipped: true) }
                } label: {
                    Label("Skip", systemImage: "forward")
                }
                .tint(.gray)
            }
            if hasLater {
                Button {
                    laterEntry = entry
                } label: {
                    Label("Later", systemImage: "clock")
                }
                .tint(.indigo)
            }
        }
        .contextMenu {
            if canComplete {
                Button {
                    withAnimation(.snappy) { store.complete(entry) }
                } label: {
                    Label("Done", systemImage: "checkmark.circle")
                }
            }
            if canSkip {
                Button {
                    withAnimation(.snappy) { store.complete(entry, skipped: true) }
                } label: {
                    Label("Skip", systemImage: "forward")
                }
            }
            if hasLater {
                Button {
                    laterEntry = entry
                } label: {
                    Label("Later…", systemImage: "clock")
                }
            }
            if canUndo {
                Button {
                    withAnimation(.snappy) { store.undo(entry) }
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
            }
            Divider()
            Button {
                editor = .edit(item)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
        }
    }

    private func toggle(_ entry: AgendaEntry) {
        withAnimation(.snappy) {
            if entry.isFinished {
                store.undo(entry)
            } else if entry.goal && entry.state == .done {
                store.undo(entry.itemID)
            } else if entry.state != .info {
                store.complete(entry)
            }
        }
    }
}

/// Date and a ring showing how much of today is done.
struct TodayHeader: View {
    var date: Date
    var remaining: Int
    var done: Int

    var body: some View {
        let total = remaining + done
        HStack(spacing: 14) {
            ZStack {
                ProgressRing(fraction: total == 0 ? 1 : Double(done) / Double(total), tint: .accentColor, lineWidth: 5)
                if remaining == 0 {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.tint)
                } else {
                    Text(verbatim: "\(remaining)")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                }
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.longDay(Day(date)))
                    .font(.headline)
                if remaining == 0 {
                    Text("All done for now")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("To do: \(remaining) · Done: \(done)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct AgendaRow: View {
    var entry: AgendaEntry
    var item: Item
    var today: Day
    var currency: String
    var onCheck: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CheckButton(state: entry.state, tint: item.color.color, progress: progress, action: onCheck)
            SymbolTile(symbol: item.symbol, color: item.color.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.displayTitle)
                    .foregroundStyle(entry.isFinished ? Color.secondary : Color.primary)
                    .lineLimit(2)
                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(.subheadline)
                        .foregroundStyle(subtitleColor)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            if item.hasCost, let cost = item.cost {
                Text(Format.money(cost, code: currency))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var progress: Double? {
        guard (entry.hourly || entry.goal), entry.total > 0, entry.state != .done else { return nil }
        return Double(entry.progress) / Double(entry.total)
    }

    private var subtitle: String? {
        if entry.goal {
            return Format.goalProgress(entry.progress, entry.total, item.schedule.goalPeriod)
        }
        var parts: [String] = []
        switch entry.state {
        case .done:
            if entry.hourly {
                parts.append(String(localized: "\(entry.progress) of \(entry.total) done"))
            } else if let at = entry.at {
                parts.append(String(localized: "Done at \(Format.time(at))"))
                if entry.day < today { parts.append(String(localized: "was due \(Format.day(entry.day))")) }
            }
        case .skipped:
            parts.append(String(localized: "Skipped"))
        case .snoozed:
            if let until = entry.snoozedUntil {
                parts.append(String(localized: "Later · \(Format.time(until))"))
            }
            if entry.overdue { parts.append(String(localized: "Due \(Format.day(entry.day))")) }
        case .waiting:
            let offset = item.schedule.afterWaking ?? 0
            parts.append(offset == 0 ? String(localized: "When you wake up") : String(localized: "\(Format.duration(minutes: offset)) after waking"))
        case .info:
            parts.append(String(localized: "Autopay"))
            if let m = entry.minute { parts.append(Format.time(m)) }
        case .due, .late, .upcoming:
            if entry.overdue { parts.append(String(localized: "Due \(Format.day(entry.day))")) }
            if let m = entry.minute {
                if entry.hourly && entry.state == .upcoming {
                    parts.append(String(localized: "Next at \(Format.time(m))"))
                } else {
                    parts.append(Format.time(m))
                }
            } else if !entry.overdue && !item.schedule.isEveryDay {
                parts.append(item.schedule.summary)
            }
        }
        if entry.hourly && entry.state != .done && entry.total > 0 {
            parts.append(String(localized: "\(entry.progress) of \(entry.total)"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var subtitleColor: Color {
        switch entry.state {
        case .due, .upcoming: return entry.overdue ? .red : .secondary
        case .late: return entry.overdue ? .red : .orange
        case .snoozed: return .indigo
        default: return .secondary
        }
    }
}

struct UpcomingRow: View {
    var entry: UpcomingEntry
    var item: Item
    var today: Day
    var currency: String

    var body: some View {
        HStack(spacing: 12) {
            SymbolTile(symbol: item.symbol, color: item.color.color, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.displayTitle)
                    .lineLimit(1)
                if let m = entry.minute {
                    Text(verbatim: Format.relative(entry.day, today: today) + " · " + Format.time(m))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(verbatim: Format.relative(entry.day, today: today))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 6)
            if item.hasCost, let cost = item.cost {
                Text(Format.money(cost, code: currency))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct TemplateRow: View {
    var template: Templates.Template

    var body: some View {
        HStack(spacing: 12) {
            SymbolTile(symbol: template.item.symbol, color: template.item.color.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: template.title)
                Text(verbatim: template.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(.tint)
        }
    }
}

/// Shown until you tap "I'm up" on days with wake-up routines.
struct WakeCard: View {
    var onUp: () -> Void
    var onEarlier: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sunrise.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Good morning")
                        .font(.headline)
                    Text("Tap when you're up. Your wake-up routines start from then.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                Button(action: onUp) {
                    Text("I'm up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button(action: onEarlier) {
                    Text("Earlier…")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(.vertical, 6)
    }
}

/// Set the time you woke up if you forgot to tap "I'm up".
struct WakeTimeSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var time = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Woke up at", selection: $time, in: Day(Date()).start...Date(), displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                } footer: {
                    Text("Wake-up routines are timed from this.")
                }
                if store.todayWake != nil {
                    Section {
                        Button("I'm not up yet", role: .destructive) {
                            store.clearWake()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("When did you wake up?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.wakeUp(at: time)
                        dismiss()
                    }
                }
            }
            .onAppear {
                let now = Date()
                if let wake = store.todayWake {
                    time = Day(now).date(minutes: wake)
                } else {
                    time = max(Day(now).start, now.addingTimeInterval(-30 * 60))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
