import Foundation

/// Where you are in your day. A day starts when you tap "I'm up" and keeps going until you tap
/// "Going to sleep", even past midnight. Until you tap "I'm up" it's simply the calendar day.
///
/// Wake-up times are saved under the calendar day you got up, in minutes after midnight.
/// Sleep times are saved under the day they end, in minutes after that day's midnight,
/// so going to bed at 1:00 the next night is 1500.
struct DayClock: Hashable {
    /// The day you're living. After midnight it's still yesterday until you sleep.
    var day: Day
    /// Minutes since the start of `day`: 1:30 the next night is 1530.
    var minute: Int
    /// When you got up, in minutes after the start of `day`. Nil until you tap "I'm up".
    var wake: Int?
    /// When you went to sleep, in minutes after the start of `day`.
    var sleep: Int?
    /// You said you were going to sleep and haven't tapped "I'm up" since.
    var asleepSince: Date?
    /// When this day began: when you got up, or midnight.
    var began: Date
    var now: Date
    /// How long your days usually last, from getting up to going to sleep.
    var usualDay: Int = DayClock.defaultDay

    static let defaultDay = 16 * 60
    /// A day never lasts more than 24 hours.
    static let longestDay = 24 * 60
    /// How long "Asleep" is shown after you tap "Going to sleep".
    static let longestSleep = 20 * 60

    static func make(now: Date, wakes: [String: Int], sleeps: [String: Int]) -> DayClock {
        let today = Day(now)
        let yesterday = today.adding(days: -1)
        let nowMinute = now.minutesOfDay
        let usual = typicalLength(wakes: wakes, sleeps: sleeps)

        // Up today.
        if let w = wakes[today.iso], w <= nowMinute {
            var slept: Int? = nil
            if let s = sleeps[today.iso], s >= w, s <= nowMinute { slept = s }
            return DayClock(day: today, minute: nowMinute, wake: w, sleep: slept,
                            asleepSince: slept.map { today.date(minutes: $0) },
                            began: today.date(minutes: w), now: now, usualDay: usual)
        }

        // Still up since yesterday: the day keeps going past midnight until you sleep.
        let lateMinute = nowMinute + 24 * 60
        if let w = wakes[yesterday.iso], lateMinute < w + longestDay {
            var slept = false
            if let s = sleeps[yesterday.iso], s >= w { slept = true }
            if !slept {
                return DayClock(day: yesterday, minute: lateMinute, wake: w, sleep: nil, asleepSince: nil,
                                began: yesterday.date(minutes: w), now: now, usualDay: usual)
            }
        }

        // Not up yet: the calendar day.
        var clock = DayClock(day: today, minute: nowMinute, wake: nil, sleep: nil, asleepSince: nil,
                             began: today.start, now: now, usualDay: usual)
        if let s = sleeps[today.iso], s <= nowMinute {
            clock.sleep = s
            clock.asleepSince = today.date(minutes: s)
        } else if let s = sleeps[yesterday.iso], s >= (wakes[yesterday.iso] ?? 0) {
            let moment = yesterday.date(minutes: s)
            if moment <= now {
                if now.timeIntervalSince(moment) < Double(longestSleep * 60) {
                    clock.asleepSince = moment
                }
                // What you did before going to sleep belongs to yesterday.
                if moment > today.start {
                    clock.began = moment
                }
            }
        }
        return clock
    }

    /// The calendar day, ignoring wake-up and sleep times. Bills use this.
    static func calendar(_ now: Date) -> DayClock {
        let today = Day(now)
        return DayClock(day: today, minute: now.minutesOfDay, wake: nil, sleep: nil, asleepSince: nil,
                        began: today.start, now: now)
    }

    /// Today with a known wake-up time and no sleep.
    static func simple(now: Date, wake: Int?) -> DayClock {
        let today = Day(now)
        return DayClock(day: today, minute: now.minutesOfDay, wake: wake, sleep: nil, asleepSince: nil,
                        began: today.date(minutes: wake ?? 0), now: now)
    }

    /// The middle of your recent day lengths, so reminders stop around when you usually sleep.
    static func typicalLength(wakes: [String: Int], sleeps: [String: Int]) -> Int {
        var lengths: [Int] = []
        for (key, slept) in sleeps {
            guard let woke = wakes[key], slept > woke else { continue }
            lengths.append(slept - woke)
        }
        guard !lengths.isEmpty else { return defaultDay }
        lengths.sort()
        return min(max(lengths[lengths.count / 2], 12 * 60), 22 * 60)
    }

    var isUp: Bool { wake != nil && sleep == nil }
    var isAsleep: Bool { asleepSince != nil }
    /// Still up after midnight.
    var isPastMidnight: Bool { minute >= 24 * 60 }
    var wakeDate: Date? { wake.map { day.date(minutes: $0) } }
    var minutesUp: Int { wake.map { max(0, minute - $0) } ?? 0 }

    /// Hourly things keep coming until you sleep, at most a day after you got up.
    var end: Int {
        if let sleep { return sleep }
        if let wake { return wake + DayClock.longestDay }
        return DayClock.longestDay
    }

    /// Reminders stop after a usual day, in case you forget to tap "Going to sleep".
    var reminderEnd: Int {
        if let sleep { return sleep }
        guard let wake else { return DayClock.longestDay }
        return min(max(wake + usualDay, minute + 2 * 60), wake + DayClock.longestDay)
    }

    /// Checked off during this day.
    func includes(_ entry: LogEntry) -> Bool {
        guard entry.at <= now.addingTimeInterval(60) else { return false }
        return entry.at >= began || (entry.day == day && entry.at >= day.start)
    }
}
