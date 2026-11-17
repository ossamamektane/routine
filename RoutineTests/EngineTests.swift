import XCTest

private func day(_ y: Int, _ m: Int, _ d: Int) -> Day { Day(year: y, month: m, day: d) }

final class DayTests: XCTestCase {
    func testEpochAndWeekdays() {
        XCTAssertEqual(day(1970, 1, 1).index, 0)
        XCTAssertEqual(day(1970, 1, 1).weekday, 5) // Thursday
        XCTAssertEqual(day(2024, 1, 1).weekday, 2) // Monday
        XCTAssertEqual(day(2024, 1, 7).weekday, 1) // Sunday
        XCTAssertEqual(Day(index: day(2024, 2, 29).index), day(2024, 2, 29))
    }

    func testDayClampsToMonthLength() {
        XCTAssertEqual(day(2023, 2, 31), day(2023, 2, 28))
        XCTAssertEqual(day(2024, 2, 31), day(2024, 2, 29))
        XCTAssertEqual(day(2024, 4, 31), day(2024, 4, 30))
    }

    func testAddingDaysAndMonths() {
        XCTAssertEqual(day(2024, 12, 31).adding(days: 1), day(2025, 1, 1))
        XCTAssertEqual(day(2024, 3, 1).adding(days: -1), day(2024, 2, 29))
        XCTAssertEqual(day(2024, 1, 31).adding(months: 1), day(2024, 2, 29))
        XCTAssertEqual(day(2023, 1, 31).adding(months: 1), day(2023, 2, 28))
        XCTAssertEqual(day(2024, 12, 15).adding(months: 1), day(2025, 1, 15))
        XCTAssertEqual(day(2024, 1, 15).adding(months: -1), day(2023, 12, 15))
    }

    func testMonday() {
        XCTAssertEqual(day(2024, 1, 3).monday, day(2024, 1, 1))
        XCTAssertEqual(day(2024, 1, 7).monday, day(2024, 1, 1))
        XCTAssertEqual(day(2024, 1, 8).monday, day(2024, 1, 8))
    }

    func testISOAndCoding() throws {
        let d = day(2025, 3, 9)
        XCTAssertEqual(d.iso, "2025-03-09")
        XCTAssertEqual(Day(iso: "2025-03-09"), d)
        XCTAssertNil(Day(iso: "March 9"))
        let data = try JSONEncoder().encode([d])
        XCTAssertEqual(String(data: data, encoding: .utf8), "[\"2025-03-09\"]")
        XCTAssertEqual(try JSONDecoder().decode([Day].self, from: data), [d])
    }

    func testMinutesRoundTrip() {
        let d = day(2024, 6, 1)
        XCTAssertEqual(d.date(minutes: 0).minutesOfDay, 0)
        XCTAssertEqual(d.date(minutes: 8 * 60 + 45).minutesOfDay, 8 * 60 + 45)
        XCTAssertEqual(Day(d.date(minutes: 23 * 60 + 59)), d)
    }
}

final class ScheduleTests: XCTestCase {
    func testMonthlyOnThe31st() {
        var s = Schedule()
        s.unit = .month
        s.start = day(2024, 1, 31)
        XCTAssertTrue(s.occurs(on: day(2024, 2, 29)))
        XCTAssertFalse(s.occurs(on: day(2024, 2, 28)))
        XCTAssertTrue(s.occurs(on: day(2024, 4, 30)))
        XCTAssertTrue(s.occurs(on: day(2024, 5, 31)))
        XCTAssertEqual(s.nextOccurrence(onOrAfter: day(2024, 2, 1)), day(2024, 2, 29))
        XCTAssertEqual(s.previousOccurrence(onOrBefore: day(2024, 3, 30)), day(2024, 2, 29))
    }

