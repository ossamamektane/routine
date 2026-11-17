import SwiftUI
import UIKit

/// The Bills tab, like the old Bills app: what you pay this month and the twelve months ahead,
/// then every bill in one list, soonest first.
struct MoneyView: View {
    @Environment(AppStore.self) private var store
    @State private var editor: EditorRequest?
    @State private var search = ""

    var body: some View {
        let code = store.settings.currency
        let now = store.now
        let today = Day(now)
        let items = store.itemsByID
        let allBills = store.visibleItems.filter(\.hasCost)
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let rows = store.bills.filter { entry in
            guard let item = items[entry.itemID] else { return false }
            return Self.matches(item, query)
        }
        let others = allBills
            .filter { ($0.paused || $0.isFinished) && Self.matches($0, query) }
            .sorted(by: Self.pausedFirst)
        // Grouped like Tasks: bills you pay yourself, then ones counted automatically.
        let toPay = rows.filter { $0.state != .info }
        let automatic = rows.filter { $0.state == .info }
        // Still to pay by hand: anything overdue, then every date left this month.
        let overdue = toPay
            .filter { !$0.isFinished && $0.day < today }
            .reduce(Decimal(0)) { $0 + (items[$1.itemID]?.cost ?? 0) }
        let leftToPay = overdue + MoneyPlanner.restOfMonth(items: allBills, today: today)
        let paused = others.filter { !$0.isFinished }
        let paidOff = others.filter(\.isFinished)
        let hasActive = allBills.contains { !$0.paused && !$0.isFinished }

        NavigationStack {
            List {
                if !allBills.isEmpty && query.isEmpty {
                    Section {
                        summaryRows(months: store.stats, hasActive: hasActive, leftToPay: leftToPay, code: code, today: today)
                    } header: {
                        Text("Summary")
                    }
                }
                if !toPay.isEmpty {
                    Section {
                        entryRows(toPay, items: items, today: today, now: now, code: code)
                    } header: {
                        Text("To pay")
                    }
                }
                if !automatic.isEmpty {
                    Section {
                        entryRows(automatic, items: items, today: today, now: now, code: code)
                    } header: {
                        Text("Counted automatically")
                    } footer: {
                        Text("Added to your totals on their own, like subscriptions and everyday spending. Nothing to check off.")
                    }
                }
                if !paused.isEmpty {
                    Section {
                        ForEach(paused) { item in
                            billRow(item, entry: nil, today: today, now: now, code: code)
                        }
                    } header: {
                        Text("Paused")
                    }
                }
                if !paidOff.isEmpty {
                    Section {
                        ForEach(paidOff) { item in
                            billRow(item, entry: nil, today: today, now: now, code: code)
                        }
                    } header: {
                        Text("Paid off")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .searchable(text: $search, prompt: Text("Search"))
            .overlay {
                if allBills.isEmpty {
                    ContentUnavailableView {
                        Label("No bills yet", systemImage: "creditcard")
                    } description: {
                        Text("Add rent, subscriptions and anything else you pay for to see what you pay each month.")
                    } actions: {
                        Button("Add a bill") { editor = .newBill() }
                            .buttonStyle(.borderedProminent)
                    }
                } else if rows.isEmpty && others.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .navigationTitle("Bills")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editor = .newBill()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("Add a bill"))
                }
            }
            .sheet(item: $editor) { request in
                EditorView(request: request)
            }
            .sensoryFeedback(.success, trigger: store.completions)
        }
    }

    /// This month, in the same rows as the bills below, then every month of the year.
    @ViewBuilder
    private func summaryRows(months: [MonthTotal], hasActive: Bool, leftToPay: Decimal, code: String, today: Day) -> some View {
        if let current = months.first(where: { $0.month == today.monthIndex }) {
            SummaryRow(title: current.firstDay.noon.formatted(.dateTime.month(.wide)),
                       subtitle: Self.monthLine(current, leftToPay: leftToPay, hasActive: hasActive, code: code),
                       amount: Format.money(current.amount, code: code))
        }
        NavigationLink {
            BillMonthsView(months: months, hasActive: hasActive, code: code, today: today)
        } label: {
            Text("Month by month")
        }
    }

    /// "MAD 750.00 left to pay", or that there's nothing left.
    static func monthLine(_ month: MonthTotal, leftToPay: Decimal, hasActive: Bool, code: String) -> String {
        if leftToPay > 0 {
            let owed = Format.money(leftToPay, code: code)
            return String(localized: "\(owed) left to pay")
        }
        if month.payments == 0 {
            return hasActive ? String(localized: "Nothing to pay") : String(localized: "Every bill is paused")
        }
        return String(localized: "Nothing left to pay")
    }

    @ViewBuilder
    private func entryRows(_ entries: [AgendaEntry], items: [UUID: Item], today: Day, now: Date, code: String) -> some View {
        ForEach(entries) { entry in
            if let item = items[entry.itemID] {
                billRow(item, entry: entry, today: today, now: now, code: code)
            }
        }
    }

    private func billRow(_ item: Item, entry: AgendaEntry?, today: Day, now: Date, code: String) -> some View {
        let paid = Self.paidToday(item, today: today)
        return BillRow(item: item, entry: entry, paidToday: paid, code: code, today: today, now: now) {
            toggle(item, entry: entry, paid: paid)
        }
        .contentShape(Rectangle())
        .onTapGesture { editor = .edit(item) }
        .itemActions(item, store: store, editor: $editor)
    }

    /// Pays the bill, or takes back today's payment.
    private func toggle(_ item: Item, entry: AgendaEntry?, paid: LogEntry?) {
        guard let entry else { return }
        withAnimation(.snappy) {
            if entry.state == .info {
                return
            } else if entry.isFinished {
                store.undo(entry)
            } else if entry.state == .future, let paid {
                store.undo(item.id, logID: paid.id)
            } else {
                store.complete(entry)
            }
        }
    }

    /// The payment made today, if any.
    static func paidToday(_ item: Item, today: Day) -> LogEntry? {
        item.log.last { $0.kind == .done && Day($0.at) == today }
    }

    private static func matches(_ item: Item, _ query: String) -> Bool {
        query.isEmpty || item.title.localizedCaseInsensitiveContains(query) || item.notes.localizedCaseInsensitiveContains(query)
    }

    /// Paused bills, then completed ones, by name.
    private static func pausedFirst(_ lhs: Item, _ rhs: Item) -> Bool {
        if lhs.isFinished != rhs.isFinished { return !lhs.isFinished }
        return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
    }
}

/// A total in the Bills list: a title and a short line under it, the amount on the right,
/// laid out exactly like a bill.
struct SummaryRow: View {
    var title: String
    var subtitle: String
    var amount: String
    /// Months still to come are shown in gray.
    var dimmed = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .lineLimit(1)
                Text(verbatim: subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            Text(verbatim: amount)
                .monospacedDigit()
                .foregroundStyle(dimmed ? Color.secondary : Color.primary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// January to December, one row each, with the year's total underneath.
struct BillMonthsView: View {
    var months: [MonthTotal]
    var hasActive: Bool
    var code: String
    var today: Day

    var body: some View {
        let year = months.reduce(Decimal(0)) { $0 + $1.amount }
        List {
            Section {
                ForEach(months) { month in
                    SummaryRow(title: month.firstDay.noon.formatted(.dateTime.month(.wide)),
                               subtitle: Self.subtitle(month, today: today, hasActive: hasActive),
                               amount: Format.money(month.amount, code: code),
                               dimmed: month.month > today.monthIndex)
                }
            } footer: {
                Text("This year · \(Format.money(year, code: code))")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text(verbatim: String(today.year)))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// "Paid", "This month", "Coming up", or why there's nothing.
    static func subtitle(_ month: MonthTotal, today: Day, hasActive: Bool) -> String {
        if month.payments == 0 {
            if !hasActive { return String(localized: "Every bill is paused") }
            return String(localized: "Nothing to pay")
        }
        if month.month < today.monthIndex { return String(localized: "Paid") }
        if month.month == today.monthIndex { return String(localized: "What you pay this month") }
        return String(localized: "Coming up")
    }
}

/// A bill: pay it with the circle, tap the row to edit. Shows when it's due and how long is left.
struct BillRow: View {
    var item: Item
    /// Nil for paused and completed bills.
    var entry: AgendaEntry?
    /// Today's payment, so the circle stays checked until tomorrow.
    var paidToday: LogEntry?
    var code: String
    var today: Day
    var now: Date
    var onCheck: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.displayTitle)
                    .foregroundStyle(entry == nil ? Color.secondary : Color.primary)
                    .lineLimit(2)
                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(.subheadline)
                        .foregroundStyle(isOverdue ? Color.red : Color.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                if let cost = item.cost {
                    Text(verbatim: Format.money(cost, code: code))
                        .monospacedDigit()
                        .foregroundStyle(entry == nil ? Color.secondary : Color.primary)
                        .lineLimit(1)
                }
                if let entry, let countdown = entry.billCountdown(now: now, today: today) {
                    CountdownLabel(countdown: countdown)
                } else if item.paused && !item.isFinished {
                    Text("Paused")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// A circle only for bills you pay yourself. Bills charged automatically, any-day, paused
    /// and paid-off ones have nothing to check off, so they show no symbol at all.
    @ViewBuilder
    private var leading: some View {
        if let entry, entry.state != .info {
            CheckButton(state: checkState(entry), tint: .accentColor, progress: progress(entry), action: onCheck)
        }
    }

    /// Paid early or today: the circle shows it until the next one is due.
    private func checkState(_ entry: AgendaEntry) -> EntryState {
        if entry.state == .future && paidToday != nil { return .done }
        return entry.state
    }

    private func progress(_ entry: AgendaEntry) -> Double? {
        guard entry.goal, entry.total > 0, entry.state != .done else { return nil }
        return Double(entry.progress) / Double(entry.total)
    }

    private var isOverdue: Bool {
        guard let entry else { return false }
        return entry.overdue && !entry.isFinished
    }

    private var subtitle: String? {
        var parts: [String] = []
        guard let entry else {
            if item.isFinished, let done = item.lastDone ?? item.log.last {
                parts.append(String(localized: "Paid \(Format.day(Day(done.at)))"))
            } else {
                parts.append(item.schedule.summary)
            }
            return parts.joined(separator: " · ")
        }
        if item.isAnyDayBill {
            let s = item.schedule
            if s.goalCount == 1 && s.goalPeriod == .week { return String(localized: "Every week · any day") }
            if s.goalCount == 1 && s.goalPeriod == .month { return String(localized: "Every month · any day") }
            if s.goalCount == 1 && s.goalPeriod == .day { return String(localized: "Every day") }
            return Format.goal(s.goalCount, s.goalPeriod) + " · " + String(localized: "any day")
        }
        if entry.state == .info && item.schedule.kind == .repeating && item.schedule.unit == .day && item.schedule.every == 1 {
            // Counted every day: the date adds nothing.
            return String(localized: "Every day")
        }
        if paidToday != nil && !entry.overdue {
            parts.append(String(localized: "Paid today"))
        }
        if entry.goal {
            parts.append(Format.goalProgress(entry.progress, entry.total, item.schedule.goalPeriod))
        } else if entry.overdue {
            parts.append(String(localized: "Due \(Format.day(entry.day))"))
        } else if entry.state == .snoozed, let until = entry.snoozedUntil {
            parts.append(String(localized: "Later · \(Format.time(until))"))
        } else {
            var when = Format.relative(entry.day, today: today)
            if let m = entry.minute { when += " · " + Format.time(m) }
            parts.append(when)
        }
        if let often = item.schedule.shortSummary {
            parts.append(often)
        }
        return parts.joined(separator: " · ")
    }
}
