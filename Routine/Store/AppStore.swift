import Foundation
import Observation
import UIKit
import UserNotifications

enum CloudState: Equatable {
    case available, noAccount, full
}

/// The single source of truth. Every change is saved to disk at once, sent to iCloud,
/// and the reminders are re-planned.
///
/// Your day: it starts at the wake-up time you set, and Routine asks "Did you sleep?" when the
/// clues add up (see `SleepCheck`). It never starts or ends a day by guessing, except that a day
/// you're still up for after midnight ends by itself the next morning (see `SleepCheck.cut`).
@Observable
final class AppStore {
    static let shared = AppStore()

    private(set) var items: [Item] = []
    /// When you got up, per calendar day: "2025-11-04" → minutes after midnight.
    private(set) var wakes: [String: Int] = [:]
    /// What Routine remembers to decide when to ask "Did you sleep?". Kept on this iPhone only.
    private(set) var sleepLog = SleepLog()
    private(set) var settings = SyncedSettings()
    /// Moves forward every 30 seconds so Today stays current.
    private(set) var now = Date()
    private(set) var cloudState: CloudState = .noAccount
    private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
    /// Bumped on every completion; drives the success haptic.
    private(set) var completions = 0
    var selectedTab: AppTab = .today

    private let persistence = Persistence()
    @ObservationIgnored private var cloud: CloudSync? = nil
    @ObservationIgnored private var timer: Timer? = nil
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var pendingReminders: DispatchWorkItem? = nil
    @ObservationIgnored private var lastBadge = -1
    @ObservationIgnored private var started = false
    /// Routine is on screen, so each tick means you're using it.
    @ObservationIgnored private var inForeground = false
    /// The last change to wake-up times, so the newest one wins in iCloud.
    @ObservationIgnored private var wakesChangedAt = Date(timeIntervalSince1970: 0)

    init() {
        UserDefaults.standard.register(defaults: [PrefKey.reminders: true, PrefKey.badge: true])
        if let stored = persistence.load() {
            items = stored.items
            wakes = stored.wakes
            wakesChangedAt = stored.wakesModifiedAt
            settings = stored.settings
        } else if !UserDefaults.standard.bool(forKey: PrefKey.legacyDone), let legacy = LegacyImport.run() {
            items = legacy.items
            wakes = legacy.wakes
            if let appearance = legacy.appearance {
                UserDefaults.standard.set(appearance.rawValue, forKey: PrefKey.appearance)
            }
            persistence.save(snapshot)
        }
        UserDefaults.standard.set(true, forKey: PrefKey.legacyDone)
        sleepLog = Self.loadSleepLog()
    }

