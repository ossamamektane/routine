import Foundation

/// Scheduling always uses the Gregorian calendar in the phone's current time zone,
/// even when the phone displays dates with another calendar.
enum RoutineCalendar {
    private static var cached = make()
    private static var zoneID = TimeZone.current.identifier

    static var current: Calendar {
        let id = TimeZone.current.identifier
        if id != zoneID {
            zoneID = id
            cached = make()
        }
        return cached
    }

    /// Call after the system reports a time-zone or locale change.
    static func refresh() {
        NSTimeZone.resetSystemTimeZone()
        zoneID = TimeZone.current.identifier
        cached = make()
    }

    private static func make() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        calendar.locale = Locale.current
        return calendar
    }
}

/// A calendar day without a clock time. Stored as "yyyy-MM-dd".
struct Day: Hashable, Comparable, Codable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        let m = min(max(month, 1), 12)
        self.year = year
        self.month = m
        self.day = min(max(day, 1), Day.daysIn(year: year, month: m))
    }

    init(_ date: Date) {
        let c = RoutineCalendar.current.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 2001, month: c.month ?? 1, day: c.day ?? 1)
    }

    init(index: Int) {
        let c = Day.civil(fromDays: index)
        self.init(year: c.year, month: c.month, day: c.day)
    }

    init?(iso: String) {
        let parts = iso.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), d >= 1, d <= Day.daysIn(year: y, month: m) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    static var today: Day { Day(Date()) }

    /// Days since 1970-01-01.
    var index: Int { Day.days(fromCivil: year, month: month, day: day) }
    var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }
    var description: String { iso }
    var monthIndex: Int { year * 12 + (month - 1) }

    /// 1 = Sunday … 7 = Saturday, like Calendar's weekday numbers.
    var weekday: Int {
        let r = (index + 4) % 7
        return (r < 0 ? r + 7 : r) + 1
    }

    /// The Monday of this day's week. Used for stable "every N weeks" counting.
    var monday: Day { adding(days: -((weekday + 5) % 7)) }

    func adding(days n: Int) -> Day { Day(index: index + n) }
    func adding(months n: Int) -> Day { Day.inMonth(monthIndex + n, day: day) }
    func days(since other: Day) -> Int { index - other.index }

    /// The given day of a month index; the day is clamped to the month's length.
    static func inMonth(_ monthIndex: Int, day: Int) -> Day {
        let y = Day.floorDiv(monthIndex, 12)
        let m = monthIndex - y * 12 + 1
        return Day(year: y, month: m, day: day)
    }

    var firstOfMonth: Day { Day(year: year, month: month, day: 1) }
    var lastOfMonth: Day { Day(year: year, month: month, day: Day.daysIn(year: year, month: month)) }

    /// The first date on `day` of a month, from the month of `from` on and not before `notBefore`.
    /// Months that are too short are skipped, so a start on the 31st really is the 31st.
    static func firstDate(onDay day: Int, from: Day, notBefore: Day) -> Day {
        let wanted = min(max(day, 1), 31)
        for k in 0..<48 {
            let first = Day.inMonth(from.monthIndex + k, day: 1)
            guard Day.daysIn(year: first.year, month: first.month) >= wanted else { continue }
            let candidate = Day(year: first.year, month: first.month, day: wanted)
            if candidate >= notBefore { return candidate }
        }
        return from
    }

    func date(minutes: Int = 0) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        let clamped = min(max(minutes, 0), 24 * 60 - 1)
        c.hour = clamped / 60
        c.minute = clamped % 60
        return RoutineCalendar.current.date(from: c) ?? Date(timeIntervalSince1970: 0)
    }

    var start: Date { date(minutes: 0) }
    var noon: Date { date(minutes: 12 * 60) }
    /// The first moment of the following day.
    var end: Date { adding(days: 1).start }

    static func < (lhs: Day, rhs: Day) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let parsed = Day(iso: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid day \(text)")
        }
        self = parsed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso)
    }

    static func isLeap(_ y: Int) -> Bool { (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 }

    static func daysIn(year: Int, month: Int) -> Int {
        switch month {
        case 2: return isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    static func floorDiv(_ a: Int, _ b: Int) -> Int {
        let q = a / b
        return (a % b != 0 && ((a < 0) != (b < 0))) ? q - 1 : q
    }

    static func mod(_ a: Int, _ b: Int) -> Int {
        let r = a % b
        return r < 0 ? r + b : r
    }

    // Howard Hinnant's civil-date algorithms.
    static func days(fromCivil year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    static func civil(fromDays days: Int) -> (year: Int, month: Int, day: Int) {
        let z = days + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }
}

extension Date {
    /// Minutes after local midnight.
    var minutesOfDay: Int {
        let c = RoutineCalendar.current.dateComponents([.hour, .minute], from: self)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
