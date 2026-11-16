import Foundation
import UserNotifications

/// Local notifications only — nothing is sent to a server.
/// iOS keeps at most 64 pending, so the next week (two days for hourly routines) is planned
/// and the whole plan is rebuilt after every change.
enum Reminders {
    static let occurrenceCategory = "OCCURRENCE"
    static let morningCategory = "MORNING"
    static let infoCategory = "INFO"
    static let doneAction = "DONE"
    static let laterAction = "LATER"
    static let wakeAction = "WAKE"
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
        let done = UNNotificationAction(identifier: doneAction, title: String(localized: "Done"), options: [],
                                        icon: UNNotificationActionIcon(systemImageName: "checkmark"))
        let later = UNNotificationAction(identifier: laterAction, title: String(localized: "In 1 hour"), options: [],
                                         icon: UNNotificationActionIcon(systemImageName: "clock"))
        let wake = UNNotificationAction(identifier: wakeAction, title: String(localized: "I'm up"), options: [],
                                        icon: UNNotificationActionIcon(systemImageName: "sunrise"))
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: occurrenceCategory, actions: [done, later], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: morningCategory, actions: [wake], intentIdentifiers: [], options: []),
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

    static func plan(items: [Item], wakes: [String: Int], settings: SyncedSettings, now: Date) -> [Planned] {
        let today = Day(now)
        var result: [Planned] = []
        var anytime: [Day: [(item: Item, slot: Int?)]] = [:]

        // Things paid automatically never send reminders: there's nothing to do.
        for item in items where item.isActive && item.reminder != .off && !item.isAutopay {
            let s = item.schedule
            let thread = item.id.uuidString

            if s.kind == .goal {
                guard let t = s.times.first else { continue }
                for offset in 0..<7 {
                    let d = today.adding(days: offset)
                    let range = s.goalRange(containing: d)
                    let count = range.contains(today) ? item.doneCount(in: range) : 0
                    if count >= s.goalCount { continue }
                    let fire = d.date(minutes: t)
                    guard fire > now else { continue }
                    result.append(Planned(id: "g|\(thread)|\(d.iso)", date: fire, title: item.displayTitle,
                                          body: Format.goalProgress(count, s.goalCount, s.goalPeriod),
                                          category: infoCategory, info: ["item": thread], thread: thread))
                }
                continue
            }

            let days = s.isHourly ? 2 : 8
            for offset in 0..<days {
                let d = today.adding(days: offset)
                guard s.occurs(on: d) else { continue }
                if s.kind == .repeating && d < item.trackFrom { continue }
                let wake = wakes[d.iso]
                if s.usesWake && wake == nil { continue }
                for slot in s.slots(on: d, wake: wake) {
                    if item.entry(day: d, slot: slot.key) != nil { continue }
                    let occurrence = Planner.occurrenceID(item.id, d, slot.key)
                    let info = ["item": thread, "day": d.iso, "slot": slot.key.map { String($0) } ?? "-"]
                    let category = occurrenceCategory
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
            for snooze in item.snoozes where snooze.day < today && snooze.until > now && item.entry(day: snooze.day, slot: snooze.slot) == nil {
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

        // "Are you up?" when wake-up routines are waiting.
        if settings.morningCheckIn && items.contains(where: { $0.isActive && !$0.isAutopay && $0.schedule.usesWake }) {
            for offset in 0..<8 {
                let d = today.adding(days: offset)
                guard wakes[d.iso] == nil else { continue }
                let fire = d.date(minutes: settings.morningMinute)
                guard fire > now else { continue }
                result.append(Planned(id: "m|" + d.iso, date: fire, title: String(localized: "Good morning"),
                                      body: String(localized: "Tap “I'm up” when you're up and your morning tasks will start."),
                                      category: morningCategory, info: [:], thread: "morning"))
            }
        }

        result.sort { $0.date < $1.date }
        return Array(result.prefix(limit))
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
            if item.isAutopay { parts.append(String(localized: "Autopay")) }
        }
        if parts.isEmpty {
            let note = item.notes.split(separator: "\n").first.map { String($0.prefix(90)) } ?? ""
            if !note.isEmpty { parts.append(note) }
        }
        return parts.joined(separator: " · ")
    }

    /// Replaces every pending reminder with a fresh plan. Runs `completion` on the main queue when finished.
    static func reschedule(items: [Item], wakes: [String: Int], settings: SyncedSettings, now: Date, completion: (() -> Void)?) {
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
                let planned = plan(items: items, wakes: wakes, settings: settings, now: now)
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
                        let count = Planner.actionableCount(items: items, at: p.date.addingTimeInterval(1), wake: wakes[Day(p.date).iso])
                        content.badge = NSNumber(value: count)
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
