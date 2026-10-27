import Foundation

/// 日額予算の1件の設定。PRD §7.1 `BudgetRule` に対応する値型。
///
/// 終了日は保持せず、次のルールの `effectiveFrom` から導出する（PRD §7.1）。
public struct BudgetRule: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    /// 有効開始日。この日以降、次のルールの開始日までこの金額を適用する。
    public let effectiveFrom: CalendarDay
    /// 日額。1円以上の整数。
    public let dailyAmountYen: Int64
    /// 同じ `effectiveFrom` が複数ある場合の優先判定に使う（PRD §6.1：最後に保存した設定が有効）。
    public let updatedAt: Date

    public init(
        id: UUID = UUID(),
        effectiveFrom: CalendarDay,
        dailyAmountYen: Int64,
        updatedAt: Date = Date()
    ) {
        precondition(dailyAmountYen >= 1, "日額予算は1円以上: \(dailyAmountYen)")
        self.id = id
        self.effectiveFrom = effectiveFrom
        self.dailyAmountYen = dailyAmountYen
        self.updatedAt = updatedAt
    }
}

/// 集計対象となる支出1件。PRD §7.2 `Expense` のうち、計算に必要な項目だけを持つ。
///
/// カテゴリ名やメモは集計に影響しないため、この型には含めない。
public struct ExpenseEntry: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let spentOn: CalendarDay
    public let amountYen: Int64

    public init(id: UUID = UUID(), spentOn: CalendarDay, amountYen: Int64) {
        precondition(amountYen >= 1, "支出は1円以上: \(amountYen)")
        self.id = id
        self.spentOn = spentOn
        self.amountYen = amountYen
    }
}

/// 1日の集計結果。PRD §4.2 の各値に1対1で対応する。
public struct DailySummary: Hashable, Sendable {
    public let day: CalendarDay
    /// `budget(d)`。利用開始日より前は 0。
    public let budgetYen: Int64
    /// `expense(d)`。
    public let expenseYen: Int64
    /// `cumulativeBudget(d)`。
    public let cumulativeBudgetYen: Int64
    /// `cumulativeExpense(d)`。
    public let cumulativeExpenseYen: Int64

    public init(
        day: CalendarDay,
        budgetYen: Int64,
        expenseYen: Int64,
        cumulativeBudgetYen: Int64,
        cumulativeExpenseYen: Int64
    ) {
        self.day = day
        self.budgetYen = budgetYen
        self.expenseYen = expenseYen
        self.cumulativeBudgetYen = cumulativeBudgetYen
        self.cumulativeExpenseYen = cumulativeExpenseYen
    }

    /// `cumulativeSurplus(d)`。負の値も保持する（PRD §4.2）。
    public var cumulativeSurplusYen: Int64 { cumulativeBudgetYen - cumulativeExpenseYen }
}

/// ホーム画面の「今日使える金額」とその内訳。PRD §5.3 の表示要件に対応する。
public struct TodayBreakdown: Hashable, Sendable {
    public let day: CalendarDay
    /// 今日の日額予算。
    public let dailyBudgetYen: Int64
    /// 前日終了時点の累積余剰。期間初日は 0。
    public let carryOverYen: Int64
    /// 今日すでに登録済みの支出合計。
    public let todayExpenseYen: Int64

    public init(day: CalendarDay, dailyBudgetYen: Int64, carryOverYen: Int64, todayExpenseYen: Int64) {
        self.day = day
        self.dailyBudgetYen = dailyBudgetYen
        self.carryOverYen = carryOverYen
        self.todayExpenseYen = todayExpenseYen
    }

    /// 今日使える金額。`todayAvailable(d) = cumulativeSurplus(d)` と一致する（PRD §4.2）。
    public var availableYen: Int64 { dailyBudgetYen + carryOverYen - todayExpenseYen }

    /// 予算超過しているか。超過時も丸めず負の値を表示する（PRD §8.3）。
    public var isOverBudget: Bool { availableYen < 0 }
}

/// 月単位の集計結果。PRD §5.6 月次レポートと §6.2 月末確定の双方が参照する。
public struct MonthSummary: Hashable, Sendable {
    public let yearMonth: YearMonth
    /// 対象月の日額予算の合計。利用開始日より前の日は加算しない（PRD AC-16）。
    public let budgetTotalYen: Int64
    public let expenseTotalYen: Int64
    /// 日付昇順の日次系列。グラフの折れ線はこれを使う（PRD §8.1）。
    public let days: [DailySummary]

    public init(
        yearMonth: YearMonth,
        budgetTotalYen: Int64,
        expenseTotalYen: Int64,
        days: [DailySummary]
    ) {
        self.yearMonth = yearMonth
        self.budgetTotalYen = budgetTotalYen
        self.expenseTotalYen = expenseTotalYen
        self.days = days
    }

    public var surplusYen: Int64 { budgetTotalYen - expenseTotalYen }
}

/// 月末確定の状態。PRD §7.4 `status` に対応する。
public enum SettlementStatus: String, Codable, Sendable {
    /// 確定済み。閲覧専用（PRD §6.3）。
    case closed
    /// 確定を解除して編集中。自動確定の対象から外す。
    case reopened
}

/// 月末確定レコード。PRD §7.4 `MonthlySettlement` に対応する値型。
public struct MonthlySettlement: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let yearMonth: YearMonth
    public let status: SettlementStatus
    public let budgetTotalYen: Int64
    public let expenseTotalYen: Int64
    /// 予算 − 支出。負値を許可する（PRD §7.4）。
    public let surplusYen: Int64
    public let closedAt: Date?
    public let recloseCount: Int

    public init(
        id: UUID = UUID(),
        yearMonth: YearMonth,
        status: SettlementStatus,
        budgetTotalYen: Int64,
        expenseTotalYen: Int64,
        surplusYen: Int64,
        closedAt: Date?,
        recloseCount: Int
    ) {
        self.id = id
        self.yearMonth = yearMonth
        self.status = status
        self.budgetTotalYen = budgetTotalYen
        self.expenseTotalYen = expenseTotalYen
        self.surplusYen = surplusYen
        self.closedAt = closedAt
        self.recloseCount = recloseCount
    }
}