    func testEveryOtherWeekOnMondayAndWednesday() {
        var s = Schedule()
        s.unit = .week
        s.every = 2
        s.start = day(2024, 1, 1)
        s.weekdays = [2, 4]
        XCTAssertTrue(s.occurs(on: day(2024, 1, 1)))
        XCTAssertTrue(s.occurs(on: day(2024, 1, 3)))
        XCTAssertFalse(s.occurs(on: day(2024, 1, 8)))
        XCTAssertTrue(s.occurs(on: day(2024, 1, 15)))
        XCTAssertEqual(s.nextOccurrence(onOrAfter: day(2024, 1, 4)), day(2024, 1, 15))
        XCTAssertEqual(s.previousOccurrence(onOrBefore: day(2024, 1, 14)), day(2024, 1, 3))
    }

    func testEveryThreeDays() {
        var s = Schedule()
        s.every = 3
        s.start = day(2024, 3, 1)
        XCTAssertTrue(s.occurs(on: day(2024, 3, 4)))
        XCTAssertFalse(s.occurs(on: day(2024, 3, 5)))
        XCTAssertFalse(s.occurs(on: day(2024, 2, 27)))
        XCTAssertEqual(s.nextOccurrence(onOrAfter: day(2024, 3, 5)), day(2024, 3, 7))
        XCTAssertEqual(s.previousOccurrence(onOrBefore: day(2024, 3, 6)), day(2024, 3, 4))
    }

    func testYearlyOnLeapDay() {
        var s = Schedule()
        s.unit = .year
        s.start = day(2024, 2, 29)
        XCTAssertTrue(s.occurs(on: day(2025, 2, 28)))
        XCTAssertEqual(s.nextOccurrence(onOrAfter: day(2024, 3, 1)), day(2025, 2, 28))
    }

    func testCarryOverRules() {
        var s = Schedule()
        XCTAssertFalse(s.carriesOver)
        s.every = 2
        XCTAssertTrue(s.carriesOver)
        s.unit = .hour
        XCTAssertFalse(s.carriesOver)
        s.unit = .month
        XCTAssertTrue(s.carriesOver)
        s.kind = .goal
        XCTAssertFalse(s.carriesOver)
        s.kind = .afterDone
        XCTAssertTrue(s.carriesOver)
    }

    func testHourlySlots() {
        let slots = Schedule.hourlySlots(first: 8 * 60, every: 2, end: 24 * 60)
        XCTAssertEqual(slots.compactMap { $0.minute }, [480, 600, 720, 840, 960, 1080, 1200, 1320])
        XCTAssertEqual(slots.first?.key, 0)
    }

    func testHourlyAfterWakingWaitsForWakeTime() {
        var s = Schedule()
        s.unit = .hour
        s.every = 3
        s.afterWaking = 30
        XCTAssertTrue(s.slots(on: day(2024, 5, 1), wake: nil).isEmpty)
        XCTAssertEqual(s.slots(on: day(2024, 5, 1), wake: 7 * 60, end: 20 * 60).compactMap { $0.minute }, [450, 630, 810, 990, 1170])
        // Without an end it keeps going until a day after waking up.
        XCTAssertEqual(s.slots(on: day(2024, 5, 1), wake: 7 * 60).last?.minute, 450 + 7 * 180)
    }

    func testNormalizedOneTime() {
        var s = Schedule()
        s.kind = .once
        s.times = [600, 540, 540]
        s.weekdays = [2]
        let n = s.normalized()
        XCTAssertEqual(n.times, [540])
        XCTAssertTrue(n.weekdays.isEmpty)
    }

    func testNormalizedWeeklyUsesStartWeekday() {
        var s = Schedule()
        s.unit = .week
        s.start = day(2024, 1, 3)
        XCTAssertEqual(s.normalized().weekdays, [4])
    }

    func testWakeOnlyForDailyAndHourly() {
        var s = Schedule()
        s.afterWaking = 15
        s.times = [480]
        XCTAssertEqual(s.normalized().afterWaking, 15)
        XCTAssertEqual(s.normalized().times, [])
        s.every = 2
        XCTAssertNil(s.normalized().afterWaking)
        XCTAssertEqual(s.normalized().times, [480])
    }