    /// Starts iCloud sync, the clock and reminders. Safe to call more than once.
    func start() {
        guard !started else { return }
        started = true

        let sync = CloudSync()
        sync.onChange = { [weak self] reason in
            self?.cloudChanged(reason: reason)
        }
        cloud = sync
        sync.start()
        mergeFromCloud()
        purgeDeleted()
        updateCloudState()

        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.tick()
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.significantTimeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            RoutineCalendar.refresh()
            self?.tick()
            self?.scheduleReminders()
        })
        observers.append(center.addObserver(forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.updateCloudState()
            self?.cloud?.synchronize()
        })
        refreshNotificationStatus()
        scheduleReminders()
        updateBadge()
    }

    /// Called whenever the app comes to the front.
    func becameActive() {
        inForeground = true
        RoutineCalendar.refresh()
        cloud?.synchronize()
        mergeFromCloud()
        updateCloudState()
        refreshNotificationStatus()
        tick()
        scheduleReminders()
    }

    /// Called when the app goes to the background: you were using it until now.
    func enteredBackground() {
        noteActivity()
        inForeground = false
    }

    func tick() {
        let date = Date()
        repairClockIfNeeded(date)
        let dayBefore = clock.day
        let newCalendarDay = Day(date) != Day(now)
        // When you last used Routine, before this moment counts as using it.
        let lastUse = SleepCheck.lastUse(sleepLog, now: date)
        now = date
        if newCalendarDay { cleanUp() }
        if inForeground {
            checkSleep(lastUse: lastUse)
            noteActivity()
        }
        if newCalendarDay || clock.day != dayBefore { scheduleReminders() }
        updateBadge()
    }

    // MARK: Reading

    var visibleItems: [Item] { items.filter { $0.deletedAt == nil } }
    /// The day you're living: it starts at the wake-up time you set and can keep going after midnight.
    var clock: DayClock { rules.clock(at: now) }
    var rules: DayRules { rules(at: now) }
    var agenda: Agenda { Planner.agenda(items: items, clock: clock) }
    /// One row per bill, soonest first.
    var bills: [AgendaEntry] { Planner.bills(items: items, now: now) }
    /// What you paid and pay in each month of this year.
    var stats: [MonthTotal] { MoneyPlanner.yearMonths(items: items, now: now) }
    var itemsByID: [UUID: Item] { Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) }
    var remindersEnabled: Bool { UserDefaults.standard.bool(forKey: PrefKey.reminders) }

    func findItem(_ id: UUID) -> Item? {
        items.first { $0.id == id }
    }

    private var snapshot: StoredData {
        StoredData(items: items, wakes: wakes, sleeps: [:], wakesModifiedAt: wakesChangedAt, settings: settings)
    }

    /// The day you're living right this moment, for actions (the 30-second `now` can lag behind).
    private var liveClock: DayClock {
        let date = Date()
        return rules(at: date).clock(at: date)
    }

    /// Everything that decides the day you're living at `date` (see `DayClock`).
    func rules(at date: Date) -> DayRules {
        let usual = SleepCheck.usualDay(sleepLog)
        var result = DayRules(wakes: wakes, usualDay: usual, cuts: [:], upSince: sleepLog.upSince)
        let today = Day(date)
        let yesterday = today.adding(days: -1)
        if let w = wakes[yesterday.iso] {
            // Up since yesterday: does the day keep going until your wake-up time, or end earlier by itself?
            let began = yesterday.date(minutes: w)
            var up = began
            if let since = sleepLog.upSince, since < began { up = since }
            let stillUp = SleepCheck.isStillUp(sleepLog, up: up, now: date)
            result.cuts[yesterday.iso] = SleepCheck.cut(wakeMinute: w, stillUp: stillUp, usualDay: usual,
                                                        fixedTimes: fixedTimes(on: today))
        }
        if let w = wakes[today.iso] {
            result.cuts[today.iso] = SleepCheck.cut(wakeMinute: w, stillUp: false, usualDay: usual,
                                                    fixedTimes: fixedTimes(on: today.adding(days: 1)))
        }
        return result
    }

    /// Tasks at a set time on a day (not timed from waking), still to do. A day you're still up
    /// for never runs past them, so they show up on time.
    private func fixedTimes(on day: Day) -> [Int] {
        var result: [Int] = []
        for item in items where item.isActive && !item.hasCost {
            let s = item.schedule
            guard s.kind != .goal, !s.isHourly, !s.usesWake, s.occurs(on: day) else { continue }
            if s.kind == .repeating && day < item.trackFrom { continue }
            for slot in s.slots(on: day, wake: nil) {
                if let m = slot.minute, item.entry(day: day, slot: slot.key) == nil { result.append(m) }
            }
        }
        return result
    }

    /// When you last got up, from the wake-up times of the last two days.
    var lastWakeDate: Date? {
        let today = Day(now)
        for back in 0...2 {
            let d = today.adding(days: -back)
            guard let w = wakes[d.iso] else { continue }
            let date = d.date(minutes: w)
            if date <= now.addingTimeInterval(600) && now.timeIntervalSince(date) <= 48 * 3600 { return date }
        }
        return nil
    }

    // MARK: Editing items

    func save(_ item: Item) {
        var copy = item
        copy.schedule = copy.schedule.normalized()
        copy.title = copy.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = items.firstIndex(where: { $0.id == copy.id })
        copy.modifiedAt = Self.stamp(after: existing.map { items[$0].modifiedAt })
        if let index = existing {
            items[index] = copy
        } else {
            items.append(copy)
        }
        noteActivity()
        commit([copy.id])
    }

    func delete(_ id: UUID) {
        mutate(id) { item in
            item.deletedAt = Date()
            item.snoozes = []
        }
    }

    func setPaused(_ id: UUID, _ paused: Bool) {
        let today = liveClock.day
        mutate(id) { item in
            item.paused = paused
            if !paused { item.trackFrom = today }
        }
    }

    private func mutate(_ id: UUID, immediate: Bool = false, _ change: (inout Item) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var copy = items[index]
        change(&copy)
        copy.modifiedAt = Self.stamp(after: items[index].modifiedAt)
        items[index] = copy
        // Checking things off (even from a reminder) means you're up.
        noteActivity()
        commit([id], immediate: immediate)
    }

    /// A change is always newer than what it replaces, even after the clock was turned back,
    /// so it wins in iCloud.
    private static func stamp(after previous: Date?) -> Date {
        let date = Date()
        guard let previous, previous >= date else { return date }
        return previous.addingTimeInterval(0.001)
    }

    // MARK: Checking things off

    func complete(_ itemID: UUID, day: Day, slot: Int?, skipped: Bool = false, immediate: Bool = false) {
        let date = Date()
        let current = liveClock
        let living = current.day
        mutate(itemID, immediate: immediate) { item in
            // Tapping twice never checks the same one off twice.
            if item.schedule.kind != .goal && Planner.isLogged(item, day: day, slot: slot, clock: current) { return }
            var entry = LogEntry(kind: skipped ? .skipped : .done, at: date, day: day, slot: slot)
            if !skipped { entry.amount = item.cost }
            if item.schedule.kind == .afterDone {
                entry.previousDue = item.schedule.nextDue
                entry.previousDueTime = item.schedule.nextDueTime
                // Bills follow the calendar; tasks the day you're living.
                item.schedule.advanceAfterDone(at: date, day: item.hasCost ? Day(date) : living)
            }
            item.log.append(entry)
            item.snoozes.removeAll { $0.day == day && $0.slot == slot }
            item.trimHistory(now: date)
        }
        Reminders.clearDelivered(itemID: itemID, day: day, slot: slot)
        if !skipped { completions += 1 }
    }

    func complete(_ entry: AgendaEntry, skipped: Bool = false) {
        complete(entry.itemID, day: entry.day, slot: entry.slot, skipped: skipped)
    }

    /// Undo a specific completion, or the latest one today when `logID` is nil.
    /// "Repeat after completion" goes back to when it was due before.
    func undo(_ itemID: UUID, logID: UUID? = nil) {
        let today = Day(Date())
        let current = liveClock
        mutate(itemID) { item in
            let index: Int?
            if let logID {
                index = item.log.lastIndex { $0.id == logID }
            } else {
                index = item.log.lastIndex { current.includes($0) || Day($0.at) == today || $0.day == today }
            }
            guard let i = index else { return }
            let entry = item.log[i]
            if item.schedule.kind == .afterDone, i == item.log.count - 1, let due = entry.previousDue {
                item.schedule.nextDue = due
                item.schedule.nextDueTime = entry.previousDueTime
            }
            item.log.remove(at: i)
        }
    }

    func undo(_ entry: AgendaEntry) {
        undo(entry.itemID, logID: entry.logID)
    }

    func snooze(_ itemID: UUID, day: Day, slot: Int?, until: Date, immediate: Bool = false) {
        mutate(itemID, immediate: immediate) { item in
            item.snoozes.removeAll { $0.day == day && $0.slot == slot }
            item.snoozes.append(Snooze(day: day, slot: slot, until: until))
        }
        Reminders.clearDelivered(itemID: itemID, day: day, slot: slot)
    }

    func laterOptions(for entry: AgendaEntry) -> [LaterOption] {
        guard let item = findItem(entry.itemID) else { return [] }
        return Planner.laterOptions(for: entry, item: item, clock: liveClock)
    }

    // MARK: "Did you sleep?"

    /// Remembers that you're using Routine right now: the best clue that you're awake.
    func noteActivity() {
        if SleepCheck.note(&sleepLog, at: Date()) { saveSleepLog() }
    }

    /// Asks "Did you sleep?" when the clues add up, and asks when you woke up when no day has started.
    /// Never in the middle of your night, and not again after "Not Now" until the next day.
    private func checkSleep(lastUse: Date?) {
        guard sleepLog.question == nil else { return }
        // Only for people whose tasks follow their day: timed from waking, hourly, or who've answered before.
        let relevant = sleepLog.used || items.contains { item in
            item.isActive && !item.hasCost && (item.schedule.usesWake || item.schedule.isHourly)
        }
        guard relevant else { return }
        let current = clock
        if current.wake == nil, let dismissed = sleepLog.dismissedAt, dismissed >= current.began { return }
        let lastWake = lastWakeDate

        // A quiet stretch that looks like sleep (unless a wake-up time was set since, on another device).
        if let lastUse, now.timeIntervalSince(lastUse) >= SleepCheck.quietGap {
            let wokeSince = lastWake.map { $0 > lastUse } ?? false
            if !wokeSince {
                let missed = missedCount(since: lastUse)
                if SleepCheck.shouldAsk(sleepLog, lastUse: lastUse, now: now, up: current.upDate ?? lastWake, missed: missed) {
                    ask(from: lastUse, auto: true)
                    return
                }
            }
        }

        // No day has started (or yesterday's ended by itself): ask, but not before your morning.
        guard current.wake == nil else { return }
        let earliest = Day(now).start.addingTimeInterval(TimeInterval((SleepCheck.usualWake(sleepLog) - 4 * 60) * 60))
        if now >= earliest {
            ask(from: now, auto: false)
        }
    }

    private func ask(from date: Date, auto: Bool) {
        sleepLog.question = SleepQuestion(from: date, auto: auto)
        saveSleepLog()
    }

    /// Reminders that went by with nothing checked off since you were last seen.
    private func missedCount(since lastUse: Date) -> Int {
        agenda.tasks.filter { e in
            guard e.deadlineKind == .time, let deadline = e.deadline else { return false }
            return deadline > lastUse && deadline <= now
        }.count
    }

    /// "Not yet": you haven't slept. The day you're in keeps going; if it already ended,
    /// a new one starts, with "Up for" still counting from when you really got up.
    func answerStillUp() {
        now = Date()
        let before = clock
        let previousUp = before.upDate ?? lastWakeDate
        sleepLog.stillUpAt = now
        sleepLog.question = nil
        sleepLog.used = true
        let after = clock
        if after.wake == nil, let previousUp {
            let today = Day(now)
            let ended = rules.cuts[today.adding(days: -1).iso] ?? 0
            wakes[today.iso] = min(now.minutesOfDay, max(ended, SleepCheck.usualWake(sleepLog)))
            sleepLog.upSince = previousUp
            saveSleepLog()
            commitWakes(immediate: false)
        } else {
            saveSleepLog()
            refreshAfterDayChange()
        }
    }

    /// "What time did you wake up?" Today starts a new day then. Yesterday means you haven't slept
    /// since: the day you're in keeps going, or a new one starts with "Up for" counting from then.
    func answerWoke(at date: Date) {
        now = Date()
        let moment = min(date, now)
        let current = clock
        let question = sleepLog.question
        let today = Day(now)
        let yesterday = today.adding(days: -1)
        let startsNewDay = current.wake == nil || current.day != today || question != nil
        if Day(moment) == today {
            let previousUp = current.upDate ?? lastWakeDate
            setWake(moment)
            sleepLog.upSince = nil
            sleepLog.stillUpAt = nil
            // Your answers teach Routine your usual wake-up time and how long your days last.
            if startsNewDay { SleepCheck.learnWake(&sleepLog, at: moment) }
            if let question, question.auto, let previousUp, question.from > previousUp {
                SleepCheck.learnDay(&sleepLog, minutes: Int(question.from.timeIntervalSince(previousUp) / 60))
            }
        } else {
            // Up since yesterday without sleep.
            let minute = moment.minutesOfDay
            sleepLog.stillUpAt = now
            wakes[yesterday.iso] = minute
            let ended = SleepCheck.cut(wakeMinute: minute, stillUp: true, usualDay: SleepCheck.usualDay(sleepLog),
                                       fixedTimes: fixedTimes(on: today))
            if now.minutesOfDay < ended {
                wakes[today.iso] = nil
                sleepLog.upSince = nil
            } else {
                wakes[today.iso] = min(now.minutesOfDay, max(ended, SleepCheck.usualWake(sleepLog)))
                sleepLog.upSince = moment
            }
        }
        sleepLog.question = nil
        sleepLog.used = true
        saveSleepLog()
        commitWakes(immediate: false)
    }

    /// "Not Now": no wake-up time for now. Routine doesn't ask again until the next day.
    func dismissQuestion() {
        sleepLog.question = nil
        sleepLog.dismissedAt = Date()
        saveSleepLog()
        refreshAfterDayChange()
    }

    /// "I'm Not Up Yet": takes back the wake-up time of the day you're in.
    func clearWake() {
        let current = liveClock
        if current.wake != nil { wakes[current.day.iso] = nil }
        sleepLog.upSince = nil
        sleepLog.stillUpAt = nil
        sleepLog.question = nil
        sleepLog.dismissedAt = Date()
        saveSleepLog()
        commitWakes(immediate: false)
    }

    /// Your day starts at `moment`. Anything recorded after that moment is replaced.
    private func setWake(_ moment: Date) {
        let day = Day(moment)
        wakes = wakes.filter { entry in
            guard entry.key != day.iso, let d = Day(iso: entry.key) else { return false }
            return d.date(minutes: entry.value) < moment
        }
        wakes[day.iso] = moment.minutesOfDay
    }

    private func trimWakes() {
        let oldest = Day.today.adding(days: -30).iso
        wakes = wakes.filter { $0.key >= oldest }
    }

    private func commitWakes(immediate: Bool) {
        trimWakes()
        wakesChangedAt = Self.stamp(after: wakesChangedAt)
        persistence.save(snapshot)
        cloud?.writeDays(WakeRecords(wakes: wakes, sleeps: [:], modifiedAt: wakesChangedAt))
        noteActivity()
        if immediate { now = Date(); scheduleRemindersNow(completion: nil); updateBadge() } else { refreshAfterDayChange() }
    }

    private func refreshAfterDayChange() {
        now = Date()
        scheduleReminders()
        updateBadge()
    }

    private func saveSleepLog() {
        if let data = try? Coding.encoder.encode(sleepLog) {
            UserDefaults.standard.set(data, forKey: PrefKey.sleepLog)
        }
    }

    private static func loadSleepLog() -> SleepLog {
        guard let data = UserDefaults.standard.data(forKey: PrefKey.sleepLog),
              let log = try? Coding.decoder.decode(SleepLog.self, from: data) else { return SleepLog() }
        return log
    }

    // MARK: The clock was turned back

    /// The phone's clock went back (set by hand, or put right after being set ahead): whatever was
    /// stamped "in the future" never really happened. Check-offs are taken back like Undo would,
    /// wake-up times that haven't come yet are removed, and the sleep question starts over.
    private func repairClockIfNeeded(_ date: Date) {
        let seen = UserDefaults.standard.double(forKey: PrefKey.lastSeen)
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: PrefKey.lastSeen)
        guard seen > 0, date.timeIntervalSince1970 < seen - 600 else { return }

        var changed: [UUID] = []
        for index in items.indices {
            var copy = items[index]
            if copy.forgetFuture(now: date) {
                copy.modifiedAt = Self.stamp(after: copy.modifiedAt)
                items[index] = copy
                changed.append(copy.id)
            }
        }
        let limit = date.addingTimeInterval(600)
        let keptWakes = wakes.filter { entry in
            guard let d = Day(iso: entry.key) else { return false }
            return d.date(minutes: entry.value) <= limit
        }
        var log = sleepLog
        log.spans = log.spans.compactMap { (span: ActivitySpan) -> ActivitySpan? in
            if span.start > limit { return nil }
            var kept = span
            if kept.end > date { kept.end = max(kept.start, date) }
            return kept
        }
        if let q = log.question, q.from > limit { log.question = nil }
        if let t = log.stillUpAt, t > limit { log.stillUpAt = nil }
        if let t = log.upSince, t > limit { log.upSince = nil }
        if let t = log.dismissedAt, t > limit { log.dismissedAt = nil }
        sleepLog = log
        saveSleepLog()
        if keptWakes != wakes {
            wakes = keptWakes
            commitWakes(immediate: false)
        }
        if !changed.isEmpty { commit(changed) }
    }

    // MARK: Settings

    func updateSettings(_ change: (inout SyncedSettings) -> Void) {
        var copy = settings
        change(&copy)
        copy.modifiedAt = Self.stamp(after: settings.modifiedAt)
        settings = copy
        persistence.save(snapshot)
        cloud?.writeSettings(settings)
        scheduleReminders()
    }

    func setRemindersEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: PrefKey.reminders)
        if on && notificationStatus == .notDetermined {
            requestNotifications()
        } else {
            scheduleReminders()
        }
    }

    func setBadgeEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: PrefKey.badge)
        lastBadge = -1
        updateBadge()
        scheduleReminders()
    }

    // MARK: Notifications

    func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { result in
            let status = result.authorizationStatus
            DispatchQueue.main.async {
                self.notificationStatus = status
            }
        }
    }

    func requestNotifications(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                self.refreshNotificationStatus()
                self.scheduleReminders()
                self.lastBadge = -1
                self.updateBadge()
                completion?(granted)
            }
        }
    }

    /// Asks for permission the first time something gets a reminder.
    func askForNotificationsIfNeeded() {
        if notificationStatus == .notDetermined && remindersEnabled {
            requestNotifications()
        }
    }

    /// Re-plans reminders shortly after a burst of changes.
    func scheduleReminders() {
        pendingReminders?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.scheduleRemindersNow(completion: nil)
        }
        pendingReminders = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func scheduleRemindersNow(completion: (() -> Void)?) {
        pendingReminders?.cancel()
        pendingReminders = nil
        let date = Date()
        Reminders.reschedule(items: items, rules: rules(at: date), settings: settings, now: date, completion: completion)
    }

    func updateBadge() {
        let count = UserDefaults.standard.bool(forKey: PrefKey.badge) ? Planner.badgeCount(items: items, clock: clock) : 0
        guard count != lastBadge else { return }
        lastBadge = count
        UNUserNotificationCenter.current().setBadgeCount(count) { _ in }
    }

    // MARK: Saving and syncing

    private func commit(_ ids: [UUID], immediate: Bool = false) {
        persistence.save(snapshot)
        if let cloud {
            for id in ids {
                if let item = findItem(id) { cloud.write(item) }
            }
        }
        now = Date()
        if immediate { scheduleRemindersNow(completion: nil) } else { scheduleReminders() }
        updateBadge()
    }

    private func cloudChanged(reason: Int?) {
        if reason == NSUbiquitousKeyValueStoreQuotaViolationChange {
            cloudState = .full
            return
        }
        mergeFromCloud()
        updateCloudState()
    }

    private func updateCloudState() {
        if !CloudSync.isAccountAvailable {
            cloudState = .noAccount
        } else if cloudState != .full {
            cloudState = .available
        }
    }

    /// Newest version of each item wins. Anything only on this iPhone is uploaded.
    private func mergeFromCloud() {
        guard let cloud else { return }
        var changed = false
        var byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, b in a.modifiedAt >= b.modifiedAt ? a : b })
        var remoteIDs = Set<UUID>()
        for remote in cloud.remoteItems() {
            remoteIDs.insert(remote.id)
            if let local = byID[remote.id] {
                if remote.modifiedAt > local.modifiedAt {
                    byID[remote.id] = remote
                    changed = true
                } else if local.modifiedAt > remote.modifiedAt {
                    cloud.write(local)
                }
            } else {
                byID[remote.id] = remote
                changed = true
            }
        }
        for local in items where !remoteIDs.contains(local.id) {
            cloud.write(local)
        }
        if changed {
            items = byID.values.sorted { $0.createdAt < $1.createdAt }
        }

        // Wake-up times: the newest change wins.
        if let remote = cloud.remoteDays() {
            if remote.modifiedAt > wakesChangedAt {
                wakes = remote.wakes
                wakesChangedAt = remote.modifiedAt
                changed = true
            } else if wakesChangedAt > remote.modifiedAt {
                cloud.writeDays(WakeRecords(wakes: wakes, sleeps: [:], modifiedAt: wakesChangedAt))
            }
        } else {
            // Nothing in the new format yet: keep wake-up times an earlier version synced.
            var merged = wakes
            for (day, minute) in cloud.remoteWakes() where merged[day] == nil {
                merged[day] = minute
            }
            if merged != wakes {
                wakes = merged
                changed = true
            }
            cloud.writeDays(WakeRecords(wakes: wakes, sleeps: [:], modifiedAt: wakesChangedAt))
        }

        if let remoteSettings = cloud.remoteSettings() {
            if remoteSettings.modifiedAt > settings.modifiedAt {
                settings = remoteSettings
                changed = true
            } else if settings.modifiedAt > remoteSettings.modifiedAt {
                cloud.writeSettings(settings)
            }
        } else {
            cloud.writeSettings(settings)
        }

        if changed {
            persistence.save(snapshot)
            now = Date()
            scheduleReminders()
            updateBadge()
        }
    }

    /// Deleted items are kept for 60 days so every device hears about it, then removed for good.
    private func purgeDeleted() {
        let cutoff = Date().addingTimeInterval(-60 * 86_400)
        let expired = items.filter { ($0.deletedAt ?? .distantFuture) < cutoff }
        guard !expired.isEmpty else { return }
        items.removeAll { ($0.deletedAt ?? .distantFuture) < cutoff }
        for item in expired { cloud?.remove(item.id) }
        persistence.save(snapshot)
    }

    private func cleanUp() {
        let date = Date()
        var changed: [UUID] = []
        for index in items.indices {
            let before = items[index]
            var copy = before
            copy.trimHistory(now: date)
            if copy != before {
                items[index] = copy
                changed.append(copy.id)
            }
        }
        trimWakes()
        purgeDeleted()
        if !changed.isEmpty { commit(changed) }
    }
}
