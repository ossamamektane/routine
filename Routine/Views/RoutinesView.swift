import SwiftUI

/// The Tasks tab: what you've done this week, then everything without an amount, grouped by how
/// often. Bills have their own tab.
struct RoutinesView: View {
    @Environment(AppStore.self) private var store
    @State private var search = ""
    @State private var editor: EditorRequest?
    @State private var showSettings = false

    private struct ListGroup: Identifiable {
        var id: String
        var title: LocalizedStringKey
        var items: [Item]
    }

    var body: some View {
        let groups = makeGroups()
        let clock = store.clock
        let tasks = store.visibleItems.filter { !$0.hasCost }
        let hasTasks = !tasks.isEmpty
        let searching = !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let count = groups.reduce(0) { $0 + $1.items.count }
        let labels = Self.labels(store.agenda, now: clock.now, today: clock.day)

        NavigationStack {
            List {
                if hasTasks && !searching {
                    Section {
                        NavigationLink {
                            TasksStatsView(tasks: tasks, today: Day(clock.now))
                        } label: {
                            summaryCard(tasks, today: Day(clock.now))
                        }
                    }
                }
                ForEach(groups) { group in
                    Section {
                        ForEach(group.items) { item in
                            Button {
                                editor = .edit(item)
                            } label: {
                                RoutineRow(item: item, label: rowLabel(item, labels: labels, today: clock.day))
                            }
                            .itemActions(item, store: store, editor: $editor)
                        }
                    } header: {
                        Text(group.title)
                    }
                }
                if hasTasks && !searching {
                    ListSummary(text: String(localized: "\(count) Tasks"))
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .searchable(text: $search, prompt: Text("Search"))
            .overlay {
                if !hasTasks {
                    ContentUnavailableView {
                        Label("No Tasks", systemImage: "checklist")
                    } description: {
                        Text("Add the things you do regularly.")
                    } actions: {
                        Button("Add a Task") { editor = .new() }
                            .buttonStyle(.borderedProminent)
                    }
                } else if groups.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editor = .new()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("Add a Task"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showSettings = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel(Text("More"))
                }
            }
            .sheet(item: $editor) { request in
                EditorView(request: request)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    /// "12 completed this week", "3 today". Tap for each day and each task.
    private func summaryCard(_ tasks: [Item], today: Day) -> some View {
        let days = TaskStats.weekDays(of: today)
        let counts = TaskStats.counts(tasks, days: days)
        let weekCount = counts.reduce(0, +)
        let todayCount = days.firstIndex(of: today).map { (i: Int) -> Int in counts[i] } ?? 0
        return SummaryCard(symbol: "checklist",
                           title: String(localized: "\(weekCount) completed this week"),
                           subtitle: String(localized: "\(todayCount) today"))
    }

    /// Each task's label on Today, from its first row there: "In 35m", "Tomorrow", "2 days late".
    private static func labels(_ agenda: Agenda, now: Date, today: Day) -> [UUID: Countdown] {
        var result: [UUID: Countdown] = [:]
        for entry in agenda.tasks where !entry.isBill {
            guard result[entry.itemID] == nil else { continue }
            if let label = entry.label(now: now, today: today) {
                result[entry.itemID] = label
            }
        }
        return result
    }

    /// The same label as on Today. Nothing for things you do every day or every hour (the
    /// section says it), paused or completed ones; goals say how far along they are.
    private func rowLabel(_ item: Item, labels: [UUID: Countdown], today: Day) -> Countdown? {
        let s = item.schedule
        if item.paused || item.isFinished || s.isEveryDay || s.isHourly { return nil }
        if s.kind == .goal {
            let done = item.doneCount(in: s.goalRange(containing: today))
            let total = s.goalCount
            return Countdown(text: String(localized: "\(done) of \(total)"), tone: .normal)
        }
        return labels[item.id]
    }

    private func makeGroups() -> [ListGroup] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = store.visibleItems
            .filter { !$0.hasCost }
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.notes.localizedCaseInsensitiveContains(query) }
            .sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }

        var daily: [Item] = [], repeating: [Item] = [], afterDone: [Item] = [], anyDay: [Item] = []
        var once: [Item] = [], paused: [Item] = [], finished: [Item] = []
        for item in all {
            let s = item.schedule
            if item.isFinished { finished.append(item); continue }
            if item.paused { paused.append(item); continue }
            switch s.kind {
            case .repeating:
                if s.fromDone { afterDone.append(item); continue }
                if s.isEveryDay || s.isHourly { daily.append(item) } else { repeating.append(item) }
            case .afterDone: afterDone.append(item)
            case .goal: anyDay.append(item)
            case .once: once.append(item)
            }
        }
        var groups: [ListGroup] = []
        if !daily.isEmpty { groups.append(ListGroup(id: "daily", title: "Every Day", items: daily)) }
        if !repeating.isEmpty { groups.append(ListGroup(id: "repeating", title: "On a Schedule", items: repeating)) }
        if !anyDay.isEmpty { groups.append(ListGroup(id: "anyDay", title: "Any Day", items: anyDay)) }
        if !afterDone.isEmpty { groups.append(ListGroup(id: "afterDone", title: "After Completion", items: afterDone)) }
        if !once.isEmpty { groups.append(ListGroup(id: "once", title: "One-Time", items: once)) }
        if !paused.isEmpty { groups.append(ListGroup(id: "paused", title: "Paused", items: paused)) }
        if !finished.isEmpty { groups.append(ListGroup(id: "finished", title: "Completed", items: finished)) }
        return groups
    }
}

/// Swipe actions and the long-press menu, shared by the Tasks and Bills lists.
struct ItemActions: ViewModifier {
    var item: Item
    var store: AppStore
    @Binding var editor: EditorRequest?

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    withAnimation { store.delete(item.id) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading) {
                if !item.isFinished {
                    Button {
                        withAnimation { store.setPaused(item.id, !item.paused) }
                    } label: {
                        if item.paused {
                            Label("Resume", systemImage: "play.fill")
                        } else {
                            Label("Pause", systemImage: "pause.fill")
                        }
                    }
                    .tint(.gray)
                }
            }
            .contextMenu {
                Button {
                    editor = .edit(item)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button {
                    editor = .new(duplicate)
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                if !item.isFinished {
                    Button {
                        withAnimation { store.setPaused(item.id, !item.paused) }
                    } label: {
                        if item.paused {
                            Label("Resume", systemImage: "play")
                        } else {
                            Label("Pause", systemImage: "pause")
                        }
                    }
                }
                if let payment = recentPayment {
                    Button {
                        withAnimation { store.undo(item.id, logID: payment.id) }
                    } label: {
                        Label("Undo Last Payment", systemImage: "arrow.uturn.backward")
                    }
                }
                Divider()
                Button(role: .destructive) {
                    withAnimation { store.delete(item.id) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    /// A bill's latest payment from the last 30 days, so a mistaken tap can be taken back.
    private var recentPayment: LogEntry? {
        guard item.hasCost, let last = item.lastDone else { return nil }
        return Date().timeIntervalSince(last.at) < 30 * 24 * 3600 ? last : nil
    }

    /// A fresh copy without history.
    private var duplicate: Item {
        var copy = item
        copy.id = UUID()
        copy.log = []
        copy.snoozes = []
        copy.paused = false
        copy.deletedAt = nil
        copy.createdAt = Date()
        copy.trackFrom = store.clock.day
        return copy
    }
}

extension View {
    func itemActions(_ item: Item, store: AppStore, editor: Binding<EditorRequest?>) -> some View {
        modifier(ItemActions(item: item, store: store, editor: editor))
    }
}

struct RoutineRow: View {
    var item: Item
    /// When it's next, in the same words as Today. Nil when there's nothing to add.
    var label: Countdown?

    // Colors are spelled out (Color.primary, not .primary): inside a list button,
    // .primary and .secondary would take on the button's tint.
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.displayTitle)
                    .foregroundStyle(item.paused ? Color.secondary : Color.primary)
                    .lineLimit(2)
                Text(verbatim: item.schedule.summary)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            if let label {
                CountdownLabel(countdown: label)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// What you checked off this week, day by day and by task. A week, because history only goes
/// back so far for things you do many times a day.
enum TaskStats {
    /// The week `today` is in, from the phone's first day of the week.
    static func weekDays(of today: Day) -> [Day] {
        let back = Day.mod(today.weekday - RoutineCalendar.current.firstWeekday, 7)
        let first = today.adding(days: -back)
        return (0..<7).map { (n: Int) -> Day in first.adding(days: n) }
    }

    /// How many times things were checked off on each of `days` (in a row, oldest first).
    static func counts(_ tasks: [Item], days: [Day]) -> [Int] {
        guard let first = days.first, let last = days.last else { return [] }
        var counts = [Int](repeating: 0, count: days.count)
        let start = first.date()
        let end = last.adding(days: 1).date()
        for item in tasks {
            for entry in item.log where entry.kind == .done && entry.at >= start && entry.at < end {
                let index = Day(entry.at).index - first.index
                if index >= 0 && index < counts.count { counts[index] += 1 }
            }
        }
        return counts
    }

    private struct TaskCount {
        var item: Item
        var count: Int
    }

    /// Each task's count for `days`, the most first.
    static func byTask(_ tasks: [Item], days: [Day]) -> [StatsView.Row] {
        var rows: [TaskCount] = []
        for item in tasks {
            let count = counts([item], days: days).reduce(0, +)
            if count > 0 { rows.append(TaskCount(item: item, count: count)) }
        }
        rows.sort { (a: TaskCount, b: TaskCount) -> Bool in
            if a.count != b.count { return a.count > b.count }
            return a.item.displayTitle.localizedStandardCompare(b.item.displayTitle) == .orderedAscending
        }
        return rows.map { (row: TaskCount) -> StatsView.Row in
            StatsView.Row(id: row.item.id.uuidString, title: row.item.displayTitle, value: row.count.formatted())
        }
    }
}

/// This week, one row per day, then each task.
struct TasksStatsView: View {
    var tasks: [Item]
    var today: Day

    var body: some View {
        let days = TaskStats.weekDays(of: today)
        let counts = TaskStats.counts(tasks, days: days)
        let total = counts.reduce(0, +)
        StatsView(title: String(localized: "This Week"),
                  periods: days.indices.map { (i: Int) -> StatsView.Row in
                      StatsView.Row(id: days[i].iso,
                                    title: days[i].noon.formatted(.dateTime.weekday(.wide)).localizedCapitalized,
                                    value: counts[i].formatted(),
                                    dimmed: days[i] > today,
                                    emphasized: days[i] == today)
                  },
                  total: String(localized: "This week · \(total)"),
                  breakdownTitle: "By Task",
                  breakdown: TaskStats.byTask(tasks, days: days))
    }
}