    func testAfterDoneMovesFromWhenItWasDone() {
        var s = Schedule()
        s.kind = .afterDone
        s.unit = .week
        s.every = 6
        s.advanceAfterDone(at: day(2024, 1, 10).date(minutes: 600))
        XCTAssertEqual(s.nextDue, day(2024, 2, 21))
        XCTAssertNil(s.nextDueTime)

        s.unit = .hour
        s.every = 3
        s.advanceAfterDone(at: day(2024, 1, 10).date(minutes: 22 * 60))
        XCTAssertEqual(s.nextDue, day(2024, 1, 11))
        XCTAssertEqual(s.nextDueTime, 60)
    }

    func testGoalMonthRange() {
        var s = Schedule()
        s.kind = .goal
        s.goalPeriod = .month
        let range = s.goalRange(containing: day(2024, 2, 10))
        XCTAssertEqual(range.lowerBound, day(2024, 2, 1))
        XCTAssertEqual(range.upperBound, day(2024, 2, 29))
    }

    func testForgivingDecoding() throws {
        let json = #"{"kind":"repeating","unit":"week","weekdays":[2,6],"start":"2024-01-01","somethingNew":true}"#
        let s = try JSONDecoder().decode(Schedule.self, from: Data(json.utf8))
        XCTAssertEqual(s.unit, .week)
        XCTAssertEqual(s.weekdays, [2, 6])
        XCTAssertEqual(s.every, 1)

        let odd = #"{"kind":"fromTheFuture","every":"x"}"#
        let fallback = try JSONDecoder().decode(Schedule.self, from: Data(odd.utf8))
        XCTAssertEqual(fallback.kind, .repeating)
        XCTAssertEqual(fallback.every, 1)
    }
}

final class ItemTests: XCTestCase {
    func testAmountParsing() {
        XCTAssertEqual(DecimalText.parse("12.99"), Decimal(string: "12.99"))
        XCTAssertEqual(DecimalText.parse("12,5"), Decimal(string: "12.5"))
        XCTAssertEqual(DecimalText.parse("1,234.56"), Decimal(string: "1234.56"))
        XCTAssertEqual(DecimalText.parse("١٢٫٥"), Decimal(string: "12.5"))
        XCTAssertEqual(DecimalText.parse("40"), Decimal(40))
        XCTAssertNil(DecimalText.parse(""))
        XCTAssertNil(DecimalText.parse("abc"))
    }

    func testItemRoundTripKeepsExactAmount() throws {
        var item = Item()
        item.title = "Rent"
        item.cost = Decimal(string: "1250.10")
        item.log = [LogEntry(kind: .done, at: Date(timeIntervalSince1970: 1_700_000_000), day: day(2023, 11, 14), amount: Decimal(string: "0.1"))]
        let data = try JSONEncoder().encode(item)
        let text = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("\"1250.1\""))
        let back = try JSONDecoder().decode(Item.self, from: data)
        XCTAssertEqual(back.cost, Decimal(string: "1250.10"))
        XCTAssertEqual(back.log.first?.amount, Decimal(string: "0.1"))
        XCTAssertEqual(back.title, "Rent")
    }

    func testItemWithMissingFieldsStillLoads() throws {
        let id = UUID()
        let json = #"{"id":"\#(id.uuidString)","title":"Water plants","log":[{"d":"2024-05-01"},{"broken":1}]}"#
        let item = try JSONDecoder().decode(Item.self, from: Data(json.utf8))
        XCTAssertEqual(item.id, id)
        XCTAssertEqual(item.title, "Water plants")
        XCTAssertEqual(item.log.count, 1)
        XCTAssertEqual(item.reminder, .onTime)
    }

    func testOneTimeFinishesWhenDone() {
        var item = Item()
        item.schedule.kind = .once
        item.schedule.start = day(2024, 5, 2)
        XCTAssertTrue(item.isActive)
        item.log.append(LogEntry(kind: .done, at: day(2024, 5, 2).noon, day: day(2024, 5, 2)))
        XCTAssertTrue(item.isFinished)
        XCTAssertFalse(item.isActive)
    }
}

