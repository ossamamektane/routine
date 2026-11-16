import SwiftUI
import Charts

struct MoneyView: View {
    @Environment(AppStore.self) private var store
    @State private var editor: EditorRequest?

    var body: some View {
        let summary = store.money
        let items = store.itemsByID
        let code = store.settings.currency
        let today = Day(store.now)

        NavigationStack {
            content(summary: summary, items: items, code: code, today: today)
                .navigationTitle("Money")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            editor = .new(billTemplate())
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

    @ViewBuilder
    private func content(summary: MoneySummary, items: [UUID: Item], code: String, today: Day) -> some View {
        if summary.hasCosts {
            List {
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
                                    .foregroundStyle(.secondary)
                                Text(Format.money(summary.paid, code: code))
                                    .font(.headline)
                                    .monospacedDigit()
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Left to pay")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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

                if !summary.upcoming.isEmpty {
                    Section("Coming up") {
                        ForEach(summary.upcoming) { line in
                            if let item = items[line.itemID] {
                                Button {
                                    editor = .edit(item)
                                } label: {
                                    MoneyLineRow(line: line, item: item, today: today, code: code)
                                }
                            }
                        }
                    }
                }

                Section {
                    ForEach(summary.perItem) { cost in
                        if let item = items[cost.itemID] {
                            Button {
                                editor = .edit(item)
                            } label: {
                                HStack(spacing: 12) {
                                    SymbolTile(symbol: item.symbol, color: item.color.color, size: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(verbatim: item.displayTitle)
                                            .foregroundStyle(.primary)
                                        Text(verbatim: item.schedule.summary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 6)
                                    VStack(alignment: .trailing, spacing: 2) {
                                        if let perMonth = cost.perMonth {
                                            Text("\(Format.money(perMonth, code: code))/mo")
                                                .font(.subheadline)
                                                .monospacedDigit()
                                                .foregroundStyle(.primary)
                                        } else {
                                            Text("One-time")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(Format.money(cost.amount, code: code))
                                            .font(.caption)
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("By routine")
                } footer: {
                    Text("Monthly amounts are averages, so a yearly bill counts as a twelfth each month.")
                }
            }
            .listStyle(.insetGrouped)
        } else {
            ContentUnavailableView {
                Label("No costs yet", systemImage: "creditcard")
            } description: {
                Text("Add a cost to anything — rent, a subscription, a haircut — and Money shows what's coming up and what's left to pay this month.")
            } actions: {
                Button("Add a bill") { editor = .new(billTemplate()) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct MoneyLineRow: View {
    var line: MoneyLine
    var item: Item
    var today: Day
    var code: String

    var body: some View {
        HStack(spacing: 12) {
            SymbolTile(symbol: item.symbol, color: item.color.color, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.displayTitle)
                    .foregroundStyle(.primary)
                Text(verbatim: subtitle)
                    .font(.subheadline)
                    .foregroundStyle(line.overdue ? Color.red : Color.secondary)
            }
            Spacer(minLength: 6)
            Text(Format.money(line.amount, code: code))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }

    private var subtitle: String {
        if line.overdue { return String(localized: "Overdue · was due \(Format.day(line.day))") }
        let when = Format.relative(line.day, today: today)
        return line.autopay ? when + " · " + String(localized: "Autopay") : when
    }
}
