import Foundation
import Testing
@testable import DailyBudgetCore

/// PRD §10 受け入れ条件のうち、計算で検証できるものを対応IDつきで確認する。
/// 永続化・UI・オフライン動作（AC-13〜AC-15）はアプリ側の責務のため、ここでは扱わない。
struct AcceptanceCriteriaTests {
    private let start = CalendarDay(year: 2026, month: 11, day: 1)

    private func day(_ d: Int) -> CalendarDay {
        CalendarDay(year: 2026, month: 11, day: d)
    }

    private func calculator(
        dailyYen: Int64 = 2_000,
        from activeStart: CalendarDay? = nil
    ) -> BudgetCalculator {
        let activeStart = activeStart ?? start
        return BudgetCalculator(
            activeStartDate: activeStart,
            rules: [BudgetRule(effectiveFrom: activeStart, dailyAmountYen: dailyYen)]
        )
    }

    private func expense(_ d: Int, _ yen: Int64) -> ExpenseEntry {
        ExpenseEntry(spentOn: day(d), amountYen: yen)
    }

    // MARK: AC-01〜AC-05：日額予算と繰越の基本

    @Test("AC-01 初回設定で日額2,000円を登録すると当日の利用可能額が2,000円")
    func initialDailyBudgetIsAvailableOnDayOne() {
        let breakdown = calculator().todayBreakdown(on: day(1), expenses: [])
        #expect(breakdown.availableYen == 2_000)
        #expect(breakdown.carryOverYen == 0)
        #expect(breakdown.isOverBudget == false)
    }

    @Test("AC-02 初日に1,300円を記録すると当日の累積余剰が+700円")
    func firstDayExpenseLeavesSurplus() {
        let summary = calculator().summary(on: day(1), expenses: [expense(1, 1_300)])
        #expect(summary.cumulativeSurplusYen == 700)
    }

    @Test("AC-03 翌日に支出が無ければ今日の利用可能額は2,700円")
    func unusedBudgetCarriesToNextDay() {
        let breakdown = calculator().todayBreakdown(on: day(2), expenses: [expense(1, 1_300)])
        #expect(breakdown.carryOverYen == 700)
        #expect(breakdown.dailyBudgetYen == 2_000)
        #expect(breakdown.availableYen == 2_700)
    }

    @Test("AC-04 2日目に2,400円を記録すると今日の利用可能額は300円")
    func sameDayExpenseReducesAvailable() {
        let breakdown = calculator().todayBreakdown(
            on: day(2),
            expenses: [expense(1, 1_300), expense(2, 2_400)]
        )
        #expect(breakdown.availableYen == 300)
    }

    @Test("AC-05 3日目に4,000円を記録すると累積余剰が−1,700円で予算超過になる")
    func overspendingIsKeptNegative() {
        let expenses = [expense(1, 1_300), expense(2, 2_400), expense(3, 4_000)]
        let breakdown = calculator().todayBreakdown(on: day(3), expenses: expenses)
        #expect(breakdown.availableYen == -1_700)
        #expect(breakdown.isOverBudget)
        // 自動でゼロに丸めない（PRD §4.2）
        #expect(calculator().summary(on: day(3), expenses: expenses).cumulativeSurplusYen == -1_700)
    }

    // MARK: AC-06：過去日の訂正

    @Test("AC-06 過去の日の支出を編集すると該当日以降の累積余剰が再計算される")
    func editingPastExpenseRecalculatesLaterDays() {
        let calculator = calculator()
        let before = [expense(1, 1_300), expense(2, 2_400)]
        #expect(calculator.summary(on: day(2), expenses: before).cumulativeSurplusYen == 300)

        // 11/1 を 1,300円 → 300円 に訂正すると、11/2 以降の累積余剰が1,000円増える。
        let after = [expense(1, 300), expense(2, 2_400)]
        #expect(calculator.summary(on: day(1), expenses: after).cumulativeSurplusYen == 1_700)
        #expect(calculator.summary(on: day(2), expenses: after).cumulativeSurplusYen == 1_300)
    }

    // MARK: AC-07：予算変更

