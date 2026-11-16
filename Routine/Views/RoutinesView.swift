import SwiftUI

/// The Tasks tab: everything without an amount. Bills have their own tab.
struct RoutinesView: View {
    @Environment(AppStore.self) private var store
    @State private var search = ""
    @State private var editor: EditorRequest?

    private struct ListGroup: Identifiable {
        var id: String
        var title: LocalizedStringKey
        var items: [Item]
    }

    var body: some View {
        let groups = makeGroups()
        let today = Day(store.now)
        let currency = store.settings.currency
        let hasTasks = store.visibleItems.contains { !$0.hasCost }

        NavigationStack {
            List {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.items) { item in
                            Button {
                                editor = .edit(item)
                            } label: {
                                RoutineRow(item: item, today: today, currency: currency)
                            }
                            .itemActions(item, store: store, editor: $editor)
                        }
                    } header: {
                        Text(group.title)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $search, prompt: Text("Search"))
            .overlay {
                if !hasTasks {
                    ContentUnavailableView {
                        Label("No tasks yet", systemImage: "checklist")
                    } description: {
                        Text("Tap + to add something you do regularly.")
                    } actions: {
                        Button("Add a task") { editor = .new() }
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
                    .accessibilityLabel(Text("Add a task"))
                }
            }
            .sheet(item: $editor) { request in
                EditorView(request: request)
            }
        }
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
                if s.isEveryDay || s.isHourly { daily.append(item) } else { repeating.append(item) }
            case .afterDone: afterDone.append(item)
            case .goal: anyDay.append(item)
            case .once: once.append(item)
            }
        }
        var groups: [ListGroup] = []
        if !daily.isEmpty { groups.append(ListGroup(id: "daily", title: "Every day", items: daily)) }
        if !repeating.isEmpty { groups.append(ListGroup(id: "repeating", title: "On a schedule", items: repeating)) }
        if !anyDay.isEmpty { groups.append(ListGroup(id: "anyDay", title: "Any day", items: anyDay)) }
        if !afterDone.isEmpty { groups.append(ListGroup(id: "afterDone", title: "After the last time", items: afterDone)) }
        if !once.isEmpty { groups.append(ListGroup(id: "once", title: "One-time", items: once)) }
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
                    .tint(.orange)
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
                Divider()
                Button(role: .destructive) {
                    withAnimation { store.delete(item.id) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
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
        copy.trackFrom = Day.today
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
    var today: Day
    var currency: String

    // Colors are spelled out (Color.primary, not .primary): inside a list button,
    // .primary and .secondary would take on the button's green tint.
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
                if let next = nextText {
                    Text(verbatim: next)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
            }
            Spacer(minLength: 6)
            if item.hasCost, let cost = item.cost {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.money(cost, code: currency))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Color.primary)
                    if item.isAutopay {
                        Text("Autopay")
                            .font(.caption2)
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var nextText: String? {
        let s = item.schedule
        if item.isFinished {
            guard let done = item.lastDone ?? item.log.last else { return nil }
            return String(localized: "Done \(Format.day(Day(done.at)))")
        }
        if item.paused { return nil }
        switch s.kind {
        case .afterDone:
            var parts: [String] = []
            if let last = item.lastDone {
                parts.append(String(localized: "Last time \(last.at.formatted(.relative(presentation: .named)))"))
            }
            if let due = s.nextDue {
                parts.append(due < today ? String(localized: "Overdue since \(Format.day(due))") : String(localized: "Next \(Format.relative(due, today: today))"))
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .goal:
            let range = s.goalRange(containing: today)
            return Format.goalProgress(item.doneCount(in: range), s.goalCount, s.goalPeriod)
        case .repeating:
            if s.isEveryDay || s.isHourly { return nil }
            guard let next = s.nextOccurrence(onOrAfter: max(today, item.trackFrom)) else { return nil }
            return String(localized: "Next \(Format.relative(next, today: today))")
        case .once:
            return nil
        }
    }
}
