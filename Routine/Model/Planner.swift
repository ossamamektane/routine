import Foundation

enum EntryState: Hashable {
    /// Due now (or any time today).
    case due
    /// Later today.
    case upcoming
    /// An hour or more past its time.
    case late
    /// Put off with "Later".
    case snoozed
    /// Timed from when you wake up, so it waits until your day has started.
    case waiting
    /// For information only; nothing to check off.
    case info
    /// The next time, on a later day. It can be checked off early.
    case future
    case done
    case skipped
}

/// What a row's countdown counts down to.
enum DeadlineKind: Hashable {
    /// A set time.
    case time
    /// Any time today, so by midnight.
    case endOfDay
    /// A goal, by the end of its day, week or month.
    case period
    /// Missed on an earlier day.
    case missed
    /// A later day.
    case later
}

/// How a countdown looks: the color says how urgent it is.
enum CountdownTone: Hashable {
    /// Plenty of time (gray).
    case normal
    /// It's time, for the first few minutes (green).
    case now
    /// Coming up soon, or almost out of time (yellow).
    case soon
    /// Late (red).
    case late
    /// Nothing to hurry for: paid automatically, or a goal already done for today (gray).
    case calm
}

/// The short text at the end of a row: "in 35m", "7h left", "2 days late".
struct Countdown: Hashable {
    var text: String
    var tone: CountdownTone
    var isRed: Bool { tone == .late }
}

/// One row on Today or Bills.
struct AgendaEntry: Identifiable, Hashable {
    var id: String
    var itemID: UUID
    var title: String
    var day: Day
    var slot: Int?
    var minute: Int?
    var state: EntryState
    var overdue: Bool = false
    var progress: Int = 0
    var total: Int = 0
    var snoozedUntil: Date? = nil
    var logID: UUID? = nil
    var at: Date? = nil
    var hourly: Bool = false
    var goal: Bool = false
    /// When it's due: its time, the end of its day, or the end of a goal's week or month.
    var deadline: Date? = nil
    var deadlineKind: DeadlineKind = .time
    /// Where its time window starts, for the "almost out of time" red.
    var windowStart: Date? = nil
    /// The order on the list.
    var sortDate: Date = .distantFuture
    /// A weekly or monthly goal checked off today: done for today, not yet for the week or month.
    var doneToday: Bool = false
    /// A bill (it has an amount). On Today, only bills you pay yourself, around when they're due.
    var isBill: Bool = false
    /// Goals: the day, week or month it's counted in.
    var goalPeriod: GoalPeriod? = nil

    /// What the badge counts.
    var isActionable: Bool { (state == .due || state == .late) && !goal }
    var isFinished: Bool { state == .done || state == .skipped }
}

