import Foundation

/// 支出を登録・編集できる日を決める。PRD §5.4「利用開始日〜当日、かつ未確定月のみ」に対応する。
public enum ExpenseEditPolicy {
    /// 支出日として選べる範囲。該当する日が1日もなければ `nil`。
    ///
    /// 下限は、利用開始日以降で最初に見つかる未確定の月の初日。上限は当日で、
    /// 未来日は登録できない（PRD §5.4）。
    /// `reopened`（確定を解除して編集中）の月は `closedMonths` に含めないため、
    /// 解除した月はそのまま編集できる。
    ///
    /// - Important: 範囲の途中に確定済みの月が残ることがある。古い月だけを解除した
    ///   場合がそれにあたる。範囲に含まれていても確定済みの月は編集できないので、
    ///   実際に登録・編集してよいかは `isEditable(_:...)` で判定する。
    public static func editableDateRange(
        activeStartDate: CalendarDay,
        today: CalendarDay,
        closedMonths: Set<YearMonth>
    ) -> ClosedRange<CalendarDay>? {
        guard let lowerBound = earliestEditableDate(
            activeStartDate: activeStartDate,
            today: today,
            closedMonths: closedMonths
        ) else { return nil }
        return lowerBound...today
    }

    /// 支出を登録・編集できる最も早い日。編集できる日が1日もなければ `nil`。
    public static func earliestEditableDate(
        activeStartDate: CalendarDay,
        today: CalendarDay,
        closedMonths: Set<YearMonth>
    ) -> CalendarDay? {
        guard activeStartDate <= today else { return nil }
        for month in activeStartDate.yearMonth.through(today.yearMonth)
        where !closedMonths.contains(month) {
            return max(activeStartDate, month.firstDay)
        }
        return nil
    }

    /// その日を編集できるか。
    public static func isEditable(
        _ day: CalendarDay,
        activeStartDate: CalendarDay,
        today: CalendarDay,
        closedMonths: Set<YearMonth>
    ) -> Bool {
        guard let range = editableDateRange(
            activeStartDate: activeStartDate,
            today: today,
            closedMonths: closedMonths
        ) else { return false }
        return range.contains(day) && !closedMonths.contains(day.yearMonth)
    }
}
