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
    /// Starts after you tap "I'm up".
    case waiting
    /// For information only; nothing to check off.
    case info
    case done
    case skipped
}

/// One row in Today.
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
    var sortMinute: Int = 2000

    var isActionable: Bool { state == .due || state == .late }
    var isFinished: Bool { state == .done || state == .skipped }
}

struct UpcomingEntry: Identifiable, Hashable {
    var id: String
    var itemID: UUID
    var title: String
    var day: Day
    var minute: Int?
}

struct UpcomingGroup: Identifiable, Hashable {
    var day: Day
    var entries: [UpcomingEntry]
    var id: String { day.iso }
}

struct Agenda {
    var overdue: [AgendaEntry] = []
    var waiting: [AgendaEntry] = []
    var today: [AgendaEntry] = []
    var goals: [AgendaEntry] = []
    var done: [AgendaEntry] = []
    var upcoming: [UpcomingGroup] = []
    /// Something depends on "I'm up", so the wake-up card is shown.
    var hasWakeItems = false

    /// What the badge counts: things that need doing right now.
    var actionableCount: Int {
        overdue.filter(\.isActionable).count + today.filter(\.isActionable).count
    }

    /// Things still to do today (not counting "any day" ones).
    var remainingCount: Int {
        overdue.count + waiting.count + today.filter { $0.state != .info }.count
    }

    var doneCount: Int { done.filter { $0.state == .done }.count }

    var isEmpty: Bool {
        overdue.isEmpty && waiting.isEmpty && today.isEmpty && goals.isEmpty && done.isEmpty && upcoming.isEmpty
    }
}

struct LaterOption: Identifiable, Hashable {
    var label: String
    var date: Date
    var id: String { label }
}

enum Planner {
    static let lateAfterMinutes = 60

    static func occurrenceID(_ id: UUID, _ day: Day, _ slot: Int?) -> String {
        id.uuidString + "|" + day.iso + "|" + (slot.map { String($0) } ?? "-")
    }

    static func agenda(items: [Item], now: Date, wake: Int?, includeUpcoming: Bool = true) -> Agenda {
        let today = Day(now)
        let nowMinute = now.minutesOfDay
        var agenda = Agenda()

        for item in items where item.deletedAt == nil && !item.paused {
            // Paid automatically: there's nothing to do, so it stays off Today. Bills shows it.
            if item.isAutopay { continue }
            let s = item.schedule
            if s.usesWake && !item.isFinished { agenda.hasWakeItems = true }

            // Everything checked off today, including overdue things done today.
            if s.kind != .goal && !s.isHourly {
                for entry in item.log where Day(entry.at) == today {
                    agenda.done.append(AgendaEntry(
                        id: "log|" + entry.id.uuidString, itemID: item.id, title: item.displayTitle,
                        day: entry.day, slot: entry.slot, minute: nil,
                        state: entry.kind == .done ? .done : .skipped,
                        logID: entry.id, at: entry.at))
                }
            }
            if item.isFinished { continue }

            switch s.kind {
            case .goal:
                let range = s.goalRange(containing: today)
                let count = item.doneCount(in: range)
                if count < s.goalCount {
                    agenda.goals.append(AgendaEntry(
                        id: item.id.uuidString + "|goal", itemID: item.id, title: item.displayTitle,
                        day: today, slot: nil, minute: s.times.first,
                        state: .due, progress: count, total: s.goalCount, goal: true))
                } else if let last = item.log.filter({ $0.kind == .done && range.contains($0.day) }).map(\.at).max(),
                          Day(last) == today {
                    // Done for the day, week or month: under Done today, then out of the way until the next one.
                    agenda.done.append(AgendaEntry(
                        id: item.id.uuidString + "|goal", itemID: item.id, title: item.displayTitle,
                        day: today, slot: nil, minute: nil,
                        state: .done, progress: count, total: s.goalCount, at: last, goal: true))
                }
            case .repeating where s.isHourly:
                addHourly(item, today: today, nowMinute: nowMinute, wake: wake, to: &agenda)
            default:
                addOverdue(item, today: today, now: now, to: &agenda)
                addToday(item, today: today, now: now, nowMinute: nowMinute, wake: wake, to: &agenda)
            }
        }

        if includeUpcoming {
            agenda.upcoming = upcoming(items: items, today: today)
        }
        sort(&agenda)
        return agenda
    }