extension AgendaEntry {
    /// "in 35m", "7h left", "3 days left", "2 days late", "Tomorrow". `today` is the day you're living.
    /// Gray while there's time, yellow when it's soon or almost out of time, green "Now" for the
    /// first few minutes, red once it's late.
    func countdown(now: Date, today: Day) -> Countdown? {
        guard let deadline else { return nil }
        switch state {
        case .skipped, .waiting:
            return nil
        case .done:
            guard goal && doneToday && progress < total else { return nil }
        default:
            break
        }
        // Paid automatically, or a goal already done for today: nothing to hurry for.
        let calm = state == .info || state == .done
        let seconds = deadline.timeIntervalSince(now)
        let left = Int((seconds / 60).rounded(.up))
        let lateBy = Int((-seconds / 60).rounded(.down))

        if seconds <= 0 && deadlineKind != .later {
            if deadlineKind == .time && lateBy < Planner.nowMinutes {
                return Countdown(text: String(localized: "Now"), tone: calm ? .calm : .now)
            }
            return Countdown(text: String(localized: "\(Format.span(minutes: max(lateBy, 1))) late"), tone: calm ? .calm : .late)
        }

        let tone: CountdownTone = calm ? .calm : (isSoon(seconds: seconds) ? .soon : .normal)
        switch deadlineKind {
        case .time:
            return Countdown(text: String(localized: "in \(Format.span(minutes: left))"), tone: tone)
        case .endOfDay:
            return Countdown(text: String(localized: "\(Format.span(minutes: left)) left"), tone: tone)
        case .period:
            let lastDay = Day(deadline.addingTimeInterval(-1))
            let days = lastDay.index - Day(now).index + 1
            if days > 1 {
                return Countdown(text: String(localized: "\(Format.days(days)) left"), tone: tone)
            }
            return Countdown(text: String(localized: "\(Format.span(minutes: left)) left"), tone: tone)
        case .missed:
            return Countdown(text: String(localized: "\(Format.span(minutes: max(lateBy, 1))) late"), tone: calm ? .calm : .late)
        case .later:
            if minute != nil && seconds > 0 && seconds < 24 * 3600 {
                return Countdown(text: String(localized: "in \(Format.span(minutes: left))"), tone: tone)
            }
            let days = day.index - today.index
            if days <= 0 {
                return Countdown(text: String(localized: "Today"), tone: tone)
            }
            if days == 1 {
                return Countdown(text: String(localized: "Tomorrow"), tone: tone)
            }
            return Countdown(text: String(localized: "In \(Format.days(days))"), tone: tone)
        }
    }

    /// Yellow: a set time in the next 30 minutes (less for things that come often), the last
    /// 2 hours of "any time today", or the last day of a goal's week or month.
    private func isSoon(seconds: TimeInterval) -> Bool {
        switch deadlineKind {
        case .time:
            return seconds <= soonWindow
        case .later:
            return minute != nil && seconds < 24 * 3600 && seconds <= soonWindow
        case .endOfDay:
            return seconds <= 2 * 3600
        case .period:
            let hours: TimeInterval = goalPeriod == .day ? 2 : 24
            return seconds <= hours * 3600
        case .missed:
            return false
        }
    }

    /// 30 minutes, or a third of the time since the one before if that's shorter.
    private var soonWindow: TimeInterval {
        var limit: TimeInterval = 30 * 60
        if let windowStart, let deadline {
            let window = deadline.timeIntervalSince(windowStart)
            if window > 0 { limit = min(limit, window / 3) }
        }
        return limit
    }
}

struct Agenda {
    /// Everything still to do, soonest first: late things, today's, goals, then when the rest are next.
    var tasks: [AgendaEntry] = []
    /// Checked off or skipped today, in the order you did them.
    var done: [AgendaEntry] = []
    /// Something is timed from when you wake up.
    var hasWakeItems = false

    var overdue: [AgendaEntry] { tasks.filter(\.overdue) }

    /// Today's, not counting goals, things waiting for your day to start or later days.
    var dueToday: [AgendaEntry] {
        tasks.filter { e in
            !e.overdue && !e.goal && (e.state == .due || e.state == .late || e.state == .upcoming || e.state == .snoozed)
        }
    }

    var later: [AgendaEntry] { tasks.filter { $0.state == .future } }

    /// What the badge counts: things that need doing right now.
    var actionableCount: Int { tasks.filter(\.isActionable).count }

    /// Things still to do today.
    var remainingCount: Int { tasks.filter { $0.state != .future && $0.state != .info }.count }

    var doneCount: Int { done.filter { $0.state == .done }.count }

    var isEmpty: Bool { tasks.isEmpty && done.isEmpty }
}

struct LaterOption: Identifiable, Hashable {
    var label: String
    var date: Date
    var id: String { label }
}

enum Planner {
    static let lateAfterMinutes = 60
    /// A set time shows "Now" for this long, then how late it is.
    static let nowMinutes = 5
    /// Bills you pay yourself show on Today from this many days before they're due.
    static let billHeadsUpDays = 3

