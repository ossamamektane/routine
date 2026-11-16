import Foundation

struct MonthTotal: Identifiable, Hashable {
    var month: Int
    var amount: Decimal
    var id: Int { month }
    var firstDay: Day { Day.inMonth(month, day: 1) }
    var value: Double { NSDecimalNumber(decimal: amount).doubleValue }
}

/// A payment coming up (or overdue).
struct MoneyLine: Identifiable, Hashable {
    var id: String
    var itemID: UUID
    var day: Day
    var amount: Decimal
    var overdue: Bool
    var autopay: Bool
}

struct ItemCost: Identifiable, Hashable {
    var itemID: UUID
    /// Nil for one-time costs.
    var perMonth: Decimal?
    var amount: Decimal
    var id: UUID { itemID }
}

struct MoneySummary {
    var paid: Decimal = 0
    var left: Decimal = 0
    var total: Decimal { paid + left }
    var months: [MonthTotal] = []
    var upcoming: [MoneyLine] = []
    var perItem: [ItemCost] = []
    var yearly: Decimal = 0
    var monthlyAverage: Decimal { yearly / 12 }
    var hasCosts = false

    var paidFraction: Double {
        let t = NSDecimalNumber(decimal: total).doubleValue
        guard t > 0 else { return 0 }
        return min(1, NSDecimalNumber(decimal: paid).doubleValue / t)
    }
}

enum MoneyPlanner {
    static func summary(items: [Item], now: Date) -> MoneySummary {
        let today = Day(now)
        let costItems = items.filter { $0.isActive && $0.hasCost }
        var s = MoneySummary()
        s.hasCosts = !costItems.isEmpty
        guard s.hasCosts else { return s }

        let monthStart = today.firstOfMonth
        let monthEnd = today.lastOfMonth
        let byID = Dictionary(costItems.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let overdue = Planner.agenda(items: costItems, now: now, wake: nil, includeUpcoming: false).overdue

        // Paid this month: everything checked off this month, plus autopay that has already gone out.
        for item in items where item.deletedAt == nil {
            for entry in item.log where entry.kind == .done {
                let d = Day(entry.at)
                if d >= monthStart && d <= today, let amount = entry.amount { s.paid += amount }
            }
        }
        for item in costItems where item.isAutopay {
            let cost = item.cost ?? 0
            for d in days(from: max(monthStart, item.trackFrom), through: today) {
                s.paid += cost * Decimal(occurrenceCount(item, on: d, today: today))
            }
        }

        // Still to pay this month: overdue, plus what's due from today to the end of the month.
        for e in overdue {
            if let cost = byID[e.itemID]?.cost { s.left += cost }
        }
        for item in costItems {
            let cost = item.cost ?? 0
            if item.schedule.kind == .goal {
                let expected = expectedGoalCount(item.schedule, inMonthOf: today)
                let done = item.log.filter { $0.kind == .done && $0.day >= monthStart && $0.day <= monthEnd }.count
                s.left += cost * Decimal(max(0, expected - done))
                continue
            }
            for d in days(from: today, through: monthEnd) {
                s.left += cost * Decimal(remaining(item, on: d, today: today))
            }
        }

        // The next 12 months, starting with this one.
        var months = [MonthTotal(month: today.monthIndex, amount: s.paid + s.left)]
        for i in 1..<12 {
            let first = Day.inMonth(today.monthIndex + i, day: 1)
            var total: Decimal = 0
            for item in costItems {
                let cost = item.cost ?? 0
                if item.schedule.kind == .goal {
                    total += cost * Decimal(expectedGoalCount(item.schedule, inMonthOf: first))
                    continue
                }
                var count = 0
                for d in days(from: first, through: first.lastOfMonth) {
                    count += occurrenceCount(item, on: d, today: today)
                }
                total += cost * Decimal(count)
            }
            months.append(MonthTotal(month: first.monthIndex, amount: total))
        }
        s.months = months

        // Coming up: overdue first, then the next payment of each item in the next 30 days.
        var lines: [MoneyLine] = []
        for e in overdue {
            if let cost = byID[e.itemID]?.cost {
                lines.append(MoneyLine(id: e.id, itemID: e.itemID, day: e.day, amount: cost, overdue: true, autopay: false))
            }
        }
        let horizon = today.adding(days: 30)
        for item in costItems where item.schedule.kind != .goal {
            for d in days(from: today, through: horizon) where remaining(item, on: d, today: today) > 0 {
                lines.append(MoneyLine(id: item.id.uuidString + "|" + d.iso, itemID: item.id, day: d,
                                       amount: item.cost ?? 0, overdue: false, autopay: item.isAutopay))
                break
            }
        }
        lines.sort { lhs, rhs in
            if lhs.overdue != rhs.overdue { return lhs.overdue }
            return lhs.day < rhs.day
        }
        s.upcoming = lines

        s.perItem = costItems.map { (item: Item) -> ItemCost in
            let cost = item.cost ?? 0
            if item.schedule.kind == .once { return ItemCost(itemID: item.id, perMonth: nil, amount: cost) }
            return ItemCost(itemID: item.id, perMonth: cost * Decimal(item.schedule.occurrencesPerYear / 12), amount: cost)
        }
        .sorted { ($0.perMonth ?? 0) > ($1.perMonth ?? 0) }

        s.yearly = costItems.reduce(Decimal(0)) { sum, item in
            sum + (item.cost ?? 0) * Decimal(item.schedule.occurrencesPerYear)
        }
        return s
    }

    static func days(from a: Day, through b: Day) -> [Day] {
        guard a <= b else { return [] }
        return (a.index...b.index).map { Day(index: $0) }
    }

    /// How many times it's due on a day, projected forward for "after done" routines.
    static func occurrenceCount(_ item: Item, on d: Day, today: Day) -> Int {
        let s = item.schedule
        switch s.kind {
        case .goal:
            return 0
        case .once:
            return d == s.start ? 1 : 0
        case .afterDone:
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
        case .repeating:
            guard d >= item.trackFrom, s.occurs(on: d) else { return 0 }
            return max(1, s.slots(on: d, wake: 7 * 60).count)
        }
    }

    /// Occurrences on a day that still need paying.
    static func remaining(_ item: Item, on d: Day, today: Day) -> Int {
        let count = occurrenceCount(item, on: d, today: today)
        guard count > 0 else { return 0 }
        if item.isAutopay { return d > today ? count : 0 }
        if d == today {
            let logged = item.log.filter { $0.day == today }.count
            return max(0, count - logged)
        }
        return count
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