    static func timeState(_ minute: Int?, _ nowMinute: Int) -> EntryState {
        guard let m = minute else { return .due }
        if m > nowMinute { return .upcoming }
        return nowMinute - m >= lateAfterMinutes ? .late : .due
    }

    private static func addToday(_ item: Item, today: Day, now: Date, nowMinute: Int, wake: Int?, to agenda: inout Agenda) {
        let s = item.schedule
        guard s.occurs(on: today) else { return }
        if s.kind == .repeating && today < item.trackFrom { return }
        let waitingForWake = s.usesWake && wake == nil
        for slot in s.slots(on: today, wake: wake) {
            if item.entry(day: today, slot: slot.key) != nil { continue }
            var e = AgendaEntry(
                id: occurrenceID(item.id, today, slot.key), itemID: item.id, title: item.displayTitle,
                day: today, slot: slot.key, minute: slot.minute, state: .due)
            e.sortMinute = slot.minute ?? 2000
            if waitingForWake {
                e.state = .waiting
                e.sortMinute = s.afterWaking ?? 0
                agenda.waiting.append(e)
                continue
            }
            guard applySnooze(item, &e, today: today, now: now) else { continue }
            if e.state != .snoozed { e.state = timeState(e.minute, nowMinute) }
            e.sortMinute = e.minute ?? 2000
            agenda.today.append(e)
        }
    }