    static func occurrenceID(_ id: UUID, _ day: Day, _ slot: Int?) -> String {
        id.uuidString + "|" + day.iso + "|" + (slot.map { String($0) } ?? "-")
    }

    /// Today's tasks for the day you're living, and bills you pay yourself around when they're due
    /// (bills follow the calendar). Bills paid automatically or on any day only count in the totals.
    static func agenda(items: [Item], clock: DayClock) -> Agenda {
        var agenda = Agenda()
        let calendar = DayClock.calendar(clock.now)
        for item in items where item.deletedAt == nil && !item.paused {
            if item.hasCost {
                addBill(item, clock: clock, calendar: calendar, to: &agenda)
                continue
            }
            let s = item.schedule
            if s.usesWake && !item.isFinished { agenda.hasWakeItems = true }

            // Everything checked off today, each hourly one too. Goals are added below.
            if s.kind != .goal {
                for entry in item.log where clock.includes(entry) {
                    agenda.done.append(doneRow(entry, item: item))
                }
            }
            if item.isFinished { continue }

            if s.kind == .goal {
                addGoal(item, clock: clock, oncePerDay: true, to: &agenda)
                continue
            }
            let before = agenda.tasks.count
            if s.isHourly {
                addHourly(item, clock: clock, to: &agenda)
            } else {
                addOverdue(item, clock: clock, to: &agenda)
                addToday(item, clock: clock, to: &agenda)
            }
            // Nothing to do for now: show when it's next.
            if agenda.tasks.count == before, let next = nextRow(item, clock: clock, after: clock.day) {
                agenda.tasks.append(next)
            }
        }
        agenda.tasks.sort(by: listOrder)
        agenda.done.sort { ($0.at ?? .distantPast) < ($1.at ?? .distantPast) }
        return agenda
    }

    /// For callers that only know today's wake-up time.
    static func agenda(items: [Item], now: Date, wake: Int?, includeUpcoming: Bool = true) -> Agenda {
        agenda(items: items, clock: DayClock.simple(now: now, wake: wake))
    }

    /// One row per bill, soonest first: what's due, or when it's next.
    static func bills(items: [Item], now: Date) -> [AgendaEntry] {
        let clock = DayClock.calendar(now)
        var rows: [AgendaEntry] = []
        for item in items where item.isActive && item.hasCost {
            if item.isAnyDayBill {
                // Any day of its week or month: counted in the totals, nothing to check off.
                var row = AgendaEntry(id: item.id.uuidString + "|info", itemID: item.id, title: item.displayTitle,
                                      day: clock.day, slot: nil, minute: nil, state: .info)
                row.isBill = true
                rows.append(row)
                continue
            }
            if item.isAutopay {
                // Paid automatically: only when it's next taken.
                if var row = nextRow(item, clock: clock, after: clock.day.adding(days: -1)) {
                    row.state = .info
                    row.isBill = true
                    rows.append(row)
                }
                continue
            }
            var agenda = Agenda()
            addOverdue(item, clock: clock, to: &agenda)
            addToday(item, clock: clock, to: &agenda)
            var pick: AgendaEntry? = nil
            if let first = agenda.tasks.sorted(by: billOrder).first {
                pick = first
            } else if let done = agenda.done.first {
                pick = done
            } else if let next = nextRow(item, clock: clock, after: clock.day) {
                pick = next
            }
            if var row = pick {
                row.isBill = true
                rows.append(row)
            }
        }
        return rows.sorted(by: billOrder)
    }

    /// The app icon badge: what needs doing now on Today, bills you pay yourself included.
    static func badgeCount(items: [Item], clock: DayClock) -> Int {
        agenda(items: items, clock: clock).actionableCount
    }

    static func timeState(due: Date, now: Date) -> EntryState {
        if due > now { return .upcoming }
        return now.timeIntervalSince(due) >= Double(lateAfterMinutes * 60) ? .late : .due
    }

