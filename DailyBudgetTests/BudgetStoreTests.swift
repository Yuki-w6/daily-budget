import Foundation
import SwiftData
import Testing
@testable import DailyBudget
import DailyBudgetCore

/// 永続化層と計算をつなぐ `BudgetStore` の振る舞いを確認する。
///
/// 計算そのものは `DailyBudgetCore` のテストで固めてある。ここで見るのは、
/// SwiftData への保存・取得を挟んでも同じ結果になるか、保存の失敗や重複を
/// どう扱うか、という永続化層に依存する部分。
@MainActor
struct BudgetStoreTests {
    private let day1 = CalendarDay.of(2026, 11, 1)

    // MARK: 初期設定

    @Test("初期設定で設定と最初の予算ルールができる")
    func onboardingCreatesSettingsAndFirstRule() throws {
        let harness = try StoreHarness(today: day1)
        #expect(harness.store.isOnboardingCompleted == false)

        try harness.start(dailyAmountYen: 2_000)

        #expect(harness.store.isOnboardingCompleted)
        #expect(harness.store.activeStartDate == day1)
        #expect(harness.store.currentDailyAmountYen == 2_000)
        #expect(harness.fetchAll(AppSettingsEntity.self).count == 1)
        #expect(harness.fetchAll(BudgetRuleEntity.self).count == 1)
        #expect(harness.store.todayBreakdown?.availableYen == 2_000)
    }

    @Test("初期カテゴリが作られる")
    func defaultCategoriesAreSeeded() throws {
        let harness = try StoreHarness(today: day1)
        #expect(harness.store.selectableCategories.map(\.name) == AppConstants.defaultCategoryNames)
    }

