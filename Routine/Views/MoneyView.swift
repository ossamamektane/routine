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
        let allBills = store.visibleItems.filter(\.hasCost)
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let due = store.bills
        let entries = Self.entriesByItem(due)
        let found = allBills.filter { (item: Item) -> Bool in Self.matches(item, query) }
        let groups = ItemGroup.make(Self.soonestFirst(found, entries: due), afterDoneTitle: "After Payment")
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
                ForEach(groups) { (group: ItemGroup) in
                    Section {
                        ForEach(group.items) { (item: Item) in
                            billRow(item, entry: entries[item.id], today: today, code: code)
                        }
                    } header: {
                        Text(group.title)
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
                } else if groups.isEmpty {
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

    private func billRow(_ item: Item, entry: AgendaEntry?, today: Day, code: String) -> some View {
        BillRow(item: item, entry: entry, paidToday: Self.paidToday(item, today: today), code: code, today: today)
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

    /// Each bill's row from the list of what's due, if it has one. Paused and completed bills don't.
    private static func entriesByItem(_ entries: [AgendaEntry]) -> [UUID: AgendaEntry] {
        var byItem: [UUID: AgendaEntry] = [:]
        for entry in entries where byItem[entry.itemID] == nil {
            byItem[entry.itemID] = entry
        }
        return byItem
    }

    /// The soonest due first, the same order as Today. Bills with nothing coming up go last, by name.
    private static func soonestFirst(_ bills: [Item], entries: [AgendaEntry]) -> [Item] {
        var rank: [UUID: Int] = [:]
        for (index, entry) in entries.enumerated() where rank[entry.itemID] == nil {
            rank[entry.itemID] = index
        }
        return bills.sorted { (lhs: Item, rhs: Item) -> Bool in
            let l = rank[lhs.id] ?? Int.max
            let r = rank[rhs.id] ?? Int.max
            if l != r { return l < r }
            return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
        }
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
                  breakdownTitle: "Cost This Year",
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

/// A bill: its name, when it's next due and how often, and the amount. Tap to edit. Like tasks,
/// bills are only checked off on Today, so there's no circle or countdown here.
struct BillRow: View {
    var item: Item
    /// Nil for paused and completed bills.
    var entry: AgendaEntry?
    /// Today's payment, so the row can say it's been paid.
    var paidToday: LogEntry?
    var code: String
    var today: Day

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
            if let cost = item.cost {
                Text(verbatim: Format.money(cost, code: code))
                    .monospacedDigit()
                    .foregroundStyle(entry == nil ? Color.secondary : Color.primary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var isOverdue: Bool {
        guard let entry else { return false }
        return entry.overdue && !entry.isFinished && entry.state != .snoozed
    }

    /// When and how often, in the same words as Today: "Tomorrow · Monthly · Automatic".
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
        var parts: [String] = []
        let everyDay = s.isEveryDay && !s.fromDone
        if paidToday != nil && !entry.overdue {
            parts.append(String(localized: "Paid today"))
        } else if entry.state == .skipped {
            parts.append(String(localized: "Skipped"))
        } else if entry.goal {
            parts.append(Format.goalProgress(entry.progress, entry.total, s.goalPeriod))
        } else if entry.state == .snoozed, let until = entry.snoozedUntil {
            parts.append(String(localized: "Later · \(Format.time(until))"))
        } else if !everyDay {
            // Every day: the date adds nothing.
            parts.append(Format.relative(entry.day, today: today))
        }
        if everyDay {
            parts.append(String(localized: "Every day"))
        } else if let often = s.shortSummary {
            parts.append(often)
        }
        if item.isAutopay {
            parts.append(String(localized: "Automatic"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
