import Foundation
import Testing
@testable import DailyBudgetCore

/// PRD §5.4「支出日は利用開始日〜当日、かつ未確定月のみ」の判定を確認する。
struct ExpenseEditPolicyTests {
    private let activeStart = CalendarDay(year: 2026, month: 11, day: 1)

    private func day(_ month: Int, _ d: Int) -> CalendarDay {
        CalendarDay(year: 2026, month: month, day: d)
    }

    @Test("確定済みの月がなければ利用開始日から当日まで選べる")
    func rangeWithoutSettlements() {
        let range = ExpenseEditPolicy.editableDateRange(
            activeStartDate: activeStart,
            today: day(11, 20),
            closedMonths: []
        )
        #expect(range?.lowerBound == activeStart)
        #expect(range?.upperBound == day(11, 20))
    }

    @Test("確定済みの月には入力できず下限が翌月初日まで繰り上がる")
    func closedMonthRaisesLowerBound() {
        let range = ExpenseEditPolicy.editableDateRange(
            activeStartDate: activeStart,
            today: day(12, 5),
            closedMonths: [YearMonth(year: 2026, month: 11)]
        )
        #expect(range?.lowerBound == day(12, 1))
        #expect(range?.contains(day(11, 30)) == false)
        #expect(range?.contains(day(12, 1)) == true)
    }

    @Test("連続して確定済みなら最後に確定した月の翌月初日が下限になる")
    func multipleClosedMonthsUseTheLatest() {
        let earliest = ExpenseEditPolicy.earliestEditableDate(
            activeStartDate: activeStart,
            today: CalendarDay(year: 2027, month: 2, day: 10),
            closedMonths: [
                YearMonth(year: 2026, month: 11),
                YearMonth(year: 2026, month: 12),
                YearMonth(year: 2027, month: 1)
            ]
        )
        #expect(earliest == CalendarDay(year: 2027, month: 2, day: 1))
    }

    @Test("古い月だけ解除したら、その月まで下限が戻る")
    func reopeningAnOlderMonthLowersTheBound() {
        // 11月を解除し、12月は確定済みのまま。11月から編集できる必要がある。
        let earliest = ExpenseEditPolicy.earliestEditableDate(
            activeStartDate: activeStart,
            today: CalendarDay(year: 2027, month: 1, day: 10),
            closedMonths: [YearMonth(year: 2026, month: 12)]
        )
        #expect(earliest == activeStart)
        // ただし確定済みのままの12月は編集できない。
        #expect(!ExpenseEditPolicy.isEditable(
            CalendarDay(year: 2026, month: 12, day: 5),
            activeStartDate: activeStart,
            today: CalendarDay(year: 2027, month: 1, day: 10),
            closedMonths: [YearMonth(year: 2026, month: 12)]
        ))
        #expect(ExpenseEditPolicy.isEditable(
            day(11, 5),
            activeStartDate: activeStart,
            today: CalendarDay(year: 2027, month: 1, day: 10),
            closedMonths: [YearMonth(year: 2026, month: 12)]
        ))
    }

    @Test("利用開始日のほうが遅ければ利用開始日が下限のまま")
    func activeStartWinsWhenLater() {
        let earliest = ExpenseEditPolicy.earliestEditableDate(
            activeStartDate: day(12, 10),
            today: day(12, 20),
            closedMonths: [YearMonth(year: 2026, month: 11)]
        )
        #expect(earliest == day(12, 10))
    }

    @Test("当月まですべて確定済みなら編集できる日がない")
    func noEditableDayWhenEveryMonthIsClosed() {
        #expect(ExpenseEditPolicy.earliestEditableDate(
            activeStartDate: activeStart,
            today: day(11, 20),
            closedMonths: [YearMonth(year: 2026, month: 11)]
        ) == nil)
    }

    @Test("確定を解除した月は編集できる")
    func reopenedMonthStaysEditable() {
        // reopened の月は closedMonths に含めない運用のため、下限が繰り上がらない。
        let range = ExpenseEditPolicy.editableDateRange(
            activeStartDate: activeStart,
            today: day(12, 5),
            closedMonths: []
        )
        #expect(range?.contains(day(11, 15)) == true)
    }

    @Test("未来日と利用開始日より前は編集できない")
    func futureAndPreStartDaysAreNotEditable() {
        let today = day(11, 20)
        #expect(!ExpenseEditPolicy.isEditable(
            day(11, 21), activeStartDate: activeStart, today: today, closedMonths: []
        ))
        #expect(!ExpenseEditPolicy.isEditable(
            day(10, 31), activeStartDate: activeStart, today: today, closedMonths: []
        ))
        #expect(ExpenseEditPolicy.isEditable(
            today, activeStartDate: activeStart, today: today, closedMonths: []
        ))
    }

    @Test("確定済みの月の日は編集できない")
    func daysInClosedMonthsAreNotEditable() {
        #expect(!ExpenseEditPolicy.isEditable(
            day(11, 15),
            activeStartDate: activeStart,
            today: day(12, 5),
            closedMonths: [YearMonth(year: 2026, month: 11)]
        ))
    }

    @Test("当日が利用開始日より前なら選べる日がない")
    func noRangeBeforeActiveStart() {
        let range = ExpenseEditPolicy.editableDateRange(
            activeStartDate: day(11, 10),
            today: day(11, 5),
            closedMonths: []
        )
        #expect(range == nil)
    }
}
