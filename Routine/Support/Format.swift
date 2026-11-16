import Foundation

enum Format {
    static func time(_ minutes: Int) -> String {
        Day.today.date(minutes: minutes).formatted(date: .omitted, time: .shortened)
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "Tue, Nov 4"
    static func day(_ d: Day) -> String {
        d.noon.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// "Tuesday, November 4"
    static func longDay(_ d: Day) -> String {
        d.noon.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    /// "Today", "Tomorrow", "Friday", or a date.
    static func relative(_ d: Day, today: Day = Day.today) -> String {
        switch d.index - today.index {
        case 0: return String(localized: "Today")
        case 1: return String(localized: "Tomorrow")
        case -1: return String(localized: "Yesterday")
        case 2...6: return d.noon.formatted(.dateTime.weekday(.wide))
        default: return day(d)
        }
    }

    static func money(_ amount: Decimal, code: String) -> String {
        amount.formatted(.currency(code: code))
    }

    static func moneyShort(_ value: Double, code: String) -> String {
        value.formatted(.currency(code: code).precision(.fractionLength(0)))
    }

    /// How an amount looks while editing it, in the phone's number style.
    static func editableAmount(_ amount: Decimal?) -> String {
        guard let amount else { return "" }
        return amount.formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
    }

    /// "1 hr, 30 min"
    static func duration(minutes: Int) -> String {
        var c = DateComponents()
        c.hour = minutes / 60
        c.minute = minutes % 60
        return DateComponentsFormatter.localizedString(from: c, unitsStyle: .short) ?? "\(minutes)"
    }

    static func weekdays(_ days: [Int]) -> String {
        let set = Set(days)
        if set == [2, 3, 4, 5, 6] { return String(localized: "weekdays") }
        if set == [1, 7] { return String(localized: "weekends") }
        let symbols = RoutineCalendar.current.shortWeekdaySymbols
        let first = RoutineCalendar.current.firstWeekday
        let ordered = days.sorted { Day.mod($0 - first, 7) < Day.mod($1 - first, 7) }
        return ordered.compactMap { (1...7).contains($0) ? symbols[$0 - 1] : nil }.joined(separator: ", ")
    }

    static func every(_ n: Int, _ unit: RepeatUnit) -> String {
        switch unit {
        case .hour: return n == 1 ? String(localized: "Every hour") : String(localized: "Every \(n) hours")
        case .day: return n == 1 ? String(localized: "Every day") : String(localized: "Every \(n) days")
        case .week: return n == 1 ? String(localized: "Every week") : String(localized: "Every \(n) weeks")
        case .month: return n == 1 ? String(localized: "Every month") : String(localized: "Every \(n) months")
        case .year: return n == 1 ? String(localized: "Every year") : String(localized: "Every \(n) years")
        }
    }

    static func afterLastTime(_ n: Int, _ unit: RepeatUnit) -> String {
        switch unit {
        case .hour: return String(localized: "\(n) hours after last time")
        case .day: return String(localized: "\(n) days after last time")
        case .week: return String(localized: "\(n) weeks after last time")
        case .month: return String(localized: "\(n) months after last time")
        case .year: return String(localized: "\(n) years after last time")
        }
    }

    static func goal(_ count: Int, _ period: GoalPeriod) -> String {
        switch period {
        case .day: return String(localized: "\(count) times a day")
        case .week: return String(localized: "\(count) times a week")
        case .month: return String(localized: "\(count) times a month")
        }
    }

    static func unitName(_ unit: RepeatUnit) -> String {
        switch unit {
        case .hour: return String(localized: "Hours")
        case .day: return String(localized: "Days")
        case .week: return String(localized: "Weeks")
        case .month: return String(localized: "Months")
        case .year: return String(localized: "Years")
        }
    }

    static func periodName(_ period: GoalPeriod) -> String {
        switch period {
        case .day: return String(localized: "Per day")
        case .week: return String(localized: "Per week")
        case .month: return String(localized: "Per month")
        }
    }

    static func goalProgress(_ done: Int, _ total: Int, _ period: GoalPeriod) -> String {
        switch period {
        case .day: return String(localized: "\(done) of \(total) today")
        case .week: return String(localized: "\(done) of \(total) this week")
        case .month: return String(localized: "\(done) of \(total) this month")
        }
    }
}

extension Schedule {
    /// A short description, like "Every 2 weeks · Mon, Thu · 8:00 AM".
    var summary: String {
        switch kind {
        case .once:
            var text = String(localized: "Once · \(Format.day(start))")
            if let t = times.first { text += " · " + Format.time(t) }
            return text
        case .goal:
            return Format.goal(goalCount, goalPeriod)
        case .afterDone:
            var text = Format.afterLastTime(every, unit)
            if unit != .hour, let t = times.first { text += " · " + Format.time(t) }
            return text
        case .repeating:
            var parts: [String] = []
            switch unit {
            case .week:
                if every == 1 && effectiveWeekdays.count == 7 {
                    parts.append(String(localized: "Every day"))
                } else if every == 1 && Set(effectiveWeekdays) == [2, 3, 4, 5, 6] {
                    parts.append(String(localized: "Every weekday"))
                } else if every == 1 && Set(effectiveWeekdays) == [1, 7] {
                    parts.append(String(localized: "Every weekend"))
                } else if every == 1 {
                    parts.append(String(localized: "Every \(Format.weekdays(effectiveWeekdays))"))
                } else {
                    parts.append(Format.every(every, unit))
                    parts.append(Format.weekdays(effectiveWeekdays))
                }
            case .month:
                parts.append(Format.every(every, unit))
                parts.append(String(localized: "day \(start.day)"))
            case .year:
                parts.append(Format.every(every, unit))
                parts.append(start.noon.formatted(.dateTime.month(.abbreviated).day()))
            case .hour, .day:
                parts.append(Format.every(every, unit))
            }
            if unit == .hour {
                if let w = afterWaking {
                    parts.append(w == 0 ? String(localized: "from when you wake up") : String(localized: "from \(Format.duration(minutes: w)) after waking"))
                    parts.append(String(localized: "until \(Format.time(hourlyEnd))"))
                } else {
                    parts.append(Format.time(times.first ?? 8 * 60) + "–" + Format.time(hourlyEnd))
                }
            } else if let w = afterWaking {
                parts.append(w == 0 ? String(localized: "when you wake up") : String(localized: "\(Format.duration(minutes: w)) after waking"))
            } else if !times.isEmpty {
                parts.append(times.map { Format.time($0) }.formatted(.list(type: .and)))
            }
            return parts.joined(separator: " · ")
        }
    }
}

extension Format {
    static func currencySymbol(_ code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.currencySymbol ?? code
    }

    static func currencyName(_ code: String) -> String {
        Locale.current.localizedString(forCurrencyCode: code) ?? code
    }
}
