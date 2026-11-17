import Foundation

/// What you pay in one month.
struct MonthTotal: Identifiable, Hashable {
    /// Months since year 0, like `Day.monthIndex`.
    var month: Int
    var amount: Decimal
    var payments: Int
    var id: Int { month }
    var firstDay: Day { Day.inMonth(month, day: 1) }
    var value: Double { NSDecimalNumber(decimal: amount).doubleValue }
}

enum MoneyPlanner {
    /// January to December of this year. Months gone by show what you paid: what you checked
    /// off, bills paid automatically on their dates, and any-day bills from when you added them.
    /// This month and the ones ahead show what you pay, every bill that isn't paused in full,
    /// paid or not, like the old Bills app.
    static func yearMonths(items: [Item], now: Date) -> [MonthTotal] {
        let today = Day(now)
        let bills = items.filter { !$0.isDeleted && $0.hasCost }
        return (1...12).map { (month: Int) -> MonthTotal in
            let first = Day(year: today.year, month: month, day: 1)
            var amount: Decimal = 0
            var payments = 0
            for item in bills {
                if first.monthIndex < today.monthIndex {
                    let paid = paidInMonth(item, first: first)
                    amount += paid.amount
                    payments += paid.count
                    continue
                }
                guard !item.paused else { continue }
                let n = item.isAnyDayBill ? anyDayCount(item, inMonthOf: first) : paymentCount(item, inMonthOf: first, today: today)
                guard n > 0 else { continue }
                amount += (item.cost ?? 0) * Decimal(n)
                payments += n
            }
            return MonthTotal(month: first.monthIndex, amount: amount, payments: payments)
        }
    }

    /// What a bill took in a month gone by.
    static func paidInMonth(_ item: Item, first: Day) -> (amount: Decimal, count: Int) {
        let last = first.lastOfMonth
        let cost = item.cost ?? 0
        if item.isAnyDayBill {
            let n = anyDayCount(item, inMonthOf: first)
            return (cost * Decimal(n), n)
        }
        if item.isAutopay {
            // Taken on each of its dates since it started, until it was paused.
            var end = last
            if item.paused { end = min(end, Day(item.modifiedAt).adding(days: -1)) }
            let n = days(from: first, through: end).filter { item.schedule.occurs(on: $0) }.count
            return (cost * Decimal(n), n)
        }
        // Paid by hand: what you checked off that month, at the price then.
        var amount: Decimal = 0
        var count = 0
        for entry in item.log where entry.kind == .done {
            let paid = Day(entry.at)
            guard paid >= first && paid <= last else { continue }
            amount += entry.amount ?? cost
            count += 1
        }
        return (amount, count)
    }

    /// Any-day bills (groceries, fuel): what a month usually takes, from the day you added it.
    static func anyDayCount(_ item: Item, inMonthOf first: Day) -> Int {
        let full = expectedGoalCount(item.schedule, inMonthOf: first)
        let added = Day(item.createdAt)
        if added.monthIndex > first.monthIndex { return 0 }
        if added.monthIndex < first.monthIndex { return full }
        let length = Day.daysIn(year: first.year, month: first.month)
        let remaining = length - added.day + 1
        return Int((Double(full) * Double(remaining) / Double(length)).rounded())
    }

    /// The next 12 months, starting with this one. Like the old Bills app, every bill that isn't
    /// paused counts in full for its month, paid or not.
    static func monthsAhead(items: [Item], now: Date) -> [MonthTotal] {
        let today = Day(now)
        let bills = items.filter { !$0.isDeleted && $0.hasCost && !$0.paused }
        return (0..<12).map { (offset: Int) -> MonthTotal in
            let first = Day.inMonth(today.monthIndex + offset, day: 1)
            var amount: Decimal = 0
            var payments = 0
            for item in bills {
                let n = paymentCount(item, inMonthOf: first, today: today)
                guard n > 0 else { continue }
                amount += (item.cost ?? 0) * Decimal(n)
                payments += n
            }
            return MonthTotal(month: first.monthIndex, amount: amount, payments: payments)
        }
    }

    /// How many times a bill is paid in a month.
    static func paymentCount(_ item: Item, inMonthOf first: Day, today: Day) -> Int {
        let s = item.schedule
        let last = first.lastOfMonth
        switch s.kind {
        case .once:
            return s.start >= first && s.start <= last ? 1 : 0
        case .goal:
            return expectedGoalCount(s, inMonthOf: first)
        case .repeating:
            return days(from: first, through: last).filter { s.occurs(on: $0) }.count
        case .afterDone:
            // Projected from when it's next due, plus what's already been paid this month.
            var n = 0
            for d in days(from: first, through: last) {
                n += occurrenceCount(item, on: d, today: today)
            }
            if first.monthIndex == today.monthIndex {
                n += item.log.filter { entry in
                    let paid = Day(entry.at)
                    return entry.kind == .done && paid >= first && paid <= today
                }.count
            }
            return n
        }
    }

    static func days(from a: Day, through b: Day) -> [Day] {
        guard a <= b else { return [] }
        return (a.index...b.index).map { Day(index: $0) }
    }

    /// How many times an "after done" bill is due on a day, projected forward.
    static func occurrenceCount(_ item: Item, on d: Day, today: Day) -> Int {
        let s = item.schedule
        guard s.kind == .afterDone else { return 0 }
        var first = s.nextDue ?? s.start
        if first < today {
            // Overdue: assume it gets done today, so the next one is an interval away.
            var copy = s
            copy.advanceAfterDone(at: today.noon)
            first = copy.nextDue ?? today
        }
        guard d >= first else { return 0 }
        let n = max(1, s.every)
        switch s.unit {
        case .hour: return d == first ? 1 : max(1, 24 / n)
        case .day: return (d.index - first.index) % n == 0 ? 1 : 0
        case .week: return (d.index - first.index) % (7 * n) == 0 ? 1 : 0
        case .month, .year:
            let step = s.unit == .month ? n : 12 * n
            let months = d.monthIndex - first.monthIndex
            return months % step == 0 && d == Day.inMonth(d.monthIndex, day: first.day) ? 1 : 0
        }
    }

    static func expectedGoalCount(_ s: Schedule, inMonthOf d: Day) -> Int {
        let length = Day.daysIn(year: d.year, month: d.month)
        switch s.goalPeriod {
        case .day: return s.goalCount * length
        case .week: return Int((Double(s.goalCount) * Double(length) / 7).rounded())
        case .month: return s.goalCount
        }
    }
}
