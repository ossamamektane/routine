import SwiftUI
import UIKit

/// The Bills tab: every bill, soonest first, grouped like Tasks, with what they come to this
/// month and this year at the bottom.
struct MoneyView: View {
    @Environment(AppStore.self) private var store
    @State private var editor: EditorRequest?
    @State private var search = ""
    @State private var showSettings = false
    @State private var showsMonths = false

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
        let paused = others.filter { !$0.isFinished }
        let completed = others.filter(\.isFinished)
        let months = store.stats

        NavigationStack {
            List {
                if !toPay.isEmpty {
                    Section {
                        entryRows(toPay, items: items, today: today, now: now, code: code)
                    } header: {
                        Text("To Pay")
                    } footer: {
                        Text("Check these off on Today.")
                    }
                }
                if !automatic.isEmpty {
                    Section {
                        entryRows(automatic, items: items, today: today, now: now, code: code)
                    } header: {
                        Text("Counted Automatically")
                    } footer: {
                        Text("Added to your totals on their own, like subscriptions and everyday spending. They don’t show on Today.")
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
                if !completed.isEmpty {
                    Section {
                        ForEach(completed) { item in
                            billRow(item, entry: nil, today: today, now: now, code: code)
                        }
                    } header: {
                        Text("Completed")
                    }
                }
                if !allBills.isEmpty && query.isEmpty {
                    ListSummary(text: Self.totals(months, today: today, code: code))
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .searchable(text: $search, prompt: Text("Search"))
            .overlay {
                if allBills.isEmpty {
                    ContentUnavailableView {
                        Label("No Bills", systemImage: "creditcard")
                    } description: {
                        Text("Add rent, subscriptions, and anything else you pay for to see what you pay each month.")
                    } actions: {
                        Button("Add a Bill") { editor = .newBill() }
                            .buttonStyle(.borderedProminent)
                    }
                } else if rows.isEmpty && others.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .navigationTitle("Bills")
            .navigationDestination(isPresented: $showsMonths) {
                BillMonthsView(months: months, code: code, today: today)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editor = .newBill()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("Add a Bill"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showsMonths = true
                        } label: {
                            Label("Month by Month", systemImage: "calendar")
                        }
                        .disabled(allBills.isEmpty)
                        Divider()
                        Button {
                            showSettings = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel(Text("More"))
                }
            }
            .sheet(item: $editor) { request in
                EditorView(request: request)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    /// "MAD 1,250.00 this month · MAD 15,000.00 this year", the same totals as Month by Month.
    static func totals(_ months: [MonthTotal], today: Day, code: String) -> String {
        let month = months.first(where: { $0.month == today.monthIndex })?.amount ?? 0
        let year = months.reduce(Decimal(0)) { $0 + $1.amount }
        let monthAmount = Format.money(month, code: code)
        let yearAmount = Format.money(year, code: code)
        return String(localized: "\(monthAmount) this month · \(yearAmount) this year")
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
        BillRow(item: item, entry: entry, paidToday: Self.paidToday(item, today: today), code: code, today: today, now: now)
            .contentShape(Rectangle())
            .onTapGesture { editor = .edit(item) }
            .itemActions(item, store: store, editor: $editor)
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
    var subtitle: String? = nil
    var amount: String
    /// Months still to come are shown in gray.
    var dimmed = false
    /// This month, in the list of months.
    var emphasized = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .fontWeight(emphasized ? Font.Weight.semibold : Font.Weight.regular)
                    .lineLimit(1)
                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                }
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

/// January to December, one row each, with the year's total underneath. Just what your bills
/// come to: nothing here says whether you paid them. This month is in bold, months ahead in gray.
struct BillMonthsView: View {
    var months: [MonthTotal]
    var code: String
    var today: Day

    var body: some View {
        let year = months.reduce(Decimal(0)) { $0 + $1.amount }
        List {
            Section {
                ForEach(months) { month in
                    SummaryRow(title: month.firstDay.noon.formatted(.dateTime.month(.wide)),
                               amount: Format.money(month.amount, code: code),
                               dimmed: month.month > today.monthIndex,
                               emphasized: month.month == today.monthIndex)
                }
            } footer: {
                Text("This year · \(Format.money(year, code: code))")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text(verbatim: String(today.year)))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A bill: when it's due and how long is left. Tap to edit. Like tasks, bills are only
/// checked off on Today, so there's no circle here.
struct BillRow: View {
    var item: Item
    /// Nil for paused and completed bills.
    var entry: AgendaEntry?
    /// Today's payment, so the row can say it's been paid.
    var paidToday: LogEntry?
    var code: String
    var today: Day
    var now: Date

    var body: some View {
        HStack(spacing: 12) {
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

    private var isOverdue: Bool {
        guard let entry else { return false }
        return entry.overdue && !entry.isFinished
    }

    private var subtitle: String? {
        var parts: [String] = []
        guard let entry else {
            if item.isFinished, let done = item.lastDone {
                parts.append(String(localized: "Paid \(Format.day(Day(done.at)))"))
            } else if item.isFinished {
                parts.append(String(localized: "Skipped"))
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
