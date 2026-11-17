import Foundation

enum ScheduleKind: String, Codable, CaseIterable, Identifiable {
    /// On a fixed rhythm: every N hours, days, weeks, months or years.
    case repeating
    /// Comes back a set time after you last did it (haircut, change the sheets).
    case afterDone
    /// A number of times per day, week or month, whenever suits you.
    case goal
    /// One date, then it's finished.
    case once

    var id: String { rawValue }
}

enum RepeatUnit: String, Codable, CaseIterable, Identifiable {
    case hour, day, week, month, year
    var id: String { rawValue }
}

enum GoalPeriod: String, Codable, CaseIterable, Identifiable {
    case day, week, month
    var id: String { rawValue }
}

/// One time a routine is due on a given day.
/// `key` is what completions are stored against; `minute` is when it's due (nil = any time that day).
struct SlotTime: Hashable {
    var key: Int?
    var minute: Int?
}

struct Schedule: Codable, Hashable {
    var kind: ScheduleKind = .repeating
    var every: Int = 1
    var unit: RepeatUnit = .day
    /// First day for repeating routines, the date for one-time items.
    var start: Day = Day.today
    /// Minutes after midnight. Empty means "any time that day".
    var times: [Int] = []
    /// 1 = Sunday … 7 = Saturday. Weekly routines only.
    var weekdays: [Int] = []
    /// Minutes after you tap "I'm up". Daily (every day) and hourly routines only.
    var afterWaking: Int? = nil
    /// "After done" routines: the next day it's due.
    var nextDue: Day? = nil
    /// "After done" hourly routines: the exact time it's due on `nextDue`.
    var nextDueTime: Int? = nil
    var goalCount: Int = 3
    var goalPeriod: GoalPeriod = .week

    enum CodingKeys: String, CodingKey {
        case kind, every, unit, start, times, weekdays, afterWaking, nextDue, nextDueTime, goalCount, goalPeriod
    }
}

