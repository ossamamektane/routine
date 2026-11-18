import Foundation

// "Did you sleep?"
//
// Routine never guesses when you sleep, and it never starts a day by itself. It only decides
// WHEN to ask, by scoring clues: how long the app sat untouched, how much of that quiet
// stretch fell in your usual night, how long you'd been up before it, how close it is to when
// you usually wake, and reminders that went by with nothing checked off. It learns your usual wake-up time and how long your days last
// from your own answers. Everything here is plain logic: the store keeps the `SleepLog`
// and passes in the time, so it can be tested with any clock.

/// A stretch of time when the app was in use.
struct ActivitySpan: Codable, Hashable {
    var start: Date
    var end: Date

    enum CodingKeys: String, CodingKey {
        case start = "s", end = "e"
    }
}

/// "Did you sleep?" is waiting for an answer on Today.
struct SleepQuestion: Codable, Hashable {
    /// When you were last seen before the quiet stretch, or when it was asked.
    var from: Date
    /// Asked because of a quiet stretch (so your answer teaches Routine how long your days are).
    var auto: Bool
}

/// What Routine remembers to decide when to ask. Kept on this iPhone only.
struct SleepLog: Codable, Hashable {
    /// When the app was used over the last few days.
    var spans: [ActivitySpan] = []
    var question: SleepQuestion? = nil
    /// Your last few wake-up times, in minutes after midnight.
    var wakeMinutes: [Int] = []
    /// How long your last few days lasted, in minutes: from waking up to when you were last seen.
    var dayLengths: [Int] = []
    /// When you last said you hadn't slept yet.
    var stillUpAt: Date? = nil
    /// When you really woke up, if the current day started without sleep in between.
    var upSince: Date? = nil
    /// You've answered the question or set a wake-up time at least once.
    var used: Bool = false
    /// When you last chose "Not Now"; Routine doesn't ask again about the same wake-up.
    var dismissedAt: Date? = nil

    enum CodingKeys: String, CodingKey {
        case spans, question, wakeMinutes, dayLengths, stillUpAt, upSince, used, dismissedAt
    }
}

extension SleepLog {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        let saved: [Lossy<ActivitySpan>] = c.field(.spans, or: [])
        spans = saved.compactMap { $0.value }.filter { $0.end >= $0.start }.sorted { $0.start < $1.start }
        question = c.optionalField(.question)
        let wakes: [Int] = c.field(.wakeMinutes, or: [])
        wakeMinutes = wakes.filter { (0..<1440).contains($0) }
        let lengths: [Int] = c.field(.dayLengths, or: [])
        dayLengths = lengths.filter { (SleepCheck.shortestLearnedDay...SleepCheck.longestLearnedDay).contains($0) }
        stillUpAt = c.optionalField(.stillUpAt)
        upSince = c.optionalField(.upSince)
        used = c.field(.used, or: false)
        dismissedAt = c.optionalField(.dismissedAt)
    }
}

/// A stretch without using the app.
struct QuietGap: Hashable {
    var start: Date
    var end: Date
    var length: TimeInterval { end.timeIntervalSince(start) }
}

enum SleepCheck {
    /// Shorter breaks than this are never sleep.
    static let quietGap: TimeInterval = 3 * 3600
    /// A new day can't start this soon after the last one: a nap isn't a new day.
    static let shortestDay: TimeInterval = 10 * 3600
    /// Until Routine knows you, it assumes you usually get up at 8:00.
    static let defaultWake = 8 * 60
    /// Day lengths outside this range are mistakes, not something to learn from.
    static let shortestLearnedDay = 4 * 60
    static let longestLearnedDay = 30 * 60
    /// How many recent answers are kept.
    static let remembered = 9

    // MARK: Using the app