final class PlannerTests: XCTestCase {
    private func dailyItem(at minute: Int?, trackFrom: Day) -> Item {
        var item = Item()
        item.title = "Vitamins"
        item.schedule.start = trackFrom
        item.schedule.times = minute.map { [$0] } ?? []
        item.trackFrom = trackFrom
        return item
    }

    func testDailyItemShowsUpAndMovesToDone() {
        let today = day(2024, 5, 10)
        var item = dailyItem(at: 8 * 60, trackFrom: today.adding(days: -10))
        var agenda = Planner.agenda(items: [item], now: today.date(minutes: 7 * 60), wake: nil, includeUpcoming: false)
        XCTAssertEqual(agenda.dueToday.count, 1)
        XCTAssertEqual(agenda.dueToday.first?.state, .upcoming)
        XCTAssertTrue(agenda.overdue.isEmpty)

        item.log.append(LogEntry(kind: .done, at: today.date(minutes: 7 * 60 + 5), day: today, slot: 8 * 60))
        agenda = Planner.agenda(items: [item], now: today.date(minutes: 7 * 60 + 6), wake: nil, includeUpcoming: false)
        XCTAssertTrue(agenda.dueToday.isEmpty)
        XCTAssertEqual(agenda.done.count, 1)
    }

    func testMissedDailyDoesNotPileUp() {
        let today = day(2024, 5, 10)
        let item = dailyItem(at: 8 * 60, trackFrom: today.adding(days: -10))
        let agenda = Planner.agenda(items: [item], now: today.date(minutes: 12 * 60), wake: nil, includeUpcoming: false)
        XCTAssertTrue(agenda.overdue.isEmpty)
        XCTAssertEqual(agenda.dueToday.count, 1)
    }

    func testMissedEveryThreeDaysCarriesOver() {
        let today = day(2024, 5, 10)
        var item = dailyItem(at: nil, trackFrom: today.adding(days: -1))
        item.schedule.every = 3
        let agenda = Planner.agenda(items: [item], now: today.date(minutes: 12 * 60), wake: nil, includeUpcoming: false)
        XCTAssertEqual(agenda.overdue.count, 1)
        XCTAssertEqual(agenda.overdue.first?.day, today.adding(days: -1))
        XCTAssertTrue(agenda.dueToday.isEmpty)
    }

    func testNothingOverdueFromBeforeTracking() {
        let today = day(2024, 5, 10)
        var item = dailyItem(at: nil, trackFrom: today)
        item.schedule.every = 3
        item.schedule.start = today.adding(days: -1)
        let agenda = Planner.agenda(items: [item], now: today.date(minutes: 12 * 60), wake: nil, includeUpcoming: false)
        XCTAssertTrue(agenda.overdue.isEmpty)
    }

    func testPausedItemsAreHidden() {
        let today = day(2024, 5, 10)
        var item = dailyItem(at: 8 * 60, trackFrom: today)
        item.paused = true
        let agenda = Planner.agenda(items: [item], now: today.date(minutes: 9 * 60), wake: nil, includeUpcoming: false)
        XCTAssertTrue(agenda.dueToday.isEmpty)
    }
}

final class MoneyTests: XCTestCase {
    private func bill(_ amount: String, start: Day, autopay: Bool = false) -> Item {
        var item = Item()
        item.title = "Internet"
        item.schedule.unit = .month
        item.schedule.start = start
        item.trackFrom = start
        item.cost = Decimal(string: amount)
        item.autopay = autopay
        return item
    }