    // MARK: Building rows

    private static func doneRow(_ entry: LogEntry, item: Item) -> AgendaEntry {
        AgendaEntry(id: "log|" + entry.id.uuidString, itemID: item.id, title: item.displayTitle,
                    day: entry.day, slot: entry.slot, minute: nil,
                    state: entry.kind == .done ? .done : .skipped,
                    logID: entry.id, at: entry.at, hourly: item.schedule.isHourly)
    }

    /// Where a timed thing's window starts: the time before it, or when the day began.
    private static func windowStart(previous: Date?, due: Date, clock: DayClock) -> Date {
        if let previous, previous < due { return previous }
        return clock.began < due ? clock.began : clock.day.start
    }

    /// A bill you pay yourself: on Today from a few days before it's due until it's paid,
    /// and under Completed on the day you paid it. Bills follow the calendar day.
    private static func addBill(_ item: Item, clock: DayClock, calendar: DayClock, to agenda: inout Agenda) {
        guard !item.isAutopay, !item.isAnyDayBill else { return }
        for entry in item.log where clock.includes(entry) || calendar.includes(entry) {
            var row = doneRow(entry, item: item)
            row.isBill = true
            agenda.done.append(row)
        }
        if item.isFinished { return }
        var due = Agenda()
        addOverdue(item, clock: calendar, to: &due)
        addToday(item, clock: calendar, to: &due)
        if due.tasks.isEmpty, let next = nextRow(item, clock: calendar, after: calendar.day),
           next.day.index - calendar.day.index <= billHeadsUpDays {
            due.tasks.append(next)
        }
        for var row in due.tasks {
            row.isBill = true
            agenda.tasks.append(row)
        }
    }

    private static func addToday(_ item: Item, clock: DayClock, to agenda: inout Agenda) {
        let s = item.schedule
        let today = clock.day
        guard s.occurs(on: today) else { return }
        if s.kind == .repeating && today < item.trackFrom { return }
        let waitingForWake = s.usesWake && clock.wake == nil
        var previous: Date? = nil
        for slot in s.slots(on: today, wake: clock.wake, end: clock.end) {
            let due = slot.minute.map { today.date(minutes: $0) }
            let before = previous
            if let due { previous = due }
            if item.entry(day: today, slot: slot.key) != nil { continue }
            var e = AgendaEntry(id: occurrenceID(item.id, today, slot.key), itemID: item.id, title: item.displayTitle,
                                day: today, slot: slot.key, minute: slot.minute, state: .due)
            if waitingForWake {
                e.state = .waiting
                e.sortDate = today.end
                agenda.tasks.append(e)
                continue
            }
            if let due {
                e.state = timeState(due: due, now: clock.now)
                e.deadline = due
                e.deadlineKind = .time
                e.windowStart = windowStart(previous: before, due: due, clock: clock)
            } else {
                e.deadline = today.end
                e.deadlineKind = .endOfDay
                e.windowStart = clock.began
            }
            applySnooze(item, &e, clock: clock)
            e.sortDate = e.deadline ?? today.end
            agenda.tasks.append(e)
        }
    }

    /// Something missed on an earlier day stays until it's done, skipped or the next one arrives.
    private static func addOverdue(_ item: Item, clock: DayClock, to agenda: inout Agenda) {
        let s = item.schedule
        guard s.carriesOver else { return }
        let today = clock.day
        let yesterday = today.adding(days: -1)
        var missed: Day? = nil
        switch s.kind {
        case .once, .afterDone:
            missed = s.previousOccurrence(onOrBefore: yesterday)
        case .repeating:
            if let p = s.previousOccurrence(onOrBefore: yesterday), p >= item.trackFrom {
                let next = s.nextOccurrence(onOrAfter: p.adding(days: 1))
                if next.map({ $0 > today }) ?? true { missed = p }
            }
        case .goal:
            break
        }
        guard let day = missed else { return }
        for slot in s.slots(on: day, wake: nil) where item.entry(day: day, slot: slot.key) == nil {
            var e = AgendaEntry(id: occurrenceID(item.id, day, slot.key), itemID: item.id, title: item.displayTitle,
                                day: day, slot: slot.key, minute: slot.minute, state: .late, overdue: true)
            e.deadline = slot.minute.map { day.date(minutes: $0) } ?? day.end
            e.deadlineKind = .missed
            applySnooze(item, &e, clock: clock)
            e.sortDate = e.deadline ?? day.end
            agenda.tasks.append(e)
        }
    }

