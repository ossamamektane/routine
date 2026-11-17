import SwiftUI

/// Today: your tasks in two lists, still to do and done. Bills have their own tab.
struct TodayView: View {
    @Environment(AppStore.self) private var store
    @State private var editor: EditorRequest?
    @State private var showSettings = false
    @State private var showWakeTime = false
    @State private var laterEntry: AgendaEntry?

    var body: some View {
        let clock = store.clock
        let agenda = Planner.agenda(items: store.items, clock: clock)
        let items = store.itemsByID
        let hasTasks = store.visibleItems.contains { !$0.hasCost }

        NavigationStack {
            List {
                if hasTasks {
                    Section {
                        wakeSection(clock)
                    }

                    Section {
                        if agenda.tasks.isEmpty {
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.title2)
                                    .foregroundStyle(.tint)
                                Text("Nothing left to do.")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            ForEach(agenda.tasks) { entry in
                                if let item = items[entry.itemID] {
                                    row(entry, item: item, clock: clock)
                                }
                            }
                        }
                    } header: {
                        Text("Tasks")
                    }

                    if !agenda.done.isEmpty {
                        Section {
                            ForEach(agenda.done) { entry in
                                if let item = items[entry.itemID] {
                                    row(entry, item: item, clock: clock)
                                }
                            }
                        } header: {
                            Text("Done")
                        }
                    }
                } else {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Nothing here yet").font(.headline)
                            Text("Add the things you do regularly. Today shows what's due, so you don't have to remember.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        Button {
                            editor = .new()
                        } label: {
                            Label("Add a task", systemImage: "checklist")
                        }
                    }
                    Section("Ideas to start with") {
                        ForEach(Templates.all(today: clock.day).filter { !$0.isBill }) { template in
                            TemplateRow(template: template)
                                .contentShape(Rectangle())
                                .onTapGesture { editor = .new(template.item) }
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
                    .accessibilityLabel(Text("Add a task"))
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

    // MARK: Waking up and going to sleep

    @ViewBuilder
    private func wakeSection(_ clock: DayClock) -> some View {
        if let since = clock.asleepSince {
            AsleepCard(since: since, onUp: {
                withAnimation(.snappy) { store.wakeUp(at: Date()) }
            }, onEarlier: {
                showWakeTime = true
            }, onStillUp: {
                withAnimation(.snappy) { store.cancelSleep() }
            })
        } else if clock.isUp && clock.isPastMidnight {
            LateNightCard(clock: clock, onSleep: {
                withAnimation(.snappy) { store.goToSleep() }
            }, onWoke: {
                withAnimation(.snappy) { store.wakeUp(at: Date()) }
            }, onChange: {
                showWakeTime = true
            })
        } else if clock.isUp {
            UpRow(clock: clock, onSleep: {
                withAnimation(.snappy) { store.goToSleep() }
            }, onWoke: {
                withAnimation(.snappy) { store.wakeUp(at: Date()) }
            }, onChange: {
                showWakeTime = true
            })
        } else {
            WakeCard(onUp: {
                withAnimation(.snappy) { store.wakeUp(at: Date()) }
            }, onEarlier: {
                showWakeTime = true
            })
        }
    }

    // MARK: Rows

    private func canComplete(_ entry: AgendaEntry) -> Bool {
        if entry.isFinished || entry.state == .info { return false }
        // An hourly one waiting for "I'm up" or tomorrow has nothing to check off yet.
        if entry.hourly && (entry.state == .waiting || entry.state == .future) { return false }
        return true
    }

    private func row(_ entry: AgendaEntry, item: Item, clock: DayClock) -> some View {
        let completable = canComplete(entry)
        let canSkip = completable && !entry.goal && entry.state != .future
        let canUndo = entry.isFinished || (entry.goal && entry.progress > 0)
        let hasLater = completable && !store.laterOptions(for: entry).isEmpty

        return AgendaRow(entry: entry, item: item, today: clock.day, now: clock.now) {
            toggle(entry)
        }
        .contentShape(Rectangle())
        .onTapGesture { editor = .edit(item) }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if completable {
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
            if completable {
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
            } else if canComplete(entry) {
                store.complete(entry)
            }
        }
    }
}

/// A task with its countdown: "in 35m", "7h left", "3 days left", "2 days late".
struct AgendaRow: View {
    var entry: AgendaEntry
    var item: Item
    /// The day you're living.
    var today: Day
    var now: Date
    var onCheck: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CheckButton(state: entry.state, tint: .accentColor, progress: progress, action: onCheck)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.displayTitle)
                    .foregroundStyle(entry.isFinished && !entry.doneToday ? Color.secondary : Color.primary)
                    .lineLimit(2)
                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(.subheadline)
                        .foregroundStyle(subtitleColor)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            if let countdown = entry.countdown(now: now, today: today) {
                CountdownLabel(countdown: countdown)
            }
        }
        .padding(.vertical, 2)
    }

    /// Goals show how far along they are.
    private var progress: Double? {
        guard entry.goal, entry.total > 0, entry.state != .done else { return nil }
        return Double(entry.progress) / Double(entry.total)
    }

    private var subtitle: String? {
        var parts: [String] = []
        if entry.goal {
            parts.append(Format.goalProgress(entry.progress, entry.total, item.schedule.goalPeriod))
            return parts.joined(separator: " · ")
        }
        switch entry.state {
        case .done:
            if let at = entry.at {
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
        case .future:
            var when = Format.day(entry.day)
            if let m = entry.minute { when += " · " + Format.time(m) }
            parts.append(when)
        case .info:
            parts.append(String(localized: "Autopay"))
        case .due, .late, .upcoming:
            if entry.overdue { parts.append(String(localized: "Due \(Format.day(entry.day))")) }
            if let m = entry.minute { parts.append(Format.time(m)) }
        }
        if !entry.isFinished && entry.state != .waiting, let often = item.schedule.shortSummary {
            parts.append(often)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var subtitleColor: Color {
        if entry.state == .snoozed { return .indigo }
        return entry.overdue && !entry.isFinished ? .red : .secondary
    }
}

struct TemplateRow: View {
    var template: Templates.Template

    var body: some View {
        HStack(spacing: 12) {
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

/// Shown until you tap "I'm up". Your day starts then, whatever the time.
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
                    Text("Just woke up?")
                        .font(.headline)
                    Text("Tap when you're up. Your day starts then, even if it's the afternoon.")
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

/// Up and about: how long for, with "Going to Sleep" in the menu.
struct UpRow: View {
    var clock: DayClock
    var onSleep: () -> Void
    var onWoke: () -> Void
    var onChange: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sun.max.fill")
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("Up for \(Format.span(minutes: clock.minutesUp))")
                    .font(.headline)
                Text(verbatim: sinceText(clock))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Menu {
                Button(action: onSleep) {
                    Label("Going to Sleep", systemImage: "moon.zzz")
                }
                Button(action: onChange) {
                    Label("Change Wake-Up Time…", systemImage: "clock.arrow.circlepath")
                }
                Button(action: onWoke) {
                    Label("I Just Woke Up", systemImage: "sunrise")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("More"))
        }
        .accessibilityElement(children: .contain)
    }
}

/// Still up after midnight: the day keeps going until you sleep.
struct LateNightCard: View {
    var clock: DayClock
    var onSleep: () -> Void
    var onWoke: () -> Void
    var onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "moon.stars.fill")
                    .font(.title2)
                    .foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Up for \(Format.span(minutes: clock.minutesUp))")
                        .font(.headline)
                    Text(verbatim: sinceText(clock))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Your day keeps going until you sleep.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Menu {
                    Button(action: onChange) {
                        Label("Change Wake-Up Time…", systemImage: "clock.arrow.circlepath")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text("More"))
            }
            HStack(spacing: 10) {
                Button(action: onSleep) {
                    Label("Going to Sleep", systemImage: "moon.zzz")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                Button(action: onWoke) {
                    Label("I Just Woke Up", systemImage: "sunrise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(.vertical, 6)
    }
}

/// After "Going to Sleep", until you tap "I'm up".
struct AsleepCard: View {
    var since: Date
    var onUp: () -> Void
    var onEarlier: () -> Void
    var onStillUp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "moon.zzz.fill")
                    .font(.title2)
                    .foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Asleep since \(Format.time(since))")
                        .font(.headline)
                    Text("Tap “I'm up” when you're up.")
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
                Menu {
                    Button(action: onEarlier) {
                        Label("Earlier…", systemImage: "clock.arrow.circlepath")
                    }
                    Button(action: onStillUp) {
                        Label("Still Up", systemImage: "arrow.uturn.backward")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityLabel(Text("More"))
            }
        }
        .padding(.vertical, 6)
    }
}

/// "Since 7:10 AM", or "Since yesterday, 11:00 PM" after midnight.
private func sinceText(_ clock: DayClock) -> String {
    guard let wake = clock.wakeDate else { return "" }
    let time = Format.time(wake)
    if Day(wake) < Day(clock.now) {
        return String(localized: "Since yesterday, \(time)")
    }
    return String(localized: "Since \(time)")
}

/// Set when you woke up: today, or yesterday if you haven't slept since.
struct WakeTimeSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var time = Date()
    @State private var yesterday = false

    var body: some View {
        let now = Date()
        NavigationStack {
            Form {
                Section {
                    Picker("Day", selection: dayBinding) {
                        Text("Yesterday").tag(true)
                        Text("Today").tag(false)
                    }
                    .pickerStyle(.segmented)
                    DatePicker("Woke up at", selection: $time, in: Self.range(yesterday: yesterday, now: now), displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                } footer: {
                    Text("Wake-up tasks are timed from this.")
                }
                if store.clock.wake != nil {
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
                if let wake = store.clock.wakeDate {
                    yesterday = Day(wake) < Day(now)
                    time = wake
                } else {
                    yesterday = false
                    time = max(Day(now).start, now.addingTimeInterval(-30 * 60))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Yesterday is only possible if it's less than a day ago.
    static func range(yesterday: Bool, now: Date) -> ClosedRange<Date> {
        let today = Day(now)
        if yesterday {
            let lower = max(today.adding(days: -1).start, now.addingTimeInterval(-24 * 3600))
            let upper = max(lower, today.start.addingTimeInterval(-60))
            return lower...upper
        }
        return today.start...max(today.start, now)
    }

    /// Switching day keeps the same time on the clock, as far as it's allowed.
    private var dayBinding: Binding<Bool> {
        Binding(
            get: { yesterday },
            set: { value in
                guard value != yesterday else { return }
                let now = Date()
                let day = value ? Day(now).adding(days: -1) : Day(now)
                let allowed = Self.range(yesterday: value, now: now)
                let wanted = day.date(minutes: time.minutesOfDay)
                time = min(max(wanted, allowed.lowerBound), allowed.upperBound)
                yesterday = value
            }
        )
    }
}