extension Schedule {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        kind = c.field(.kind, or: kind)
        every = c.field(.every, or: every)
        unit = c.field(.unit, or: unit)
        start = c.field(.start, or: start)
        times = c.field(.times, or: times)
        weekdays = c.field(.weekdays, or: weekdays)
        afterWaking = c.optionalField(.afterWaking)
        nextDue = c.optionalField(.nextDue)
        nextDueTime = c.optionalField(.nextDueTime)
        goalCount = c.field(.goalCount, or: goalCount)
        goalPeriod = c.field(.goalPeriod, or: goalPeriod)
        self = normalized()
    }

    var isHourly: Bool { kind == .repeating && unit == .hour }

    /// Wake-relative timing only makes sense for things that happen every day.
    var supportsWake: Bool { kind == .repeating && (unit == .hour || (unit == .day && every == 1)) }
    var usesWake: Bool { supportsWake && afterWaking != nil }

    var effectiveWeekdays: [Int] { weekdays.isEmpty ? [start.weekday] : weekdays }

    var isEveryDay: Bool {
        guard kind == .repeating, every == 1 else { return false }
        return unit == .day || (unit == .week && effectiveWeekdays.count == 7)
    }

    /// A missed occurrence stays on the list until it's done, skipped or the next one arrives.
    /// Daily and hourly routines simply roll over instead.
    var carriesOver: Bool {
        switch kind {
        case .once, .afterDone: return true
        case .goal: return false
        case .repeating:
            switch unit {
            case .hour: return false
            case .day: return every > 1
            case .week, .month, .year: return true
            }
        }
    }

    func normalized() -> Schedule {
        var s = self
        s.every = min(max(s.every, 1), 999)
        s.times = Array(Set(s.times.filter { (0..<1440).contains($0) })).sorted()
        s.weekdays = Array(Set(s.weekdays.filter { (1...7).contains($0) })).sorted()
        s.goalCount = min(max(s.goalCount, 1), 99)
        if let t = s.nextDueTime, !(0..<1440).contains(t) { s.nextDueTime = nil }
        switch s.kind {
        case .repeating:
            if s.unit == .hour {
                s.every = min(s.every, 12)
                s.times = Array(s.times.prefix(1))
            }
            if s.unit == .week {
                if s.weekdays.isEmpty { s.weekdays = [s.start.weekday] }
            } else {
                s.weekdays = []
            }
            s.nextDue = nil
            s.nextDueTime = nil
        case .afterDone:
            s.times = Array(s.times.prefix(1))
            s.weekdays = []
            if s.nextDue == nil { s.nextDue = s.start }
            if s.unit != .hour { s.nextDueTime = nil }
        case .once, .goal:
            s.times = Array(s.times.prefix(1))
            s.weekdays = []
            s.nextDue = nil
            s.nextDueTime = nil
        }
        if let w = s.afterWaking { s.afterWaking = min(max(w, 0), 18 * 60) }
        if !s.supportsWake { s.afterWaking = nil }
        if s.afterWaking != nil && s.unit != .hour { s.times = [] }
        return s
    }

    // MARK: Occurrences

    func occurs(on d: Day) -> Bool {
        switch kind {
        case .goal: return false
        case .once: return d == start
        case .afterDone: return d == (nextDue ?? start)
        case .repeating:
            guard d >= start else { return false }
            let n = max(1, every)
            switch unit {
            case .hour:
                return true
            case .day:
                return (d.index - start.index) % n == 0
            case .week:
                let weeks = (d.monday.index - start.monday.index) / 7
                return weeks % n == 0 && effectiveWeekdays.contains(d.weekday)
            case .month, .year:
                let step = unit == .month ? n : 12 * n
                let months = d.monthIndex - start.monthIndex
                return months % step == 0 && d == Day.inMonth(d.monthIndex, day: start.day)
            }
        }
    }

    func nextOccurrence(onOrAfter d: Day) -> Day? {
        switch kind {
        case .goal:
            return nil
        case .once:
            return start >= d ? start : nil
        case .afterDone:
            let due = nextDue ?? start
            return due >= d ? due : nil
        case .repeating:
            let from = max(d, start)
            let n = max(1, every)
            switch unit {
            case .hour:
                return from
            case .day:
                let k = (from.index - start.index + n - 1) / n
                return start.adding(days: k * n)
            case .week:
                for offset in 0..<(7 * n + 7) {
                    let candidate = from.adding(days: offset)
                    if occurs(on: candidate) { return candidate }
                }
                return nil
            case .month, .year:
                let step = unit == .month ? n : 12 * n
                var k = (from.monthIndex - start.monthIndex) / step
                for _ in 0..<3 {
                    let candidate = Day.inMonth(start.monthIndex + k * step, day: start.day)
                    if candidate >= from { return candidate }
                    k += 1
                }
                return nil
            }
        }
    }

    func previousOccurrence(onOrBefore d: Day) -> Day? {
        switch kind {
        case .goal:
            return nil
        case .once:
            return start <= d ? start : nil
        case .afterDone:
            let due = nextDue ?? start
            return due <= d ? due : nil
        case .repeating:
            guard d >= start else { return nil }
            let n = max(1, every)
            switch unit {
            case .hour:
                return d
            case .day:
                let k = (d.index - start.index) / n
                return start.adding(days: k * n)
            case .week:
                for offset in 0..<(7 * n + 7) {
                    let candidate = d.adding(days: -offset)
                    if candidate < start { return nil }
                    if occurs(on: candidate) { return candidate }
                }
                return nil
            case .month, .year:
                let step = unit == .month ? n : 12 * n
                var k = (d.monthIndex - start.monthIndex) / step
                while k >= 0 {
                    let candidate = Day.inMonth(start.monthIndex + k * step, day: start.day)
                    if candidate <= d { return candidate }
                    k -= 1
                }
                return nil
            }
        }
    }

    /// The times something is due on a day that it occurs, in minutes after that day's midnight.
    /// Wake-relative routines have no time until you've tapped "I'm up" (`wake` is nil).
    /// Hourly routines repeat until `end`: by default a day after waking up, or midnight.
    func slots(on day: Day, wake: Int?, end: Int? = nil) -> [SlotTime] {
        switch kind {
        case .goal:
            return []
        case .once:
            return [SlotTime(key: nil, minute: times.first)]
        case .afterDone:
            return [SlotTime(key: nil, minute: unit == .hour ? (nextDueTime ?? times.first) : times.first)]
        case .repeating:
            if unit == .hour {
                let first: Int
                if let offset = afterWaking {
                    guard let w = wake else { return [] }
                    first = w + offset
                } else {
                    first = times.first ?? 8 * 60
                }
                let limit = end ?? (wake.map { $0 + 24 * 60 } ?? 24 * 60)
                return Schedule.hourlySlots(first: first, every: every, end: limit)
            }
            if let offset = afterWaking {
                return [SlotTime(key: nil, minute: wake.map { $0 + offset })]
            }
            if times.isEmpty { return [SlotTime(key: nil, minute: nil)] }
            return times.map { SlotTime(key: $0, minute: $0) }
        }
    }

    /// Every N hours from `first`, stopping before `end`.
    static func hourlySlots(first: Int, every: Int, end: Int) -> [SlotTime] {
        let step = max(1, every) * 60
        var result: [SlotTime] = []
        var minute = first
        var k = 0
        while minute < end && k < 48 {
            result.append(SlotTime(key: k, minute: minute))
            minute += step
            k += 1
        }
        return result
    }

    /// The day, week or month a goal is counted in. Weeks follow the phone's first weekday.
    func goalRange(containing d: Day) -> ClosedRange<Day> {
        switch goalPeriod {
        case .day:
            return d...d
        case .week:
            let back = Day.mod(d.weekday - RoutineCalendar.current.firstWeekday, 7)
            let first = d.adding(days: -back)
            return first...first.adding(days: 6)
        case .month:
            return d.firstOfMonth...d.lastOfMonth
        }
    }

    /// Moves an "after done" routine forward from the moment it was done or skipped.
    mutating func advanceAfterDone(at date: Date) {
        let n = max(1, every)
        let day = Day(date)
        switch unit {
        case .hour:
            let next = date.addingTimeInterval(TimeInterval(n * 3600))
            nextDue = Day(next)
            nextDueTime = next.minutesOfDay
        case .day:
            nextDue = day.adding(days: n)
            nextDueTime = nil
        case .week:
            nextDue = day.adding(days: 7 * n)
            nextDueTime = nil
        case .month:
            nextDue = day.adding(months: n)
            nextDueTime = nil
        case .year:
            nextDue = day.adding(months: 12 * n)
            nextDueTime = nil
        }
    }

    /// How many times a day it usually comes up (for cost estimates).
    var typicalSlotsPerDay: Int {
        guard kind == .repeating else { return 1 }
        return max(1, slots(on: start, wake: 7 * 60, end: 7 * 60 + DayClock.defaultDay).count)
    }

    /// Roughly how many times a year this comes up. Used for cost estimates only.
    var occurrencesPerYear: Double {
        let n = Double(max(1, every))
        let perDay = Double(typicalSlotsPerDay)
        switch kind {
        case .once:
            return 0
        case .goal:
            let count = Double(goalCount)
            switch goalPeriod {
            case .day: return count * 365
            case .week: return count * 365 / 7
            case .month: return count * 12
            }
        case .afterDone:
            switch unit {
            case .hour: return 365 * 24 / n
            case .day: return 365 / n
            case .week: return 365 / 7 / n
            case .month: return 12 / n
            case .year: return 1 / n
            }
        case .repeating:
            switch unit {
            case .hour: return 365 * perDay
            case .day: return 365 / n * perDay
            case .week: return 365 / 7 / n * Double(effectiveWeekdays.count) * perDay
            case .month: return 12 / n * perDay
            case .year: return 1 / n * perDay
            }
        }
    }
}

// MARK: - Forgiving decoding

/// Reading saved data never fails because one field is missing or from a newer version.
extension KeyedDecodingContainer {
    func field<T: Decodable>(_ key: Key, or fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }

    func optionalField<T: Decodable>(_ key: Key) -> T? {
        try? decodeIfPresent(T.self, forKey: key)
    }
}

/// Decodes an element if it can; a damaged element is dropped instead of failing the whole list.
struct Lossy<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