    /// "Later": shows when it comes back, then it's due from that time.
    private static func applySnooze(_ item: Item, _ e: inout AgendaEntry, clock: DayClock) {
        guard let snooze = item.snooze(day: e.day, slot: e.slot) else { return }
        if snooze.until > clock.now {
            e.state = .snoozed
            e.snoozedUntil = snooze.until
            e.minute = snooze.until.minutesOfDay
            e.deadline = snooze.until
            e.deadlineKind = .time
            e.windowStart = nil
        } else if !e.overdue {
            e.minute = snooze.until.minutesOfDay
            e.state = timeState(due: snooze.until, now: clock.now)
            e.deadline = snooze.until
            e.deadlineKind = .time
            e.windowStart = nil
        }
    }

    /// Hourly things are one row that moves along: the one that's due, or the next one.
    private static func addHourly(_ item: Item, clock: DayClock, to agenda: inout Agenda) {
        let s = item.schedule
        let today = clock.day
        guard today >= s.start, today >= item.trackFrom else { return }
        let rowID = item.id.uuidString + "|hourly"
        if s.usesWake && clock.wake == nil {
            var e = AgendaEntry(id: rowID, itemID: item.id, title: item.displayTitle, day: today, slot: 0, minute: nil,
                                state: .waiting, hourly: true)
            e.sortDate = today.end
            agenda.tasks.append(e)
            return
        }
        if s.fromDone {
            // Repeats after completion: N hours after the last one you checked off.
            guard let next = fromDoneNext(item, clock: clock), let m = next.minute else { return }
            let due = today.date(minutes: m)
            var e = AgendaEntry(id: rowID, itemID: item.id, title: item.displayTitle, day: today, slot: next.key, minute: m,
                                state: timeState(due: due, now: clock.now), hourly: true)
            e.deadline = due
            e.deadlineKind = .time
            let last = hourlyChecks(item, day: today, clock: clock).max { $0.at < $1.at }
            e.windowStart = windowStart(previous: last?.at ?? clock.wakeDate, due: due, clock: clock)
            e.sortDate = due
            agenda.tasks.append(e)
            return
        }
        let slots = s.slots(on: today, wake: clock.wake, end: clock.end)
        let logged = loggedSlots(item, day: today, clock: clock)
        var index: Int? = nil
        if let i = slots.lastIndex(where: { ($0.minute ?? 0) <= clock.minute }), !logged.contains(slots[i].key ?? -1) {
            index = i
        } else {
            index = slots.firstIndex(where: { ($0.minute ?? 0) > clock.minute && !logged.contains($0.key ?? -1) })
        }
        guard let i = index, let m = slots[i].minute else { return }
        let due = today.date(minutes: m)
        var e = AgendaEntry(id: rowID, itemID: item.id, title: item.displayTitle, day: today, slot: slots[i].key, minute: m,
                            state: timeState(due: due, now: clock.now), hourly: true)
        e.deadline = due
        e.deadlineKind = .time
        var previous: Date? = clock.wakeDate
        if i > 0, let pm = slots[i - 1].minute {
            previous = today.date(minutes: pm)
        }
        e.windowStart = windowStart(previous: previous, due: due, clock: clock)
        e.sortDate = due
        agenda.tasks.append(e)
    }

