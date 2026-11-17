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

/// Add or edit a task or a bill. Nothing is saved until you tap Add or Save.
/// Tasks get the full schedule (times, wake-up, after the last time) and a reminder by default.
/// Bills get an amount, a due date and a payment choice, and no reminder until you turn one on.
struct EditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let request: EditorRequest

    @State private var draft: Item
    /// The item as it opened, to tell whether anything changed.
    @State private var baseline: Item
    @State private var amountText: String
    @State private var times: [TimeRow]
    @State private var confirmDelete = false
    @State private var showsWakeWheel = false
    /// "Check Off When Paid" was turned off because the bill became daily, not by you.
    @State private var autopayFromDaily = false
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case title, amount
    }

    /// What a bill's Repeats menu shows. Any-day bills show as their week or month.
    private enum BillRepeat: Hashable {
        case day, week, month, year, afterDone, once
    }

    init(request: EditorRequest) {
        self.request = request
        var item = request.item
        if !request.isBill && item.schedule.kind == .afterDone && item.schedule.unit == .hour {
            item.schedule.kind = .repeating
            item.schedule.fromDone = true
            if let minute = item.schedule.nextDueTime { item.schedule.times = [minute] }
            item.schedule.nextDue = nil
            item.schedule.nextDueTime = nil
        }
        if request.isBill {
            if request.isNew { item.reminder = .dayBefore }
            // Bills fall on a day: no wake-ups, and no times except an any-day bill's reminder and
            // a daily bill's set time.
            item.schedule.afterWaking = nil
            if item.schedule.kind == .repeating && item.schedule.unit == .hour { item.schedule.unit = .day }
            let daily = item.schedule.kind == .repeating && item.schedule.unit == .day && item.schedule.every == 1
            if item.schedule.kind != .goal && !daily { item.schedule.times = [] }
        }
        _draft = State(initialValue: item)
        _baseline = State(initialValue: item)
        _amountText = State(initialValue: Format.editableAmount(item.cost))
        _times = State(initialValue: item.schedule.times.map { TimeRow(minute: $0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                if request.isBill {
                    dueSection
                    if allowsAutopay {
                        paymentSection
                    }
                    if draft.schedule.kind == .goal {
                        Section { Text("Counted in your totals. It doesn’t show on Today or send reminders.") }
                    } else if !paidAutomatically && (!isDailyBill || !times.isEmpty) {
                        billReminderSection
                    }
                } else {
                    scheduleSection
                    reminderSection
                }
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
            .onChange(of: draft.reminder) { _, mode in
                if draft.schedule.kind == .goal && mode != .off && times.isEmpty {
                    times = [TimeRow(minute: eveningMinute)]
                }
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
                startOnLivingDay()
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
            TextField("Name", text: $draft.title)
                .font(.headline)
                .focused($focus, equals: .title)
                .submitLabel(request.isBill ? SubmitLabel.next : SubmitLabel.done)
                .onSubmit {
                    if request.isBill && amountText.isEmpty {
                        focus = .amount
                    } else {
                        focus = nil
                    }
                }
            if request.isBill {
                amountRow
            }
            TextField("Notes", text: $draft.notes, axis: .vertical)
                .lineLimit(1...6)
        }
    }

    /// Bills only: how much it is, in the currency chosen in Settings.
    private var amountRow: some View {
        HStack(spacing: 8) {
            Text(verbatim: Format.currencySymbol(store.settings.currency))
                .foregroundStyle(Color.secondary)
            TextField("Amount", text: $amountText)
                .keyboardType(.decimalPad)
                .focused($focus, equals: .amount)
        }
    }

    private var typePicker: some View {
        Picker("Type", selection: kindBinding) {
            Text("Repeating").tag(ScheduleKind.repeating)
            Text("Just once").tag(ScheduleKind.once)
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var scheduleSection: some View {
        switch draft.schedule.kind {
        case .repeating, .goal:
            repeatingSection
        case .afterDone:
            afterDoneSection
        case .once:
            onceSection
        }
    }

    /// Fixed days and times, or "any day" of the week or month (saved as a count per week or month).
    private var repeatingSection: some View {
        Section {
            typePicker
            Picker("Repeats", selection: frequencyBinding) {
                Text("Hourly").tag(RepeatUnit.hour)
                Text("Daily").tag(RepeatUnit.day)
                Text("Weekly").tag(RepeatUnit.week)
                Text("Monthly").tag(RepeatUnit.month)
                Text("Yearly").tag(RepeatUnit.year)
            }
            if frequency == .week || frequency == .month {
                Picker("Day", selection: anyDayBinding) {
                    Text(setDayLabel).tag(false)
                    Text("Any Day").tag(true)
                }
                .pickerStyle(.segmented)
            }
            if draft.schedule.kind == .goal {
                Stepper(value: $draft.schedule.goalCount, in: 1...99) {
                    Text(Format.goal(draft.schedule.goalCount, draft.schedule.goalPeriod))
                }
            } else {
                fixedRows
            }
        } footer: {
            Text(scheduleFooter)
        }
    }

    @ViewBuilder
    private var fixedRows: some View {
        Stepper(value: $draft.schedule.every, in: 1...maxEvery) {
            Text(Format.every(draft.schedule.every, draft.schedule.unit))
        }
        Toggle(isOn: repeatAfterBinding) {
            VStack(alignment: .leading) {
                Text("Repeat After Completion")
                if draft.schedule.unit == .hour {
                    Text("Next time is based on when you finish")
                        .font(.caption).foregroundStyle(Color.secondary)
                } else {
                    Text("Next date is based on completion")
                        .font(.caption).foregroundStyle(Color.secondary)
                }
            }
        }
        if draft.schedule.unit == .week {
            WeekdayPicker(selection: weekdaysBinding, tint: .accentColor)
        }
        if draft.schedule.unit == .month {
            monthDayPicker
        }
        if showsStart {
            DatePicker("Starting", selection: startBinding, displayedComponents: .date)
        }
        if draft.schedule.supportsWake {
            Toggle("After I Wake Up", isOn: wakeBinding)
            if draft.schedule.afterWaking != nil {
                wakeOffsetRow
                if showsWakeWheel {
                    wakeWheel
                }
            }
        }
        if draft.schedule.unit == .hour {
            // Hourly things keep going until your day ends, so there's no end time.
            if draft.schedule.afterWaking == nil {
                DatePicker("From", selection: singleTime(default: SleepCheck.usualWake(store.sleepLog)), displayedComponents: .hourAndMinute)
            }
        } else if draft.schedule.afterWaking == nil {
            timeRows
        }
    }

    private var afterDoneSection: some View {
        Section {
            typePicker
            Picker("Repeats", selection: frequencyBinding) {
                Text("Hourly").tag(RepeatUnit.hour)
                Text("Daily").tag(RepeatUnit.day)
                Text("Weekly").tag(RepeatUnit.week)
                Text("Monthly").tag(RepeatUnit.month)
                Text("Yearly").tag(RepeatUnit.year)
            }
            Stepper(value: $draft.schedule.every, in: 1...maxEvery) {
                Text(Format.every(draft.schedule.every, draft.schedule.unit))
            }
            Toggle(isOn: repeatAfterBinding) {
                VStack(alignment: .leading) {
                    Text("Repeat After Completion")
                    Text("Next date is based on completion")
                        .font(.caption).foregroundStyle(Color.secondary)
                }
            }
            DatePicker("Next One", selection: nextDueBinding, displayedComponents: .date)
            Toggle("At a Set Time", isOn: hasTimeBinding)
            if !times.isEmpty {
                DatePicker("At", selection: singleTime(default: 9 * 60), displayedComponents: .hourAndMinute)
            }
        } footer: {
            Text(scheduleFooter)
        }
    }

    private var onceSection: some View {
        Section {
            typePicker
            DatePicker("Date", selection: startBinding, displayedComponents: .date)
            Toggle("At a Set Time", isOn: hasTimeBinding)
            if !times.isEmpty {
                DatePicker("At", selection: singleTime(default: 9 * 60), displayedComponents: .hourAndMinute)
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
                DatePicker("At", selection: timeBinding(row.id), displayedComponents: .hourAndMinute)
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

    /// "6 min after waking". Tap to pick the exact number of minutes.
    private var wakeOffsetRow: some View {
        Button {
            withAnimation(.snappy) { showsWakeWheel.toggle() }
        } label: {
            LabeledContent {
                Text(verbatim: wakeOffsetLabel(draft.schedule.afterWaking ?? 0))
                    .foregroundStyle(showsWakeWheel ? Color.accentColor : Color.secondary)
            } label: {
                Text(wakeRowTitle)
                    .foregroundStyle(Color.primary)
            }
        }
    }

    private var wakeWheel: some View {
        Picker("Time After Waking", selection: wakeOffsetBinding) {
            ForEach(wakeOffsetChoices, id: \.self) { minutes in
                Text(verbatim: wakeChoiceLabel(minutes)).tag(minutes)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
    }

    @ViewBuilder
    private var reminderSection: some View {
        if draft.schedule.kind == .goal {
            Section {
                Picker("Remind Me", selection: $draft.reminder) {
                    Text("Off").tag(ReminderMode.off)
                    Text("When I’m Behind").tag(ReminderMode.whenBehind)
                    Text("Every Day").tag(ReminderMode.onTime)
                }
                if draft.reminder != .off {
                    DatePicker("At", selection: singleTime(default: eveningMinute), displayedComponents: .hourAndMinute)
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
        } else if draft.schedule.kind == .goal && draft.reminder == .whenBehind {
            Text("At this time, only on days you’re behind.")
        } else if draft.schedule.kind == .goal && draft.reminder == .onTime {
            Text("Once a day at this time, until it’s done.")
        } else if draft.reminder == .dayBefore {
            Text("At the same time the day before, or at \(Format.time(9 * 60)) if there’s no time.")
        } else if draft.reminder == .onTime && !hasTime {
            Text("Things without a time are grouped into one reminder at \(Format.time(9 * 60)).")
        }
    }

    private var monthDayPicker: some View {
        Picker("On the", selection: monthDayBinding) {
            ForEach(1...31, id: \.self) { day in
                Text(verbatim: Format.ordinal(day)).tag(day)
            }
        }
    }

    // MARK: Bill sections

    /// When a bill is due. Bills fall on a day, so there are no times or wake-ups.
    private var dueSection: some View {
        Section {
            Picker("Repeats", selection: billRepeatBinding) {
                Text("Every day").tag(BillRepeat.day)
                Text("Every week").tag(BillRepeat.week)
                Text("Every month").tag(BillRepeat.month)
                Text("Every year").tag(BillRepeat.year)
                Text("Just once").tag(BillRepeat.once)
            }
            dueRows
        } header: {
            Text("Due")
        } footer: {
            Text(scheduleFooter)
        }
    }

    @ViewBuilder
    private var dueRows: some View {
        switch draft.schedule.kind {
        case .once:
            DatePicker("Due Date", selection: startBinding, displayedComponents: .date)
        case .afterDone:
            Stepper(value: $draft.schedule.every, in: 1...maxEvery) {
                Text(Format.every(draft.schedule.every, draft.schedule.unit))
            }
            repeatAfterPaymentToggle
            DatePicker("Next Due Date", selection: nextDueBinding, displayedComponents: .date)
        case .repeating, .goal:
            if frequency == .week || frequency == .month {
                Picker("Day", selection: anyDayBinding) {
                    Text(setDayLabel).tag(false)
                    Text("Any Day").tag(true)
                }
                .pickerStyle(.segmented)
            }
            if draft.schedule.kind == .goal {
                Stepper(value: $draft.schedule.goalCount, in: 1...99) {
                    Text(Format.goal(draft.schedule.goalCount, draft.schedule.goalPeriod))
                }
            } else {
                Stepper(value: $draft.schedule.every, in: 1...maxEvery) {
                    Text(Format.every(draft.schedule.every, draft.schedule.unit))
                }
                if !draft.autopay {
                    repeatAfterPaymentToggle
                }
                if draft.schedule.unit == .week {
                    WeekdayPicker(selection: weekdaysBinding, tint: .accentColor)
                }
                if draft.schedule.unit == .month {
                    monthDayPicker
                }
                DatePicker("Starting", selection: startBinding, displayedComponents: .date)
                if isDailyBill && !draft.autopay {
                    Toggle("At a Set Time", isOn: hasTimeBinding)
                    if !times.isEmpty {
                        DatePicker("At", selection: singleTime(default: 9 * 60), displayedComponents: .hourAndMinute)
                    }
                }
            }
        }
    }

    /// The next due date counts from when you pay, like tasks that repeat after completion.
    private var repeatAfterPaymentToggle: some View {
        Toggle(isOn: repeatAfterBinding) {
            VStack(alignment: .leading) {
                Text("Repeat After Payment")
                Text("Next due date is based on when you pay")
                    .font(.caption).foregroundStyle(Color.secondary)
            }
        }
    }

    /// A bill due every day. A reminder only makes sense at a set time of day.
    private var isDailyBill: Bool {
        let s = draft.schedule
        return request.isBill && s.kind == .repeating && s.unit == .day && s.every == 1
    }

    /// Bills on set dates: paid by hand (it shows on Today) or automatically (nothing to do, no reminder).
    private var paymentSection: some View {
        Section {
            Toggle("Check Off When Paid", isOn: checkOffBinding)
        } footer: {
            Text(paymentFooter)
        }
    }

    /// Off for new bills, but always shown when you pay it yourself, so it's clear a reminder is there.
    private var billReminderSection: some View {
        Section {
            Toggle("Remind Me", isOn: billReminderBinding)
            if draft.reminder != .off && !isDailyBill {
                if draft.schedule.kind == .goal {
                    DatePicker("At", selection: singleTime(default: eveningMinute), displayedComponents: .hourAndMinute)
                } else {
                    Picker("When", selection: $draft.reminder) {
                        if dayBeforeAllowed {
                            Text("The day before").tag(ReminderMode.dayBefore)
                        }
                        Text("On the due date").tag(ReminderMode.onTime)
                    }
                }
            }
        } header: {
            Text("Reminder")
        } footer: {
            Text(billReminderFooter)
        }
    }

    private var billReminderFooter: String {
        if draft.reminder != .off && store.notificationStatus == .denied {
            return String(localized: "Notifications are turned off for Routine. You can turn them on in the Settings app.")
        }
        switch draft.reminder {
        case .off:
            return String(localized: "Turn it on to get a notification before it’s due.")
        case .dayBefore:
            return String(localized: "You’ll get a notification at \(Format.time(9 * 60)) the day before it’s due.")
        case .whenBehind:
            return String(localized: "At this time, only on days you’re behind.")
        case .onTime:
            if draft.schedule.kind == .goal {
                return String(localized: "Once a day at this time, until it’s done.")
            }
            if isDailyBill, let minute = times.first?.minute {
                let time = Format.time(minute)
                return String(localized: "You’ll get a notification every day at \(time).")
            }
            return String(localized: "You’ll get a notification at \(Format.time(9 * 60)) on the due date.")
        }
    }

    // MARK: More sections

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
                    HistoryRow(entry: entry, currency: store.settings.currency, showsAmount: request.isBill)
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
        if !request.isNew { return Text("Details") }
        return request.isBill ? Text("New Bill") : Text("New Task")
    }

    private var kindExplanation: LocalizedStringKey {
        switch draft.schedule.kind {
        case .repeating: return "On fixed days and times, like every morning or the 1st of the month."
        case .goal: return "A number of times per day, week or month, whenever it suits you."
        case .afterDone: return "Counts from the last time you did it, like a haircut 6 weeks after the last one."
        case .once: return "Just one time. It stays on Today until it’s done."
        }
    }

    private var setDayLabel: LocalizedStringKey {
        frequency == .week ? "Specific Days" : "Specific Day"
    }

    private var wakeRowTitle: LocalizedStringKey {
        draft.schedule.unit == .hour ? "First One" : "When"
    }

    private var paymentFooter: LocalizedStringKey {
        if draft.autopay { return "Counted in your totals on each date, with nothing to check off. Good for subscriptions and things you buy all the time, like coffee." }
        return "It shows on Today when it’s due. Check it off once you’ve paid."
    }

    /// "Check Off When Paid" is the opposite of counting it automatically.
    private var checkOffBinding: Binding<Bool> {
        Binding(
            get: { !draft.autopay },
            set: { on in
                draft.autopay = !on
                autopayFromDaily = false
            }
        )
    }

    /// For "any day" reminders: in your evening, 4 hours before your day usually ends, 5 to 10 PM.
    private var eveningMinute: Int {
        let end = SleepCheck.usualWake(store.sleepLog) + SleepCheck.usualDay(store.sleepLog) - 240
        return min(max(end, 17 * 60), 22 * 60)
    }

    private var onTimeLabel: LocalizedStringKey {
        hasTime ? "At the time" : "In the morning"
    }

    private func wakeOffsetLabel(_ minutes: Int) -> String {
        minutes == 0 ? String(localized: "Right when I wake up") : String(localized: "\(Format.duration(minutes: minutes)) after waking")
    }

    private func wakeChoiceLabel(_ minutes: Int) -> String {
        minutes == 0 ? String(localized: "Right away") : Format.duration(minutes: minutes)
    }

    private var scheduleFooter: String {
        let s = previewSchedule
        var text = s.summary
        if s.kind == .goal {
            text += "\n" + flexibleNote(s.goalPeriod)
        } else if let next = nextDay(for: s) {
            text += "\n" + String(localized: "Next: \(Format.relative(next, today: livingDay))")
        }
        if s.isHourly {
            text += "\n" + String(localized: "It repeats all day, until you go to sleep.")
        }
        return text
    }

    /// The day you're living for tasks (still yesterday after midnight if you haven't slept),
    /// the calendar day for bills.
    private var livingDay: Day {
        request.isBill ? Day(store.now) : store.clock.day
    }

    /// Minutes since the start of `livingDay`; past 24 hours after midnight.
    private var livingMinute: Int {
        request.isBill ? store.now.minutesOfDay : store.clock.minute
    }

    private func flexibleNote(_ period: GoalPeriod) -> String {
        switch period {
        case .day: return String(localized: "It stays on Today until it’s done for the day.")
        case .week: return String(localized: "It stays on Today until it’s done for the week.")
        case .month: return String(localized: "It stays on Today until it’s done for the month.")
        }
    }

    // MARK: State helpers

    private var maxEvery: Int {
        draft.schedule.kind == .repeating && draft.schedule.unit == .hour ? 12 : 99
    }

    /// What the Frequency picker shows. "Any day" items are counted per day, week or month.
    private var frequency: RepeatUnit {
        let s = draft.schedule
        guard s.kind == .goal else { return s.unit }
        switch s.goalPeriod {
        case .day: return .day
        case .week: return .week
        case .month: return .month
        }
    }

    private var showsStart: Bool {
        let s = draft.schedule
        return s.unit != .hour || s.start > livingDay
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
        case .repeating, .afterDone: return s.unit != .hour && !(s.unit == .day && s.every == 1)
        case .once: return true
        }
    }

    /// Automatic payments need a date, so not for "after the last time" or "any day".
    private var allowsAutopay: Bool {
        draft.schedule.kind == .repeating || draft.schedule.kind == .once
    }

    /// A bill that's paid automatically: nothing to check off and no reminders.
    private var paidAutomatically: Bool {
        request.isBill && draft.autopay && allowsAutopay
    }

    private var parsedAmount: Decimal? {
        guard let value = DecimalText.parse(amountText), value > 0 else { return nil }
        return value
    }

    private var canSave: Bool {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return !request.isBill || parsedAmount != nil
    }

    private var isDirty: Bool {
        draft != baseline
            || times.map(\.minute) != baseline.schedule.times
            || amountText != Format.editableAmount(baseline.cost)
    }

    private var suggestedNewTime: Int {
        guard let last = times.map(\.minute).max() else { return 9 * 60 }
        return min(last + 4 * 60, 22 * 60)
    }

    private var roundedNow: Int {
        min((store.now.minutesOfDay + 4) / 5 * 5, 23 * 60 + 55)
    }

    /// Every minute for the first two hours, then every 5 and every 15 minutes.
    private var wakeOffsetChoices: [Int] {
        var choices = Array(0...120)
        choices.append(contentsOf: stride(from: 125, through: 600, by: 5))
        choices.append(contentsOf: stride(from: 615, through: 18 * 60, by: 15))
        let current = draft.schedule.afterWaking ?? 0
        if !choices.contains(current) {
            choices.append(current)
            choices.sort()
        }
        return choices
    }

    /// The schedule as it will be saved.
    private var previewSchedule: Schedule {
        var s = draft.schedule
        s.times = times.map(\.minute)
        if request.isBill {
            // Bills fall on a day. An any-day bill keeps a time only for its reminder.
            s.afterWaking = nil
            if s.kind != .goal && s.unit == .hour { s.unit = .day }
            if s.kind == .repeating && s.unit == .day && s.every == 1 && !draft.autopay {
                // A daily bill you check off can have a time, for its reminder and to show when it's due.
                s.times = Array(s.times.prefix(1))
            } else if s.kind != .goal {
                s.times = []
            }
        }
        if s.kind == .repeating && s.unit == .hour && s.afterWaking == nil && s.times.isEmpty {
            // Not from waking: starts at the time you usually get up.
            s.times = [SleepCheck.usualWake(store.sleepLog)]
        }
        if s.kind == .afterDone && s.unit == .hour && s.nextDueTime == nil {
            s.nextDueTime = roundedNow
        }
        if s.kind == .goal && draft.reminder != .off && s.times.isEmpty {
            s.times = [eveningMinute]
        }
        return s.normalized()
    }

    private func nextDay(for s: Schedule) -> Day? {
        let today = livingDay
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
               last < livingMinute, let later = s.nextOccurrence(onOrAfter: today.adding(days: 1)) {
                return later
            }
            return next
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
            if s.nextDue == nil { draft.schedule.nextDue = livingDay }
            if s.unit == .hour && s.nextDueTime == nil { draft.schedule.nextDueTime = roundedNow }
        }
        if !draft.schedule.supportsWake && draft.schedule.afterWaking != nil {
            draft.schedule.afterWaking = nil
        }
        if draft.schedule.afterWaking == nil {
            showsWakeWheel = false
        }
        if draft.reminder == .dayBefore && !dayBeforeAllowed {
            draft.reminder = .onTime
        }
        // "When I'm behind" only makes sense for any-day goals.
        if draft.reminder == .whenBehind && draft.schedule.kind != .goal {
            draft.reminder = .onTime
        }
    }

    /// Still up after midnight: a new task starts on the day you're living, not the new calendar day.
    private func startOnLivingDay() {
        guard request.isNew, !request.isBill else { return }
        let day = store.clock.day
        guard draft.schedule.start == Day(Date()), day < draft.schedule.start else { return }
        draft.schedule.start = day
        baseline.schedule.start = day
    }

    /// Leaving "any day": the reminder comes back the way it was. A bill's stays off unless it had one.
    private func restoreReminder() {
        guard draft.reminder == .off || draft.reminder == .whenBehind else { return }
        let original = baseline
        if original.schedule.kind == .goal || original.reminder == .whenBehind {
            draft.reminder = request.isBill ? .off : .onTime
        } else {
            draft.reminder = original.reminder
        }
    }

    private func save() {
        var item = draft
        item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.notes = item.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        item.schedule = previewSchedule
        item.cost = request.isBill ? parsedAmount : nil
        if item.cost == nil || !allowsAutopay { item.autopay = false }
        // Paid automatically: there's nothing to be reminded of.
        if item.isAutopay || item.isAnyDayBill { item.reminder = .off }
        // A daily bill only reminds you at the time you set.
        if isDailyBill && times.isEmpty { item.reminder = .off }
        if item.reminder == .dayBefore && !dayBeforeAllowed { item.reminder = .onTime }
        let today = livingDay
        if request.isNew {
            item.createdAt = Date()
            item.trackFrom = today
        } else if item.schedule != baseline.schedule {
            // A new schedule starts fresh: nothing from before today shows up as missed.
            item.trackFrom = today
            item.snoozes = []
        }
        store.save(item)
        if item.reminder != .off { store.askForNotificationsIfNeeded() }
        dismiss()
    }

    // MARK: Bindings

    /// "Any day" items are shown as "On a schedule" with Any Day picked.
    private var kindBinding: Binding<ScheduleKind> {
        Binding(
            get: { draft.schedule.kind == .once ? .once : .repeating },
            set: { kind in
                let wasAnyDay = draft.schedule.kind == .goal
                if kind == .repeating && wasAnyDay { return }
                draft.schedule.kind = kind
                if kind == .repeating { draft.schedule.fromDone = false }
                if wasAnyDay { restoreReminder() }
            }
        )
    }

    private var frequencyBinding: Binding<RepeatUnit> {
        Binding(
            get: { frequency },
            set: { unit in
                guard unit != frequency else { return }
                if draft.schedule.kind == .goal {
                    if unit == .week || unit == .month {
                        // Still any day, now counted per week or month.
                        draft.schedule.goalPeriod = unit == .week ? .week : .month
                        return
                    }
                    draft.schedule.kind = .repeating
                    restoreReminder()
                }
                if draft.schedule.kind == .afterDone && unit == .hour {
                    draft.schedule.kind = .repeating
                    draft.schedule.fromDone = true
                } else if draft.schedule.kind == .repeating && draft.schedule.fromDone && unit != .hour {
                    // Leaving hourly keeps "repeat after completion" on, counted in days instead.
                    draft.schedule.kind = .afterDone
                    draft.schedule.fromDone = false
                    if draft.schedule.nextDue == nil { draft.schedule.nextDue = livingDay }
                }
                draft.schedule.unit = unit
                // Like Routine always did: hourly things start when you wake up, not at a set hour.
                if unit == .hour && draft.schedule.afterWaking == nil && !request.isBill {
                    draft.schedule.afterWaking = 0
                }
            }
        )
    }

    private var repeatAfterBinding: Binding<Bool> {
        Binding(
            get: { draft.schedule.kind == .afterDone || draft.schedule.fromDone },
            set: { on in
                if draft.schedule.unit == .hour {
                    draft.schedule.kind = .repeating
                    draft.schedule.fromDone = on
                } else if on {
                    let next = previewSchedule.nextOccurrence(onOrAfter: livingDay) ?? livingDay
                    draft.schedule.kind = .afterDone
                    draft.schedule.nextDue = next
                } else {
                    draft.schedule.kind = .repeating
                    draft.schedule.fromDone = false
                    draft.schedule.start = draft.schedule.nextDue ?? livingDay
                }
            }
        )
    }

    private var anyDayBinding: Binding<Bool> {
        Binding(
            get: { draft.schedule.kind == .goal },
            set: { anyDay in
                guard anyDay != (draft.schedule.kind == .goal) else { return }
                let unit = frequency
                if anyDay {
                    let s = draft.schedule
                    let original = baseline
                    let period: GoalPeriod = unit == .month ? .month : .week
                    draft.schedule.kind = .goal
                    draft.schedule.goalPeriod = period
                    if original.schedule.kind == .goal && original.schedule.goalPeriod == period {
                        draft.schedule.goalCount = original.schedule.goalCount
                    } else {
                        draft.schedule.goalCount = unit == .week && s.every == 1 ? s.effectiveWeekdays.count : 1
                    }
                    // A daily nudge is opt-in for things that can happen any day.
                    draft.reminder = original.schedule.kind == .goal ? original.reminder : (request.isBill ? .off : .whenBehind)
                    if draft.reminder != .off && times.isEmpty { times = [TimeRow(minute: eveningMinute)] }
                } else {
                    draft.schedule.kind = .repeating
                    draft.schedule.unit = unit
                    restoreReminder()
                }
            }
        )
    }

    private var billRepeat: BillRepeat {
        switch draft.schedule.kind {
        case .once: return .once
        case .afterDone, .repeating, .goal:
            switch frequency {
            case .hour, .day: return .day
            case .week: return .week
            case .month: return .month
            case .year: return .year
            }
        }
    }

    private var billRepeatBinding: Binding<BillRepeat> {
        Binding(
            get: { billRepeat },
            set: { choice in
                guard choice != billRepeat else { return }
                switch choice {
                case .once:
                    draft.schedule.kind = .once
                    if autopayFromDaily {
                        draft.autopay = false
                        autopayFromDaily = false
                    }
                case .afterDone: draft.schedule.kind = .afterDone
                case .day: setBillUnit(.day)
                case .week: setBillUnit(.week)
                case .month: setBillUnit(.month)
                case .year: setBillUnit(.year)
                }
            }
        )
    }

    /// An any-day bill stays any day when it moves between weekly and monthly.
    private func setBillUnit(_ unit: RepeatUnit) {
        if draft.schedule.kind == .goal && (unit == .week || unit == .month) {
            draft.schedule.goalPeriod = unit == .week ? .week : .month
            return
        }
        if draft.schedule.kind == .afterDone {
            // Still repeating after payment, now counted in the new unit.
            draft.schedule.unit = unit
        } else {
            draft.schedule.kind = .repeating
            draft.schedule.unit = unit
        }
        // Every day with no set time: it's usually counted automatically, so that's the default.
        if unit == .day && draft.schedule.kind == .repeating && draft.schedule.every == 1 && times.isEmpty && !draft.autopay {
            draft.autopay = true
            autopayFromDaily = true
        } else if unit != .day && autopayFromDaily {
            draft.autopay = false
            autopayFromDaily = false
        }
    }

    /// Turning a bill's reminder on picks the day before (or a daily nudge for an any-day bill).
    private var billReminderBinding: Binding<Bool> {
        Binding(
            get: { draft.reminder != .off },
            set: { on in
                if !on {
                    draft.reminder = .off
                } else if draft.schedule.kind == .goal {
                    draft.reminder = .onTime
                    if times.isEmpty { times = [TimeRow(minute: eveningMinute)] }
                } else {
                    draft.reminder = dayBeforeAllowed ? .dayBefore : .onTime
                }
            }
        )
    }

    /// Picking a day of the month moves the start to the next date on that day.
    private var monthDayBinding: Binding<Int> {
        Binding(
            get: { draft.schedule.start.day },
            set: { day in
                let start = draft.schedule.start
                draft.schedule.start = Day.firstDate(onDay: day, from: start, notBefore: min(start, livingDay))
            }
        )
    }

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
            set: { on in
                draft.schedule.afterWaking = on ? (draft.schedule.afterWaking ?? 0) : nil
                // Turning it on goes straight to choosing how long after.
                showsWakeWheel = on
            }
        )
    }

    private var wakeOffsetBinding: Binding<Int> {
        Binding(
            get: { draft.schedule.afterWaking ?? 0 },
            set: { draft.schedule.afterWaking = $0 }
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
                draft.schedule.nextDueTime = nil
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
                if on && times.isEmpty { times = [TimeRow(minute: eveningMinute)] }
            }
        )
    }

    /// The first time, created on demand. Never indexes into an empty list.
    private func singleTime(default minute: Int) -> Binding<Date> {
        Binding(
            get: { times.first?.date ?? Day.today.date(minutes: minute) },
            set: { value in
                if draft.schedule.kind == .afterDone { draft.schedule.nextDueTime = nil }
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
    var currency: String
    /// Only bills show what was paid.
    var showsAmount: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.kind == .done ? "checkmark.circle.fill" : "arrow.uturn.forward.circle")
                .font(.title3)
                .foregroundStyle(entry.kind == .done ? Color.accentColor : Color.secondary)
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
            if showsAmount, let amount = entry.amount {
                Text(Format.money(amount, code: currency))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
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
