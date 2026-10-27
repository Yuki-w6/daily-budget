import Foundation

/// 予算計算の単一の入口。PRD §8.1「単一の計算サービス」に対応する。
///
/// ホーム・履歴・月次レポート・月末確定はすべてこの型の結果を参照し、
/// 画面ごとに独自の集計を持たない。保存済みの `MonthlySettlement` は入力に含めないため、
/// 進行中の月の計算に過去の確定値が混入することはない（PRD §8.1）。
public struct BudgetCalculator: Sendable {
    /// 初回利用開始日。この日より前の日付には日額予算を割り当てない（PRD §4.2）。
    public let activeStartDate: CalendarDay

    /// `effectiveFrom` 昇順。同一日付は `updatedAt` が最新の1件に正規化済み。
    private let rules: [BudgetRule]

    public init(activeStartDate: CalendarDay, rules: [BudgetRule]) {
        self.activeStartDate = activeStartDate
        self.rules = Self.normalize(rules)
    }

    /// 同じ有効開始日の設定は最後に保存したものを有効値とする（PRD §6.1）。
    private static func normalize(_ rules: [BudgetRule]) -> [BudgetRule] {
        var latest: [CalendarDay: BudgetRule] = [:]
        for rule in rules {
            if let existing = latest[rule.effectiveFrom], existing.updatedAt >= rule.updatedAt {
                continue
            }
            latest[rule.effectiveFrom] = rule
        }
        return latest.values.sorted { $0.effectiveFrom < $1.effectiveFrom }
    }

    /// 適用中の予算ルール。`effectiveFrom` 昇順、同一日付は正規化済み。
    public var budgetRules: [BudgetRule] { rules }

    /// ルールを1件足した計算機を返す。変更を保存する前に影響を試算するために使う。
    public func applying(_ rule: BudgetRule) -> BudgetCalculator {
        BudgetCalculator(activeStartDate: activeStartDate, rules: rules + [rule])
    }

    // MARK: - 日単位

    /// `budget(d)`：その日に新たに加算される利用可能額。
    ///
    /// 利用開始日より前は 0。適用するルールは「その日以前の開始日を持つ最新ルール」（PRD §7.1）。
    /// 利用開始日以降でそれより前に開始するルールが無い場合は、最も早いルールの金額を適用する。
    public func dailyBudget(on day: CalendarDay) -> Int64 {
        guard day >= activeStartDate, let first = rules.first else { return 0 }
        guard let applicable = rules.last(where: { $0.effectiveFrom <= day }) else {
            return first.dailyAmountYen
        }
        return applicable.dailyAmountYen
    }

    /// `periodStart(d) = max(monthStart(d), activeStart)`（PRD §4.2）。
    public func periodStart(of day: CalendarDay) -> CalendarDay {
        max(day.yearMonth.firstDay, activeStartDate)
    }

    /// `cumulativeBudget(d)`：期間開始日から `day` までの日額予算の合計。
    public func cumulativeBudget(through day: CalendarDay) -> Int64 {
        guard day >= activeStartDate else { return 0 }
        return periodStart(of: day).through(day).reduce(0) { $0 + dailyBudget(on: $1) }
    }

    /// `day` 終了時点の集計。`expenses` は当該月の全支出を渡せばよい（範囲外は無視する）。
    public func summary(on day: CalendarDay, expenses: [ExpenseEntry]) -> DailySummary {
        let totals = Self.dailyTotals(of: expenses)
        let start = periodStart(of: day)
        let cumulativeExpense = day < activeStartDate
            ? 0
            : start.through(day).reduce(0) { $0 + (totals[$1] ?? 0) }
        return DailySummary(
            day: day,
            budgetYen: dailyBudget(on: day),
            expenseYen: totals[day] ?? 0,
            cumulativeBudgetYen: cumulativeBudget(through: day),
            cumulativeExpenseYen: cumulativeExpense
        )
    }

    /// ホームの「今日使える金額」とその内訳（PRD §5.3）。
    public func todayBreakdown(on day: CalendarDay, expenses: [ExpenseEntry]) -> TodayBreakdown {
        let totals = Self.dailyTotals(of: expenses)
        let start = periodStart(of: day)
        let carryOver: Int64
        if day <= start {
            // 期間初日は繰越なし。利用開始日より前の日も同様に 0 とする。
            carryOver = 0
        } else {
            let yesterday = summary(on: day.previousDay, expenses: expenses)
            carryOver = yesterday.cumulativeSurplusYen
        }
        return TodayBreakdown(
            day: day,
            dailyBudgetYen: dailyBudget(on: day),
            carryOverYen: carryOver,
            todayExpenseYen: totals[day] ?? 0
        )
    }