    /// Hourly times already checked off. After a new wake-up, the ones from before it don't count.
    static func loggedSlots(_ item: Item, day: Day, clock: DayClock) -> Set<Int> {
        Set(hourlyChecks(item, day: day, clock: clock).compactMap { $0.slot })
    }

    /// An hourly thing's check-offs (and skips) on a day. After a new wake-up, the ones from before it don't count.
    static func hourlyChecks(_ item: Item, day: Day, clock: DayClock) -> [LogEntry] {
        let since: Date? = item.schedule.usesWake && day == clock.day ? clock.began : nil
        return item.log.filter { entry in
            guard entry.day == day, entry.slot != nil else { return false }
            if let since, entry.at < since { return false }
            return true
        }
    }

    /// Hourly, repeating after completion: the first one at its usual time, then every N hours
    /// after the last one you checked off or skipped. Nil once the day you're living is over.
    /// Each one gets the next number, so checking one off never hides another.
    static func fromDoneNext(_ item: Item, clock: DayClock) -> SlotTime? {
        let s = item.schedule
        let today = clock.day
        guard let first = s.slots(on: today, wake: clock.wake, end: clock.end).first, let firstMinute = first.minute else {
            return nil
        }
        let checks = hourlyChecks(item, day: today, clock: clock)
        let key = (checks.compactMap { $0.slot }.max() ?? -1) + 1
        var minute = firstMinute
        if let last = checks.max(by: { $0.at < $1.at }) {
            minute = today.minutes(until: last.at) + max(1, s.every) * 60
        }
        guard minute < clock.end else { return nil }
        return SlotTime(key: key, minute: minute)
    }

    /// A number of times per day, week or month. On Today, weekly and monthly ones count once a day.
    private static func addGoal(_ item: Item, clock: DayClock, oncePerDay: Bool, to agenda: inout Agenda) {
        let s = item.schedule
        let periodDay = s.goalPeriod == .day ? clock.day : Day(clock.now)
        let range = s.goalRange(containing: periodDay)
        let checks = item.log.filter { $0.kind == .done && range.contains($0.day) }
        let count = checks.count
        var e = AgendaEntry(id: item.id.uuidString + "|goal", itemID: item.id, title: item.displayTitle,
                            day: periodDay, slot: nil, minute: s.times.first, state: .due,
                            progress: count, total: s.goalCount, goal: true)
        e.goalPeriod = s.goalPeriod
        e.deadline = range.upperBound.end
        e.deadlineKind = .period
        e.windowStart = s.goalPeriod == .day ? clock.began : range.lowerBound.start
        e.sortDate = range.upperBound.end
        let met = count >= s.goalCount
        let checkedToday = oncePerDay && s.goalPeriod != .day && checks.contains { clock.includes($0) }
        // The latest check, so "Undo" takes back that one.
        let latest = checks.max { $0.at < $1.at }
        e.logID = latest?.id
        if met || checkedToday {
            e.state = .done
            e.at = latest?.at
            e.doneToday = checkedToday && !met
            if met { e.sortDate = range.upperBound.adding(days: 1).start }
            agenda.done.append(e)
        } else {
            agenda.tasks.append(e)
        }
    }

