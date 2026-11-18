import Foundation

/// Everything that decides the day you're living, so it can be worked out for any moment
/// (now, or when a reminder arrives).
struct DayRules: Hashable {
    /// When each day started, by calendar day: "2025-11-04" → minutes after midnight.
    var wakes: [String: Int] = [:]
    /// How long your days usually last.
    var usualDay: Int = DayClock.defaultDay
    /// When a day you're still up for ends, in minutes after the next midnight, by the day it began.
    /// Missing days use `SleepCheck.cut` for someone who isn't known to be still up.
    var cuts: [String: Int] = [:]
    /// When you really got up, if you haven't slept since before the current day began.
    var upSince: Date? = nil

    func clock(at now: Date) -> DayClock {
        DayClock.make(now: now, rules: self)
    }
}

/// Where you are in your day. A day starts at the wake-up time you set, and it keeps going past
/// midnight while you're still up, until it ends by itself (see `SleepCheck.cut`) or you say you
/// slept. Without a wake-up time it's simply the calendar day.
///
/// Wake-up times are saved under the calendar day you got up, in minutes after midnight.
struct DayClock: Hashable {
    /// The day you're living. After midnight it can still be yesterday.
    var day: Day
    /// Minutes since the start of `day`: 1:30 the next night is 1530.
    var minute: Int
    /// When the day started, in minutes after the start of `day`. Nil until you've set it.
    var wake: Int?
    /// When you really got up, if that was before `wake` because you haven't slept since.
    var upSince: Date? = nil
    /// When this day began: when you got up, or midnight (or when yesterday's day ended).
    var began: Date
    var now: Date
    /// How long your days usually last.
    var usualDay: Int = DayClock.defaultDay

    static let defaultDay = 16 * 60
    /// A day never lasts more than 24 hours.
    static let longestDay = 24 * 60

    static func make(now: Date, rules: DayRules) -> DayClock {
        let today = Day(now)
        let yesterday = today.adding(days: -1)
        let nowMinute = now.minutesOfDay
        let usual = rules.usualDay

        // Up today. A wake-up a few minutes ahead (another device's clock) still counts.
        if let w = rules.wakes[today.iso], w <= nowMinute + 10 {
            let began = today.date(minutes: w)
            return DayClock(day: today, minute: nowMinute, wake: w, upSince: realStart(rules.upSince, began: began),
                            began: began, now: now, usualDay: usual)
        }

        var began = today.start
        // Up since yesterday and not slept: the day keeps going past midnight, until it ends by itself.
        if let w = rules.wakes[yesterday.iso] {
            let cut = rules.cuts[yesterday.iso] ?? SleepCheck.cut(wakeMinute: w, stillUp: false, usualDay: usual)
            if nowMinute < cut {
                let start = yesterday.date(minutes: w)
                return DayClock(day: yesterday, minute: nowMinute + 24 * 60, wake: w,
                                upSince: realStart(rules.upSince, began: start),
                                began: start, now: now, usualDay: usual)
            }
            // What you did before yesterday's day ended belongs to yesterday.
            began = today.date(minutes: cut)
        }

        // Not started yet: the calendar day.
        return DayClock(day: today, minute: nowMinute, wake: nil, upSince: nil, began: min(began, now), now: now, usualDay: usual)
    }

    /// For tests and simple callers: wake-up times only, nobody known to be still up.
    static func make(now: Date, wakes: [String: Int], usualDay: Int = defaultDay) -> DayClock {
        make(now: now, rules: DayRules(wakes: wakes, usualDay: usualDay))
    }

    /// `upSince` only counts if it's before the day began, and not days ago.
    private static func realStart(_ upSince: Date?, began: Date) -> Date? {
        guard let up = upSince, up < began, began.timeIntervalSince(up) < 72 * 3600 else { return nil }
        return up
    }

    /// The calendar day, ignoring wake-up times. Bills use this.
    static func calendar(_ now: Date) -> DayClock {
        let today = Day(now)
        return DayClock(day: today, minute: now.minutesOfDay, wake: nil, began: today.start, now: now)
    }

    /// Today with a known wake-up time.
    static func simple(now: Date, wake: Int?) -> DayClock {
        let today = Day(now)
        return DayClock(day: today, minute: now.minutesOfDay, wake: wake, began: today.date(minutes: wake ?? 0), now: now)
    }

    var isUp: Bool { wake != nil }
    /// Still up after midnight.
    var isPastMidnight: Bool { minute >= 24 * 60 }
    var wakeDate: Date? { wake.map { day.date(minutes: $0) } }
    /// When you really got up: before this day began if you haven't slept since.
    var upDate: Date? { upSince ?? wakeDate }
    var minutesUp: Int {
        guard let start = upDate else { return 0 }
        return max(0, Int(now.timeIntervalSince(start) / 60))
    }

    /// Hourly things keep coming until the day ends, at most a day after it began.
    var end: Int {
        if let wake { return wake + DayClock.longestDay }
        return DayClock.longestDay
    }

    /// Reminders stop after a usual day, so they don't ring all night.
    var reminderEnd: Int {
        guard let wake else { return DayClock.longestDay }
        return min(max(wake + usualDay, minute + 2 * 60), wake + DayClock.longestDay)
    }

    /// Checked off during this day.
    func includes(_ entry: LogEntry) -> Bool {
        guard entry.at <= now.addingTimeInterval(60) else { return false }
        return entry.at >= began || (entry.day == day && entry.at >= day.start)
    }
}
