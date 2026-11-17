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
    /// January to December of this year. Every month shows what your bills come to on their usual
    /// dates, as if you'd always had them, so months before you added a bill aren't empty. A start
    /// date you picked yourself is kept. What you actually paid replaces the usual amount, a skipped
    /// payment counts as nothing, and a paused bill only counts while it was active.
    static func yearMonths(items: [Item], now: Date) -> [MonthTotal] {
        let today = Day(now)
        let bills = items.filter { !$0.isDeleted && $0.hasCost }
        return (1...12).map { (month: Int) -> MonthTotal in
            let first = Day(year: today.year, month: month, day: 1)
            var amount: Decimal = 0
            var payments = 0
            for item in bills {
                let cost = item.cost ?? 0
                // A paused bill only counted while it was active: from when you added it until you
                // paused it. Payments you checked off always count.
                let pausedOn: Day? = item.paused ? Day(item.modifiedAt) : nil
                let added = Day(item.createdAt)
                if item.isAnyDayBill {
                    if pausedOn != nil { continue }
                    let n = expectedGoalCount(item.schedule, inMonthOf: first)
                    amount += cost * Decimal(n)
                    payments += n
                    continue
                }
                for d in billDays(item, inMonthOf: first) {
                    let entry = item.log.last(where: { $0.day == d })
                    if let entry, entry.kind == .skipped { continue }
                    if let pausedOn, entry == nil, d < added || d >= pausedOn { continue }
                    amount += entry?.amount ?? cost
                    payments += 1
                }
            }
            return MonthTotal(month: first.monthIndex, amount: amount, payments: payments)
        }
    }

    /// The days a bill on set dates falls on in a month.
    static func billDays(_ item: Item, inMonthOf first: Day) -> [Day] {
        let s = item.schedule
        let month = days(from: first, through: first.lastOfMonth)
        switch s.kind {
        case .goal:
            return []
        case .once:
            return month.filter { $0 == s.start }
        case .repeating, .afterDone:
            let anchor = s.kind == .afterDone ? (s.nextDue ?? s.start) : s.start
            let since: Day? = startsWhenAdded(item) ? nil : s.start
            let n = max(1, s.every)
            var weekdays = s.effectiveWeekdays
            if s.kind == .afterDone { weekdays = [anchor.weekday] }
            return month.filter { (d: Day) -> Bool in
                if let since, d < since { return false }
                switch s.unit {
                case .hour:
                    return true
                case .day:
                    return mod(d.index - anchor.index, n) == 0
                case .week:
                    let weeks = (d.monday.index - anchor.monday.index) / 7
                    return mod(weeks, n) == 0 && weekdays.contains(d.weekday)
                case .month, .year:
                    let step = s.unit == .month ? n : 12 * n
                    return mod(d.monthIndex - anchor.monthIndex, step) == 0 && d == Day.inMonth(d.monthIndex, day: anchor.day)
                }
            }
        }
    }

    /// The start date wasn't picked: it's the first usual date after the bill was added.
    static func startsWhenAdded(_ item: Item) -> Bool {
        let s = item.schedule
        let added = Day(item.createdAt)
        guard s.start >= added else { return false }
        let n = max(1, s.every)
        let limit: Day
        switch s.unit {
        case .hour, .day: limit = added.adding(days: n)
        case .week: limit = added.adding(days: 7 * n)
        case .month: limit = added.adding(months: n)
        case .year: limit = added.adding(months: 12 * n)
        }
        return s.start <= limit
    }

    /// Remainder that's never negative, for counting back before a start date.
    static func mod(_ a: Int, _ n: Int) -> Int {
        ((a % n) + n) % n
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

    /// What bills you check off still come to from today to the end of the month: every date
    /// that isn't paid or skipped yet. Bills counted automatically have nothing left to pay.
    static func restOfMonth(items: [Item], today: Day) -> Decimal {
        let rest = days(from: today, through: today.lastOfMonth)
        var total: Decimal = 0
        for item in items where item.isActive && item.hasCost && !item.isAutopay && !item.isAnyDayBill {
            let s = item.schedule
            var n = 0
            for d in rest where !item.log.contains(where: { $0.day == d }) {
                if s.kind == .afterDone {
                    n += occurrenceCount(item, on: d, today: today)
                } else if s.occurs(on: d) {
                    n += 1
                }
            }
            total += (item.cost ?? 0) * Decimal(n)
        }
        return total
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
