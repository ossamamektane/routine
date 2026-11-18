import Foundation
import UserNotifications

/// Local notifications only — nothing is sent to a server.
/// iOS keeps at most 64 pending, so the next week (three days for hourly routines) is planned
/// and the whole plan is rebuilt after every change.
enum Reminders {
    static let occurrenceCategory = "OCCURRENCE"
    static let hourlyCategory = "HOURLY"
    static let infoCategory = "INFO"
    static let doneAction = "DONE"
    static let laterAction = "LATER"
    static let limit = 60
    static let anytimeMinute = 9 * 60

    struct Planned {
        var id: String
        var date: Date
        var title: String
        var body: String
        var category: String
        var info: [String: String]
        var thread: String
    }

    static func registerCategories() {
        let done = UNNotificationAction(identifier: doneAction, title: String(localized: "Mark as Completed"), options: [],
                                        icon: UNNotificationActionIcon(systemImageName: "checkmark"))
        let later = UNNotificationAction(identifier: laterAction, title: String(localized: "Remind Me in 1 Hour"), options: [],
                                         icon: UNNotificationActionIcon(systemImageName: "clock"))
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: occurrenceCategory, actions: [done, later], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: hourlyCategory, actions: [done], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: infoCategory, actions: [], intentIdentifiers: [], options: []),
        ])
    }

    static func identifiers(for itemID: UUID, day: Day, slot: Int?) -> [String] {
        let occurrence = Planner.occurrenceID(itemID, day, slot)
        return ["o|" + occurrence, "b|" + occurrence, "s|" + occurrence]
    }

    /// Removes a reminder that already arrived once the thing has been done.
    static func clearDelivered(itemID: UUID, day: Day, slot: Int?) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers(for: itemID, day: day, slot: slot))
    }

    static func plan(items: [Item], rules: DayRules, settings: SyncedSettings, now: Date) -> [Planned] {
        let today = Day(now)
        // The day you're living, which can still be yesterday after midnight.
        let clock = rules.clock(at: now)
        let dayEnds = clock.day.date(minutes: clock.reminderEnd)
        var result: [Planned] = []
        var anytime: [Day: [(item: Item, slot: Int?)]] = [:]

        // Bills paid automatically or on any day never send reminders: there's nothing to do.
        for item in items where item.isActive && item.reminder != .off && !item.isAutopay && !item.isAnyDayBill {
            let s = item.schedule
            let thread = item.id.uuidString

            if s.kind == .goal {
                result.append(contentsOf: goalReminders(item, today: today, now: now))
                continue
            }

            let days = s.isHourly ? 3 : 9
            for offset in 0..<days {
                let d = clock.day.adding(days: offset)
                guard s.occurs(on: d) else { continue }
                if s.kind == .repeating && d < item.trackFrom { continue }
                let isCurrent = d == clock.day
                // Only the day you're living has a wake-up time. Later days start when you set one.
                let wake = isCurrent ? clock.wake : nil
                if s.usesWake && wake == nil { continue }
                let end = isCurrent ? clock.reminderEnd : DayClock.longestDay
                let logged = s.isHourly ? Planner.loggedSlots(item, day: d, clock: clock) : Set<Int>()
                var slots = s.slots(on: d, wake: wake, end: end)
                if s.isHourly && s.fromDone {
                    // Repeats after completion: only the next one is known, from when you last checked one off.
                    if isCurrent {
                        slots = Planner.fromDoneNext(item, clock: clock).map { [$0] } ?? []
                        slots = slots.filter { ($0.minute ?? 0) < end }
                    } else {
                        slots = Array(slots.prefix(1))
                    }
                }
                for slot in slots {
                    if s.isHourly {
                        if let key = slot.key, logged.contains(key) { continue }
                    } else if item.entry(day: d, slot: slot.key) != nil {
                        continue
                    }
                    // Still up from the day before: its hourly reminders cover this time already.
                    if !isCurrent && s.isHourly && clock.isUp, let m = slot.minute, d.date(minutes: m) <= dayEnds { continue }
                    let occurrence = Planner.occurrenceID(item.id, d, slot.key)
                    let info = ["item": thread, "day": d.iso, "slot": slot.key.map { String($0) } ?? "-"]
                    let category = s.isHourly ? hourlyCategory : occurrenceCategory
                    if let snooze = item.snooze(day: d, slot: slot.key) {
                        if snooze.until > now {
                            result.append(Planned(id: "s|" + occurrence, date: snooze.until, title: item.displayTitle,
                                                  body: body(for: item, dayBefore: false, currency: settings.currency), category: category, info: info, thread: thread))
                        }
                        continue
                    }
                    if item.reminder == .dayBefore && !s.isHourly {
                        let fire = d.adding(days: -1).date(minutes: slot.minute ?? anytimeMinute)
                        if fire > now {
                            result.append(Planned(id: "b|" + occurrence, date: fire, title: item.displayTitle,
                                                  body: body(for: item, dayBefore: true, minute: slot.minute, currency: settings.currency), category: infoCategory, info: info, thread: thread))
                        }
                        continue
                    }
                    guard let minute = slot.minute else {
                        anytime[d, default: []].append((item: item, slot: slot.key))
                        continue
                    }
                    let fire = d.date(minutes: minute)
                    guard fire > now else { continue }
                    result.append(Planned(id: "o|" + occurrence, date: fire, title: item.displayTitle,
                                          body: body(for: item, dayBefore: false, currency: settings.currency), category: category, info: info, thread: thread))
                }
            }

            // Overdue things that were put off with "Later".
            for snooze in item.snoozes where snooze.day < clock.day && snooze.until > now && item.entry(day: snooze.day, slot: snooze.slot) == nil {
                let occurrence = Planner.occurrenceID(item.id, snooze.day, snooze.slot)
                let info = ["item": thread, "day": snooze.day.iso, "slot": snooze.slot.map { String($0) } ?? "-"]
                result.append(Planned(id: "s|" + occurrence, date: snooze.until, title: item.displayTitle,
                                      body: body(for: item, dayBefore: false, currency: settings.currency), category: occurrenceCategory, info: info, thread: thread))
            }
        }

        // Things for "any time today" share one morning notification instead of one each.
        for (d, list) in anytime {
            let fire = d.date(minutes: anytimeMinute)
            guard fire > now, let first = list.first else { continue }
            if list.count == 1 {
                let info = ["item": first.item.id.uuidString, "day": d.iso, "slot": first.slot.map { String($0) } ?? "-"]
                result.append(Planned(id: "o|" + Planner.occurrenceID(first.item.id, d, first.slot), date: fire,
                                      title: first.item.displayTitle, body: body(for: first.item, dayBefore: false, currency: settings.currency),
                                      category: occurrenceCategory, info: info, thread: first.item.id.uuidString))
            } else {
                let titles = list.map { $0.item.displayTitle }
                result.append(Planned(id: "a|" + d.iso, date: fire, title: String(localized: "Today"),
                                      body: titles.formatted(.list(type: .and)), category: infoCategory, info: [:], thread: "anytime"))
            }
        }

        result.sort { $0.date < $1.date }
        return Array(result.prefix(limit))
    }

    /// Any-day tasks: at their time each day until they're done for the day, week or month.
    /// "When I'm Behind" only on days you're behind the pace you need to finish in time.
    static func goalReminders(_ item: Item, today: Day, now: Date) -> [Planned] {
        let s = item.schedule
        guard let t = s.times.first else { return [] }
        let thread = item.id.uuidString
        var result: [Planned] = []
        for offset in 0..<7 {
            let d = today.adding(days: offset)
            let range = s.goalRange(containing: d)
            let count = range.contains(today) ? item.doneCount(in: range) : 0
            if count >= s.goalCount { continue }
            if item.reminder == .whenBehind && count >= s.goalPace(byEndOf: d) { continue }
            // A weekly or monthly one already checked off today counts as done for today.
            if d == today && s.goalPeriod != .day && item.log.contains(where: { $0.kind == .done && $0.day == today }) { continue }
            let fire = d.date(minutes: t)
            guard fire > now else { continue }
            var body = Format.goalProgress(count, s.goalCount, s.goalPeriod)
            if s.goalPeriod != .day {
                let left = range.upperBound.index - d.index + 1
                body += " · " + String(localized: "\(Format.days(left)) left")
            }
            result.append(Planned(id: "g|\(thread)|\(d.iso)", date: fire, title: item.displayTitle, body: body,
                                  category: infoCategory, info: ["item": thread], thread: thread))
        }
        return result
    }

    static func body(for item: Item, dayBefore: Bool, minute: Int? = nil, currency: String) -> String {
        var parts: [String] = []
        if dayBefore {
            if let m = minute {
                parts.append(String(localized: "Tomorrow at \(Format.time(m))"))
            } else {
                parts.append(String(localized: "Tomorrow"))
            }
        }
        if item.hasCost, let cost = item.cost {
            parts.append(Format.money(cost, code: currency))
        }
        if parts.isEmpty {
            let note = item.notes.split(separator: "\n").first.map { String($0.prefix(90)) } ?? ""
            if !note.isEmpty { parts.append(note) }
        }
        return parts.joined(separator: " · ")
    }

    /// Replaces every pending reminder with a fresh plan. Runs `completion` on the main queue when finished.
    static func reschedule(items: [Item], rules: DayRules, settings: SyncedSettings, now: Date,
                           completion: (() -> Void)?) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { status in
            let allowed = status.authorizationStatus == .authorized
                || status.authorizationStatus == .provisional
                || status.authorizationStatus == .ephemeral
            DispatchQueue.main.async {
                center.removeAllPendingNotificationRequests()
                guard allowed, UserDefaults.standard.bool(forKey: PrefKey.reminders) else {
                    completion?()
                    return
                }
                let badgeOn = UserDefaults.standard.bool(forKey: PrefKey.badge)
                let planned = plan(items: items, rules: rules, settings: settings, now: now)
                let group = DispatchGroup()
                for p in planned {
                    let content = UNMutableNotificationContent()
                    content.title = p.title
                    if !p.body.isEmpty { content.body = p.body }
                    content.sound = .default
                    content.categoryIdentifier = p.category
                    content.threadIdentifier = p.thread
                    content.userInfo = p.info
                    if badgeOn {
                        // What Today will count when it arrives.
                        let later = rules.clock(at: p.date.addingTimeInterval(1))
                        content.badge = NSNumber(value: Planner.badgeCount(items: items, clock: later))
                    }
                    let parts = RoutineCalendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: p.date)
                    let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                    group.enter()
                    center.add(UNNotificationRequest(identifier: p.id, content: content, trigger: trigger)) { _ in
                        group.leave()
                    }
                }
                group.notify(queue: .main) {
                    completion?()
                }
            }
        }
    }
}
