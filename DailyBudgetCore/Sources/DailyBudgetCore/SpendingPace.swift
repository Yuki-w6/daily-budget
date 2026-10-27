import Foundation

/// 今月これまでの平均支出がこのまま続いた場合の月末見込み。
///
/// PRD §5.6 の「月末予測」を、1日あたりの平均支出から見積もる形で表す。
/// 実績（`MonthSummary`）とは別の型にして、取り違えないようにしている。
public struct SpendingPaceProjection: Hashable, Sendable {
    public let yearMonth: YearMonth
    /// 集計した日数。期間開始日から閲覧日まで。
    public let elapsedDays: Int
    /// 期間全体の日数。期間開始日から月末まで。月途中に使い始めた月は暦日数より短い。
    public let totalDays: Int
    /// 期間全体の予算。
    public let budgetTotalYen: Int64
    /// 閲覧日までの支出。
    public let expenseToDateYen: Int64
    /// 月末時点の支出見込み。平均支出 × 期間全体の日数。
    public let projectedExpenseYen: Int64

    public init(
        yearMonth: YearMonth,
        elapsedDays: Int,
        totalDays: Int,
        budgetTotalYen: Int64,
        expenseToDateYen: Int64,
        projectedExpenseYen: Int64
    ) {
        self.yearMonth = yearMonth
        self.elapsedDays = elapsedDays
        self.totalDays = totalDays
        self.budgetTotalYen = budgetTotalYen
        self.expenseToDateYen = expenseToDateYen
        self.projectedExpenseYen = projectedExpenseYen
    }

    /// 月末時点の余剰見込み。負なら超過。
    public var projectedSurplusYen: Int64 { budgetTotalYen - projectedExpenseYen }

    /// 1日あたりの平均支出。
    public var averageDailyExpenseYen: Int64 {
        guard elapsedDays > 0 else { return 0 }
        return SpendingPace.divideRounding(expenseToDateYen, by: Int64(elapsedDays))
    }

    /// 期間の最終日まで到達していて、見込みではなく実績であるか。
    public var isActual: Bool { elapsedDays >= totalDays }
}

public enum SpendingPace {
    /// 見込みを出すのに必要な最低日数。
    ///
    /// 数日分の平均は振れ幅が大きく、月末の見込みとして当てにならない。
    /// これを下回る間は見込みを出さない。
    public static let minimumElapsedDays = 5

    /// 平均支出から月末を見積もる。日数が足りなければ `nil`。
    ///
    /// - Parameter asOf: 閲覧日。通常は今日。
    public static func projection(
        calculator: BudgetCalculator,
        yearMonth: YearMonth,
        expenses: [ExpenseEntry],
        asOf: CalendarDay
    ) -> SpendingPaceProjection? {
        let toDate = calculator.monthSummary(for: yearMonth, expenses: expenses, asOf: asOf)
        let fullPeriod = calculator.monthSummary(for: yearMonth, expenses: expenses, asOf: nil)

        let elapsedDays = toDate.days.count
        let totalDays = fullPeriod.days.count
        guard elapsedDays >= minimumElapsedDays, totalDays > 0 else { return nil }

        // 期間の最終日まで来ていれば、見積もらずに実績をそのまま使う。
        let projectedExpense = elapsedDays >= totalDays
            ? toDate.expenseTotalYen
            : divideRounding(toDate.expenseTotalYen * Int64(totalDays), by: Int64(elapsedDays))

        return SpendingPaceProjection(
            yearMonth: yearMonth,
            elapsedDays: elapsedDays,
            totalDays: totalDays,
            budgetTotalYen: fullPeriod.budgetTotalYen,
            expenseToDateYen: toDate.expenseTotalYen,
            projectedExpenseYen: projectedExpense
        )
    }

    /// 四捨五入する整数除算。金額は円単位の整数で扱うため、浮動小数点を挟まない。
    static func divideRounding(_ value: Int64, by divisor: Int64) -> Int64 {
        guard divisor != 0 else { return 0 }
        let halved = divisor / 2
        return value >= 0 ? (value + halved) / divisor : (value - halved) / divisor
    }
}
