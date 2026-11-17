import SwiftUI

/// Today: what's still to do and what's done. At the top, your day: how long you've been up,
/// or "Did you sleep?" when Routine thinks a new day may have started. Bills you pay yourself
/// show up here around when they're due.
struct TodayView: View {
    @Environment(AppStore.self) private var store
    @State private var editor: EditorRequest?
    @State private var showSettings = false
    @State private var wakeSheet: WakeSheetRequest?
    @State private var laterEntry: AgendaEntry?

    var body: some View {
        let clock = store.clock
        let agenda = Planner.agenda(items: store.items, clock: clock)
        let items = store.itemsByID
        let hasTasks = store.visibleItems.contains { !$0.hasCost }
        let currency = store.settings.currency

        NavigationStack {
            List {
                if hasTasks || !agenda.isEmpty {
                    if hasTasks {
                        Section {
                            dayHeader(clock)
                        }
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
                                    row(entry, item: item, clock: clock, currency: currency)
                                }
                            }
                        }
                    } header: {
                        Text("To Do")
                    }

                    if !agenda.done.isEmpty {
                        Section {
                            ForEach(agenda.done) { entry in
                                if let item = items[entry.itemID] {
                                    row(entry, item: item, clock: clock, currency: currency)
                                }
                            }
                        } header: {
                            Text("Completed")
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
            .sheet(item: $wakeSheet) { request in
                WakeTimeSheet(answering: request.answering)
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

    // MARK: Your day

    /// "Did you sleep?" when Routine asks; otherwise how long you've been up, or a way to start your day.
    @ViewBuilder
    private func dayHeader(_ clock: DayClock) -> some View {
        if store.sleepLog.question != nil {
            if store.lastWakeDate != nil {
                QuestionCard(symbol: "moon.zzz.fill", tint: Color.indigo,
                             title: "Did you sleep?", text: "Tap Yes to start a new day.") {
                    Button {
                        wakeSheet = WakeSheetRequest(answering: true)
                    } label: {
                        Text("Yes")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Button {
                        withAnimation(.snappy) { store.answerStillUp() }
                    } label: {
                        Text("Not Yet")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            } else {
                QuestionCard(symbol: "sunrise.fill", tint: Color.orange,
                             title: "What time did you wake up?", text: "Your day starts from then.") {
                    Button {
                        wakeSheet = WakeSheetRequest(answering: true)
                    } label: {
                        Text("Set Wake-Up Time")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Button {
                        withAnimation(.snappy) { store.dismissQuestion() }
                    } label: {
                        Text("Not Now")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
        } else if clock.isUp {
            UpRow(clock: clock) {
                wakeSheet = WakeSheetRequest(answering: false)
            }
        } else {
            StartDayRow {
                wakeSheet = WakeSheetRequest(answering: false)
            }
        }
    }

    // MARK: Rows

    private func canComplete(_ entry: AgendaEntry) -> Bool {
        if entry.isFinished || entry.state == .info { return false }
        // An hourly one waiting for your day to start, or for tomorrow, has nothing to check off yet.
        if entry.hourly && (entry.state == .waiting || entry.state == .future) { return false }
        return true
    }

    private func row(_ entry: AgendaEntry, item: Item, clock: DayClock, currency: String) -> some View {
        let completable = canComplete(entry)
        let canSkip = completable && !entry.goal && entry.state != .future
        let canUndo = entry.isFinished || (entry.goal && entry.progress > 0)
        let hasLater = completable && !store.laterOptions(for: entry).isEmpty

        return AgendaRow(entry: entry, item: item, today: clock.day, now: clock.now, currency: currency) {
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
                .tint(Color.accentColor)
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

/// A task or bill with its countdown: "Now", "in 35m", "7h left", "3 days left", "2 days late".
struct AgendaRow: View {
    var entry: AgendaEntry
    var item: Item
    /// The day you're living.
    var today: Day
    var now: Date
    var currency: String
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
                        .lineLimit(2)
                        .font(.subheadline)
                        .foregroundStyle(subtitleColor)
                }
            }
            Spacer(minLength: 6)
            if let countdown = rowCountdown {
                CountdownLabel(countdown: countdown)
            }
        }
        .padding(.vertical, 2)
    }

    /// Bills say when they're due; tasks how long is left.
    private var rowCountdown: Countdown? {
        if entry.isBill { return entry.billCountdown(now: now, today: today) }
        return entry.countdown(now: now, today: today)
    }

    /// Goals show how far along they are.
    private var progress: Double? {
        guard entry.goal, entry.total > 0, entry.state != .done else { return nil }
        return Double(entry.progress) / Double(entry.total)
    }

    private var subtitle: String? {
        var parts: [String] = []
        // Bills lead with their amount.
        if entry.isBill, item.hasCost, let cost = item.cost {
            parts.append(Format.money(cost, code: currency))
        }
        if entry.goal {
            parts.append(Format.goalProgress(entry.progress, entry.total, item.schedule.goalPeriod))
            return parts.joined(separator: " · ")
        }
        switch entry.state {
        case .done:
            if let at = entry.at {
                if entry.isBill {
                    parts.append(String(localized: "Paid at \(Format.time(at))"))
                } else {
                    parts.append(String(localized: "Done at \(Format.time(at))"))
                }
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
            break
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

/// Which wake-up sheet to show.
struct WakeSheetRequest: Identifiable {
    let id = UUID()
    /// Answering "Did you sleep?" or starting your day, rather than changing when it started.
    var answering: Bool
}

/// "Did you sleep?" and "What time did you wake up?": asked right on Today, never as an alert.
struct QuestionCard<Buttons: View>: View {
    var symbol: String
    var tint: Color
    var title: LocalizedStringKey
    var text: LocalizedStringKey
    var buttons: Buttons

    init(symbol: String, tint: Color, title: LocalizedStringKey, text: LocalizedStringKey,
         @ViewBuilder buttons: () -> Buttons) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.text = text
        self.buttons = buttons()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 10) {
                buttons
            }
        }
        .padding(.vertical, 6)
    }
}

/// Up and about: how long for. Tap to change when you woke up.
struct UpRow: View {
    var clock: DayClock
    var onChange: () -> Void

    var body: some View {
        Button(action: onChange) {
            HStack(spacing: 12) {
                Image(systemName: clock.isPastMidnight ? "moon.stars.fill" : "sun.max.fill")
                    .font(.title3)
                    .foregroundStyle(clock.isPastMidnight ? Color.indigo : Color.orange)
                    .frame(width: 30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Up for \(Format.span(minutes: clock.minutesUp))")
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    Text(verbatim: sinceText(clock))
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
                Spacer(minLength: 6)
                Text("Change")
                    .font(.subheadline)
                    .foregroundStyle(.tint)
            }
        }
    }
}

/// No day has started yet: set when you woke up.
struct StartDayRow: View {
    var onStart: () -> Void

    var body: some View {
        Button(action: onStart) {
            HStack(spacing: 12) {
                Image(systemName: "sunrise.fill")
                    .font(.title3)
                    .foregroundStyle(Color.orange)
                    .frame(width: 30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start My Day")
                        .font(.headline)
                        .foregroundStyle(.tint)
                    Text("Set the time you woke up.")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
                Spacer(minLength: 6)
            }
        }
        .accessibilityLabel(Text("Start My Day"))
    }
}

/// "Since 7:10 AM", or "Since yesterday, 11:00 PM" after midnight. From when you really got up.
private func sinceText(_ clock: DayClock) -> String {
    guard let up = clock.upDate else { return "" }
    let time = Format.time(up)
    let days = Day(clock.now).index - Day(up).index
    if days <= 0 {
        return String(localized: "Since \(time)")
    }
    if days == 1 {
        return String(localized: "Since yesterday, \(time)")
    }
    let moment = Format.day(Day(up)) + ", " + time
    return String(localized: "Since \(moment)")
}

/// "What time did you wake up?" Today starts your day then. Yesterday means you haven't slept
/// since, so the day you're in keeps going.
struct WakeTimeSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Answering "Did you sleep?" or starting your day, rather than changing when it started.
    var answering: Bool
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
                } header: {
                    Text("What time did you wake up?")
                        .textCase(nil)
                } footer: {
                    Text("Haven’t slept? Choose Yesterday and the time you woke up.")
                }
                if hasNotUpButton {
                    Section {
                        Button("I’m Not Up Yet", role: .destructive) {
                            store.clearWake()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Wake-Up Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        withAnimation(.snappy) { store.answerWoke(at: time) }
                        dismiss()
                    }
                }
            }
            .onAppear {
                let now = Date()
                if !answering, let up = store.clock.upDate {
                    yesterday = Day(up) < Day(now)
                    let allowed = Self.range(yesterday: yesterday, now: now)
                    time = min(max(up, allowed.lowerBound), allowed.upperBound)
                } else {
                    // Now, to the 5 minutes.
                    yesterday = false
                    let minute = (now.minutesOfDay / 5) * 5
                    time = min(Day(now).start.addingTimeInterval(TimeInterval(minute * 60)), now)
                }
            }
        }
        .presentationDetents([.height(hasNotUpButton ? 490 : 430), .large])
    }

    /// "I'm Not Up Yet" adds a row, so the sheet is a little taller.
    private var hasNotUpButton: Bool {
        !answering && store.clock.wake != nil
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
