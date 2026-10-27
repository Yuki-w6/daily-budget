import Foundation
import Testing
@testable import DailyBudgetCore

/// PRD §4.3 の計算例と、月次集計・月末見込みの振る舞いを確認する。
struct BudgetCalculatorTests {
    private let start = CalendarDay(year: 2026, month: 11, day: 1)

    private func day(_ d: Int) -> CalendarDay {
        CalendarDay(year: 2026, month: 11, day: d)
    }

    private var calculator: BudgetCalculator {
        BudgetCalculator(
            activeStartDate: start,
            rules: [BudgetRule(effectiveFrom: start, dailyAmountYen: 2_000)]
        )
    }

    /// PRD §4.3 の表をそのまま検証する。
    @Test("PRD §4.3 計算例の5日分が表のとおりになる")
    func matchesWorkedExampleFromSpec() {
        let expenses = [
            ExpenseEntry(spentOn: day(1), amountYen: 1_300),
            ExpenseEntry(spentOn: day(2), amountYen: 2_400),
            ExpenseEntry(spentOn: day(3), amountYen: 1_000),
            ExpenseEntry(spentOn: day(4), amountYen: 3_000),
            ExpenseEntry(spentOn: day(5), amountYen: 500)
        ]
        let expected: [(day: Int, budget: Int64, expense: Int64, surplus: Int64)] = [
            (1, 2_000, 1_300, 700),
            (2, 4_000, 3_700, 300),
            (3, 6_000, 4_700, 1_300),
            (4, 8_000, 7_700, 300),
            (5, 10_000, 8_200, 1_800)
        ]

        let summary = calculator.monthSummary(
            for: YearMonth(year: 2026, month: 11),
            expenses: expenses,
            asOf: day(5)
        )
        #expect(summary.days.count == 5)
        for (actual, row) in zip(summary.days, expected) {
            #expect(actual.day == day(row.day))
            #expect(actual.cumulativeBudgetYen == row.budget)
            #expect(actual.cumulativeExpenseYen == row.expense)
            #expect(actual.cumulativeSurplusYen == row.surplus)
        }

        // 11/6 の開始時点では 1,800 + 2,000 = 3,800円 使える。
        let november6 = calculator.todayBreakdown(on: day(6), expenses: expenses)
        #expect(november6.carryOverYen == 1_800)
        #expect(november6.availableYen == 3_800)
    }

    @Test("同じ日に複数の支出を登録しても合算される")
    func multipleExpensesOnSameDayAreSummed() {
        let expenses = [
            ExpenseEntry(spentOn: day(1), amountYen: 500),
            ExpenseEntry(spentOn: day(1), amountYen: 800)
        ]
        #expect(calculator.summary(on: day(1), expenses: expenses).expenseYen == 1_300)
    }

    @Test("未記録の日は支出0円として扱い予算だけが加算される")
    func daysWithoutExpensesStillAccrueBudget() {
        let summary = calculator.summary(on: day(3), expenses: [])
        #expect(summary.expenseYen == 0)
        #expect(summary.cumulativeBudgetYen == 6_000)
        #expect(summary.cumulativeSurplusYen == 6_000)
    }

    @Test("asOf を指定すると閲覧日までの実績だけを集計する")
    func asOfLimitsSummaryToElapsedDays() {
        let expenses = [ExpenseEntry(spentOn: day(1), amountYen: 1_000)]
        let summary = calculator.monthSummary(
            for: YearMonth(year: 2026, month: 11),
            expenses: expenses,
            asOf: day(3)
        )
        #expect(summary.days.count == 3)
        #expect(summary.budgetTotalYen == 6_000)
        #expect(summary.expenseTotalYen == 1_000)
        #expect(summary.surplusYen == 5_000)
    }

    @Test("日数が異なる月は月間予算も異なる")
    func monthlyBudgetFollowsCalendarDayCount() {
        let calculator = BudgetCalculator(
            activeStartDate: CalendarDay(year: 2026, month: 1, day: 1),
            rules: [
                BudgetRule(
                    effectiveFrom: CalendarDay(year: 2026, month: 1, day: 1),
                    dailyAmountYen: 2_000
                )
            ]
        )
        let january = calculator.monthSummary(for: YearMonth(year: 2026, month: 1), expenses: [])
        let february = calculator.monthSummary(for: YearMonth(year: 2026, month: 2), expenses: [])
        let april = calculator.monthSummary(for: YearMonth(year: 2026, month: 4), expenses: [])
        #expect(january.budgetTotalYen == 62_000)   // 31日
        #expect(february.budgetTotalYen == 56_000)  // 28日
        #expect(april.budgetTotalYen == 60_000)     // 30日
    }

    @Test("閏年の2月は29日分の予算になる")
    func leapFebruaryAccruesTwentyNineDays() {
        let calculator = BudgetCalculator(
            activeStartDate: CalendarDay(year: 2028, month: 1, day: 1),
            rules: [
                BudgetRule(
                    effectiveFrom: CalendarDay(year: 2028, month: 1, day: 1),
                    dailyAmountYen: 2_000
                )
            ]
        )
        let february = calculator.monthSummary(for: YearMonth(year: 2028, month: 2), expenses: [])
        #expect(february.days.count == 29)
        #expect(february.budgetTotalYen == 58_000)
    }

    @Test("月内で予算が変わると日付ごとの適用額を合計する")
    func midMonthBudgetChangeSumsPerDayAmounts() {
        let calculator = BudgetCalculator(
            activeStartDate: start,
            rules: [
                BudgetRule(effectiveFrom: day(1), dailyAmountYen: 2_000),
                BudgetRule(effectiveFrom: day(11), dailyAmountYen: 3_000)
            ]
        )
        let summary = calculator.monthSummary(for: YearMonth(year: 2026, month: 11), expenses: [])
        // 11/1〜11/10 が2,000円、11/11〜11/30 が3,000円。
        #expect(summary.budgetTotalYen == 2_000 * 10 + 3_000 * 20)
    }

    @Test("利用開始日より前の月は実績を持たない")
    func monthsBeforeActiveStartAreEmpty() {
        let summary = calculator.monthSummary(for: YearMonth(year: 2026, month: 10), expenses: [])
        #expect(summary.days.isEmpty)
        #expect(summary.budgetTotalYen == 0)
        #expect(summary.surplusYen == 0)
    }

    @Test("集計には対象月の支出だけが含まれる")
    func expensesOutsideTheMonthAreIgnored() {
        let expenses = [
            ExpenseEntry(spentOn: day(1), amountYen: 1_000),
            ExpenseEntry(spentOn: CalendarDay(year: 2026, month: 12, day: 1), amountYen: 9_000)
        ]
        let summary = calculator.monthSummary(for: YearMonth(year: 2026, month: 11), expenses: expenses)
        #expect(summary.expenseTotalYen == 1_000)
    }
}
