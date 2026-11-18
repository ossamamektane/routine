import SwiftUI

/// The Tasks tab: what you've done this week, then everything without an amount, grouped by how
/// often. Bills have their own tab.
struct RoutinesView: View {
    @Environment(AppStore.self) private var store
    @State private var search = ""
    @State private var editor: EditorRequest?
    @State private var showSettings = false

    var body: some View {
        let groups = makeGroups()
        let clock = store.clock
        let tasks = store.visibleItems.filter { !$0.hasCost }
        let hasTasks = !tasks.isEmpty
        let searching = !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let count = groups.reduce(0) { $0 + $1.items.count }

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
                                RoutineRow(item: item)
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

    /// "9 tasks completed today", "49 this week": the shorter time first, like Bills. Tap for
    /// each day and each task.
    private func summaryCard(_ tasks: [Item], today: Day) -> some View {
        let days = TaskStats.weekDays(of: today)
        let counts = TaskStats.counts(tasks, days: days)
        let weekCount = counts.reduce(0, +)
        let todayCount = days.firstIndex(of: today).map { (i: Int) -> Int in counts[i] } ?? 0
        return SummaryCard(symbol: "checklist",
                           title: String(localized: "\(todayCount) tasks completed today"),
                           subtitle: String(localized: "\(weekCount) this week"))
    }

    private func makeGroups() -> [ItemGroup] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = store.visibleItems
            .filter { !$0.hasCost }
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.notes.localizedCaseInsensitiveContains(query) }
            .sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        return ItemGroup.make(all, afterDoneTitle: "After Completion")
    }
}

/// A section in Tasks or Bills. Both tabs group the same way, by how often things happen.
struct ItemGroup: Identifiable {
    var id: String
    var title: LocalizedStringKey
    var items: [Item]

    /// Every Day, On a Schedule, Any Day, After Completion (or After Payment), One-Time,
    /// Paused, Completed. Keeps the order the items come in.
    static func make(_ items: [Item], afterDoneTitle: LocalizedStringKey) -> [ItemGroup] {
        var daily: [Item] = [], repeating: [Item] = [], afterDone: [Item] = [], anyDay: [Item] = []
        var once: [Item] = [], paused: [Item] = [], finished: [Item] = []
        for item in items {
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
        var groups: [ItemGroup] = []
        if !daily.isEmpty { groups.append(ItemGroup(id: "daily", title: "Every Day", items: daily)) }
        if !repeating.isEmpty { groups.append(ItemGroup(id: "repeating", title: "On a Schedule", items: repeating)) }
        if !anyDay.isEmpty { groups.append(ItemGroup(id: "anyDay", title: "Any Day", items: anyDay)) }
        if !afterDone.isEmpty { groups.append(ItemGroup(id: "afterDone", title: afterDoneTitle, items: afterDone)) }
        if !once.isEmpty { groups.append(ItemGroup(id: "once", title: "One-Time", items: once)) }
        if !paused.isEmpty { groups.append(ItemGroup(id: "paused", title: "Paused", items: paused)) }
        if !finished.isEmpty { groups.append(ItemGroup(id: "finished", title: "Completed", items: finished)) }
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
        copy.pauses = []
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

/// A task: its name and how often. When it's next and how late it is are on Today.
struct RoutineRow: View {
    var item: Item

    // Colors are spelled out (Color.primary, not .primary): inside a list button,
    // .primary and .secondary would take on the button's tint.
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: item.displayTitle)
                .foregroundStyle(item.paused ? Color.secondary : Color.primary)
                .lineLimit(2)
            Text(verbatim: item.schedule.summary)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
}

/// This week, one row per day.
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
                  total: String(localized: "This week · \(total)"))
    }
}
