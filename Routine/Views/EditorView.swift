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

/// Add or edit a task or a bill. Nothing is saved until you tap the checkmark.
/// Tasks get the full schedule (times, wake-up, after the last time) and a reminder by default.
/// Bills get an amount, a date, how they're paid, and a reminder the day before by default.
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
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case title, amount
    }

    /// What a bill's Repeat menu shows. Any-day bills show as their week or month.
    private enum BillRepeat: Hashable {
        case day, week, month, year, afterDone, once
    }

    /// What a task's Repeat menu shows. Never is just once; any-day tasks show as their week or month.
    private enum TaskRepeat: Hashable {
        case never, hour, day, week, month, year
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
            // Bills fall on a day: no wake-ups and no times.
            item.schedule.afterWaking = nil
            if item.schedule.kind == .repeating && item.schedule.unit == .hour { item.schedule.unit = .day }
            item.schedule.times = []
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
                    paymentSection
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
                if !request.isBill && draft.schedule.kind == .goal && mode != .off && times.isEmpty {
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
                Button(deleteLabel, role: .destructive) {
                    store.delete(request.item.id)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deleteMessage)
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
        // Switches and pickers in blue, like the rest of the app.
        .tint(Color.accentColor)
    }

    // MARK: Sections

    private var nameSection: some View {
        Section {
            TextField("Title", text: $draft.title)
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

    /// Like Calendar and Reminders: Never for just once, or how often it repeats.
    private var taskRepeatPicker: some View {
        Picker(selection: taskRepeatBinding) {
            Text("Never").tag(TaskRepeat.never)
            Text("Hourly").tag(TaskRepeat.hour)
            Text("Daily").tag(TaskRepeat.day)
            Text("Weekly").tag(TaskRepeat.week)
            Text("Monthly").tag(TaskRepeat.month)
            Text("Yearly").tag(TaskRepeat.year)
        } label: {
            Label("Repeat", systemImage: "repeat")
        }
    }

    /// Weekly and monthly: on set days, or any day as long as it gets done.
    private var anyDayPicker: some View {
        Picker("Day", selection: anyDayBinding) {
            Text(setDayLabel).tag(false)
            Text("Any Day").tag(true)
        }
        .pickerStyle(.segmented)
    }

    /// "Every 2 weeks"
    private var everyStepper: some View {
        Stepper(value: $draft.schedule.every, in: 1...maxEvery) {
            Label {
                Text(verbatim: Format.every(draft.schedule.every, draft.schedule.unit))
            } icon: {
                Image(systemName: "clock.arrow.circlepath")
            }
        }
    }

    /// "3 times a week"
    private var goalStepper: some View {
        Stepper(value: $draft.schedule.goalCount, in: 1...99) {
            Label {
                Text(verbatim: Format.goal(draft.schedule.goalCount, draft.schedule.goalPeriod))
            } icon: {
                Image(systemName: "number")
            }
        }
    }

    /// The next date counts from when you finish.
    private var repeatAfterCompletionToggle: some View {
        Toggle(isOn: repeatAfterBinding) {
            Label("Repeat After Completion", systemImage: "arrow.triangle.2.circlepath")
        }
    }

    /// A date row with a calendar icon, like the rest of the form.
    private func datePicker(_ title: LocalizedStringKey, selection: Binding<Date>) -> some View {
        DatePicker(selection: selection, displayedComponents: .date) {
            Label(title, systemImage: "calendar")
        }
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

    /// How often first, then the time of day, like Calendar. "Any day" is saved as a count per
    /// week or month.
    @ViewBuilder
    private var repeatingSection: some View {
        Section {
            taskRepeatPicker
            if frequency == .week || frequency == .month {
                anyDayPicker
            }
            if draft.schedule.kind == .goal {
                goalStepper
            } else {
                everyStepper
                repeatAfterCompletionToggle
                if draft.schedule.unit == .week {
                    WeekdayPicker(selection: weekdaysBinding, tint: .accentColor)
                }
                if showsStart {
                    datePicker("Start Date", selection: startBinding)
                }
            }
        }
        if draft.schedule.kind != .goal {
            Section {
                timeOfDayRows
            }
        }
    }

    /// When in the day: after you wake up, or at set times.
    @ViewBuilder
    private var timeOfDayRows: some View {
        if draft.schedule.supportsWake {
            Toggle(isOn: wakeBinding) {
                Label("After I Wake Up", systemImage: "sunrise")
            }
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
                DatePicker(selection: singleTime(default: SleepCheck.usualWake(store.sleepLog)), displayedComponents: .hourAndMinute) {
                    Label("Starts", systemImage: "clock")
                }
            }
        } else if draft.schedule.afterWaking == nil {
            timeRows(limit: 12)
        }
    }

    /// Repeats a while after the last time: how often, then the next date.
    @ViewBuilder
    private var afterDoneSection: some View {
        Section {
            taskRepeatPicker
            everyStepper
            repeatAfterCompletionToggle
            datePicker("Next Date", selection: nextDueBinding)
        }
        Section {
            timeRows(limit: 1)
        }
    }

    @ViewBuilder
    private var onceSection: some View {
        Section {
            taskRepeatPicker
            datePicker("Date", selection: startBinding)
        }
        Section {
            timeRows(limit: 1)
        }
    }

    /// Set times, or Anytime. `limit` is how many times it can have.
    @ViewBuilder
    private func timeRows(limit: Int) -> some View {
        ForEach(times) { row in
            HStack(spacing: 12) {
                Button {
                    withAnimation { removeTime(row.id) }
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
            timesChanged()
        }
        if times.isEmpty {
            LabeledContent {
                Text("Anytime")
            } label: {
                Label("Time", systemImage: "clock")
            }
        }
        if times.count < limit {
            Button {
                withAnimation { addTime() }
            } label: {
                Label("Add a Time", systemImage: "plus.circle.fill")
            }
        }
    }

    /// "Right when I wake up". Tap to pick the exact number of minutes.
    private var wakeOffsetRow: some View {
        Button {
            withAnimation(.snappy) { showsWakeWheel.toggle() }
        } label: {
            LabeledContent {
                Text(verbatim: wakeOffsetLabel(draft.schedule.afterWaking ?? 0))
                    .foregroundStyle(showsWakeWheel ? Color.accentColor : Color.secondary)
            } label: {
                Label {
                    Text(wakeRowTitle)
                        .foregroundStyle(Color.primary)
                } icon: {
                    Image(systemName: "clock")
                        .foregroundStyle(Color.accentColor)
                }
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

    /// One Remind Me menu. Goals can remind you only when you're behind, at a time you pick.
    private var reminderSection: some View {
        Section {
            Picker(selection: $draft.reminder) {
                Text("None").tag(ReminderMode.off)
                if draft.schedule.kind == .goal {
                    Text("When I’m behind").tag(ReminderMode.whenBehind)
                    Text("Every day").tag(ReminderMode.onTime)
                } else {
                    Text(onTimeLabel).tag(ReminderMode.onTime)
                    if dayBeforeAllowed {
                        Text("The day before").tag(ReminderMode.dayBefore)
                    }
                }
            } label: {
                Label("Remind Me", systemImage: "bell")
            }
            if draft.schedule.kind == .goal && draft.reminder != .off {
                DatePicker(selection: singleTime(default: eveningMinute), displayedComponents: .hourAndMinute) {
                    Label("Time", systemImage: "clock")
                }
            }
        } footer: {
            notificationsOffFooter
        }
    }

    /// Only when it matters: a reminder is set but notifications are off.
    @ViewBuilder
    private var notificationsOffFooter: some View {
        if draft.reminder != .off && !paidAutomatically && store.notificationStatus == .denied {
            Text("Notifications are turned off for Routine. You can turn them on in the Settings app.")
        }
    }

    // MARK: Bill sections

    /// When a bill is due, laid out like a task's schedule. Bills fall on a day, with no times.
    private var dueSection: some View {
        Section {
            Picker(selection: billRepeatBinding) {
                Text("Never").tag(BillRepeat.once)
                Text("Daily").tag(BillRepeat.day)
                Text("Weekly").tag(BillRepeat.week)
                Text("Monthly").tag(BillRepeat.month)
                Text("Yearly").tag(BillRepeat.year)
            } label: {
                Label("Repeat", systemImage: "repeat")
            }
            dueRows
        }
    }

    @ViewBuilder
    private var dueRows: some View {
        switch draft.schedule.kind {
        case .once:
            datePicker("Date", selection: startBinding)
        case .afterDone:
            everyStepper
            repeatAfterPaymentToggle
            datePicker("Next Date", selection: nextDueBinding)
        case .repeating, .goal:
            if frequency == .week || frequency == .month {
                anyDayPicker
            }
            if draft.schedule.kind == .goal {
                goalStepper
            } else {
                everyStepper
                if !draft.autopay {
                    repeatAfterPaymentToggle
                }
                if draft.schedule.unit == .week {
                    WeekdayPicker(selection: weekdaysBinding, tint: .accentColor)
                }
                datePicker("Start Date", selection: startBinding)
            }
        }
    }

    /// The next date counts from when you pay, like tasks that repeat after completion.
    private var repeatAfterPaymentToggle: some View {
        Toggle(isOn: repeatAfterBinding) {
            Label("Repeat After Payment", systemImage: "arrow.triangle.2.circlepath")
        }
    }

    /// Paid by you (it shows on Today to check off) or automatically (only counted in the totals),
    /// then the reminder. Any-day bills are only counted, so they have neither.
    @ViewBuilder
    private var paymentSection: some View {
        if draft.schedule.kind != .goal {
            Section {
                if allowsAutopay {
                    Picker(selection: $draft.autopay) {
                        Text("Manual").tag(false)
                        Text("Automatic").tag(true)
                    } label: {
                        Label("Payment", systemImage: "creditcard")
                    }
                }
                if !paidAutomatically {
                    Picker(selection: $draft.reminder) {
                        Text("None").tag(ReminderMode.off)
                        if dayBeforeAllowed {
                            Text("The day before").tag(ReminderMode.dayBefore)
                        }
                        Text("On the day").tag(ReminderMode.onTime)
                    } label: {
                        Label("Remind Me", systemImage: "bell")
                    }
                }
            } footer: {
                notificationsOffFooter
            }
        }
    }

    // MARK: More sections

    private var pauseSection: some View {
        Section {
            Toggle(isOn: $draft.paused) {
                Label("Paused", systemImage: "pause.circle")
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        let recent = Array(draft.log.sorted { $0.at > $1.at }.prefix(5))
        if !recent.isEmpty {
            Section("History") {
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
                Text(deleteLabel)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            CancelButton { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            ConfirmButton(title: confirmTitle) { save() }
                .disabled(!canSave)
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            KeyboardDoneButton { focus = nil }
        }
    }

    // MARK: Labels

    private var heading: Text {
        if !request.isNew { return Text("Details") }
        return request.isBill ? Text("New Bill") : Text("New Task")
    }

    private var confirmTitle: LocalizedStringKey {
        request.isNew ? "Add" : "Save"
    }

    private var deleteLabel: LocalizedStringKey {
        request.isBill ? "Delete Bill" : "Delete Task"
    }

    private var deleteMessage: LocalizedStringKey {
        request.isBill ? "This bill and its history will be deleted from all your devices." : "This task and its history will be deleted from all your devices."
    }

    private var setDayLabel: LocalizedStringKey {
        frequency == .week ? "Specific Days" : "Specific Day"
    }

    private var wakeRowTitle: LocalizedStringKey {
        draft.schedule.unit == .hour ? "Starts" : "Time"
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

    /// The day you're living for tasks (still yesterday after midnight if you haven't slept),
    /// the calendar day for bills.
    private var livingDay: Day {
        request.isBill ? Day(store.now) : store.clock.day
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
            // Bills fall on a day: no wake-ups and no times.
            s.afterWaking = nil
            if s.kind != .goal && s.unit == .hour { s.unit = .day }
            s.times = []
        }
        if s.kind == .repeating && s.unit == .hour && s.afterWaking == nil && s.times.isEmpty {
            // Not from waking: starts at the time you usually get up.
            s.times = [SleepCheck.usualWake(store.sleepLog)]
        }
        if s.kind == .afterDone && s.unit == .hour && s.nextDueTime == nil {
            s.nextDueTime = roundedNow
        }
        if !request.isBill && s.kind == .goal && draft.reminder != .off && s.times.isEmpty {
            s.times = [eveningMinute]
        }
        return s.normalized()
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

    /// Leaving "any day": the reminder comes back the way it was, or the usual one.
    private func restoreReminder() {
        guard draft.reminder == .off || draft.reminder == .whenBehind else { return }
        let original = baseline
        if original.schedule.kind == .goal || original.reminder == .whenBehind {
            draft.reminder = request.isBill ? .dayBefore : .onTime
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
        // Paid automatically or any day: there's nothing to be reminded of.
        if item.isAutopay || item.isAnyDayBill { item.reminder = .off }
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

    private var taskRepeat: TaskRepeat {
        if draft.schedule.kind == .once { return .never }
        switch frequency {
        case .hour: return .hour
        case .day: return .day
        case .week: return .week
        case .month: return .month
        case .year: return .year
        }
    }

    /// Never makes it a one-time task. Picking how often makes it repeat again, keeping the rest
    /// of its settings.
    private var taskRepeatBinding: Binding<TaskRepeat> {
        Binding(
            get: { taskRepeat },
            set: { choice in
                guard choice != taskRepeat else { return }
                let unit: RepeatUnit
                switch choice {
                case .never:
                    kindBinding.wrappedValue = .once
                    return
                case .hour: unit = .hour
                case .day: unit = .day
                case .week: unit = .week
                case .month: unit = .month
                case .year: unit = .year
                }
                if draft.schedule.kind == .once {
                    kindBinding.wrappedValue = .repeating
                }
                frequencyBinding.wrappedValue = unit
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
                    if !request.isBill && draft.reminder != .off && times.isEmpty { times = [TimeRow(minute: eveningMinute)] }
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
                    timesChanged()
                }
            }
        )
    }

    private func addTime() {
        times.append(TimeRow(minute: suggestedNewTime))
        timesChanged()
    }

    private func removeTime(_ id: UUID) {
        times.removeAll { $0.id == id }
        timesChanged()
    }

    /// "Repeat after completion" with a time you picked: the next one is at that time again.
    private func timesChanged() {
        if draft.schedule.kind == .afterDone { draft.schedule.nextDueTime = nil }
    }
}

// MARK: - History row

private struct HistoryRow: View {
    var entry: LogEntry
    var currency: String
    /// Bills say "Paid" and show the amount.
    var showsAmount: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.kind == .done ? "checkmark.circle.fill" : "arrow.uturn.forward.circle")
                .font(.title3)
                .foregroundStyle(entry.kind == .done ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                if entry.kind == .done && showsAmount {
                    Text("Paid")
                } else if entry.kind == .done {
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
