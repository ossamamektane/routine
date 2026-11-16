import SwiftUI
import Charts

/// The Bills tab: everything with an amount, what's paid this month and what's coming up.
struct MoneyView: View {
    @Environment(AppStore.self) private var store
    @State private var editor: EditorRequest?

    var body: some View {
        let summary = store.money
        let items = store.itemsByID
        let code = store.settings.currency
        let today = Day(store.now)
        let bills = store.visibleItems.filter(\.hasCost)

        NavigationStack {
            Group {
                if bills.isEmpty {
                    ContentUnavailableView {
                        Label("No bills yet", systemImage: "creditcard")
                    } description: {
                        Text("Add rent, subscriptions and anything else you pay for to see what’s coming up and what’s left to pay this month.")
                    } actions: {
                        Button("Add a bill") { editor = .newBill() }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    billList(summary: summary, items: items, bills: bills, code: code, today: today)
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
        }
    }

    private func billList(summary: MoneySummary, items: [UUID: Item], bills: [Item], code: String, today: Day) -> some View {
        let paused = bills.filter { $0.paused && !$0.isFinished }.sorted(by: Self.byTitle)
        let finished = bills.filter(\.isFinished).sorted(by: Self.byTitle)
        return List {
            if summary.hasCosts {
                monthSection(summary, code: code, today: today)
                chartSection(summary, code: code, today: today)
                if !summary.upcoming.isEmpty {
                    upcomingSection(summary, items: items, code: code, today: today)
                }
                billsSection(summary, items: items, code: code)
            }
            if !paused.isEmpty {
                Section("Paused") {
                    ForEach(paused) { item in
                        plainRow(item, today: today, code: code)
                    }
                }
            }
            if !finished.isEmpty {
                Section("Completed") {
                    ForEach(finished) { item in
                        plainRow(item, today: today, code: code)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private static func byTitle(_ lhs: Item, _ rhs: Item) -> Bool {
        lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
    }

    private func monthSection(_ summary: MoneySummary, code: String, today: Day) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text(Format.money(summary.total, code: code))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                ProgressView(value: summary.paidFraction)
                    .tint(.accentColor)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Paid")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                        Text(Format.money(summary.paid, code: code))
                            .font(.headline)
                            .monospacedDigit()
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Left to pay")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                        Text(Format.money(summary.left, code: code))
                            .font(.headline)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        } header: {
            Text(today.noon.formatted(.dateTime.month(.wide).year()))
        }
    }

    private func chartSection(_ summary: MoneySummary, code: String, today: Day) -> some View {
        Section {
            Chart(summary.months) { month in
                BarMark(
                    x: .value("Month", month.firstDay.noon, unit: .month),
                    y: .value("Amount", month.value)
                )
                .foregroundStyle(month.month == today.monthIndex ? Color.accentColor : Color.accentColor.opacity(0.45))
                .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(Format.moneyShort(amount, code: code))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                }
            }
            .frame(height: 180)
            .padding(.vertical, 8)
        } header: {
            Text("Next 12 months")
        } footer: {
            Text("About \(Format.money(summary.monthlyAverage, code: code)) a month · \(Format.money(summary.yearly, code: code)) a year")
        }
    }

    private func upcomingSection(_ summary: MoneySummary, items: [UUID: Item], code: String, today: Day) -> some View {
        Section("Coming up") {
            ForEach(summary.upcoming) { line in
                if let item = items[line.itemID] {
                    Button {
                        editor = .edit(item)
                    } label: {
                        MoneyLineRow(line: line, item: item, today: today, code: code)
                    }
                    .itemActions(item, store: store, editor: $editor)
                }
            }
        }
    }

    private func billsSection(_ summary: MoneySummary, items: [UUID: Item], code: String) -> some View {
        Section {
            ForEach(summary.perItem) { cost in
                if let item = items[cost.itemID] {
                    Button {
                        editor = .edit(item)
                    } label: {
                        BillCostRow(item: item, cost: cost, code: code)
                    }
                    .itemActions(item, store: store, editor: $editor)
                }
            }
        } header: {
            Text("Monthly cost")
        } footer: {
            Text("Monthly amounts are averages, so a yearly bill counts as a twelfth each month.")
        }
    }

    private func plainRow(_ item: Item, today: Day, code: String) -> some View {
        Button {
            editor = .edit(item)
        } label: {
            RoutineRow(item: item, today: today, currency: code)
        }
        .itemActions(item, store: store, editor: $editor)
    }
}

/// A bill with what it comes to each month. Colors are spelled out so the list's tint doesn't show through.
struct BillCostRow: View {
    var item: Item
    var cost: ItemCost
    var code: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.displayTitle)
                    .foregroundStyle(Color.primary)
                Text(verbatim: subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                if let perMonth = cost.perMonth {
                    Text("\(Format.money(perMonth, code: code))/mo")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Color.primary)
                } else {
                    Text("One-time")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
                Text(Format.money(cost.amount, code: code))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        let summary = item.schedule.summary
        return item.isAutopay ? summary + " · " + String(localized: "Autopay") : summary
    }
}

struct MoneyLineRow: View {
    var line: MoneyLine
    var item: Item
    var today: Day
    var code: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.displayTitle)
                    .foregroundStyle(Color.primary)
                Text(verbatim: subtitle)
                    .font(.subheadline)
                    .foregroundStyle(line.overdue ? Color.red : Color.secondary)
            }
            Spacer(minLength: 6)
            Text(Format.money(line.amount, code: code))
                .monospacedDigit()
                .foregroundStyle(Color.primary)
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        if line.overdue { return String(localized: "Overdue · was due \(Format.day(line.day))") }
        let when = Format.relative(line.day, today: today)
        return line.autopay ? when + " · " + String(localized: "Autopay") : when
    }
}
