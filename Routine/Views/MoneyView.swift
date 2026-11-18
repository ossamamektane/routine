import SwiftUI
import UIKit

/// The Bills tab: what your bills come to this month and this year, then every bill, soonest
/// first, grouped like Tasks.
struct MoneyView: View {
    @Environment(AppStore.self) private var store
    @State private var editor: EditorRequest?
    @State private var search = ""
    @State private var showSettings = false

    var body: some View {
        let code = store.settings.currency
        let now = store.now
        let today = Day(now)
        let items = store.itemsByID
        let allBills = store.visibleItems.filter(\.hasCost)
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let rows = store.bills.filter { (entry: AgendaEntry) -> Bool in
            guard let item = items[entry.itemID] else { return false }
            return Self.matches(item, query)
        }
        let others = allBills
            .filter { ($0.paused || $0.isFinished) && Self.matches($0, query) }
            .sorted(by: Self.pausedFirst)
        // Grouped like Tasks: bills you pay yourself, ones paid automatically, then any-day ones.
        let toPay = rows.filter { $0.state != .info }
        let anyDay = rows.filter { $0.state == .info && items[$0.itemID]?.isAnyDayBill == true }
        let automatic = rows.filter { $0.state == .info && items[$0.itemID]?.isAnyDayBill != true }
        let paused = others.filter { !$0.isFinished }
        let completed = others.filter(\.isFinished)
        let months = store.stats

        NavigationStack {
            List {
                if !allBills.isEmpty && query.isEmpty {
                    Section {
                        NavigationLink {
                            BillsStatsView(bills: allBills, months: months, now: now, code: code)
                        } label: {
                            summaryCard(months, today: today, code: code)
                        }
                    }
                }
                if !toPay.isEmpty {
                    Section {
                        entryRows(toPay, items: items, today: today, now: now, code: code)
                    } header: {
                        Text("To Pay")
                    }
                }
                if !automatic.isEmpty {
                    Section {
                        entryRows(automatic, items: items, today: today, now: now, code: code)
                    } header: {
                        Text("Paid Automatically")
                    }
                }
                if !anyDay.isEmpty {
                    Section {
                        entryRows(anyDay, items: items, today: today, now: now, code: code)
                    } header: {
                        Text("Any Day")
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
                    ListSummary(text: String(localized: "\(allBills.count) Bills"))
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
                        Text("Add rent, subscriptions, and other bills.")
                    } actions: {
                        Button("Add a Bill") { editor = .newBill() }
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
                    .accessibilityLabel(Text("Add a Bill"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
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

    /// "MAD 1,250.00 this month", "MAD 15,000.00 this year". Tap for each month and each bill.
    private func summaryCard(_ months: [MonthTotal], today: Day, code: String) -> some View {
        let month = months.first(where: { (m: MonthTotal) -> Bool in m.month == today.monthIndex })?.amount ?? 0
        let year = months.reduce(Decimal(0)) { (sum: Decimal, m: MonthTotal) -> Decimal in sum + m.amount }
        let monthText = Format.money(month, code: code)
        let yearText = Format.money(year, code: code)
        return SummaryCard(symbol: "creditcard.fill",
                           title: String(localized: "\(monthText) this month"),
                           subtitle: String(localized: "\(yearText) this year"))
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

/// Numbers over time, the same way for bills and tasks: one row per month (or day), the total
/// under them, then the same numbers by bill or by task. The current one is in bold, ones still
/// to come in gray.
struct StatsView: View {
    struct Row: Identifiable {
        var id: String
        var title: String
        var value: String
        var dimmed = false
        var emphasized = false
    }

    var title: String
    var periods: [Row]
    var total: String
    var breakdownTitle: LocalizedStringKey
    var breakdown: [Row]

    var body: some View {
        List {
            Section {
                ForEach(periods) { (row: Row) in
                    SummaryRow(title: row.title, amount: row.value, dimmed: row.dimmed, emphasized: row.emphasized)
                }
            } footer: {
                Text(verbatim: total)
            }
            if !breakdown.isEmpty {
                Section {
                    ForEach(breakdown) { (row: Row) in
                        SummaryRow(title: row.title, amount: row.value)
                    }
                } header: {
                    Text(breakdownTitle)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text(verbatim: title))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// January to December, then each bill's total for the year. Just what your bills come to:
/// nothing here says whether you paid them.
struct BillsStatsView: View {
    var bills: [Item]
    var months: [MonthTotal]
    var now: Date
    var code: String

    var body: some View {
        let today = Day(now)
        let year = months.reduce(Decimal(0)) { (sum: Decimal, m: MonthTotal) -> Decimal in sum + m.amount }
        let yearText = Format.money(year, code: code)
        StatsView(title: String(today.year),
                  periods: months.map { (m: MonthTotal) -> StatsView.Row in
                      StatsView.Row(id: String(m.month),
                                    title: m.firstDay.noon.formatted(.dateTime.month(.wide)).localizedCapitalized,
                                    value: Format.money(m.amount, code: code),
                                    dimmed: m.month > today.monthIndex,
                                    emphasized: m.month == today.monthIndex)
                  },
                  total: String(localized: "This year · \(yearText)"),
                  breakdownTitle: "By Bill",
                  breakdown: Self.byBill(bills, now: now, code: code))
    }

    private struct BillTotal {
        var item: Item
        var amount: Decimal
    }

    /// Each bill's total this year, the biggest first. The same totals as the months above.
    static func byBill(_ bills: [Item], now: Date, code: String) -> [StatsView.Row] {
        var totals: [BillTotal] = []
        for item in bills {
            let months = MoneyPlanner.yearMonths(items: [item], now: now)
            let amount = months.reduce(Decimal(0)) { (sum: Decimal, m: MonthTotal) -> Decimal in sum + m.amount }
            if amount > 0 { totals.append(BillTotal(item: item, amount: amount)) }
        }
        totals.sort { (a: BillTotal, b: BillTotal) -> Bool in
            if a.amount != b.amount { return a.amount > b.amount }
            return a.item.displayTitle.localizedStandardCompare(b.item.displayTitle) == .orderedAscending
        }
        return totals.map { (t: BillTotal) -> StatsView.Row in
            StatsView.Row(id: t.item.id.uuidString, title: t.item.displayTitle, value: Format.money(t.amount, code: code))
        }
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
        return entry.overdue && !entry.isFinished && entry.state != .snoozed
    }

    /// What and when, in the same words as Today: the date when it isn't today, then how often.
    private var subtitle: String? {
        let s = item.schedule
        guard let entry else {
            if item.isFinished, let done = item.lastDone {
                return String(localized: "Paid \(Format.day(Day(done.at)))")
            }
            if item.isFinished { return String(localized: "Skipped") }
            return s.summary
        }
        if item.isAnyDayBill {
            if s.goalCount == 1 && s.goalPeriod == .week { return String(localized: "Every week · any day") }
            if s.goalCount == 1 && s.goalPeriod == .month { return String(localized: "Every month · any day") }
            if s.goalCount == 1 && s.goalPeriod == .day { return String(localized: "Every day") }
            return Format.goal(s.goalCount, s.goalPeriod) + " · " + String(localized: "any day")
        }
        if entry.state == .info && s.kind == .repeating && s.unit == .day && s.every == 1 {
            // Taken every day: the date adds nothing.
            return String(localized: "Every day")
        }
        var parts: [String] = []
        if paidToday != nil && !entry.overdue {
            parts.append(String(localized: "Paid today"))
        }
        if entry.goal {
            parts.append(Format.goalProgress(entry.progress, entry.total, s.goalPeriod))
        } else if entry.state == .snoozed, let until = entry.snoozedUntil {
            parts.append(String(localized: "Later · \(Format.time(until))"))
        } else if entry.day != today || entry.overdue {
            parts.append(Format.day(entry.day))
        }
        if let often = s.shortSummary {
            parts.append(often)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