    func testMonthlyBillCountsEveryMonth() {
        let start = day(2024, 3, 1)
        let now = day(2024, 3, 15).date(minutes: 12 * 60)
        let months = MoneyPlanner.monthsAhead(items: [bill("100", start: start)], now: now)
        XCTAssertEqual(months.count, 12)
        XCTAssertEqual(months[0].month, day(2024, 3, 1).monthIndex)
        XCTAssertEqual(months[0].amount, 100)
        XCTAssertEqual(months[0].payments, 1)
        XCTAssertEqual(months[1].amount, 100)
        XCTAssertEqual(months.reduce(Decimal(0)) { $0 + $1.amount }, 1200)
    }

    func testPaidOrNotEveryBillCounts() {
        let start = day(2024, 3, 1)
        let now = day(2024, 3, 15).date(minutes: 12 * 60)
        var paid = bill("100", start: start)
        paid.log.append(LogEntry(kind: .done, at: day(2024, 3, 2).noon, day: start, amount: 100))
        let months = MoneyPlanner.monthsAhead(items: [paid, bill("50", start: start, autopay: true)], now: now)
        XCTAssertEqual(months[0].amount, 150)
        XCTAssertEqual(months[0].payments, 2)
    }

    func testYearlyBillOnlyInItsMonth() {
        var item = bill("600", start: day(2024, 5, 10))
        item.schedule.unit = .year
        let months = MoneyPlanner.monthsAhead(items: [item], now: day(2024, 3, 15).date(minutes: 12 * 60))
        XCTAssertEqual(months[2].amount, 600)
        XCTAssertEqual(months.filter { $0.amount > 0 }.count, 1)
    }

    func testPausedBillsCountNothing() {
        var item = bill("100", start: day(2024, 3, 1))
        item.paused = true
        let months = MoneyPlanner.monthsAhead(items: [item], now: day(2024, 3, 15).date(minutes: 12 * 60))
        XCTAssertTrue(months.allSatisfy { $0.amount == 0 && $0.payments == 0 })
    }

    func testNoCostsMeansNothingToPay() {
        let months = MoneyPlanner.monthsAhead(items: [Item()], now: Date())
        XCTAssertEqual(months.count, 12)
        XCTAssertTrue(months.allSatisfy { $0.amount == 0 })
    }
}

final class DayClockTests: XCTestCase {
    func testStillUpAfterMidnightIsYesterday() {
        let today = day(2024, 5, 10)
        let yesterday = today.adding(days: -1)
        let clock = DayClock.make(now: today.date(minutes: 90), wakes: [yesterday.iso: 14 * 60], sleeps: [:])
        XCTAssertEqual(clock.day, yesterday)
        XCTAssertEqual(clock.minute, 24 * 60 + 90)
        XCTAssertTrue(clock.isUp)
        XCTAssertTrue(clock.isPastMidnight)
        XCTAssertEqual(clock.minutesUp, 10 * 60 + 90)
    }

    func testGoingToSleepEndsTheDay() {
        let today = day(2024, 5, 10)
        let yesterday = today.adding(days: -1)
        let clock = DayClock.make(now: today.date(minutes: 90), wakes: [yesterday.iso: 14 * 60], sleeps: [yesterday.iso: 25 * 60])
        XCTAssertEqual(clock.day, today)
        XCTAssertNil(clock.wake)
        XCTAssertTrue(clock.isAsleep)
        XCTAssertEqual(clock.asleepSince, today.date(minutes: 60))
    }

    func testUpAgainTheNextDay() {
        let today = day(2024, 5, 10)
        let yesterday = today.adding(days: -1)
        let clock = DayClock.make(now: today.date(minutes: 12 * 60), wakes: [yesterday.iso: 14 * 60, today.iso: 10 * 60],
                                  sleeps: [yesterday.iso: 25 * 60])
        XCTAssertEqual(clock.day, today)
        XCTAssertEqual(clock.wake, 10 * 60)
        XCTAssertFalse(clock.isAsleep)
        XCTAssertEqual(clock.minutesUp, 2 * 60)
    }

