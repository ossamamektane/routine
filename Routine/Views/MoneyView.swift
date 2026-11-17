import SwiftUI
import UIKit

/// The Bills tab, like the old Bills app: what you pay this month and the twelve months ahead,
/// then every bill in one list, soonest first.
struct MoneyView: View {
    @Environment(AppStore.self) private var store
    @State private var editor: EditorRequest?
    @State private var search = ""
    @State private var selectedMonth: Int? = nil

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
        let hasActive = allBills.contains { !$0.paused && !$0.isFinished }

        NavigationStack {
            List {
                if !allBills.isEmpty && query.isEmpty {
                    Section {
                        BillStats(months: store.stats, hasActive: hasActive, code: code, selected: $selectedMonth, today: today)
                    }
                }
                if !rows.isEmpty || !others.isEmpty {
                    Section {
                        ForEach(rows) { entry in
                            if let item = items[entry.itemID] {
                                billRow(item, entry: entry, today: today, now: now, code: code)
                            }
                        }
                        ForEach(others) { item in
                            billRow(item, entry: nil, today: today, now: now, code: code)
                        }
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

/// The big number for one month and the twelve months ahead. Tapping a month changes the number.
struct BillStats: View {
    var months: [MonthTotal]
    /// At least one bill isn't paused.
    var hasActive: Bool
    var code: String
    @Binding var selected: Int?
    var today: Day

    var body: some View {
        if months.isEmpty {
            EmptyView()
        } else {
            let index = selected ?? (today.month - 1)
            card(index: months.indices.contains(index) ? index : 0)
        }
    }

    private func card(index: Int) -> some View {
        let month = months[index]
        let first = months[0].value
        let flat = months.allSatisfy { abs($0.value - first) < 0.005 }
        let year = months.reduce(Decimal(0)) { $0 + $1.amount }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

        return VStack(spacing: 0) {
            Text(verbatim: month.firstDay.noon.formatted(.dateTime.month(.wide).year()))
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: Self.amount(month.amount))
                    .font(.system(size: 46, weight: .medium))
                    .monospacedDigit()
                Text(verbatim: code)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.top, 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: Format.money(month.amount, code: code)))
            Text(verbatim: subtitle(month, index: index))
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 2)

            Divider()
                .padding(.vertical, 18)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Month by month")
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                Text(hint(flat: flat))
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.bottom, 12)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(months.indices, id: \.self) { k in
                    MonthCell(month: months[k], isSelected: k == index, isCurrent: months[k].month == today.monthIndex, isFuture: months[k].month > today.monthIndex, code: code) {
                        withAnimation(.snappy) { selected = k }
                    }
                }
            }

            Text("This year · \(Format.money(year, code: code))")
                .font(.footnote)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    /// "1,234.00", always with two decimals, like the old Bills app.
    static func amount(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    private func subtitle(_ month: MonthTotal, index: Int) -> String {
        let name = month.firstDay.noon.formatted(.dateTime.month(.wide))
        if month.month < today.monthIndex {
            if month.payments == 0 { return String(localized: "Nothing paid in \(name)") }
            return String(localized: "What you paid in \(name)")
        }
        if month.payments == 0 {
            if !hasActive { return String(localized: "Every bill is paused") }
            if month.month == today.monthIndex { return String(localized: "Nothing to pay this month") }
            return String(localized: "Nothing to pay in \(name)")
        }
        if month.month == today.monthIndex { return String(localized: "What you pay this month") }
        return String(localized: "What you’ll pay in \(name)")
    }

    private func hint(flat: Bool) -> LocalizedStringKey {
        if flat { return "Every month costs the same" }
        return "Tap a month to see its total"
    }
}

/// One month in the grid: its name, a short amount and a bar compared with the busiest month.
struct MonthCell: View {
    var month: MonthTotal
    var isSelected: Bool
    var isCurrent: Bool
    var isFuture: Bool
    var code: String
    var action: () -> Void
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: month.firstDay.noon.formatted(.dateTime.month(.abbreviated)))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isSelected ? Color.white : (isCurrent ? Color.accentColor : Color.secondary))
                    .lineLimit(1)
                Text(verbatim: Self.short(month.value))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.white : (isFuture ? Color.secondary : Color.primary))
                    .opacity(month.value == 0 && !isSelected ? 0.45 : 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 4)

            }
            .padding(.horizontal, 9)
            .padding(.top, 8)
            .padding(.bottom, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color(uiColor: .systemGroupedBackground))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color(uiColor: .separator), lineWidth: 2 / max(displayScale, 1))
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: month.firstDay.noon.formatted(.dateTime.month(.wide)) + ", " + Format.money(month.amount, code: code)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// "250", "1.2K", "12.5K".
    static func short(_ value: Double) -> String {
        let rounded = abs(value) < 1000 ? value.rounded() : value
        return rounded.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
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
            let goal = Format.goal(item.schedule.goalCount, item.schedule.goalPeriod)
            return goal + " · " + String(localized: "no set day")
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
        if item.isAutopay {
            parts.append(String(localized: "Charged automatically"))
        }
        return parts.joined(separator: " · ")
    }
}