    @Test("初期カテゴリは起動を繰り返しても増えない")
    func seedingIsIdempotent() throws {
        let harness = try StoreHarness(today: day1)
        harness.store.bootstrap()
        harness.store.bootstrap()
        #expect(harness.fetchAll(ExpenseCategoryEntity.self).count
                == AppConstants.defaultCategoryNames.count)
    }

    // MARK: 支出の登録・編集・削除

    @Test("支出を登録すると今日使える金額と当月の集計が変わる")
    func savingAnExpenseUpdatesDerivedState() throws {
        let harness = try StoreHarness(today: day1)
        try harness.start()

        try harness.addExpense(1_300, on: day1)

        #expect(harness.store.todayBreakdown?.availableYen == 700)
        #expect(harness.store.currentMonthSummary?.expenseTotalYen == 1_300)
        #expect(harness.store.currentMonthExpenses.count == 1)
    }

    @Test("支出を編集すると集計が追随する")
    func editingAnExpenseRecalculates() throws {
        let harness = try StoreHarness(today: day1)
        try harness.start()
        let expense = try harness.addExpense(1_300, on: day1)

        try harness.store.saveExpense(
            editing: expense,
            amountYen: 300,
            spentOn: day1,
            category: harness.category(named: "交通費"),
            memo: nil
        )

        #expect(harness.store.todayBreakdown?.availableYen == 1_700)
        #expect(harness.store.currentMonthExpenses.count == 1)
        #expect(harness.store.currentMonthExpenses.first?.category?.name == "交通費")
    }

    @Test("支出を削除すると集計から消える")
    func deletingAnExpenseRemovesIt() throws {
        let harness = try StoreHarness(today: day1)
        try harness.start()
        let expense = try harness.addExpense(1_300, on: day1)

        try harness.store.deleteExpense(expense)

        #expect(harness.store.currentMonthExpenses.isEmpty)
        #expect(harness.store.todayBreakdown?.availableYen == 2_000)
    }

    @Test("メモは200文字で切り詰められ、空白だけなら保存しない")
    func memoIsNormalized() throws {
        let harness = try StoreHarness(today: day1)
        try harness.start()

        let long = String(repeating: "あ", count: 250)
        let saved = try harness.addExpense(100, on: day1, memo: long)
        #expect(saved.memo?.count == AppConstants.memoMaxLength)

        let blank = try harness.addExpense(200, on: day1, memo: "   ")
        #expect(blank.memo == nil)
    }

    @Test("未来日の支出は登録できない")
    func futureExpensesAreRejected() throws {
        let harness = try StoreHarness(today: day1)
        try harness.start()

        #expect(throws: BudgetStore.StoreError.self) {
            try harness.store.saveExpense(
                amountYen: 100,
                spentOn: day1.nextDay,
                category: nil,
                memo: nil
            )
        }
        #expect(harness.store.currentMonthExpenses.isEmpty)
    }

    // MARK: 月末確定

    @Test("月をまたぐと前月が確定される")
    func crossingAMonthSettlesThePreviousMonth() throws {
        let harness = try StoreHarness(today: day1)
        try harness.start()
        try harness.addExpense(1_300, on: day1)

        harness.travel(to: CalendarDay.of(2026, 12, 1))

        let settlements = harness.fetchAll(MonthlySettlementEntity.self)
        #expect(settlements.count == 1)
        #expect(settlements.first?.yearMonthISO == "2026-11")
        #expect(settlements.first?.budgetTotalYen == 60_000)
        #expect(settlements.first?.expenseTotalYen == 1_300)
        #expect(settlements.first?.surplusYen == 58_700)
        // 前月の余剰は12月に繰り越さない（AC-08）。
        #expect(harness.store.todayBreakdown?.availableYen == 2_000)
    }

    @Test("起動を繰り返しても確定レコードは1件のまま")
    func settlementIsIdempotentAcrossLaunches() throws {
        let harness = try StoreHarness(today: day1)
        try harness.start()
        harness.travel(to: CalendarDay.of(2026, 12, 1))

        harness.store.bootstrap()
        harness.store.bootstrap()

        #expect(harness.fetchAll(MonthlySettlementEntity.self).count == 1)
    }

    @Test("数か月開かなくても未確定の月がまとめて確定される")
    func catchesUpOnSeveralMonths() throws {
        let harness = try StoreHarness(today: day1)
        try harness.start()

        harness.travel(to: CalendarDay.of(2027, 2, 15))

        let months = harness.fetchAll(MonthlySettlementEntity.self)
            .map(\.yearMonthISO)
            .sorted()
        #expect(months == ["2026-11", "2026-12", "2027-01"])
    }

    @Test("確定済みの月には支出を登録できない")
    func closedMonthsRejectExpenses() throws {
        let harness = try StoreHarness(today: day1)
        try harness.start()
        harness.travel(to: CalendarDay.of(2026, 12, 5))

        #expect(throws: BudgetStore.StoreError.self) {
            try harness.store.saveExpense(
                amountYen: 500,
                spentOn: CalendarDay.of(2026, 11, 10),
                category: nil,
                memo: nil
            )
        }
    }

    // MARK: 確定の解除と再確定

    @Test("確定を解除すると編集でき、再確定で値が更新される")
    func reopenThenRecloseRecalculates() throws {
        let harness = try StoreHarness(today: day1)
        try harness.start()
        try harness.addExpense(1_300, on: day1)
        harness.travel(to: CalendarDay.of(2026, 12, 5))
        let november = YearMonth(year: 2026, month: 11)

        try harness.store.reopenSettlement(for: november)
        #expect(harness.store.isClosed(november) == false)

        try harness.store.saveExpense(
            amountYen: 2_000,
            spentOn: CalendarDay.of(2026, 11, 10),
            category: nil,
            memo: nil
        )
        try harness.store.recloseSettlement(for: november)

        let settlements = harness.fetchAll(MonthlySettlementEntity.self)
        #expect(settlements.count == 1)
        #expect(settlements.first?.expenseTotalYen == 3_300)
        #expect(settlements.first?.surplusYen == 56_700)
        #expect(settlements.first?.recloseCount == 1)
        #expect(settlements.first?.statusRaw == SettlementStatus.closed.rawValue)
    }

    @Test("解除した月は起動しても自動で確定しなおされない")
    func reopenedMonthSurvivesRelaunch() throws {
        let harness = try StoreHarness(today: day1)
        try harness.start()
        harness.travel(to: CalendarDay.of(2026, 12, 5))
        let november = YearMonth(year: 2026, month: 11)
        try harness.store.reopenSettlement(for: november)

        harness.store.bootstrap()

        #expect(harness.store.isClosed(november) == false)
        #expect(harness.fetchAll(MonthlySettlementEntity.self).count == 1)
    }

    // MARK: 同期で入りうる壊れた状態

    @Test("確定レコードが重複しても1件に収束する")
    func duplicateSettlementsCollapse() throws {
        let harness = try StoreHarness(today: day1)
        try harness.start()
        harness.travel(to: CalendarDay.of(2026, 12, 5))

        // 別の端末から同じ月の確定が流れ込んだ状態を作る。
        harness.context.insert(
            MonthlySettlementEntity(
                yearMonthISO: "2026-11",
                statusRaw: SettlementStatus.closed.rawValue,
                budgetTotalYen: 60_000,
                expenseTotalYen: 9_999,
                surplusYen: 50_001,
                closedAt: harness.now,
                recloseCount: 0,
                updatedAt: harness.now.addingTimeInterval(60)
            )
        )
        try harness.context.save()
        #expect(harness.fetchAll(MonthlySettlementEntity.self).count == 2)

        harness.store.bootstrap()

        let settlements = harness.fetchAll(MonthlySettlementEntity.self)
        #expect(settlements.count == 1)
        // 更新が新しいほう（あとから流れ込んだレコード）が残る。
        #expect(settlements.first?.expenseTotalYen == 9_999)
    }

    @Test("カテゴリが重複しても統合され、支出は残ったほうに付け替わる")
    func duplicateCategoriesMergeAndKeepExpenses() throws {
        let harness = try StoreHarness(today: day1)
        try harness.start()
        try harness.addExpense(1_000, on: day1, categoryName: "食費")

        // 別の端末から同じ名前のカテゴリが流れ込んだ状態を作る。
        let duplicate = ExpenseCategoryEntity(
            name: "食費",
            sortOrder: 0,
            updatedAt: harness.now.addingTimeInterval(60)
        )
        harness.context.insert(duplicate)
        let existing = harness.store.currentMonthExpenses.first!
        existing.category = duplicate
        try harness.context.save()

        harness.store.bootstrap()

        let foodCategories = harness.fetchAll(ExpenseCategoryEntity.self)
            .filter { $0.name == "食費" }
        #expect(foodCategories.count == 1)
        // 支出のカテゴリが失われていない。
        #expect(harness.store.currentMonthExpenses.first?.category?.name == "食費")
    }

    @Test("設定レコードが重複しても1件に収束する")
    func duplicateSettingsCollapse() throws {
        let harness = try StoreHarness(today: day1)
        try harness.start()

        harness.context.insert(
            AppSettingsEntity(
                activeStartDateISO: "2026-10-01",
                onboardingCompleted: true,
                updatedAt: harness.now.addingTimeInterval(60)
            )
        )
        try harness.context.save()

        harness.store.bootstrap()

        #expect(harness.fetchAll(AppSettingsEntity.self).count == 1)
        #expect(harness.store.activeStartDate == CalendarDay.of(2026, 10, 1))
    }

    @Test("壊れた日付や0円以下の支出は集計に入らない")
    func brokenRecordsAreIgnoredInTotals() throws {
        let harness = try StoreHarness(today: day1)
        try harness.start()
        try harness.addExpense(1_000, on: day1)

        harness.context.insert(
            ExpenseEntity(spentOnISO: "こわれた日付", spentOnMonthISO: "2026-11", amountYen: 5_000)
        )
        harness.context.insert(
            ExpenseEntity(spentOnISO: "2026-11-02", spentOnMonthISO: "2026-11", amountYen: 0)
        )
        try harness.context.save()
        harness.store.bootstrap()

        // 集計に入るのは正しい1件だけ。
        #expect(harness.store.currentMonthSummary?.expenseTotalYen == 1_000)
    }
}