    func testNotUpYetIsTheCalendarDay() {
        let today = day(2024, 5, 10)
        let clock = DayClock.make(now: today.date(minutes: 8 * 60), wakes: [:], sleeps: [:])
        XCTAssertEqual(clock.day, today)
        XCTAssertNil(clock.wake)
        XCTAssertFalse(clock.isUp)
    }

    func testMinutesPastMidnightRollOver() {
        XCTAssertEqual(day(2024, 5, 1).date(minutes: 25 * 60), day(2024, 5, 2).date(minutes: 60))
    }

    func testHourlyKeepsGoingPastMidnight() {
        let today = day(2024, 5, 10)
        let yesterday = today.adding(days: -1)
        var item = Item()
        item.title = "Water"
        item.schedule.unit = .hour
        item.schedule.every = 2
        item.schedule.afterWaking = 0
        item.schedule.start = yesterday.adding(days: -5)
        item.trackFrom = yesterday.adding(days: -5)
        let clock = DayClock.make(now: today.date(minutes: 90), wakes: [yesterday.iso: 14 * 60], sleeps: [:])
        let agenda = Planner.agenda(items: [item], clock: clock)
        let row = agenda.tasks.first
        XCTAssertEqual(row?.day, yesterday)
        XCTAssertEqual(row?.minute, 24 * 60)
    }
}

final class LegacyImportTests: XCTestCase {
    func testTimeParsing() {
        XCTAssertEqual(LegacyImport.minutes("07:05"), 425)
        XCTAssertEqual(LegacyImport.minutes("23:59"), 1439)
        XCTAssertNil(LegacyImport.minutes("24:00"))
        XCTAssertNil(LegacyImport.minutes("soon"))
    }

    func testFixedWeeklyRoutine() throws {
        let today = day(2024, 5, 10)
        let o: [String: Any] = [
            "id": UUID().uuidString, "name": "Take out the trash", "kind": "fixed", "n": 1, "unit": "w",
            "times": ["19:30"], "next": "2024-05-14", "anchor": "2024-05-07",
            "log": ["2024-05-07", "2024-06-01"],
        ]
        let item = try XCTUnwrap(LegacyImport.convert(o, today: today, now: today.noon))
        XCTAssertEqual(item.schedule.kind, .repeating)
        XCTAssertEqual(item.schedule.unit, .week)
        XCTAssertEqual(item.schedule.weekdays, [day(2024, 5, 7).weekday])
        XCTAssertEqual(item.schedule.times, [19 * 60 + 30])
        XCTAssertEqual(item.trackFrom, day(2024, 5, 14))
        XCTAssertEqual(item.log.count, 1)
        XCTAssertEqual(item.reminder, .onTime)
    }

    func testFlexibleBecomesAfterLastTime() throws {
        let today = day(2024, 5, 10)
        let o: [String: Any] = ["name": "Haircut", "kind": "flex", "n": 6, "unit": "w", "next": "2024-06-01"]
        let item = try XCTUnwrap(LegacyImport.convert(o, today: today, now: today.noon))
        XCTAssertEqual(item.schedule.kind, .afterDone)
        XCTAssertEqual(item.schedule.every, 6)
        XCTAssertEqual(item.schedule.nextDue, day(2024, 6, 1))
        XCTAssertEqual(item.reminder, .off)
    }

    func testWindowBecomesGoal() throws {
        let today = day(2024, 5, 10)
        let o: [String: Any] = ["name": "Workout", "kind": "window", "quota": 3, "period": "w"]
        let item = try XCTUnwrap(LegacyImport.convert(o, today: today, now: today.noon))
        XCTAssertEqual(item.schedule.kind, .goal)
        XCTAssertEqual(item.schedule.goalCount, 3)
        XCTAssertEqual(item.schedule.goalPeriod, .week)
    }

    func testNamelessEntriesAreSkipped() {
        XCTAssertNil(LegacyImport.convert(["name": "   "], today: day(2024, 5, 10), now: Date()))
        XCTAssertNil(LegacyImport.convert(["kind": "fixed"], today: day(2024, 5, 10), now: Date()))
    }
}
