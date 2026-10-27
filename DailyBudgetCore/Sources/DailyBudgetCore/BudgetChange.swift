import Foundation

/// 日額予算の変更をいつから適用するか（PRD §5.7 / §6.1）。
///
/// 昨日以前は選べない。過去の予算を遡って変えないことで、確定済みの月や
/// 前日までの累積余剰が後から動かないようにする（PRD §6.1）。
public enum BudgetChangeTiming: String, CaseIterable, Sendable {
    case today
    case tomorrow
    case nextMonth

    public func effectiveDate(from today: CalendarDay) -> CalendarDay {
        switch self {
        case .today: today
        case .tomorrow: today.nextDay
        case .nextMonth: today.yearMonth.next.firstDay
        }
    }
}

/// 予算変更が計算に与える影響。保存前に確認するために使う（PRD §5.7）。
public struct BudgetChangeImpact: Hashable, Sendable {
    public let effectiveFrom: CalendarDay
    public let currentDailyAmountYen: Int64
    public let newDailyAmountYen: Int64
    /// 変更前の今日の利用可能額。
    public let todayAvailableBeforeYen: Int64
    /// 変更後の今日の利用可能額。
    public let todayAvailableAfterYen: Int64
    /// 変更前の当月の月間予算（月末まで）。
    public let monthBudgetBeforeYen: Int64
    /// 変更後の当月の月間予算（月末まで）。
    public let monthBudgetAfterYen: Int64

    public init(
        effectiveFrom: CalendarDay,
        currentDailyAmountYen: Int64,
        newDailyAmountYen: Int64,
        todayAvailableBeforeYen: Int64,
        todayAvailableAfterYen: Int64,
        monthBudgetBeforeYen: Int64,
        monthBudgetAfterYen: Int64
    ) {
        self.effectiveFrom = effectiveFrom
        self.currentDailyAmountYen = currentDailyAmountYen
        self.newDailyAmountYen = newDailyAmountYen
        self.todayAvailableBeforeYen = todayAvailableBeforeYen
        self.todayAvailableAfterYen = todayAvailableAfterYen
        self.monthBudgetBeforeYen = monthBudgetBeforeYen
        self.monthBudgetAfterYen = monthBudgetAfterYen
    }

    /// 今日の利用可能額が変わるか。「明日」「翌月1日」適用なら変わらない。
    public var changesToday: Bool { todayAvailableBeforeYen != todayAvailableAfterYen }

    /// 当月の月間予算が変わるか。「翌月1日」適用なら変わらない。
    public var changesThisMonth: Bool { monthBudgetBeforeYen != monthBudgetAfterYen }
}

public enum BudgetChangePreview {
    /// 予算変更の影響を試算する。保存はしない。
    public static func impact(
        current: BudgetCalculator,
        newDailyAmountYen: Int64,
        effectiveFrom: CalendarDay,
        today: CalendarDay,
        expenses: [ExpenseEntry]
    ) -> BudgetChangeImpact {
        let newRule = BudgetRule(
            effectiveFrom: effectiveFrom,
            dailyAmountYen: newDailyAmountYen,
            // 同じ有効開始日に既存ルールがあっても新しい値が勝つようにする（PRD §6.1）。
            // 試算用の一時的なルールなので、保存される値には使わない。
            updatedAt: .distantFuture
        )
        let updated = current.applying(newRule)
        let month = today.yearMonth
        return BudgetChangeImpact(
            effectiveFrom: effectiveFrom,
            currentDailyAmountYen: current.dailyBudget(on: today),
            newDailyAmountYen: newDailyAmountYen,
            todayAvailableBeforeYen: current
                .todayBreakdown(on: today, expenses: expenses).availableYen,
            todayAvailableAfterYen: updated
                .todayBreakdown(on: today, expenses: expenses).availableYen,
            monthBudgetBeforeYen: current
                .monthSummary(for: month, expenses: expenses).budgetTotalYen,
            monthBudgetAfterYen: updated
                .monthSummary(for: month, expenses: expenses).budgetTotalYen
        )
    }
}
