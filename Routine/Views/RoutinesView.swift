import SwiftUI

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
                                    var copy = item
                                    copy.id = UUID()
                                    copy.log = []
                                    copy.snoozes = []
                                    copy.paused = false
                                    copy.createdAt = Date()
                                    copy.trackFrom = Day.today
                                    editor = .new(copy)
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
                    } header: {
                        Text(group.title)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $search, prompt: Text("Search"))
            .overlay {
                if store.visibleItems.isEmpty {
                    ContentUnavailableView {
                        Label("No routines yet", systemImage: "repeat")
                    } description: {
                        Text("Tap + to add something you do regularly, a bill, or a goal.")
                    } actions: {
                        Button("Add a routine") { editor = .new() }
                            .buttonStyle(.borderedProminent)
                    }
                } else if groups.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .navigationTitle("Routines")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            editor = .new()
                        } label: {
                            Label("Routine", systemImage: "repeat")
                        }
                        Button {
                            editor = .new(billTemplate())
                        } label: {
                            Label("Bill", systemImage: "creditcard")
                        }
                        Button {
                            var item = Item()
                            item.symbol = "star.fill"
                            item.color = .orange
                            item.schedule.kind = .goal
                            item.reminder = .off
                            editor = .new(item)
                        } label: {
                            Label("Goal", systemImage: "star")
                        }
                        Button {
                            var item = Item()
                            item.schedule.kind = .once
                            editor = .new(item)
                        } label: {
                            Label("One-time", systemImage: "calendar")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("Add"))
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
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.notes.localizedCaseInsensitiveContains(query) }
            .sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }

        var daily: [Item] = [], repeating: [Item] = [], afterDone: [Item] = [], goals: [Item] = []
        var once: [Item] = [], paused: [Item] = [], finished: [Item] = []
        for item in all {
            let s = item.schedule
            if item.isFinished { finished.append(item); continue }
            if item.paused { paused.append(item); continue }
            switch s.kind {
            case .repeating:
                if s.isEveryDay || s.isHourly { daily.append(item) } else { repeating.append(item) }
            case .afterDone: afterDone.append(item)
            case .goal: goals.append(item)
            case .once: once.append(item)
            }
        }
        var groups: [ListGroup] = []
        if !daily.isEmpty { groups.append(ListGroup(id: "daily", title: "Every day", items: daily)) }
        if !repeating.isEmpty { groups.append(ListGroup(id: "repeating", title: "On a schedule", items: repeating)) }
        if !afterDone.isEmpty { groups.append(ListGroup(id: "afterDone", title: "After the last time", items: afterDone)) }
        if !goals.isEmpty { groups.append(ListGroup(id: "goals", title: "Goals", items: goals)) }
        if !once.isEmpty { groups.append(ListGroup(id: "once", title: "One-time", items: once)) }
        if !paused.isEmpty { groups.append(ListGroup(id: "paused", title: "Paused", items: paused)) }
        if !finished.isEmpty { groups.append(ListGroup(id: "finished", title: "Completed", items: finished)) }
        return groups
    }
}

struct RoutineRow: View {
    var item: Item
    var today: Day
    var currency: String

    var body: some View {
        HStack(spacing: 12) {
            SymbolTile(symbol: item.symbol, color: item.paused || item.isFinished ? Color.gray : item.color.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.displayTitle)
                    .foregroundStyle(item.paused ? Color.secondary : Color.primary)
                    .lineLimit(2)
                Text(verbatim: item.schedule.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let next = nextText {
                    Text(verbatim: next)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 6)
            if item.hasCost, let cost = item.cost {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.money(cost, code: currency))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    if item.isAutopay {
                        Text("Autopay")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
