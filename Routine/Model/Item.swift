import Foundation

enum ReminderMode: String, Codable, CaseIterable, Identifiable {
    case off, onTime, dayBefore
    var id: String { rawValue }
}

enum ItemColor: String, Codable, CaseIterable, Identifiable {
    case green, mint, teal, cyan, blue, indigo, purple, pink, red, orange, yellow, brown, gray
    var id: String { rawValue }

    /// A stable color for text, so imported items don't all look the same.
    static func forText(_ text: String) -> ItemColor {
        let sum = text.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return allCases[Day.mod(sum, allCases.count)]
    }
}

/// A completion or skip of one occurrence.
struct LogEntry: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case done, skipped }

    var id: UUID = UUID()
    var kind: Kind = .done
    /// When it was checked off.
    var at: Date = Date()
    /// The day of the occurrence it belongs to (can be earlier than `at` for overdue things).
    var day: Day
    var slot: Int? = nil
    /// "After done" routines: what was due before, so Undo can put it back.
    var previousDue: Day? = nil
    var previousDueTime: Int? = nil
    /// The cost at the time, so totals don't change if the price changes later.
    var amount: Decimal? = nil

    // Short keys keep iCloud usage small.
    enum CodingKeys: String, CodingKey {
        case id = "i", kind = "k", at = "a", day = "d", slot = "s", previousDue = "p", previousDueTime = "t", amount = "m"
    }
}

extension LogEntry {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let day = try c.decode(Day.self, forKey: .day)
        self.init(day: day)
        id = c.field(.id, or: id)
        kind = c.field(.kind, or: kind)
        at = c.field(.at, or: day.noon)
        slot = c.optionalField(.slot)
        previousDue = c.optionalField(.previousDue)
        previousDueTime = c.optionalField(.previousDueTime)
        amount = DecimalText.decode(c, .amount)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(at, forKey: .at)
        try c.encode(day, forKey: .day)
        try c.encodeIfPresent(slot, forKey: .slot)
        try c.encodeIfPresent(previousDue, forKey: .previousDue)
        try c.encodeIfPresent(previousDueTime, forKey: .previousDueTime)
        try c.encodeIfPresent(amount.map(DecimalText.string), forKey: .amount)
    }
}

/// "Later": an occurrence moved to a later time.
struct Snooze: Codable, Hashable {
    var day: Day
    var slot: Int?
    var until: Date
}

/// Everything in the app is an item: tasks and bills.
/// An item with a cost is a bill; that's what makes it show up under Bills.
struct Item: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var symbol: String = "checkmark"
    var color: ItemColor = .green
    var schedule: Schedule = Schedule()
    var cost: Decimal? = nil
    /// Paid automatically: counted as paid on its date, never on Today and no reminders.
    var autopay: Bool = false
    var reminder: ReminderMode = .onTime
    var paused: Bool = false
    /// Occurrences before this day are never shown as missed (set when created, edited or resumed).
    var trackFrom: Day = Day.today
    var log: [LogEntry] = []
    var snoozes: [Snooze] = []
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    /// Deleted items are kept briefly so the deletion reaches your other devices.
    var deletedAt: Date? = nil

    enum CodingKeys: String, CodingKey {
        case id, title, notes, symbol, color, schedule, cost, autopay, reminder, paused, trackFrom, log, snoozes, createdAt, modifiedAt, deletedAt
    }
}

extension Item {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        id = try c.decode(UUID.self, forKey: .id)
        title = c.field(.title, or: "")
        notes = c.field(.notes, or: "")
        symbol = c.field(.symbol, or: symbol)
        color = c.field(.color, or: color)
        schedule = c.field(.schedule, or: schedule)
        cost = DecimalText.decode(c, .cost)
        autopay = c.field(.autopay, or: false)
        reminder = c.field(.reminder, or: reminder)
        paused = c.field(.paused, or: false)
        trackFrom = c.field(.trackFrom, or: schedule.start)
        let entries: [Lossy<LogEntry>] = c.field(.log, or: [])
        log = entries.compactMap { $0.value }
        let pending: [Lossy<Snooze>] = c.field(.snoozes, or: [])
        snoozes = pending.compactMap { $0.value }
        createdAt = c.field(.createdAt, or: Date(timeIntervalSince1970: 0))
        modifiedAt = c.field(.modifiedAt, or: createdAt)
        deletedAt = c.optionalField(.deletedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(notes, forKey: .notes)
        try c.encode(symbol, forKey: .symbol)
        try c.encode(color, forKey: .color)
        try c.encode(schedule, forKey: .schedule)
        try c.encodeIfPresent(cost.map(DecimalText.string), forKey: .cost)
        try c.encode(autopay, forKey: .autopay)
        try c.encode(reminder, forKey: .reminder)
        try c.encode(paused, forKey: .paused)
        try c.encode(trackFrom, forKey: .trackFrom)
        try c.encode(log, forKey: .log)
        try c.encode(snoozes, forKey: .snoozes)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(modifiedAt, forKey: .modifiedAt)
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }

    var isDeleted: Bool { deletedAt != nil }
    var hasCost: Bool { (cost ?? 0) > 0 }

    /// Autopay only applies to things on set dates.
    var isAutopay: Bool {
        hasCost && autopay && (schedule.kind == .repeating || schedule.kind == .once)
    }

    /// A one-time item that has been done or skipped.
    var isFinished: Bool {
        schedule.kind == .once && log.contains { $0.day == schedule.start }
    }

    /// Shows up in Today, reminders and Money.
    var isActive: Bool { deletedAt == nil && !paused && !isFinished }

    var displayTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? String(localized: "Untitled") : t
    }

    func entry(day: Day, slot: Int?) -> LogEntry? {
        log.last { $0.day == day && $0.slot == slot }
    }

    func snooze(day: Day, slot: Int?) -> Snooze? {
        snoozes.first { $0.day == day && $0.slot == slot }
    }

    func doneCount(in range: ClosedRange<Day>) -> Int {
        log.filter { $0.kind == .done && range.contains($0.day) }.count
    }

    var lastDone: LogEntry? {
        log.filter { $0.kind == .done }.max { $0.at < $1.at }
    }

    /// Keeps saved history (and iCloud usage) small.
    mutating func trimHistory(now: Date) {
        let oldest = now.addingTimeInterval(-400 * 86_400)
        log.removeAll { $0.at < oldest }
        if log.count > 150 {
            log.sort { $0.at < $1.at }
            log.removeFirst(log.count - 150)
        }
        let staleSnooze = now.addingTimeInterval(-86_400)
        snoozes.removeAll { $0.until < staleSnooze }
    }
}

/// Amounts are saved as text ("12.99") so they never pick up floating-point noise.
enum DecimalText {
    static let posix = Locale(identifier: "en_US_POSIX")

    static func string(_ value: Decimal) -> String {
        "\(value)"
    }

    static func decimal(_ text: String) -> Decimal? {
        Decimal(string: text, locale: posix)
    }

    static func decode<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Decimal? {
        if let text = try? c.decodeIfPresent(String.self, forKey: key), let value = decimal(text) {
            return value
        }
        if let number = try? c.decodeIfPresent(Double.self, forKey: key) {
            return decimal(String(number))
        }
        return nil
    }

    /// Reads what someone typed: "12,99", "1 200.50", "١٢٫٩٩" all work.
    static func parse(_ input: String) -> Decimal? {
        var text = ""
        for scalar in input.unicodeScalars {
            switch scalar.value {
            case 0x30...0x39: text.unicodeScalars.append(scalar)
            case 0x660...0x669: text.unicodeScalars.append(Unicode.Scalar(scalar.value - 0x660 + 0x30)!)
            case 0x6F0...0x6F9: text.unicodeScalars.append(Unicode.Scalar(scalar.value - 0x6F0 + 0x30)!)
            case 0x2E, 0x2C, 0x66B: text.append(".")
            default: break
            }
        }
        // Only the last separator can be the decimal point; earlier ones group thousands.
        if let last = text.lastIndex(of: ".") {
            let whole = text[..<last].replacingOccurrences(of: ".", with: "")
            var fraction = String(text[text.index(after: last)...])
            // "1.200" or "1,200" with exactly three digits after a single separator is a thousands group
            // unless the phone writes decimals with that symbol.
            let separatorCount = text.filter { $0 == "." }.count
            let decimalSymbol = Locale.current.decimalSeparator ?? "."
            let typedSymbol = input.last(where: { $0 == "." || $0 == "," || $0 == "٫" }).map { String($0) } ?? "."
            if separatorCount == 1 && fraction.count == 3 && typedSymbol != decimalSymbol && typedSymbol != "٫" {
                return Decimal(string: whole + fraction, locale: posix)
            }
            if fraction.isEmpty { fraction = "0" }
            return Decimal(string: (whole.isEmpty ? "0" : whole) + "." + fraction, locale: posix)
        }
        return text.isEmpty ? nil : Decimal(string: text, locale: posix)
    }
}