    /// Remembers that the app is in use at `now`. Uses within 15 minutes of each other join up.
    /// Returns whether anything changed, so the caller only saves when it has to.
    @discardableResult
    static func note(_ log: inout SleepLog, at now: Date) -> Bool {
        var changed = false
        // A clock that was set ahead leaves uses "in the future". They never happened: forget them.
        let before = log.spans.count
        log.spans.removeAll { $0.start > now.addingTimeInterval(600) }
        if log.spans.count != before { changed = true }
        if let last = log.spans.last, now >= last.start, now.timeIntervalSince(last.end) < 15 * 60 {
            if now.timeIntervalSince(last.end) >= 60 {
                log.spans[log.spans.count - 1].end = now
                changed = true
            }
        } else {
            log.spans.append(ActivitySpan(start: now, end: now))
            log.spans.sort { $0.start < $1.start }
            changed = true
        }
        // Only the last few days matter.
        let oldest = now.addingTimeInterval(-4 * 86_400)
        let kept = log.spans.count
        log.spans.removeAll { $0.end < oldest }
        if log.spans.count > 300 { log.spans.removeFirst(log.spans.count - 300) }
        if log.spans.count != kept { changed = true }
        return changed
    }

    /// The last moment the app was in use, never later than `now`.
    static func lastUse(_ log: SleepLog, now: Date) -> Date? {
        guard let last = log.spans.last(where: { $0.start <= now }) else { return nil }
        return min(last.end, now)
    }

    // MARK: Learning from your answers

    static func learnWake(_ log: inout SleepLog, at date: Date) {
        log.wakeMinutes.append(date.minutesOfDay)
        if log.wakeMinutes.count > remembered { log.wakeMinutes.removeFirst(log.wakeMinutes.count - remembered) }
    }

    static func learnDay(_ log: inout SleepLog, minutes: Int) {
        guard (shortestLearnedDay...longestLearnedDay).contains(minutes) else { return }
        log.dayLengths.append(minutes)
        if log.dayLengths.count > remembered { log.dayLengths.removeFirst(log.dayLengths.count - remembered) }
    }

    /// Your usual wake-up time: the middle of the last few you set, 8:00 until Routine knows you.
    static func usualWake(_ log: SleepLog) -> Int {
        circularMedian(log.wakeMinutes) ?? defaultWake
    }

    /// How long your days usually last, from waking up until you were last seen:
    /// the middle of your last few days, closer to 16 hours while there are only one or two.
    static func usualDay(_ log: SleepLog) -> Int {
        let lengths = log.dayLengths.sorted()
        guard !lengths.isEmpty else { return DayClock.defaultDay }
        let middle = lengths[lengths.count / 2]
        let value = lengths.count < 3 ? (middle + DayClock.defaultDay) / 2 : middle
        return min(max(value, 8 * 60), 24 * 60)
    }

    /// The middle of some times of day, read around the clock: 23:50 and 0:10 give midnight, not noon.
    static func circularMedian(_ minutes: [Int]) -> Int? {
        let values = minutes.map { Day.mod($0, 1440) }.sorted()
        guard !values.isEmpty else { return nil }
        // Open the circle at the biggest gap between two times.
        var start = 0
        var biggest = -1
        for i in values.indices {
            let next = i + 1 < values.count ? values[i + 1] : values[0] + 1440
            let gap = next - values[i]
            if gap > biggest {
                biggest = gap
                start = (i + 1) % values.count
            }
        }
        let line = Array(values[start...]) + values[..<start].map { $0 + 1440 }
        let n = line.count
        let middle = n % 2 == 1 ? line[n / 2] : (line[n / 2 - 1] + line[n / 2] + 1) / 2
        return Day.mod(middle, 1440)
    }

    // MARK: Quiet stretches

    /// Breaks of 3 hours or more without the app between `from` and `to`.
    static func gaps(_ log: SleepLog, from: Date, to: Date) -> [QuietGap] {
        guard to > from else { return [] }
        var result: [QuietGap] = []
        var cursor = from
        for span in log.spans {
            if span.end < from || span.start > to { continue }
            let start = max(span.start, from)
            if start.timeIntervalSince(cursor) >= quietGap {
                result.append(QuietGap(start: cursor, end: start))
            }
            if span.end > cursor { cursor = min(span.end, to) }
        }
        if to.timeIntervalSince(cursor) >= quietGap {
            result.append(QuietGap(start: cursor, end: to))
        }
        return result
    }

