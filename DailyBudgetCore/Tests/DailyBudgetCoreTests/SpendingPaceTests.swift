import Foundation
import Testing
@testable import DailyBudgetCore

/// PRD §5.6 の月末予測を、今月の平均支出から見積もる計算の確認。
struct SpendingPaceTests {
    private let start = CalendarDay(year: 2026, month: 11, day: 1)

    private func day(_ d: Int) -> CalendarDay {
        CalendarDay(year: 2026, month: 11, day: d)
    }

    private func calculator(from activeStart: CalendarDay? = nil) -> BudgetCalculator {
        let activeStart = activeStart ?? start
        return BudgetCalculator(
            activeStartDate: activeStart,
            rules: [BudgetRule(effectiveFrom: activeStart, dailyAmountYen: 2_000)]
        )
    }

    private func expenses(_ rows: [(Int, Int64)]) -> [ExpenseEntry] {
        rows.map { ExpenseEntry(spentOn: day($0.0), amountYen: $0.1) }
    }

    private func projection(
        asOf: CalendarDay,
        expenses rows: [(Int, Int64)],
        from activeStart: CalendarDay? = nil
    ) -> SpendingPaceProjection? {
        SpendingPace.projection(
            calculator: calculator(from: activeStart),
            yearMonth: YearMonth(year: 2026, month: 11),
            expenses: expenses(rows),
            asOf: asOf
        )
    }

    // MARK: 日数の下限

    @Test("経過日数が5日に満たなければ見込みを出さない")
    func noProjectionBeforeFiveDays() {
        #expect(projection(asOf: day(4), expenses: [(1, 1_000)]) == nil)
        #expect(projection(asOf: day(1), expenses: [(1, 1_000)]) == nil)
    }

    @Test("5日経てば見込みを出す")
    func projectionStartsAtFiveDays() {
        #expect(projection(asOf: day(5), expenses: [(1, 1_000)]) != nil)
    }

    @Test("月途中に使い始めた月は、利用開始日からの経過日数で判定する")
    func elapsedDaysAreCountedFromActiveStart() {
        let activeStart = day(20)
        // 11/23 時点では開始から4日なので出さない。
        #expect(projection(asOf: day(23), expenses: [(20, 1_000)], from: activeStart) == nil)
        // 11/24 で5日になる。
        let result = projection(asOf: day(24), expenses: [(20, 1_000)], from: activeStart)
        #expect(result?.elapsedDays == 5)
        // 期間全体は 11/20〜11/30 の11日。
        #expect(result?.totalDays == 11)
        #expect(result?.budgetTotalYen == 22_000)
    }

    // MARK: 見込みの計算

    @Test("平均支出が月末まで続くとして支出を見積もる")
    func projectsExpenseFromDailyAverage() {
        // 10日で15,000円 → 1日1,500円。30日で45,000円の見込み。
        let result = projection(
            asOf: day(10),
            expenses: (1...10).map { ($0, Int64(1_500)) }
        )
        #expect(result?.elapsedDays == 10)
        #expect(result?.totalDays == 30)
        #expect(result?.expenseToDateYen == 15_000)
        #expect(result?.averageDailyExpenseYen == 1_500)
        #expect(result?.projectedExpenseYen == 45_000)
        // 月間予算 60,000円 − 見込み支出 45,000円。
        #expect(result?.projectedSurplusYen == 15_000)
        #expect(result?.isActual == false)
    }

    @Test("平均が日額予算を超えていれば超過の見込みになる")
    func projectsOverBudgetWhenPaceIsTooHigh() {
        // 10日で25,000円 → 1日2,500円。30日で75,000円の見込み。
        let result = projection(
            asOf: day(10),
            expenses: (1...10).map { ($0, Int64(2_500)) }
        )
        #expect(result?.projectedExpenseYen == 75_000)
        #expect(result?.projectedSurplusYen == -15_000)
    }

    @Test("割り切れない平均は四捨五入する")
    func roundsProjectedExpense() {
        // 7日で10,000円 → 30日なら 10,000 × 30 / 7 = 42,857.14… → 42,857円。
        let result = projection(asOf: day(7), expenses: [(1, 10_000)])
        #expect(result?.projectedExpenseYen == 42_857)
    }

    @Test("支出が無ければ見込み支出も0になる")
    func noExpensesMeansNoProjectedExpense() {
        let result = projection(asOf: day(10), expenses: [])
        #expect(result?.projectedExpenseYen == 0)
        #expect(result?.projectedSurplusYen == 60_000)
    }

    // MARK: 月末

    @Test("月末まで来たら見込みではなく実績になる")
    func lastDayUsesActualInsteadOfEstimate() {
        let rows = (1...30).map { ($0, Int64(1_500)) }
        let result = projection(asOf: day(30), expenses: rows)
        #expect(result?.isActual == true)
        #expect(result?.projectedExpenseYen == 45_000)   // 見積もらずそのまま
        #expect(result?.projectedSurplusYen == 15_000)
    }

    @Test("月末の実績は当月の集計と一致する")
    func lastDayMatchesMonthSummary() {
        let rows = (1...30).map { ($0, Int64(2_100)) }
        let calculator = calculator()
        let summary = calculator.monthSummary(
            for: YearMonth(year: 2026, month: 11),
            expenses: expenses(rows)
        )
        let result = projection(asOf: day(30), expenses: rows)
        #expect(result?.projectedSurplusYen == summary.surplusYen)
        #expect(result?.projectedSurplusYen == -3_000)
    }

    @Test("月末の前日はまだ見込み扱い")
    func dayBeforeMonthEndIsStillAnEstimate() {
        let rows = (1...29).map { ($0, Int64(1_500)) }
        let result = projection(asOf: day(29), expenses: rows)
        #expect(result?.isActual == false)
        #expect(result?.elapsedDays == 29)
        #expect(result?.totalDays == 30)
    }
}