    private static func addOverdue(_ item: Item, today: Day, now: Date, to agenda: inout Agenda) {
        let s = item.schedule
        guard s.carriesOver, !item.isAutopay else { return }
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
            var e = AgendaEntry(
                id: occurrenceID(item.id, day, slot.key), itemID: item.id, title: item.displayTitle,
                day: day, slot: slot.key, minute: slot.minute, state: .due, overdue: true)
            guard applySnooze(item, &e, today: today, now: now) else { continue }
            e.sortMinute = e.minute ?? 2000
            agenda.overdue.append(e)
        }
    }

    /// Returns false when the occurrence was put off until another day.
    private static func applySnooze(_ item: Item, _ e: inout AgendaEntry, today: Day, now: Date) -> Bool {
        guard let snooze = item.snooze(day: e.day, slot: e.slot) else { return true }
        if snooze.until >= today.end { return false }
        if snooze.until > now {
            e.state = .snoozed
            e.snoozedUntil = snooze.until
            e.minute = snooze.until.minutesOfDay
        } else if Day(snooze.until) == today {
            e.minute = snooze.until.minutesOfDay
        }
        return true
    }

    /// Hourly routines are one row that moves along through the day.
    private static func addHourly(_ item: Item, today: Day, nowMinute: Int, wake: Int?, to agenda: inout Agenda) {
        let s = item.schedule
        guard today >= s.start, today >= item.trackFrom else { return }
        let todays = item.log.filter { $0.day == today }
        let progress = todays.filter { $0.kind == .done }.count
        let rowID = item.id.uuidString + "|hourly"
        if s.usesWake && wake == nil {
            var e = AgendaEntry(id: rowID, itemID: item.id, title: item.displayTitle, day: today, slot: 0, minute: nil,
                                state: .waiting, progress: progress, total: 0, hourly: true)
            e.sortMinute = s.afterWaking ?? 0
            agenda.waiting.append(e)
            return
        }
        let slots = s.slots(on: today, wake: wake)
        guard !slots.isEmpty else { return }
        let logged = Set(todays.compactMap { $0.slot })
        var target: SlotTime? = nil
        if let last = slots.last(where: { ($0.minute ?? 0) <= nowMinute }), !logged.contains(last.key ?? -1) {
            target = last
        } else {
            target = slots.first(where: { ($0.minute ?? 0) > nowMinute && !logged.contains($0.key ?? -1) })
        }
        if let t = target {
            var e = AgendaEntry(id: rowID, itemID: item.id, title: item.displayTitle, day: today, slot: t.key, minute: t.minute,
                                state: timeState(t.minute, nowMinute), progress: progress, total: slots.count, hourly: true)
            e.sortMinute = t.minute ?? 2000
            agenda.today.append(e)
        } else if progress > 0 {
            agenda.done.append(AgendaEntry(id: rowID, itemID: item.id, title: item.displayTitle, day: today, slot: nil, minute: nil,
                                           state: .done, progress: progress, total: slots.count,
                                           at: todays.map(\.at).max(), hourly: true))
        }
    }

    static func upcoming(items: [Item], today: Day, days: Int = 7) -> [UpcomingGroup] {
        let first = today.adding(days: 1)
        let last = today.adding(days: days)
        var byDay: [Day: [UpcomingEntry]] = [:]
        for item in items where item.isActive && !item.isAutopay {
            let s = item.schedule
            if s.kind == .goal || s.isHourly || s.isEveryDay { continue }
            let from = s.kind == .repeating ? max(first, item.trackFrom) : first
            guard let d = s.nextOccurrence(onOrAfter: from), d <= last else { continue }
            let minute = s.slots(on: d, wake: nil).first?.minute
            byDay[d, default: []].append(UpcomingEntry(
                id: occurrenceID(item.id, d, nil), itemID: item.id, title: item.displayTitle, day: d, minute: minute))
        }
        return byDay.keys.sorted().map { (d: Day) -> UpcomingGroup in
            let entries = (byDay[d] ?? []).sorted { lhs, rhs in
                let l = lhs.minute ?? 2000, r = rhs.minute ?? 2000
                return l != r ? l < r : lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            return UpcomingGroup(day: d, entries: entries)
        }
    }

    private static func sort(_ a: inout Agenda) {
        func byTime(_ lhs: AgendaEntry, _ rhs: AgendaEntry) -> Bool {
            if lhs.day != rhs.day { return lhs.day < rhs.day }
            if lhs.sortMinute != rhs.sortMinute { return lhs.sortMinute < rhs.sortMinute }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        a.overdue.sort(by: byTime)
        a.waiting.sort(by: byTime)
        a.today.sort(by: byTime)
        a.goals.sort { lhs, rhs in
            let l = lhs.state == .done ? 1 : 0, r = rhs.state == .done ? 1 : 0
            return l != r ? l < r : lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        a.done.sort { ($0.at ?? .distantPast) > ($1.at ?? .distantPast) }
    }

    static func actionableCount(items: [Item], at date: Date, wake: Int?) -> Int {
        agenda(items: items, now: date, wake: wake, includeUpcoming: false).actionableCount
    }

    /// "Later" choices that land before the next time it's due anyway.
    static func laterOptions(for entry: AgendaEntry, item: Item, now: Date) -> [LaterOption] {
        guard !entry.hourly, !entry.goal, !entry.isFinished, entry.state != .info else { return [] }
        let s = item.schedule
        let today = Day(now)
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
        if now.minutesOfDay < 18 * 60 {
            candidates.append((String(localized: "This evening"), today.date(minutes: 19 * 60)))
        }
        candidates.append((String(localized: "Tomorrow morning"), today.adding(days: 1).date(minutes: 9 * 60)))
        return candidates
            .filter { $0.1 > now && $0.1 < limit }
            .map { LaterOption(label: $0.0, date: $0.1) }
    }
}
