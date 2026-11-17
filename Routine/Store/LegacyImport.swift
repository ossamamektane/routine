import Foundation

/// One-time move of routines saved by the previous version of the app (same bundle ID),
/// which kept everything in Documents/routines-a.json and routines-b.json.
/// The old files are left untouched.
enum LegacyImport {
    struct Result {
        var items: [Item]
        var wakes: [String: Int]
        var appearance: Appearance?
    }

    static func run(now: Date = Date()) -> Result? {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        var bestRev = -1.0
        var best: [String: Any]? = nil
        for name in ["routines-a.json", "routines-b.json"] {
            let url = docs.appendingPathComponent(name)
            guard let raw = try? Data(contentsOf: url),
                  let object = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any],
                  let data = object["data"] as? [String: Any] else { continue }
            let rev = (object["rev"] as? NSNumber)?.doubleValue ?? 0
            if rev > bestRev {
                bestRev = rev
                best = data
            }
        }
        guard let data = best else { return nil }

        let today = Day(now)
        var items: [Item] = []
        if let text = data["r.items"] as? String,
           let list = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [[String: Any]] {
            items = list.compactMap { convert($0, today: today, now: now) }
        }

        var wakes: [String: Int] = [:]
        if let text = data["r.wake"] as? String,
           let wake = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
           let ms = (wake["at"] as? NSNumber)?.doubleValue {
            let date = Date(timeIntervalSince1970: ms / 1000)
            if Day(date) == today && date <= now.addingTimeInterval(600) {
                wakes[today.iso] = date.minutesOfDay
            }
        }

        var appearance: Appearance? = nil
        switch (data["r.theme"] as? String) ?? "" {
        case "dark": appearance = .dark
        case "light": appearance = .light
        default: appearance = nil
        }

        guard !items.isEmpty || !wakes.isEmpty else { return nil }
        return Result(items: items, wakes: wakes, appearance: appearance)
    }

    static func minutes(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }

    static func convert(_ o: [String: Any], today: Day, now: Date) -> Item? {
        guard let rawName = o["name"] as? String else { return nil }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        var item = Item()
        if let id = o["id"] as? String, let uuid = UUID(uuidString: id) { item.id = uuid }
        item.title = String(name.prefix(120))
        item.notes = ((o["desc"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        item.paused = (o["paused"] as? Bool) ?? false
        item.createdAt = now
        item.modifiedAt = now

        let kind = (o["kind"] as? String) ?? "flex"
        let n = max(1, (o["n"] as? NSNumber)?.intValue ?? 1)
        let unit: RepeatUnit
        switch (o["unit"] as? String) ?? "w" {
        case "h": unit = .hour
        case "d": unit = .day
        case "m": unit = .month
        default: unit = .week
        }
        let times = ((o["times"] as? [String]) ?? []).compactMap { minutes($0) }.sorted()
        let next = (o["next"] as? String).flatMap { Day(iso: $0) }
        let anchor = (o["anchor"] as? String).flatMap { Day(iso: $0) }
        let shift = (o["shift"] as? Bool) ?? false
        let wake = (o["wake"] as? NSNumber)?.intValue
        let gridStart = (o["at0"] as? String).flatMap { minutes($0) }

        var s = Schedule()
        s.every = n
        s.unit = unit
        switch kind {
        case "window":
            s.kind = .goal
            s.goalCount = max(1, (o["quota"] as? NSNumber)?.intValue ?? 1)
            switch (o["period"] as? String) ?? "w" {
            case "d": s.goalPeriod = .day
            case "m": s.goalPeriod = .month
            default: s.goalPeriod = .week
            }
            item.trackFrom = today
        case "fixed" where !(shift && unit != .hour):
            s.kind = .repeating
            s.start = anchor ?? next ?? today
            s.times = unit == .hour ? [gridStart ?? times.first ?? 8 * 60] : times
            if unit == .week { s.weekdays = [s.start.weekday] }
            s.afterWaking = wake
            // Anything before the next one was already handled in the old app.
            item.trackFrom = next ?? today
        default:
            s.kind = .afterDone
            s.start = anchor ?? next ?? today
            s.nextDue = next ?? today
            s.times = Array(times.prefix(1))
            if unit == .hour { s.nextDueTime = times.first }
            item.trackFrom = today
        }
        item.schedule = s.normalized()

        let days = ((o["log"] as? [String]) ?? []).compactMap { Day(iso: $0) }.filter { $0 <= today }
        item.log = days.suffix(150).map { LogEntry(kind: .done, at: $0.noon, day: $0) }

        let hasTime = !item.schedule.times.isEmpty || item.schedule.afterWaking != nil || item.schedule.nextDueTime != nil
        item.reminder = hasTime ? .onTime : .off

        if let choice = Symbols.suggest(for: item.title) {
            item.symbol = choice.symbol
            item.color = choice.color
        } else {
            item.symbol = item.schedule.kind == .goal ? "star.fill" : "checkmark"
            item.color = ItemColor.forText(item.title)
        }
        return item
    }
}