    @Test("AC-07 日額2,000→2,500円を翌日から適用すると前日までの累積予算は変わらない")
    func budgetChangeAppliesFromEffectiveDateOnly() {
        // 11/2 に「明日から」を選び、11/3 開始のルールを追加した状態。
        let calculator = BudgetCalculator(
            activeStartDate: start,
            rules: [
                BudgetRule(effectiveFrom: day(1), dailyAmountYen: 2_000),
                BudgetRule(effectiveFrom: day(3), dailyAmountYen: 2_500)
            ]
        )
        #expect(calculator.dailyBudget(on: day(2)) == 2_000)
        #expect(calculator.cumulativeBudget(through: day(2)) == 4_000)
        #expect(calculator.dailyBudget(on: day(3)) == 2_500)
        #expect(calculator.cumulativeBudget(through: day(3)) == 6_500)
    }

    @Test("PRD §6.1 同じ有効開始日に複数回変更した場合は最後に保存した設定が有効")
    func latestRuleWinsForSameEffectiveDate() {
        let base = Date(timeIntervalSince1970: 1_000)
        let calculator = BudgetCalculator(
            activeStartDate: start,
            rules: [
                BudgetRule(effectiveFrom: day(1), dailyAmountYen: 2_000, updatedAt: base),
                BudgetRule(effectiveFrom: day(3), dailyAmountYen: 2_500, updatedAt: base),
                BudgetRule(effectiveFrom: day(3), dailyAmountYen: 3_000, updatedAt: base.addingTimeInterval(60))
            ]
        )
        #expect(calculator.dailyBudget(on: day(3)) == 3_000)
    }

    // MARK: AC-08〜AC-09：月末確定と翌月リセット

    @Test("AC-08 11月末余剰+5,000円で12月に移ると11月は+5,000円で確定し12/1は日額予算のみ")
    func positiveSurplusDoesNotCarryToNextMonth() {
        let calculator = calculator()
        // 11月の月間予算は 2,000 × 30日 = 60,000円。支出 55,000円で +5,000円。
        let expenses = (1...25).map { expense($0, 2_200) }
        #expect(expenses.reduce(0) { $0 + $1.amountYen } == 55_000)

        let settlement = calculator.settlement(
            for: YearMonth(year: 2026, month: 11),
            expenses: expenses,
            closedAt: Date()
        )
        #expect(settlement.budgetTotalYen == 60_000)
        #expect(settlement.expenseTotalYen == 55_000)
        #expect(settlement.surplusYen == 5_000)
        #expect(settlement.status == .closed)
        #expect(settlement.recloseCount == 0)

        // 12/1 の開始時点は日額予算のみ。前月の確定額は一切加算しない（PRD §4.2）。
        let december1 = CalendarDay(year: 2026, month: 12, day: 1)
        let breakdown = calculator.todayBreakdown(on: december1, expenses: expenses)
        #expect(breakdown.carryOverYen == 0)
        #expect(breakdown.availableYen == 2_000)
    }

    @Test("AC-09 11月末余剰−3,000円でも12月に負債を持ち越さない")
    func negativeSurplusDoesNotCarryToNextMonth() {
        let calculator = calculator()
        let expenses = (1...30).map { expense($0, 2_100) }  // 63,000円
        let settlement = calculator.settlement(
            for: YearMonth(year: 2026, month: 11),
            expenses: expenses,
            closedAt: Date()
        )
        #expect(settlement.surplusYen == -3_000)

        let december1 = CalendarDay(year: 2026, month: 12, day: 1)
        let breakdown = calculator.todayBreakdown(on: december1, expenses: expenses)
        #expect(breakdown.carryOverYen == 0)
        #expect(breakdown.availableYen == 2_000)
    }

    // MARK: AC-10〜AC-11：自動確定

