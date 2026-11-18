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
        let clock = DayClock.make(now: today.date(minutes: 90), wakes: [yesterday.iso: 14 * 60])
        XCTAssertEqual(clock.day, yesterday)
        XCTAssertEqual(clock.minute, 24 * 60 + 90)
        XCTAssertTrue(clock.isUp)
        XCTAssertTrue(clock.isPastMidnight)
        XCTAssertEqual(clock.minutesUp, 10 * 60 + 90)
    }

    func testUpAgainTheNextDay() {
        let today = day(2024, 5, 10)
        let yesterday = today.adding(days: -1)
        let clock = DayClock.make(now: today.date(minutes: 12 * 60), wakes: [yesterday.iso: 14 * 60, today.iso: 10 * 60])
        XCTAssertEqual(clock.day, today)
        XCTAssertEqual(clock.wake, 10 * 60)
        XCTAssertEqual(clock.minutesUp, 2 * 60)
    }

    func testNotUpYetIsTheCalendarDay() {
        let today = day(2024, 5, 10)
        let clock = DayClock.make(now: today.date(minutes: 8 * 60), wakes: [:])
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
        let clock = DayClock.make(now: today.date(minutes: 90), wakes: [yesterday.iso: 14 * 60])
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

final class NewDayScenarioTests: XCTestCase {
    func testNightBreakAsksInMorningButNotAtThree() {
        let yesterday = day(2024, 5, 9)
        let today = day(2024, 5, 10)
        let up = yesterday.date(minutes: 8 * 60)
        let last = yesterday.date(minutes: 22 * 60)
        let log = SleepLog()
        XCTAssertFalse(SleepCheck.shouldAsk(log, lastUse: last, now: today.date(minutes: 3 * 60), up: up, missed: 2))
        XCTAssertTrue(SleepCheck.shouldAsk(log, lastUse: last, now: today.date(minutes: 8 * 60), up: up, missed: 0))
    }

    func testAfternoonNapDoesNotStartANewDay() {
        let d = day(2024, 5, 10)
        XCTAssertFalse(SleepCheck.shouldAsk(SleepLog(), lastUse: d.date(minutes: 13 * 60), now: d.date(minutes: 17 * 60), up: d.date(minutes: 8 * 60), missed: 0))
    }

    func testLongBreakAfterLongDayCanAsk() {
        let d = day(2024, 5, 10)
        let up = d.date(minutes: 1 * 60)
        let last = d.date(minutes: 17 * 60)
        let now = d.adding(days: 1).date(minutes: 8 * 60)
        XCTAssertTrue(SleepCheck.shouldAsk(SleepLog(), lastUse: last, now: now, up: up, missed: 1))
    }

    func testActivityDropsFutureAfterClockChange() {
        let now = day(2024, 5, 10).noon
        var log = SleepLog()
        log.spans = [ActivitySpan(start: now.addingTimeInterval(7200), end: now.addingTimeInterval(7200))]
        SleepCheck.note(&log, at: now)
        XCTAssertEqual(log.spans.count, 1)
        XCTAssertEqual(log.spans.first?.start, now)
    }

    func testWakeMedianAcrossMidnightAndCuts() {
        XCTAssertEqual(SleepCheck.circularMedian([23 * 60 + 50, 10]), 0)
        XCTAssertEqual(SleepCheck.cut(wakeMinute: 8 * 60, stillUp: true, usualDay: 16 * 60, fixedTimes: [6 * 60]), 6 * 60)
        let today = day(2024, 5, 10)
        let yesterday = today.adding(days: -1)
        let rules = DayRules(wakes: [yesterday.iso: 8 * 60], cuts: [yesterday.iso: 6 * 60])
        XCTAssertEqual(rules.clock(at: today.date(minutes: 5 * 60)).day, yesterday)
        XCTAssertEqual(rules.clock(at: today.date(minutes: 7 * 60)).day, today)
    }

    func testFromDoneHourlyAndUndo() {
        let d = day(2024, 5, 10)
        var item = Item()
        item.schedule.start = d
        item.schedule.unit = .hour
        item.schedule.every = 2
        item.schedule.fromDone = true
        item.schedule.times = [8 * 60]
        item.trackFrom = d
        let clock = DayClock.simple(now: d.date(minutes: 10 * 60), wake: nil)
        XCTAssertEqual(Planner.fromDoneNext(item, clock: clock)?.minute, 8 * 60)
        item.log = [LogEntry(kind: .done, at: d.date(minutes: 9 * 60 + 15), day: d, slot: 0)]
        XCTAssertEqual(Planner.fromDoneNext(item, clock: clock)?.minute, 11 * 60 + 15)
        item.log.removeAll()
        XCTAssertEqual(Planner.fromDoneNext(item, clock: clock)?.minute, 8 * 60)
    }

    func testRepeatAfterCompletionAndClockRollback() {
        let d = day(2024, 5, 10)
        var item = Item()
        item.createdAt = d.start
        item.modifiedAt = d.start
        item.trackFrom = d
        item.schedule.kind = .afterDone
        item.schedule.unit = .week
        item.schedule.every = 2
        item.schedule.nextDue = d
        item.schedule.times = [9 * 60]
        item.schedule.nextDueTime = 9 * 60
        let future = d.date(minutes: 14 * 60)
        item.log = [LogEntry(kind: .done, at: future, day: d, previousDue: d, previousDueTime: 9 * 60)]
        item.schedule.advanceAfterDone(at: future, day: d)
        XCTAssertEqual(item.schedule.nextDue, d.adding(days: 14))
        XCTAssertEqual(item.schedule.nextDueTime, 14 * 60)
        XCTAssertTrue(item.forgetFuture(now: d.date(minutes: 12 * 60)))
        XCTAssertTrue(item.log.isEmpty)
        XCTAssertEqual(item.schedule.nextDue, d)
        XCTAssertEqual(item.schedule.nextDueTime, 9 * 60)
    }

    func testGoalPaceAndCalendarYearBills() {
        let d = day(2024, 5, 10)
        var s = Schedule()
        s.kind = .goal
        s.goalPeriod = .month
        s.goalCount = 3
        XCTAssertEqual(s.goalPace(byEndOf: d), 1)
        var bill = Item()
        bill.cost = 100
        bill.schedule.unit = .month
        bill.schedule.start = day(2024, 1, 1)
        bill.createdAt = day(2024, 1, 1).noon
        bill.log = [LogEntry(kind: .done, at: day(2024, 3, 2).noon, day: day(2024, 3, 1), amount: 80)]
        let months = MoneyPlanner.yearMonths(items: [bill], now: d.noon)
        XCTAssertEqual(months.count, 12)
        XCTAssertEqual(months[2].amount, 80)
        XCTAssertEqual(months[4].amount, 100)
        XCTAssertEqual(months[11].amount, 100)
    }

    func testManualBillsAppearButAutomaticAndAnyDayDoNot() {
        let d = day(2024, 5, 10)
        var manual = Item()
        manual.title = "Rent"
        manual.cost = 100
        manual.schedule.start = d
        manual.trackFrom = d
        var automatic = manual
        automatic.id = UUID()
        automatic.autopay = true
        var anyDay = manual
        anyDay.id = UUID()
        anyDay.schedule.kind = .goal
        let agenda = Planner.agenda(items: [manual, automatic, anyDay], now: d.noon, wake: nil)
        XCTAssertTrue(agenda.tasks.contains { $0.itemID == manual.id })
        XCTAssertFalse(agenda.tasks.contains { $0.itemID == automatic.id || $0.itemID == anyDay.id })
        // Like tasks, a bill you pay yourself is on Today even when it's weeks away.
        var later = manual
        later.id = UUID()
        later.schedule.start = d.adding(days: 20)
        let ahead = Planner.agenda(items: [later], now: d.noon, wake: nil)
        XCTAssertTrue(ahead.tasks.contains { $0.itemID == later.id && $0.day == d.adding(days: 20) })
    }

    func testCountdownTones() {
        let d = day(2024, 5, 10)
        let due = d.date(minutes: 12 * 60)
        var entry = AgendaEntry(id: "x", itemID: UUID(), title: "x", day: d, slot: nil, minute: 12 * 60, state: .due)
        entry.deadline = due
        XCTAssertEqual(entry.countdown(now: due.addingTimeInterval(-3600), today: d)?.tone, .normal)
        XCTAssertEqual(entry.countdown(now: due.addingTimeInterval(-600), today: d)?.tone, .soon)
        XCTAssertEqual(entry.countdown(now: due, today: d)?.tone, .now)
        XCTAssertEqual(entry.countdown(now: due.addingTimeInterval(600), today: d)?.tone, .now)
        XCTAssertEqual(entry.countdown(now: due.addingTimeInterval(1200), today: d)?.tone, .late)
        XCTAssertFalse(entry.needsAttention(now: due.addingTimeInterval(-600), today: d))
        XCTAssertTrue(entry.needsAttention(now: due, today: d))
        XCTAssertTrue(entry.needsAttention(now: due.addingTimeInterval(1200), today: d))
    }

    func testAnytimeTaskIsNotCountedUntilLate() {
        let d = day(2024, 5, 10)
        var entry = AgendaEntry(id: "y", itemID: UUID(), title: "y", day: d, slot: nil, minute: nil, state: .due)
        entry.deadline = d.adding(days: 1).date(minutes: 0)
        entry.deadlineKind = .endOfDay
        XCTAssertFalse(entry.needsAttention(now: d.noon, today: d))
        let agenda = Agenda(tasks: [entry])
        XCTAssertEqual(agenda.attentionCount(now: d.noon, today: d), 0)
    }


    func testCheckOffWorksAfterWakeTimeChanges() {
        let d = day(2024, 5, 10)
        var item = Item()
        item.schedule.start = d
        item.schedule.unit = .hour
        item.schedule.every = 3
        item.schedule.afterWaking = 0
        item.trackFrom = d
        item.log = [LogEntry(kind: .done, at: d.date(minutes: 7 * 60 + 30), day: d, slot: 0)]
        // Woke at 7:00: the 7:30 check-off counts.
        let early = DayClock.simple(now: d.date(minutes: 10 * 60), wake: 7 * 60)
        XCTAssertTrue(Planner.isLogged(item, day: d, slot: 0, clock: early))
        // Wake-up time changed to 9:00: Today shows it again, so it must be possible to check it off.
        let later = DayClock.simple(now: d.date(minutes: 10 * 60), wake: 9 * 60)
        XCTAssertFalse(Planner.isLogged(item, day: d, slot: 0, clock: later))
        XCTAssertNotNil(item.entry(day: d, slot: 0))
    }

    func testBillAddedMidYearCountsEveryMonth() {
        var rent = Item()
        rent.cost = 3000
        rent.schedule.unit = .month
        // Added on November 17th for the 1st of each month, so its first date is December 1st.
        rent.createdAt = day(2026, 11, 17).noon
        rent.schedule.start = day(2026, 12, 1)
        let months = MoneyPlanner.yearMonths(items: [rent], now: day(2026, 11, 17).noon)
        XCTAssertEqual(months.count, 12)
        XCTAssertEqual(months[0].amount, 3000)
        XCTAssertEqual(months[10].amount, 3000)
        XCTAssertEqual(months[11].amount, 3000)
        XCTAssertEqual(months.reduce(Decimal(0)) { $0 + $1.amount }, 36000)
    }

    func testChosenStartDateAndSkippedPaymentsAreKept() {
        var gym = Item()
        gym.cost = 200
        gym.schedule.unit = .month
        gym.createdAt = day(2026, 1, 10).noon
        gym.trackFrom = day(2026, 1, 10)
        gym.schedule.start = day(2026, 6, 1)
        gym.log = [LogEntry(kind: .skipped, at: day(2026, 7, 1).noon, day: day(2026, 7, 1))]
        let months = MoneyPlanner.yearMonths(items: [gym], now: day(2026, 3, 1).noon)
        XCTAssertEqual(months[4].amount, 0)
        XCTAssertEqual(months[5].amount, 200)
        XCTAssertEqual(months[6].amount, 0)
        XCTAssertEqual(months[7].amount, 200)
    }

    func testEveryOtherDayBillCountsBackBeforeItsStart() {
        var bill = Item()
        bill.cost = 10
        bill.schedule.unit = .day
        bill.schedule.every = 2
        bill.createdAt = day(2024, 5, 1).noon
        bill.schedule.start = day(2024, 5, 1)
        let months = MoneyPlanner.yearMonths(items: [bill], now: day(2024, 5, 1).noon)
        XCTAssertEqual(months[3].payments, 15)
        XCTAssertEqual(months[3].amount, 150)
    }

    func testBillCountdownOnlyForBillsYouPay() {
        let d = day(2024, 5, 10)
        var late = AgendaEntry(id: "a", itemID: UUID(), title: "a", day: d.adding(days: -2), slot: nil, minute: nil, state: .late)
        late.overdue = true
        XCTAssertEqual(late.billCountdown(now: d.noon, today: d)?.tone, .late)
        let soon = AgendaEntry(id: "b", itemID: UUID(), title: "b", day: d.adding(days: 3), slot: nil, minute: nil, state: .future)
        XCTAssertEqual(soon.billCountdown(now: d.noon, today: d)?.tone, .normal)
        let today = AgendaEntry(id: "c", itemID: UUID(), title: "c", day: d, slot: nil, minute: nil, state: .due)
        XCTAssertEqual(today.billCountdown(now: d.noon, today: d)?.tone, .now)
        XCTAssertEqual(today.billCountdown(now: d.noon, today: d)?.text, String(localized: "Today"))
        let automatic = AgendaEntry(id: "d", itemID: UUID(), title: "d", day: d.adding(days: 3), slot: nil, minute: nil, state: .info)
        XCTAssertNil(automatic.billCountdown(now: d.noon, today: d))
    }


    func testPausedBillOnlyCountsWhileActive() {
        var bill = Item()
        bill.cost = 1000
        bill.schedule.unit = .month
        bill.createdAt = day(2026, 11, 17).noon
        bill.schedule.start = day(2026, 12, 1)
        bill.paused = true
        bill.modifiedAt = day(2026, 11, 18).noon
        let months = MoneyPlanner.yearMonths(items: [bill], now: day(2026, 11, 20).noon)
        XCTAssertEqual(months.reduce(Decimal(0)) { $0 + $1.amount }, 0)
    }

    func testBillRepeatingAfterPaymentCountsMonthly() {
        var bill = Item()
        bill.cost = 50
        bill.schedule.kind = .afterDone
        bill.schedule.unit = .month
        bill.createdAt = day(2026, 11, 7).noon
        bill.schedule.start = day(2026, 11, 7)
        bill.schedule.nextDue = day(2026, 12, 7)
        let months = MoneyPlanner.yearMonths(items: [bill], now: day(2026, 11, 8).noon)
        XCTAssertEqual(months.map(\.payments), Array(repeating: 1, count: 12))
        XCTAssertEqual(months.reduce(Decimal(0)) { $0 + $1.amount }, 600)
    }

    func testWeeklyAnyDayBillCountsEveryWeekOnce() {
        var groceries = Item()
        groceries.cost = 100
        groceries.schedule.kind = .goal
        groceries.schedule.goalPeriod = .week
        groceries.schedule.goalCount = 1
        groceries.createdAt = day(2026, 3, 1).noon
        let months = MoneyPlanner.yearMonths(items: [groceries], now: day(2026, 6, 1).noon)
        // 2026 has 52 weeks starting in it, whichever day the week starts on (only Thursday has 53).
        XCTAssertEqual(months.reduce(0) { $0 + $1.payments }, 52)
        XCTAssertEqual(months.reduce(Decimal(0)) { $0 + $1.amount }, 5200)
    }

    func testPauseAndResumeOnlyLeavesOutPausedDays() {
        var bill = Item()
        bill.cost = 100
        bill.schedule.unit = .month
        bill.schedule.start = day(2026, 1, 1)
        bill.createdAt = day(2026, 1, 1).noon
        bill.trackFrom = day(2026, 1, 1)
        bill.setPaused(true, on: day(2026, 3, 15))
        bill.setPaused(false, on: day(2026, 6, 10))
        XCTAssertEqual(bill.pauses, [PauseSpan(start: day(2026, 3, 15), end: day(2026, 6, 10))])
        XCTAssertEqual(bill.trackFrom, day(2026, 6, 10))
        XCTAssertTrue(bill.wasPaused(on: day(2026, 6, 1)))
        XCTAssertFalse(bill.wasPaused(on: day(2026, 6, 10)))
        let months = MoneyPlanner.yearMonths(items: [bill], now: day(2026, 7, 1).noon)
        XCTAssertEqual(months.map(\.payments), [1, 1, 1, 0, 0, 0, 1, 1, 1, 1, 1, 1])
        XCTAssertEqual(months.reduce(Decimal(0)) { $0 + $1.amount }, 900)
    }

    func testOlderPausedBillDoesNotInventUnpaidCosts() {
        var bill = Item()
        bill.cost = 4016
        bill.schedule.kind = .goal
        bill.schedule.goalPeriod = .month
        bill.schedule.goalCount = 1
        bill.createdAt = day(2026, 11, 1).noon
        bill.modifiedAt = day(2026, 11, 18).noon
        bill.paused = true // Saved by an older version, with no pause history.
        let before = MoneyPlanner.yearMonths(items: [bill], now: day(2026, 11, 20).noon)
        XCTAssertEqual(before[10].amount, 0)
        XCTAssertEqual(before[11].amount, 0)

        bill.setPaused(false, on: day(2026, 12, 1))
        let after = MoneyPlanner.yearMonths(items: [bill], now: day(2026, 12, 1).noon)
        XCTAssertEqual(after[10].amount, 0)
        XCTAssertEqual(after[11].amount, 4016)
    }

    func testVisibleBillsWithAnOlderPausedBill() {
        let start = day(2026, 11, 1)
        func repeating(_ cost: Decimal, unit: RepeatUnit) -> Item {
            var item = Item()
            item.cost = cost
            item.schedule.unit = unit
            item.schedule.start = start
            item.createdAt = start.noon
            item.trackFrom = start
            return item
        }
        func monthlyGoal(_ cost: Decimal, count: Int = 1) -> Item {
            var item = Item()
            item.cost = cost
            item.schedule.kind = .goal
            item.schedule.goalPeriod = .month
            item.schedule.goalCount = count
            item.createdAt = start.noon
            return item
        }
        var olderPaused = monthlyGoal(4016)
        olderPaused.paused = true
        olderPaused.modifiedAt = day(2026, 11, 18).noon
        let bills = [repeating(32, unit: .day), repeating(2, unit: .day),
                     repeating(249, unit: .month), repeating(500, unit: .month),
                     monthlyGoal(30), monthlyGoal(30, count: 2), monthlyGoal(50),
                     monthlyGoal(30), monthlyGoal(20), olderPaused]
        let months = MoneyPlanner.yearMonths(items: bills, now: day(2026, 11, 20).noon)
        XCTAssertEqual(months[10].amount, 1959)
        XCTAssertEqual(months[11].amount, 1993)
    }

    func testOlderPausedBillKeepsRecordedPayments() {
        var bill = Item()
        bill.cost = 100
        bill.schedule.unit = .month
        bill.schedule.start = day(2026, 11, 1)
        bill.createdAt = day(2026, 11, 1).noon
        bill.paused = true
        bill.log = [LogEntry(kind: .done, at: day(2026, 11, 1).noon,
                             day: day(2026, 11, 1), amount: 90)]
        let months = MoneyPlanner.yearMonths(items: [bill], now: day(2026, 11, 20).noon)
        XCTAssertEqual(months[10].amount, 90)
        XCTAssertEqual(months[11].amount, 0)
    }

    func testMovedDueDateNeverCountsTwice() {
        var rent = Item()
        rent.cost = 100
        rent.schedule.unit = .month
        rent.createdAt = day(2026, 1, 1).noon
        // Paid on the 1st from January to June, then moved to the 5th on July 1st.
        rent.log = (1...6).map { (m: Int) -> LogEntry in
            LogEntry(kind: .done, at: day(2026, m, 1).noon, day: day(2026, m, 1), amount: 90)
        }
        rent.schedule.start = day(2026, 7, 5)
        rent.trackFrom = day(2026, 7, 1)
        let months = MoneyPlanner.yearMonths(items: [rent], now: day(2026, 7, 10).noon)
        XCTAssertEqual(months.map(\.payments), Array(repeating: 1, count: 12))
        XCTAssertEqual(months[0].amount, 90)
        XCTAssertEqual(months[6].amount, 100)
        XCTAssertEqual(months.reduce(Decimal(0)) { $0 + $1.amount }, 1140)
    }

    func testAutomaticBillKeepsEarlierMonthsAfterItsDateChanges() {
        var netflix = Item()
        netflix.cost = 10
        netflix.autopay = true
        netflix.schedule.unit = .month
        netflix.createdAt = day(2026, 1, 15).noon
        netflix.schedule.start = day(2026, 7, 20)
        netflix.trackFrom = day(2026, 7, 3)
        let months = MoneyPlanner.yearMonths(items: [netflix], now: day(2026, 7, 3).noon)
        XCTAssertEqual(months.map(\.payments), Array(repeating: 1, count: 12))
    }

    // MARK: "Did you sleep?" model

    private func wakeLog(_ wakes: [Int], days: [Int]) -> SleepLog {
        var log = SleepLog()
        log.wakeMinutes = wakes
        log.dayLengths = days
        return log
    }

    func testRegularSleeperIsAskedInTheMorningOnly() {
        let log = wakeLog([450, 480, 495, 465, 510], days: Array(repeating: 960, count: 5))
        let d = day(2024, 5, 10)
        let up = d.date(minutes: 8 * 60)
        let last = d.date(minutes: 23 * 60 + 30)
        let next = d.adding(days: 1)
        // Checking the phone at 4:15 in the middle of the night: not asked.
        XCTAssertFalse(SleepCheck.shouldAsk(log, lastUse: last, now: next.date(minutes: 4 * 60 + 15), up: up, missed: 0))
        // 8:30, after a whole night: asked.
        XCTAssertTrue(SleepCheck.shouldAsk(log, lastUse: last, now: next.date(minutes: 8 * 60 + 30), up: up, missed: 0))
        // Asleep at 3, up at 11: asked.
        XCTAssertTrue(SleepCheck.shouldAsk(log, lastUse: next.date(minutes: 3 * 60), now: next.date(minutes: 11 * 60), up: up, missed: 0))
        // A quiet afternoon at work is not sleep.
        XCTAssertFalse(SleepCheck.shouldAsk(log, lastUse: d.date(minutes: 12 * 60), now: d.date(minutes: 22 * 60), up: up, missed: 0))
    }

    func testNightOwlIsAskedAroundTheirOwnWakeUp() {
        let log = wakeLog([780, 750, 810, 780, 765], days: Array(repeating: 1020, count: 5))
        let d = day(2024, 5, 10)
        let up = d.date(minutes: 13 * 60)
        let next = d.adding(days: 1)
        let last = next.date(minutes: 5 * 60)
        XCTAssertFalse(SleepCheck.shouldAsk(log, lastUse: last, now: next.date(minutes: 10 * 60), up: up, missed: 0))
        XCTAssertTrue(SleepCheck.shouldAsk(log, lastUse: last, now: next.date(minutes: 13 * 60 + 30), up: up, missed: 0))
    }

    func testSleepScoreStaysBetweenZeroAndOne() {
        let d = day(2024, 5, 10)
        let up = d.date(minutes: 8 * 60)
        for start in stride(from: 9 * 60, to: 30 * 60, by: 45) {
            for length in stride(from: 3 * 60, to: 14 * 60, by: 60) {
                let last = d.date(minutes: start)
                let now = last.addingTimeInterval(TimeInterval(length * 60))
                if let p = SleepCheck.sleepProbability(SleepLog(), lastUse: last, now: now, up: up, missed: 1) {
                    XCTAssertTrue(p >= 0 && p <= 1)
                    XCTAssertFalse((2 * 60..<4 * 60).contains(now.minutesOfDay))
                }
            }
        }
    }

    func testWakeSpreadLearnsHowRegularYouAre() {
        XCTAssertEqual(SleepCheck.wakeSpread(SleepLog()), 75)
        let steady = SleepCheck.wakeSpread(wakeLog([480, 480, 485, 475, 480], days: []))
        let messy = SleepCheck.wakeSpread(wakeLog([360, 600, 420, 660, 480], days: []))
        XCTAssertEqual(steady, 20, accuracy: 0.5)
        XCTAssertGreaterThan(messy, 60)
        // Around midnight, 23:50 and 0:10 are close together, not 23 hours apart.
        XCTAssertLessThan(SleepCheck.wakeSpread(wakeLog([1430, 10, 1435, 5, 0], days: [])), 25)
    }
}
