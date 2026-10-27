import Foundation
import Testing
@testable import DailyBudgetCore

/// PRD §5.7「適用日を今日・明日・翌月1日から選ぶ」と §6.1 の変更ルールを確認する。
struct BudgetChangeTests {
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

    private func impact(
        _ timing: BudgetChangeTiming,
        to amount: Int64 = 2_500,
        today: CalendarDay,
        expenses: [ExpenseEntry] = []
    ) -> BudgetChangeImpact {
        BudgetChangePreview.impact(
            current: calculator,
            newDailyAmountYen: amount,
            effectiveFrom: timing.effectiveDate(from: today),
            today: today,
            expenses: expenses
        )
    }

    // MARK: 適用日

    @Test("適用日は今日・明日・翌月1日から決まる")
    func effectiveDatesForEachTiming() {
        let today = day(10)
        #expect(BudgetChangeTiming.today.effectiveDate(from: today) == day(10))
        #expect(BudgetChangeTiming.tomorrow.effectiveDate(from: today) == day(11))
        #expect(BudgetChangeTiming.nextMonth.effectiveDate(from: today)
                == CalendarDay(year: 2026, month: 12, day: 1))
    }

    @Test("月末に明日を選ぶと翌月1日になる")
    func tomorrowAtMonthEndCrossesIntoNextMonth() {
        let today = day(30)
        #expect(BudgetChangeTiming.tomorrow.effectiveDate(from: today)
                == CalendarDay(year: 2026, month: 12, day: 1))
        #expect(BudgetChangeTiming.nextMonth.effectiveDate(from: today)
                == CalendarDay(year: 2026, month: 12, day: 1))
    }

    @Test("年末に翌月1日を選ぶと翌年1月1日になる")
    func nextMonthCrossesIntoNextYear() {
        let today = CalendarDay(year: 2026, month: 12, day: 20)
        #expect(BudgetChangeTiming.nextMonth.effectiveDate(from: today)
                == CalendarDay(year: 2027, month: 1, day: 1))
    }

    // MARK: 影響の試算

    @Test("今日から適用するとその日の予算全体が新しい金額になる")
    func applyingTodayChangesTodayWholeBudget() {
        let today = day(5)
        let result = impact(.today, today: today)
        #expect(result.effectiveFrom == today)
        #expect(result.currentDailyAmountYen == 2_000)
        #expect(result.newDailyAmountYen == 2_500)
        // 5日目の累積予算が 10,000 → 10,500 になる。差額は1日分の500円だけ。
        #expect(result.todayAvailableAfterYen - result.todayAvailableBeforeYen == 500)
        #expect(result.changesToday)
        #expect(result.changesThisMonth)
    }

    @Test("明日から適用すると今日の利用可能額は変わらない")
    func applyingTomorrowLeavesTodayUntouched() {
        let result = impact(.tomorrow, today: day(5))
        #expect(result.effectiveFrom == day(6))
        #expect(result.todayAvailableBeforeYen == result.todayAvailableAfterYen)
        #expect(!result.changesToday)
        // 11/6〜11/30 の25日分が 2,000 → 2,500 になる。
        #expect(result.monthBudgetAfterYen - result.monthBudgetBeforeYen == 500 * 25)
        #expect(result.changesThisMonth)
    }

    @Test("翌月1日から適用すると当月の月間予算は変わらない")
    func applyingNextMonthLeavesThisMonthUntouched() {
        let result = impact(.nextMonth, today: day(5))
        #expect(result.effectiveFrom == CalendarDay(year: 2026, month: 12, day: 1))
        #expect(!result.changesToday)
        #expect(!result.changesThisMonth)
        #expect(result.monthBudgetBeforeYen == 60_000)
        #expect(result.monthBudgetAfterYen == 60_000)
    }

    @Test("前日までの累積余剰は変更後も保持される")
    func pastSurplusIsPreserved() {
        let today = day(5)
        let expenses = [
            ExpenseEntry(spentOn: day(1), amountYen: 1_300),
            ExpenseEntry(spentOn: day(2), amountYen: 2_400)
        ]
        let updated = calculator.applying(
            BudgetRule(effectiveFrom: today, dailyAmountYen: 2_500)
        )
        // 11/4 までの累積余剰は変更前と同じ。
        #expect(calculator.summary(on: day(4), expenses: expenses).cumulativeSurplusYen
                == updated.summary(on: day(4), expenses: expenses).cumulativeSurplusYen)
        // 11/5 以降だけ新しい日額が加算される。
        #expect(updated.dailyBudget(on: day(5)) == 2_500)
        #expect(updated.dailyBudget(on: day(4)) == 2_000)
    }

    @Test("試算は保存前の計算機を書き換えない")
    func previewDoesNotMutateCurrentCalculator() {
        let current = calculator
        _ = BudgetChangePreview.impact(
            current: current,
            newDailyAmountYen: 9_000,
            effectiveFrom: day(5),
            today: day(5),
            expenses: []
        )
        #expect(current.dailyBudget(on: day(5)) == 2_000)
        #expect(current.budgetRules.count == 1)
    }

    @Test("同じ有効開始日に既存ルールがあっても試算では新しい金額が使われる")
    func previewWinsOverExistingRuleOnSameDate() {
        let result = impact(.today, to: 3_000, today: start)
        #expect(result.newDailyAmountYen == 3_000)
        // 利用開始日と同じ日に変更した場合、その日の予算は 2,000 → 3,000。
        #expect(result.todayAvailableAfterYen == 3_000)
    }
}
