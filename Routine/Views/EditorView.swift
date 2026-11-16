import SwiftUI
import UIKit

/// One time of day in the editor. Kept as a Date so a DatePicker can edit it.
struct TimeRow: Identifiable, Hashable {
    let id = UUID()
    var date: Date

    init(minute: Int) {
        date = Day.today.date(minutes: minute)
    }

    init(date: Date) {
        self.date = date
    }

    var minute: Int { date.minutesOfDay }
}

/// Add or edit a routine, bill, goal or one-time task. Nothing is saved until you tap Add or Save.
struct EditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let request: EditorRequest

    @State private var draft: Item
    @State private var amountText: String
    @State private var times: [TimeRow]
    @State private var symbolTouched: Bool
    @State private var confirmDelete = false
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case title, amount
    }

    init(request: EditorRequest) {
        self.request = request
        _draft = State(initialValue: request.item)
        _amountText = State(initialValue: Format.editableAmount(request.item.cost))
        _times = State(initialValue: request.item.schedule.times.map { TimeRow(minute: $0) })
        _symbolTouched = State(initialValue: !request.isNew)
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                kindSection
                scheduleSection
                reminderSection
                costSection
                if !request.isNew {
                    pauseSection
                    historySection
                    deleteSection
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(heading)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .interactiveDismissDisabled(isDirty)
            .onChange(of: draft.title) { _, title in
                suggestSymbol(for: title)
            }
            .onChange(of: draft.schedule.kind) { _, _ in
                keepConsistent()
            }
            .onChange(of: draft.schedule.unit) { _, _ in
                keepConsistent()
            }
            .onChange(of: draft.schedule.every) { _, _ in
                keepConsistent()
            }
            .confirmationDialog(Text("Delete “\(draft.displayTitle)”?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    store.delete(request.item.id)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes it and its history from all your devices.")
            }
            .onAppear {
                store.refreshNotificationStatus()
            }
            .task {
                guard request.isNew, draft.title.isEmpty else { return }
                try? await Task.sleep(nanoseconds: 500_000_000)
                focus = .title
            }
        }
    }

    // MARK: Sections

    private var nameSection: some View {
        Section {
            HStack(spacing: 12) {
                SymbolTile(symbol: draft.symbol, color: draft.color.color, size: 36)
                TextField("Name", text: $draft.title)
                    .font(.headline)
                    .focused($focus, equals: .title)
                    .submitLabel(.done)
                    .onSubmit { focus = nil }
            }
            NavigationLink {
                SymbolPicker(symbol: $draft.symbol, color: $draft.color, touched: $symbolTouched)
            } label: {
                Label("Icon and Color", systemImage: "paintpalette")
            }
            TextField("Notes", text: $draft.notes, axis: .vertical)
                .lineLimit(1...6)
        }
    }

    private var kindSection: some View {
        Section {
            Picker("Type", selection: $draft.schedule.kind) {
                Text("On a schedule").tag(ScheduleKind.repeating)
                Text("After the last time").tag(ScheduleKind.afterDone)
                Text("A goal").tag(ScheduleKind.goal)
                Text("Just once").tag(ScheduleKind.once)
            }
        } footer: {
            Text(kindExplanation)
        }
    }

    @ViewBuilder
    private var scheduleSection: some View {
        switch draft.schedule.kind {
        case .repeating:
            repeatingSection
        case .afterDone:
            afterDoneSection
        case .goal:
            goalSection
        case .once:
            onceSection
        }
    }

    private var repeatingSection: some View {
        Section {
            Picker("Frequency", selection: $draft.schedule.unit) {
                Text("Hourly").tag(RepeatUnit.hour)
                Text("Daily").tag(RepeatUnit.day)
                Text("Weekly").tag(RepeatUnit.week)
                Text("Monthly").tag(RepeatUnit.month)
                Text("Yearly").tag(RepeatUnit.year)
            }
            Stepper(value: $draft.schedule.every, in: 1...maxEvery) {
                Text(Format.every(draft.schedule.every, draft.schedule.unit))
            }
            if draft.schedule.unit == .week {
                WeekdayPicker(selection: weekdaysBinding, tint: draft.color.color)
            }
            if showsStart {
                DatePicker("Starts", selection: startBinding, displayedComponents: .date)
            }
            if draft.schedule.supportsWake {
                Toggle("After I Wake Up", isOn: wakeBinding)
                if draft.schedule.afterWaking != nil {
                    wakeOffsetPicker
                }
            }
            if draft.schedule.unit == .hour {
                if draft.schedule.afterWaking == nil {
                    DatePicker("From", selection: singleTime(default: 8 * 60), displayedComponents: .hourAndMinute)
                }
                DatePicker("Until", selection: hourlyEndBinding, displayedComponents: .hourAndMinute)
            } else if draft.schedule.afterWaking == nil {
                timeRows
            }
        } footer: {
            Text(scheduleFooter)
        }
    }

    private var afterDoneSection: some View {
        Section {
            Picker("Unit", selection: $draft.schedule.unit) {
                ForEach(RepeatUnit.allCases) { unit in
                    Text(Format.unitName(unit)).tag(unit)
                }
            }
            Stepper(value: $draft.schedule.every, in: 1...maxEvery) {
                Text(Format.afterLastTime(draft.schedule.every, draft.schedule.unit))
            }
            if draft.schedule.unit == .hour {
                DatePicker("Next Time", selection: nextDueBinding, displayedComponents: [.date, .hourAndMinute])
            } else {
                DatePicker("Next Time", selection: nextDueBinding, displayedComponents: .date)
                Toggle("At a Set Time", isOn: hasTimeBinding)
                if !times.isEmpty {
                    DatePicker("Time", selection: singleTime(default: 9 * 60), displayedComponents: .hourAndMinute)
                }
            }
        } footer: {
            Text(scheduleFooter)
        }
    }

    private var goalSection: some View {
        Section {
            Stepper(value: $draft.schedule.goalCount, in: 1...99) {
                Text(Format.goal(draft.schedule.goalCount, draft.schedule.goalPeriod))
            }
            Picker("Period", selection: $draft.schedule.goalPeriod) {
                ForEach(GoalPeriod.allCases) { period in
                    Text(Format.periodName(period)).tag(period)
                }
            }
        } footer: {
            Text("Check it off each time you do it. Today shows how close you are.")
        }
    }

    private var onceSection: some View {
        Section {
            DatePicker("Date", selection: startBinding, displayedComponents: .date)
            Toggle("At a Set Time", isOn: hasTimeBinding)
            if !times.isEmpty {
                DatePicker("Time", selection: singleTime(default: 9 * 60), displayedComponents: .hourAndMinute)
            }
        } footer: {
            Text(scheduleFooter)
        }
    }

    @ViewBuilder
    private var timeRows: some View {
        ForEach(times) { row in
            HStack(spacing: 12) {
                Button {
                    withAnimation { times.removeAll { $0.id == row.id } }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Remove Time"))
                DatePicker("Time", selection: timeBinding(row.id), displayedComponents: .hourAndMinute)
            }
        }
        .onDelete { offsets in
            times.remove(atOffsets: offsets)
        }
        if times.isEmpty {
            LabeledContent("Time") {
                Text("Anytime")
            }
        }
        Button {
            withAnimation { times.append(TimeRow(minute: suggestedNewTime)) }
        } label: {
            Label("Add a Time", systemImage: "plus.circle.fill")
        }
    }

    private var wakeOffsetPicker: some View {
        let current = draft.schedule.afterWaking ?? 0
        let options = Array(Set([0, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240, 300, 360, 480, 600, current])).sorted()
        return Picker("When", selection: wakeOffsetBinding) {
            ForEach(options, id: \.self) { minutes in
                Text(wakeOffsetLabel(minutes)).tag(minutes)
            }
        }
    }

    @ViewBuilder
    private var reminderSection: some View {
        if draft.schedule.kind == .goal {
            Section {
                Toggle("Daily Nudge", isOn: goalReminderBinding)
                if draft.reminder != .off {
                    DatePicker("Time", selection: singleTime(default: 18 * 60), displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Reminder")
            } footer: {
                reminderFooter
            }
        } else {
            Section {
                Picker("Remind Me", selection: $draft.reminder) {
                    Text("Off").tag(ReminderMode.off)
                    Text(onTimeLabel).tag(ReminderMode.onTime)
                    if dayBeforeAllowed {
                        Text("The day before").tag(ReminderMode.dayBefore)
                    }
                }
            } header: {
                Text("Reminder")
            } footer: {
                reminderFooter
            }
        }
    }

    @ViewBuilder
    private var reminderFooter: some View {
        if draft.reminder != .off && store.notificationStatus == .denied {
            Text("Notifications are turned off for Routine. You can turn them on in the Settings app.")
        } else if draft.schedule.kind == .goal {
            Text("Only on days you haven’t reached your goal yet.")
        } else if draft.reminder == .dayBefore {
            Text("At the same time the day before, or at \(Format.time(9 * 60)) if there’s no time.")
        } else if draft.reminder == .onTime && !hasTime {
            Text("Things without a time are grouped into one reminder at \(Format.time(9 * 60)).")
        }
    }

    private var costSection: some View {
        Section {
            HStack(spacing: 8) {
                Text(Format.currencySymbol(store.settings.currency))
                    .foregroundStyle(.secondary)
                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)
                    .focused($focus, equals: .amount)
            }
            if parsedAmount != nil && allowsAutopay {
                Toggle("Paid Automatically", isOn: $draft.autopay)
            }
        } header: {
            Text("Cost")
        } footer: {
            if parsedAmount != nil && allowsAutopay && draft.autopay {
                Text("Counted as paid on the due date, so you don’t need to check it off.")
            } else {
                Text("Optional. Add an amount for bills and subscriptions to see them in Money.")
            }
        }
    }

    private var pauseSection: some View {
        Section {
            Toggle("Paused", isOn: $draft.paused)
        } footer: {
            Text("Paused items stay in your list but don’t show up on Today or send reminders.")
        }
    }

    @ViewBuilder
    private var historySection: some View {
        let recent = Array(draft.log.sorted { $0.at > $1.at }.prefix(5))
        if !recent.isEmpty {
            Section("Recent") {
                ForEach(recent) { entry in
                    HistoryRow(entry: entry, tint: draft.color.color, currency: store.settings.currency)
                }
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Text("Delete")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button {
                save()
            } label: {
                if request.isNew {
                    Text("Add")
                } else {
                    Text("Save")
                }
            }
            .disabled(!canSave)
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { focus = nil }
        }
    }

    // MARK: Labels

    private var heading: Text {
        let item = request.item
        if !request.isNew { return Text("Details") }
        switch item.schedule.kind {
        case .goal:
            return Text("New Goal")
        case .once:
            return Text("New Task")
        case .repeating, .afterDone:
            if item.hasCost || item.autopay || item.symbol == "doc.text.fill" {
                return Text("New Bill")
            }
            return Text("New Routine")
        }
    }

    private var kindExplanation: LocalizedStringKey {
        switch draft.schedule.kind {
        case .repeating: return "On fixed days and times, like every morning or the 1st of the month."
        case .afterDone: return "Counts from the last time you did it, like a haircut 6 weeks after the last one."
        case .goal: return "A number of times per day, week or month, whenever it suits you."
        case .once: return "Just one time. It stays on Today until it’s done."
        }
    }

    private var onTimeLabel: LocalizedStringKey {
        hasTime ? "At the time" : "In the morning"
    }

    private func wakeOffsetLabel(_ minutes: Int) -> String {
        minutes == 0 ? String(localized: "Right when I wake up") : String(localized: "\(Format.duration(minutes: minutes)) after waking")
    }

    private var scheduleFooter: String {
        let s = previewSchedule
        var text = s.summary
        if let next = nextDay(for: s) {
            text += "\n" + String(localized: "Next: \(Format.relative(next, today: Day(store.now)))")
        }
        return text
    }

    // MARK: State helpers

    private var maxEvery: Int {
        draft.schedule.kind == .repeating && draft.schedule.unit == .hour ? 12 : 99
    }

    private var showsStart: Bool {
        let s = draft.schedule
        return s.unit != .hour || s.start > Day(store.now)
    }

    private var hasTime: Bool {
        let s = draft.schedule
        switch s.kind {
        case .repeating: return s.unit == .hour || s.afterWaking != nil || !times.isEmpty
        case .afterDone: return s.unit == .hour || !times.isEmpty
        case .once, .goal: return !times.isEmpty
        }
    }

    private var dayBeforeAllowed: Bool {
        let s = draft.schedule
        switch s.kind {
        case .goal: return false
        case .repeating, .afterDone: return s.unit != .hour
        case .once: return true
        }
    }

    private var allowsAutopay: Bool {
        draft.schedule.kind == .repeating || draft.schedule.kind == .once
    }

    private var parsedAmount: Decimal? {
        guard let value = DecimalText.parse(amountText), value > 0 else { return nil }
        return value
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isDirty: Bool {
        draft != request.item
            || times.map(\.minute) != request.item.schedule.times
            || amountText != Format.editableAmount(request.item.cost)
    }

    private var suggestedNewTime: Int {
        guard let last = times.map(\.minute).max() else { return 9 * 60 }
        return min(last + 4 * 60, 22 * 60)
    }

    private var roundedNow: Int {
        min((store.now.minutesOfDay + 4) / 5 * 5, 23 * 60 + 55)
    }

    /// The schedule as it will be saved.
    private var previewSchedule: Schedule {
        var s = draft.schedule
        s.times = times.map(\.minute)
        if s.kind == .repeating && s.unit == .hour && s.afterWaking == nil && s.times.isEmpty {
            s.times = [8 * 60]
        }
        if s.kind == .afterDone && s.unit == .hour && s.nextDueTime == nil {
            s.nextDueTime = roundedNow
        }
        if s.kind == .goal && draft.reminder != .off && s.times.isEmpty {
            s.times = [18 * 60]
        }
        return s.normalized()
    }

    private func nextDay(for s: Schedule) -> Day? {
        let today = Day(store.now)
        switch s.kind {
        case .goal:
            return nil
        case .once:
            return s.start
        case .afterDone:
            return s.nextDue ?? s.start
        case .repeating:
            guard let next = s.nextOccurrence(onOrAfter: today) else { return nil }
            if next == today, s.unit != .hour, s.afterWaking == nil, let last = s.times.last,
               last < store.now.minutesOfDay, let later = s.nextOccurrence(onOrAfter: today.adding(days: 1)) {
                return later
            }
            return next
        }
    }

    private func suggestSymbol(for title: String) {
        guard !symbolTouched, let choice = Symbols.suggest(for: title) else { return }
        guard draft.symbol != choice.symbol || draft.color != choice.color else { return }
        withAnimation(.snappy) {
            draft.symbol = choice.symbol
            draft.color = choice.color
        }
    }

    /// Keeps the draft sensible when the kind, unit or interval changes.
    private func keepConsistent() {
        let s = draft.schedule
        if s.kind == .repeating && s.unit == .hour && s.every > 12 {
            draft.schedule.every = 12
        }
        if s.unit == .week && s.weekdays.isEmpty {
            draft.schedule.weekdays = [s.start.weekday]
        }
        if s.kind == .afterDone {
            if s.nextDue == nil { draft.schedule.nextDue = Day(store.now) }
            if s.unit == .hour && s.nextDueTime == nil { draft.schedule.nextDueTime = roundedNow }
        }
        if !draft.schedule.supportsWake && draft.schedule.afterWaking != nil {
            draft.schedule.afterWaking = nil
        }
        if draft.reminder == .dayBefore && !dayBeforeAllowed {
            draft.reminder = .onTime
        }
    }

    private func save() {
        var item = draft
        item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.notes = item.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        item.schedule = previewSchedule
        item.cost = parsedAmount
        if item.cost == nil { item.autopay = false }
        if item.reminder == .dayBefore && !dayBeforeAllowed { item.reminder = .onTime }
        let today = Day(Date())
        if request.isNew {
            item.createdAt = Date()
            item.trackFrom = today
        } else if item.schedule != request.item.schedule {
            // A new schedule starts fresh: nothing from before today shows up as missed.
            item.trackFrom = today
            item.snoozes = []
        }
        store.save(item)
        if item.reminder != .off { store.askForNotificationsIfNeeded() }
        dismiss()
    }

    // MARK: Bindings

    private var startBinding: Binding<Date> {
        Binding(
            get: { draft.schedule.start.noon },
            set: { value in
                let day = Day(value)
                let oldWeekday = draft.schedule.start.weekday
                draft.schedule.start = day
                // A weekly routine that only had the old start day follows the new one.
                if draft.schedule.unit == .week && draft.schedule.weekdays == [oldWeekday] {
                    draft.schedule.weekdays = [day.weekday]
                }
            }
        )
    }

    private var weekdaysBinding: Binding<[Int]> {
        Binding(
            get: { draft.schedule.effectiveWeekdays },
            set: { draft.schedule.weekdays = $0.sorted() }
        )
    }

    private var wakeBinding: Binding<Bool> {
        Binding(
            get: { draft.schedule.afterWaking != nil },
            set: { on in draft.schedule.afterWaking = on ? (draft.schedule.afterWaking ?? 0) : nil }
        )
    }

    private var wakeOffsetBinding: Binding<Int> {
        Binding(
            get: { draft.schedule.afterWaking ?? 0 },
            set: { draft.schedule.afterWaking = $0 }
        )
    }

    private var hourlyEndBinding: Binding<Date> {
        Binding(
            get: { Day.today.date(minutes: draft.schedule.hourlyEnd) },
            set: { draft.schedule.hourlyEnd = $0.minutesOfDay }
        )
    }

    private var nextDueBinding: Binding<Date> {
        Binding(
            get: {
                let s = draft.schedule
                return (s.nextDue ?? s.start).date(minutes: s.nextDueTime ?? 9 * 60)
            },
            set: { value in
                draft.schedule.nextDue = Day(value)
                draft.schedule.nextDueTime = draft.schedule.unit == .hour ? value.minutesOfDay : nil
            }
        )
    }

    private var hasTimeBinding: Binding<Bool> {
        Binding(
            get: { !times.isEmpty },
            set: { on in
                if on {
                    if times.isEmpty { times = [TimeRow(minute: 9 * 60)] }
                } else {
                    times = []
                }
            }
        )
    }

    private var goalReminderBinding: Binding<Bool> {
        Binding(
            get: { draft.reminder != .off },
            set: { on in
                draft.reminder = on ? .onTime : .off
                if on && times.isEmpty { times = [TimeRow(minute: 18 * 60)] }
            }
        )
    }

    /// The first time, created on demand. Never indexes into an empty list.
    private func singleTime(default minute: Int) -> Binding<Date> {
        Binding(
            get: { times.first?.date ?? Day.today.date(minutes: minute) },
            set: { value in
                if times.isEmpty {
                    times = [TimeRow(date: value)]
                } else {
                    times[0].date = value
                }
            }
        )
    }

    private func timeBinding(_ id: UUID) -> Binding<Date> {
        Binding(
            get: { times.first(where: { $0.id == id })?.date ?? Date() },
            set: { value in
                if let index = times.firstIndex(where: { $0.id == id }) {
                    times[index].date = value
                }
            }
        )
    }
}

// MARK: - History row

private struct HistoryRow: View {
    var entry: LogEntry
    var tint: Color
    var currency: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.kind == .done ? "checkmark.circle.fill" : "arrow.uturn.forward.circle")
                .font(.title3)
                .foregroundStyle(entry.kind == .done ? tint : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                if entry.kind == .done {
                    Text("Done")
                } else {
                    Text("Skipped")
                }
                Text(entry.at.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let amount = entry.amount {
                Text(Format.money(amount, code: currency))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Icon and color

struct SymbolPicker: View {
    @Binding var symbol: String
    @Binding var color: ItemColor
    @Binding var touched: Bool

    private let columns = [GridItem(.adaptive(minimum: 48), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Spacer()
                    SymbolTile(symbol: symbol, color: color.color, size: 72)
                    Spacer()
                }
                .padding(.top, 8)
                .accessibilityHidden(true)

                Text("Color")
                    .font(.headline)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(ItemColor.allCases) { option in
                        Button {
                            color = option
                            touched = true
                        } label: {
                            Circle()
                                .fill(option.color.gradient)
                                .frame(width: 34, height: 34)
                                .overlay {
                                    if option == color {
                                        Circle()
                                            .strokeBorder(Color.primary, lineWidth: 2)
                                            .frame(width: 44, height: 44)
                                    }
                                }
                                .frame(width: 48, height: 48)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(option.name))
                        .accessibilityAddTraits(option == color ? .isSelected : [])
                    }
                }

                Text("Icon")
                    .font(.headline)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Symbols.all, id: \.self) { name in
                        Button {
                            symbol = name
                            touched = true
                        } label: {
                            Image(systemName: name)
                                .font(.title3)
                                .foregroundStyle(name == symbol ? Color.white : Color.primary)
                                .frame(width: 48, height: 48)
                                .background(name == symbol ? color.color : Color(uiColor: .secondarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(name == symbol ? .isSelected : [])
                    }
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Icon and Color")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Weekdays

struct WeekdayPicker: View {
    @Binding var selection: [Int]
    var tint: Color

    var body: some View {
        let calendar = RoutineCalendar.current
        let letters = calendar.veryShortWeekdaySymbols
        let names = calendar.weekdaySymbols
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        HStack(spacing: 6) {
            ForEach(order, id: \.self) { day in
                let on = selection.contains(day)
                Button {
                    toggle(day)
                } label: {
                    Text(letters[day - 1])
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(on ? tint : Color(uiColor: .tertiarySystemFill), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(names[day - 1]))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private func toggle(_ day: Int) {
        if let index = selection.firstIndex(of: day) {
            // Keep at least one day.
            if selection.count > 1 { selection.remove(at: index) }
        } else {
            selection.append(day)
            selection.sort()
        }
    }
}