    @Test("AC-10 1か月以上開かなかった場合は未確定の過去月が時系列順に並ぶ")
    func pendingMonthsAreOrderedOldestFirst() {
        let months = SettlementPlanner.monthsAwaitingSettlement(
            activeStartDate: start,
            today: CalendarDay(year: 2027, month: 2, day: 15),
            recordedMonths: []
        )
        #expect(months == [
            YearMonth(year: 2026, month: 11),
            YearMonth(year: 2026, month: 12),
            YearMonth(year: 2027, month: 1)
        ])
    }

    @Test("AC-11 確定処理を複数回呼んでも同じ月は一度しか対象にならない")
    func settlementIsIdempotent() {
        let today = CalendarDay(year: 2026, month: 12, day: 5)
        let first = SettlementPlanner.monthsAwaitingSettlement(
            activeStartDate: start,
            today: today,
            recordedMonths: []
        )
        #expect(first == [YearMonth(year: 2026, month: 11)])

        let second = SettlementPlanner.monthsAwaitingSettlement(
            activeStartDate: start,
            today: today,
            recordedMonths: Set(first)
        )
        #expect(second.isEmpty)
    }

    @Test("当月は確定の対象にしない")
    func currentMonthIsNeverSettled() {
        let months = SettlementPlanner.monthsAwaitingSettlement(
            activeStartDate: start,
            today: day(20),
            recordedMonths: []
        )
        #expect(months.isEmpty)
    }

    // MARK: AC-12：確定解除と再確定

    @Test("AC-12 確定解除中の月は自動確定で上書きされない")
    func reopenedMonthIsExcludedFromAutoSettlement() {
        // PRD §6.2 と §6.3 の衝突に対する実装上の決定を固定する。
        let november = YearMonth(year: 2026, month: 11)
        let months = SettlementPlanner.monthsAwaitingSettlement(
            activeStartDate: start,
            today: CalendarDay(year: 2026, month: 12, day: 5),
            recordedMonths: [november]
        )
        #expect(months.isEmpty)
    }

    @Test("AC-12 再確定すると確定値が再計算され再確定回数が増える")
    func reclosingRecalculatesAndCountsUp() {
        let calculator = calculator()
        let november = YearMonth(year: 2026, month: 11)
        let closed = calculator.settlement(
            for: november,
            expenses: [expense(1, 1_300)],
            closedAt: Date()
        )
        #expect(closed.surplusYen == 58_700)

        let reopened = MonthlySettlement(
            id: closed.id,
            yearMonth: closed.yearMonth,
            status: .reopened,
            budgetTotalYen: closed.budgetTotalYen,
            expenseTotalYen: closed.expenseTotalYen,
            surplusYen: closed.surplusYen,
            closedAt: closed.closedAt,
            recloseCount: closed.recloseCount
        )
        let reclosed = calculator.settlement(
            for: november,
            expenses: [expense(1, 1_300), expense(2, 2_000)],
            closedAt: Date(),
            previous: reopened
        )
        #expect(reclosed.id == closed.id)  // レコードは増やさない
        #expect(reclosed.expenseTotalYen == 3_300)
        #expect(reclosed.surplusYen == 56_700)
        #expect(reclosed.status == .closed)
        #expect(reclosed.recloseCount == 1)
    }

    // MARK: AC-16〜AC-17：期間の境界

    @Test("AC-16 月途中に利用を開始すると開始日より前の予算は加算されない")
    func budgetDoesNotAccrueBeforeActiveStart() {
        let activeStart = day(10)
        let calculator = calculator(from: activeStart)
        #expect(calculator.dailyBudget(on: day(5)) == 0)
        #expect(calculator.cumulativeBudget(through: day(9)) == 0)
        #expect(calculator.periodStart(of: day(20)) == activeStart)
        // 11/10〜11/30 の21日分だけが月間予算になる。
        #expect(calculator.cumulativeBudget(through: day(30)) == 42_000)

        let summary = calculator.monthSummary(for: YearMonth(year: 2026, month: 11), expenses: [])
        #expect(summary.budgetTotalYen == 42_000)
        #expect(summary.days.first?.day == activeStart)
        #expect(summary.days.count == 21)
    }

    @Test("AC-17 11/30から12/1へ日付が変わると前月確定と当月リセットが起きる")
    func monthBoundaryResetsCumulativeSurplus() {
        let calculator = calculator()
        let expenses = (1...30).map { expense($0, 1_000) }  // 30,000円、+30,000円で確定

        let lastDay = calculator.todayBreakdown(on: day(30), expenses: expenses)
        #expect(lastDay.availableYen == 30_000)  // 繰越29,000 + 日額2,000 − 当日1,000

        let settlement = calculator.settlement(
            for: YearMonth(year: 2026, month: 11),
            expenses: expenses,
            closedAt: Date()
        )
        #expect(settlement.surplusYen == 30_000)

        let december1 = CalendarDay(year: 2026, month: 12, day: 1)
        #expect(calculator.periodStart(of: december1) == december1)
        #expect(calculator.todayBreakdown(on: december1, expenses: expenses).availableYen == 2_000)
    }
}
