import Foundation
import Observation
import UIKit
import UserNotifications

enum CloudState: Equatable {
    case available, noAccount, full
}

/// The single source of truth. Every change is saved to disk at once, sent to iCloud,
/// and the reminders are re-planned.
@Observable
final class AppStore {
    static let shared = AppStore()

    private(set) var items: [Item] = []
    private(set) var wakes: [String: Int] = [:]
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

    init() {
        UserDefaults.standard.register(defaults: [PrefKey.reminders: true, PrefKey.badge: true])
        if let stored = persistence.load() {
            items = stored.items
            wakes = stored.wakes
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
        RoutineCalendar.refresh()
        cloud?.synchronize()
        mergeFromCloud()
        updateCloudState()
        refreshNotificationStatus()
        tick()
        scheduleReminders()
    }

    func tick() {
        let date = Date()
        let newDay = Day(date) != Day(now)
        now = date
        if newDay {
            cleanUp()
            scheduleReminders()
        }
        updateBadge()
    }

    // MARK: Reading

    var visibleItems: [Item] { items.filter { $0.deletedAt == nil } }
    var todayWake: Int? { wakes[Day(now).iso] }
    var agenda: Agenda { Planner.agenda(items: items, now: now, wake: todayWake) }
    var money: MoneySummary { MoneyPlanner.summary(items: items, now: now) }
    var itemsByID: [UUID: Item] { Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) }
    var remindersEnabled: Bool { UserDefaults.standard.bool(forKey: PrefKey.reminders) }

    func findItem(_ id: UUID) -> Item? {
        items.first { $0.id == id }
    }

    private var snapshot: StoredData {
        StoredData(items: items, wakes: wakes, settings: settings)
    }

    // MARK: Editing items

    func save(_ item: Item) {
        var copy = item
        copy.schedule = copy.schedule.normalized()
        copy.title = copy.title.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.modifiedAt = Date()
        if let index = items.firstIndex(where: { $0.id == copy.id }) {
            items[index] = copy
        } else {
            items.append(copy)
        }
        commit([copy.id])
    }

    func delete(_ id: UUID) {
        mutate(id) { item in
            item.deletedAt = Date()
            item.snoozes = []
        }
    }

    func setPaused(_ id: UUID, _ paused: Bool) {
        mutate(id) { item in
            item.paused = paused
            if !paused { item.trackFrom = Day.today }
        }
    }

    private func mutate(_ id: UUID, immediate: Bool = false, _ change: (inout Item) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var copy = items[index]
        change(&copy)
        copy.modifiedAt = Date()
        items[index] = copy
        commit([id], immediate: immediate)
    }

    // MARK: Checking things off

    func complete(_ itemID: UUID, day: Day, slot: Int?, skipped: Bool = false, immediate: Bool = false) {
        let date = Date()
        mutate(itemID, immediate: immediate) { item in
            if item.schedule.kind != .goal && item.entry(day: day, slot: slot) != nil { return }
            var entry = LogEntry(kind: skipped ? .skipped : .done, at: date, day: day, slot: slot)
            if !skipped { entry.amount = item.cost }
            if item.schedule.kind == .afterDone {
                entry.previousDue = item.schedule.nextDue
                entry.previousDueTime = item.schedule.nextDueTime
                item.schedule.advanceAfterDone(at: date)
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
    func undo(_ itemID: UUID, logID: UUID? = nil) {
        let today = Day(Date())
        mutate(itemID) { item in
            let index: Int?
            if let logID {
                index = item.log.lastIndex { $0.id == logID }
            } else {
                index = item.log.lastIndex { Day($0.at) == today || $0.day == today }
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
        return Planner.laterOptions(for: entry, item: item, now: Date())
    }

    // MARK: Waking up

    func wakeUp(at date: Date, immediate: Bool = false) {
        let clamped = min(date, Date())
        wakes[Day(clamped).iso] = clamped.minutesOfDay
        trimWakes()
        commitWakes(immediate: immediate)
    }

    func clearWake() {
        wakes[Day(Date()).iso] = nil
        commitWakes(immediate: false)
    }

    private func trimWakes() {
        let oldest = Day.today.adding(days: -30).iso
        wakes = wakes.filter { $0.key >= oldest }
    }

    private func commitWakes(immediate: Bool) {
        persistence.save(snapshot)
        cloud?.writeWakes(wakes)
        now = Date()
        if immediate { scheduleRemindersNow(completion: nil) } else { scheduleReminders() }
        updateBadge()
    }

    // MARK: Settings

    func updateSettings(_ change: (inout SyncedSettings) -> Void) {
        var copy = settings
        change(&copy)
        copy.modifiedAt = Date()
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
        Reminders.reschedule(items: items, wakes: wakes, settings: settings, now: Date(), completion: completion)
    }

    func updateBadge() {
        let count = UserDefaults.standard.bool(forKey: PrefKey.badge) ? agenda.actionableCount : 0
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

        let remoteWakes = cloud.remoteWakes()
        var mergedWakes = wakes
        for (day, minute) in remoteWakes where mergedWakes[day] == nil {
            mergedWakes[day] = minute
        }
        if mergedWakes != wakes {
            wakes = mergedWakes
            changed = true
        }
        if mergedWakes != remoteWakes { cloud.writeWakes(mergedWakes) }

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