    /// When it's next due after `day`, for things with nothing to do before then.
    /// Times already checked off early are skipped.
    private static func nextRow(_ item: Item, clock: DayClock, after day: Day) -> AgendaEntry? {
        let s = item.schedule
        var from = day.adding(days: 1)
        if s.kind == .repeating { from = max(from, item.trackFrom) }
        var found: (Day, SlotTime)? = nil
        for _ in 0..<60 {
            guard let d = s.nextOccurrence(onOrAfter: from) else { return nil }
            let slots = s.slots(on: d, wake: nil)
            if s.isHourly || slots.isEmpty {
                found = (d, slots.first ?? SlotTime(key: s.isHourly ? 0 : nil, minute: nil))
                break
            }
            if let open = slots.first(where: { item.entry(day: d, slot: $0.key) == nil }) {
                found = (d, open)
                break
            }
            from = d.adding(days: 1)
        }
        guard let pick = found else { return nil }
        let d = pick.0
        let slot = pick.1
        var e = AgendaEntry(id: occurrenceID(item.id, d, slot.key), itemID: item.id, title: item.displayTitle,
                            day: d, slot: slot.key, minute: slot.minute, state: .future, hourly: s.isHourly)
        let due = slot.minute.map { d.date(minutes: $0) } ?? d.end
        e.deadline = due
        e.deadlineKind = .later
        e.windowStart = previousTime(item, before: d)
        e.sortDate = due
        return e
    }

    /// When the time before this one was, for the "coming up soon" red on later days.
    private static func previousTime(_ item: Item, before d: Day) -> Date? {
        let s = item.schedule
        switch s.kind {
        case .repeating:
            if let p = s.previousOccurrence(onOrBefore: d.adding(days: -1)) {
                if let m = s.slots(on: p, wake: nil).last?.minute { return p.date(minutes: m) }
                return p.end
            }
            return item.trackFrom.start
        case .afterDone:
            return item.lastDone?.at ?? item.createdAt
        case .once, .goal:
            return item.createdAt
        }
    }

    // MARK: Order

    private static func rank(_ e: AgendaEntry) -> Int {
        switch e.state {
        case .waiting: return 1
        case .future: return 3
        default: return e.goal ? 2 : 0
        }
    }

    /// Today: what's late or due first, then things waiting for your day to start, goals, and later days.
    static func listOrder(_ lhs: AgendaEntry, _ rhs: AgendaEntry) -> Bool {
        let l = rank(lhs), r = rank(rhs)
        if l != r { return l < r }
        if lhs.sortDate != rhs.sortDate { return lhs.sortDate < rhs.sortDate }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    /// Bills: soonest first.
    static func billOrder(_ lhs: AgendaEntry, _ rhs: AgendaEntry) -> Bool {
        if lhs.sortDate != rhs.sortDate { return lhs.sortDate < rhs.sortDate }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    // MARK: Later

    /// "Later" choices that land before the next time it's due anyway.
    static func laterOptions(for entry: AgendaEntry, item: Item, clock: DayClock) -> [LaterOption] {
        guard !entry.hourly, !entry.goal, !entry.isFinished else { return [] }
        switch entry.state {
        case .info, .future, .waiting: return []
        default: break
        }
        let s = item.schedule
        let now = clock.now
        var limit = Date.distantFuture
        if s.kind == .repeating {
            let sameDay = s.slots(on: entry.day, wake: nil)
            if let key = entry.slot, let next = sameDay.first(where: { ($0.key ?? -1) > key }), let m = next.minute {
                limit = entry.day.date(minutes: m)
            } else if let nextDay = s.nextOccurrence(onOrAfter: entry.day.adding(days: 1)) {
                limit = nextDay.date(minutes: s.slots(on: nextDay, wake: nil).first?.minute ?? 0)
            }
            if !s.carriesOver { limit = min(limit, entry.day.end) }
        }
        var candidates: [(String, Date)] = []
        candidates.append((String(localized: "In 1 hour"), now.addingTimeInterval(3600)))
        candidates.append((String(localized: "In 3 hours"), now.addingTimeInterval(3 * 3600)))
        if clock.minute < 18 * 60 {
            candidates.append((String(localized: "This evening"), clock.day.date(minutes: 19 * 60)))
        }
        candidates.append((String(localized: "Tomorrow morning"), clock.day.adding(days: 1).date(minutes: 9 * 60)))
        return candidates
            .filter { $0.1 > now && $0.1 < limit }
            .map { LaterOption(label: $0.0, date: $0.1) }
    }
}