    /// Sleep happens at night — your night: at least 2 hours of the stretch fall between 8 hours
    /// before your usual wake-up and 2 hours after it. An afternoon without the app isn't sleep.
    static func isNightish(from: Date, to: Date, usualWake: Int) -> Bool {
        guard to > from else { return false }
        let first = Day(from).adding(days: -1)
        for k in 0..<4 {
            let midnight = first.adding(days: k).start
            let nightStart = midnight.addingTimeInterval(TimeInterval((usualWake - 8 * 60) * 60))
            let nightEnd = midnight.addingTimeInterval(TimeInterval((usualWake + 2 * 60) * 60))
            if min(to, nightEnd).timeIntervalSince(max(from, nightStart)) >= 2 * 3600 { return true }
        }
        return false
    }

    /// The earliest a break can count as sleep: 10 hours after you got up, or when you last said you were still up.
    static func sleepFrom(_ log: SleepLog, up: Date) -> Date {
        let earliest = up.addingTimeInterval(shortestDay)
        if let still = log.stillUpAt, still > earliest { return still }
        return earliest
    }

    /// Still up since `up`: no long night-time break in using the app since it could count as sleep.
    /// Using the app all night means you're still up, and your day keeps going.
    static func isStillUp(_ log: SleepLog, up: Date, now: Date) -> Bool {
        let from = sleepFrom(log, up: up)
        if from >= now { return true }
        let wake = usualWake(log)
        return !gaps(log, from: from, to: now).contains { isNightish(from: $0.start, to: $0.end, usualWake: wake) }
    }

    // MARK: When to ask

    // The decision is a small logistic model. Each clue becomes a number between 0 and about 2,
    // they're weighted and added up, and the total becomes a probability. Routine only asks
    // when it's at least 80% sure you slept. The weights were tuned on hundreds of simulated
    // days (regular sleepers, night owls, new users, naps, short nights, all-nighters): it
    // never asked at a wrong time, and the few cases it holds back on are short nights, where
    // "Start My Day" is still one tap away.

    static let askThreshold = 0.8
    static let baseWeight = -10.0
    static let nightWeight = 3.0
    static let lengthWeight = 4.0
    static let awakeWeight = 4.0
    static let morningWeight = 3.0
    static let missedWeight = 0.5

    /// Whether to ask "Did you sleep?" now, after the app went unused since `lastUse`.
    /// `up` is when your current day really started (nil if none has), and `missed` counts
    /// reminders that went by during the break with nothing checked off.
    static func shouldAsk(_ log: SleepLog, lastUse: Date, now: Date, up: Date?, missed: Int) -> Bool {
        guard let p = sleepProbability(log, lastUse: lastUse, now: now, up: up, missed: missed) else { return false }
        return p >= askThreshold
    }