    // MARK: - 月単位

    /// 対象月の集計。
    ///
    /// - Parameter asOf: ここまでの実績に限定する。進行中の月は閲覧日を渡す（PRD §5.6）。
    ///   月末確定では `nil` を渡し、月全体を対象にする（PRD §6.2）。
    public func monthSummary(
        for yearMonth: YearMonth,
        expenses: [ExpenseEntry],
        asOf: CalendarDay? = nil
    ) -> MonthSummary {
        let start = periodStart(of: yearMonth.firstDay)
        var end = yearMonth.lastDay
        if let asOf, asOf < end { end = asOf }

        guard start <= end else {
            // 月全体が利用開始日より前、または閲覧日より後。実績なし。
            return MonthSummary(
                yearMonth: yearMonth,
                budgetTotalYen: 0,
                expenseTotalYen: 0,
                days: []
            )
        }

        let totals = Self.dailyTotals(of: expenses)
        var cumulativeBudget: Int64 = 0
        var cumulativeExpense: Int64 = 0
        var days: [DailySummary] = []
        days.reserveCapacity(start.days(until: end) + 1)

        for day in start.through(end) {
            let budget = dailyBudget(on: day)
            let expense = totals[day] ?? 0
            cumulativeBudget += budget
            cumulativeExpense += expense
            days.append(
                DailySummary(
                    day: day,
                    budgetYen: budget,
                    expenseYen: expense,
                    cumulativeBudgetYen: cumulativeBudget,
                    cumulativeExpenseYen: cumulativeExpense
                )
            )
        }

        return MonthSummary(
            yearMonth: yearMonth,
            budgetTotalYen: cumulativeBudget,
            expenseTotalYen: cumulativeExpense,
            days: days
        )
    }

    /// 月末時点の見込み。未来日の予算を加算するため、実績（`monthSummary`）とは別物として扱う（PRD §5.6）。
    public func monthEndProjection(
        for yearMonth: YearMonth,
        expenses: [ExpenseEntry],
        asOf: CalendarDay
    ) -> MonthEndProjection {
        let fullMonth = monthSummary(for: yearMonth, expenses: expenses, asOf: nil)
        let toDate = monthSummary(for: yearMonth, expenses: expenses, asOf: asOf)
        return MonthEndProjection(
            yearMonth: yearMonth,
            budgetTotalYen: fullMonth.budgetTotalYen,
            expenseTotalToDateYen: toDate.expenseTotalYen
        )
    }

    // MARK: - 月末確定

    /// 対象月の確定値を算出する（PRD §6.2 の 1〜3）。
    ///
    /// `previous` を渡すと再確定として扱い、`recloseCount` を1増やす（PRD §6.3）。
    public func settlement(
        for yearMonth: YearMonth,
        expenses: [ExpenseEntry],
        closedAt: Date,
        previous: MonthlySettlement? = nil
    ) -> MonthlySettlement {
        let summary = monthSummary(for: yearMonth, expenses: expenses, asOf: nil)
        return MonthlySettlement(
            id: previous?.id ?? UUID(),
            yearMonth: yearMonth,
            status: .closed,
            budgetTotalYen: summary.budgetTotalYen,
            expenseTotalYen: summary.expenseTotalYen,
            surplusYen: summary.surplusYen,
            closedAt: closedAt,
            recloseCount: previous == nil ? 0 : previous!.recloseCount + 1
        )
    }

    // MARK: - 補助

    private static func dailyTotals(of expenses: [ExpenseEntry]) -> [CalendarDay: Int64] {
        var totals: [CalendarDay: Int64] = [:]
        for expense in expenses {
            totals[expense.spentOn, default: 0] += expense.amountYen
        }
        return totals
    }
}

/// 月末見込み。実績と区別するために専用の型にする（PRD §5.6）。
public struct MonthEndProjection: Hashable, Sendable {
    public let yearMonth: YearMonth
    /// 月全体の日額予算の合計。
    public let budgetTotalYen: Int64
    /// 閲覧日までの支出合計。
    public let expenseTotalToDateYen: Int64

    public init(yearMonth: YearMonth, budgetTotalYen: Int64, expenseTotalToDateYen: Int64) {
        self.yearMonth = yearMonth
        self.budgetTotalYen = budgetTotalYen
        self.expenseTotalToDateYen = expenseTotalToDateYen
    }

    /// 残りの日に支出が無かった場合の月末余剰。
    public var projectedSurplusYen: Int64 { budgetTotalYen - expenseTotalToDateYen }
}
