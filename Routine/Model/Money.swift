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
    /// A running total: how much, and how many payments.
    struct Tally {
        var amount: Decimal = 0
        var payments = 0

        mutating func pay(_ value: Decimal) {
            amount += value
            payments += 1
        }

        mutating func add(_ other: Tally) {
            amount += other.amount
            payments += other.payments
        }
    }

    /// January to December of this year: what your bills come to in each month.
    /// - A payment you checked off counts what you paid, in the month it was due (for bills that
    ///   repeat after payment, the month you paid). A skipped one counts nothing.
    /// - Every other date counts the bill's amount: dates still to come, bills paid automatically
    ///   and ones not checked off yet.
    /// - A bill goes back to January on its usual dates, as if you'd always had it, unless you
    ///   picked its start date on purpose.
    /// - Days a bill was paused don't count, and a bill that's paused now only counts from when
    ///   you added it.
    static func yearMonths(items: [Item], now: Date) -> [MonthTotal] {
        let today = Day(now)
        let bills = items.filter { (item: Item) -> Bool in !item.isDeleted && item.hasCost }
        return (1...12).map { (month: Int) -> MonthTotal in
            let first = Day(year: today.year, month: month, day: 1)
            var total = Tally()
            for item in bills {
                total.add(billMonth(item, first: first, today: today))
            }
            return MonthTotal(month: first.monthIndex, amount: total.amount, payments: total.payments)
        }
    }

    /// What one bill comes to in the month that starts on `first`.
    static func billMonth(_ item: Item, first: Day, today: Day) -> Tally {
        switch item.schedule.kind {
        case .goal:
            return anyDayMonth(item, first: first)
        case .afterDone:
            return afterPaymentMonth(item, first: first, today: today)
        case .once, .repeating:
            return datedMonth(item, first: first)
        }
    }

    /// A bill on set dates. What you checked off is what counts; every other date counts the amount.
    static func datedMonth(_ item: Item, first: Day) -> Tally {
        let cost = item.cost ?? 0
        let last = first.lastOfMonth
        let dates = billDays(item, inMonthOf: first)
        let onDates = Set(dates)
        // The latest check-off for each date this month.
        var records: [Day: LogEntry] = [:]
        for entry in item.log where entry.day >= first && entry.day <= last {
            if let kept = records[entry.day], kept.at > entry.at { continue }
            records[entry.day] = entry
        }
        var tally = Tally()
        var open = 0
        for d in dates {
            if let entry = records[d] {
                if entry.kind == .done { tally.pay(entry.amount ?? cost) }
            } else if !item.wasPaused(on: d) {
                open += 1
            }
        }
        // Checked off on a date the bill isn't on any more (its dates were changed): it still
        // counts, in place of one of this month's dates that wasn't checked off, so the same
        // payment never counts twice.
        var moved = 0
        for (d, entry) in records where !onDates.contains(d) {
            moved += 1
            if entry.kind == .done { tally.pay(entry.amount ?? cost) }
        }
        for _ in 0..<max(0, open - moved) {
            tally.pay(cost)
        }
        return tally
    }

    /// The dates a bill on set dates falls on in a month.
    static func billDays(_ item: Item, inMonthOf first: Day) -> [Day] {
        let s = item.schedule
        let month = days(from: first, through: first.lastOfMonth)
        switch s.kind {
        case .goal, .afterDone:
            return []
        case .once:
            return month.filter { (d: Day) -> Bool in d == s.start }
        case .repeating:
            // From its start date, or back to January as if you'd always had it. A bill that's
            // paused now doesn't go back further than when you added it.
            let back = goesBack(item)
            let from: Day? = back ? (item.paused ? Day(item.createdAt) : nil) : s.start
            return month.filter { (d: Day) -> Bool in
                if let from, d < from { return false }
                return onRepeat(d, s)
            }
        }
    }

    /// Whether a repeating bill falls on `d`, counting back before its start date too. The same
    /// dates as `Schedule.occurs(on:)` from the start date on.
    static func onRepeat(_ d: Day, _ s: Schedule) -> Bool {
        let n = max(1, s.every)
        switch s.unit {
        case .hour:
            return true
        case .day:
            return mod(d.index - s.start.index, n) == 0
        case .week:
            let weeks = (d.monday.index - s.start.monday.index) / 7
            return mod(weeks, n) == 0 && s.effectiveWeekdays.contains(d.weekday)
        case .month, .year:
            let step = s.unit == .month ? n : 12 * n
            return mod(d.monthIndex - s.start.monthIndex, step) == 0 && d == Day.inMonth(d.monthIndex, day: s.start.day)
        }
    }

    /// Whether a repeating bill's dates go back before its start date, as if you'd always had it.
    /// They do when the start date is just when it was next (or last) due on the day you added it
    /// or changed it. A start date further away was picked on purpose: nothing counts before it.
    static func goesBack(_ item: Item) -> Bool {
        let s = item.schedule
        guard s.kind == .repeating else { return false }
        var changed = [Day(item.createdAt)]
        // Resuming also moves `trackFrom`, but doesn't change the dates.
        if !item.pauses.contains(where: { (span: PauseSpan) -> Bool in span.end == item.trackFrom }) {
            changed.append(item.trackFrom)
        }
        for d in changed where s.start >= step(d, s, -1) && s.start <= step(d, s, 1) {
            return true
        }
        return false
    }

    /// `k` repeats after `d` (or before it, when `k` is negative).
    static func step(_ d: Day, _ s: Schedule, _ k: Int) -> Day {
        let n = max(1, s.every)
        switch s.unit {
        case .hour: return d.adding(days: k)
        case .day: return d.adding(days: k * n)
        case .week: return d.adding(days: 7 * k * n)
        case .month: return d.adding(months: k * n)
        case .year: return d.adding(months: 12 * k * n)
        }
    }

    /// A bill that repeats after payment: each payment counts in the month you paid it. Dates
    /// still to come count from when it's next due, and before the first payment it goes back on
    /// the same interval, as if you'd always had it.
    static func afterPaymentMonth(_ item: Item, first: Day, today: Day) -> Tally {
        let cost = item.cost ?? 0
        let last = first.lastOfMonth
        var tally = Tally()
        for entry in item.log where entry.kind == .done {
            let paid = Day(entry.at)
            if paid >= first && paid <= last { tally.pay(entry.amount ?? cost) }
        }
        for d in afterPaymentDays(item, from: first, through: last, today: today) where !item.wasPaused(on: d) {
            tally.pay(cost)
        }
        return tally
    }

    /// The dates without a payment yet for a bill that repeats after payment, from `first`
    /// through `last`.
    static func afterPaymentDays(_ item: Item, from first: Day, through last: Day, today: Day) -> [Day] {
        let s = item.schedule
        let next = s.nextDue ?? s.start
        var result: [Day] = []
        // When it's due next, then one interval after each, as if each is paid on time (or
        // today, when it's late).
        if next >= first && next <= last { result.append(next) }
        let base = max(next, today)
        var k = 1
        while k < 2000 {
            let d = step(base, s, k)
            if d > last { break }
            if d >= first { result.append(d) }
            k += 1
        }
        // Before the first payment. Not when its first date was set further out on purpose, and
        // for a bill that's paused now, not before you added it.
        let added = Day(item.createdAt)
        let earliest = item.log.map { (entry: LogEntry) -> Day in Day(entry.at) }.min() ?? next
        let anchor = min(earliest, next)
        guard anchor <= step(added, s, 1) else { return result }
        let lowest: Day? = item.paused ? added : nil
        k = 1
        while k < 2000 {
            let d = step(anchor, s, -k)
            if d < first { break }
            if let lowest, d < lowest { break }
            if d <= last { result.append(d) }
            k += 1
        }
        return result
    }

    /// An any-day bill: its amount the number of times you set, for each day, week or month of
    /// it. A week counts in the month it starts in, so each week counts once in the year.
    static func anyDayMonth(_ item: Item, first: Day) -> Tally {
        let s = item.schedule
        let added = Day(item.createdAt)
        let times = max(0, s.goalCount)
        // Every day, as if you'd always had it, except days it was paused. A bill that's paused
        // now only from when you added it.
        let counts = { (d: Day) -> Bool in
            if item.paused && d < added { return false }
            return !item.wasPaused(on: d)
        }
        let month = days(from: first, through: first.lastOfMonth)
        var periods = 0
        switch s.goalPeriod {
        case .day:
            periods = month.filter(counts).count
        case .week:
            for d in month where s.goalRange(containing: d).lowerBound == d {
                if days(from: d, through: d.adding(days: 6)).contains(where: counts) { periods += 1 }
            }
        case .month:
            periods = month.contains(where: counts) ? 1 : 0
        }
        var tally = Tally()
        tally.payments = times * periods
        tally.amount = (item.cost ?? 0) * Decimal(times * periods)
        return tally
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