    /// How sure Routine is that you slept during the quiet stretch, from 0 to 1. Nil when it's
    /// never the moment to ask: between 2 and 4 a.m., under 3 quiet hours, too soon after you
    /// got up, or still the middle of your night.
    static func sleepProbability(_ log: SleepLog, lastUse: Date, now: Date, up: Date?, missed: Int) -> Double? {
        let minute = now.minutesOfDay
        if minute >= 2 * 60 && minute < 4 * 60 { return nil }
        var quietFrom = lastUse
        if let still = log.stillUpAt, still > quietFrom { quietFrom = still }
        let quiet = now.timeIntervalSince(quietFrom) / 60
        guard quiet >= quietGap / 60 else { return nil }

        // What Routine has learned about you.
        let day = Double(usualDay(log))
        let wake = Double(usualWake(log))
        let spread = wakeSpread(log)
        let sleep = min(max(1440 - day, 240), 720)

        // A nap isn't a new day: you've been up at least your usual day minus 4 hours (8 to 12 hours).
        let minAwake = min(max(day - 240, 480), 720)
        if let up, now.timeIntervalSince(up) / 60 < minAwake { return nil }

        // Your night, from bedtime until 4 hours before you usually wake: never interrupt it.
        let bed = clockMinute(wake - sleep - spread)
        let nightEnd = clockMinute(wake - 240)
        if isBetween(Double(minute), bed, nightEnd) { return nil }

        // 1. How much of the quiet stretch fell in your usual sleep window (widened by how much
        //    your wake-up time varies). 6 hours, or your whole usual night, counts as all of it.
        var overlap = 0.0
        let firstDay = Day(quietFrom).index - 1
        let lastDay = max(firstDay, min(Day(now).index + 1, firstDay + 30))
        for index in firstDay...lastDay {
            let midnight = Day(index: index).start
            let windowStart = midnight.addingTimeInterval((wake - sleep - spread) * 60)
            let windowEnd = midnight.addingTimeInterval((wake + spread) * 60)
            let from = max(quietFrom, windowStart)
            let to = min(now, windowEnd)
            if to > from { overlap += to.timeIntervalSince(from) / 60 }
        }
        let night = min(overlap / min(sleep, 360), 1)
        // 2. How long the quiet stretch was, against how long you usually sleep.
        let length = min(quiet / sleep, 1.5)
        // 3. How long you'd been up before it, against your usual day. The longer, the likelier sleep.
        var awake = 1.0
        if let up { awake = min(max(quietFrom.timeIntervalSince(up) / 60 / day, 0), 2) }
        // 4. How close it is to your usual wake-up: full from just before it, fading earlier.
        let before = clockMinute(wake - spread - Double(minute) + 720) - 720
        let morning = before <= 0 ? 1 : exp(-0.5 * (before / 90) * (before / 90))
        // 5. Reminders that went by with nothing checked off.
        let ignored = Double(min(max(missed, 0), 3))

        let z = baseWeight + nightWeight * night + lengthWeight * length + awakeWeight * awake
            + morningWeight * morning + missedWeight * ignored
        return 1 / (1 + exp(-z))
    }

    /// How much your wake-up time varies, in minutes: the circular standard deviation of your
    /// last few answers, between 20 minutes and 3 hours. At least 75 minutes until there are three.
    static func wakeSpread(_ log: SleepLog) -> Double {
        let values = log.wakeMinutes
        guard !values.isEmpty else { return 75 }
        let angles = values.map { Double($0) / 1440 * 2 * Double.pi }
        let c = angles.map { cos($0) }.reduce(0, +) / Double(angles.count)
        let s = angles.map { sin($0) }.reduce(0, +) / Double(angles.count)
        let r = max((c * c + s * s).squareRoot(), 1e-9)
        var spread = max(0, -2 * Foundation.log(r)).squareRoot() / (2 * Double.pi) * 1440
        if values.count < 3 { spread = max(spread, 75) }
        return min(max(spread, 20), 180)
    }

    /// A number of minutes as a time of day, 0 up to 1440.
    static func clockMinute(_ value: Double) -> Double {
        value - 1440 * (value / 1440).rounded(.down)
    }

    /// Whether a time of day falls from `start` up to `end`, going past midnight if it has to.
    static func isBetween(_ t: Double, _ start: Double, _ end: Double) -> Bool {
        if start <= end { return t >= start && t < end }
        return t >= start || t < end
    }

    // MARK: When a day you're still up for ends

    /// Minutes after midnight when a day that began yesterday at `wakeMinute` ends by itself.
    /// Still up: at the time you got up, noon at the latest. Otherwise after your usual day
    /// plus 4 hours, never past your wake-up time or noon. And never past a task set for a time
    /// today, so today's own tasks are never hidden behind yesterday.
    static func cut(wakeMinute: Int, stillUp: Bool, usualDay: Int, fixedTimes: [Int] = []) -> Int {
        var c: Int
        if stillUp {
            c = max(60, min(wakeMinute, 720))
        } else {
            c = max(60, min(wakeMinute, 720, wakeMinute + usualDay + 240 - 1440))
        }
        for t in fixedTimes where t >= 0 && t < c {
            c = t
        }
        return c
    }
}
