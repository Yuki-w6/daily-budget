import Foundation

/// 支出を登録・編集できる日を決める。PRD §5.4「利用開始日〜当日、かつ未確定月のみ」に対応する。
public enum ExpenseEditPolicy {
    /// 支出日として選べる範囲。該当する日が1日もなければ `nil`。
    ///
    /// 下限は利用開始日。ただし確定済みの月には入力させない。確定は古い月から順に
    /// 行われるため、最後に確定した月の翌月初日まで下限が繰り上がる。
    /// `reopened`（確定を解除して編集中）の月は `closedMonths` に含めないので、
    /// 解除した月はそのまま編集できる。
    ///
    /// 上限は当日。未来日は登録できない（PRD §5.4）。
    public static func editableDateRange(
        activeStartDate: CalendarDay,
        today: CalendarDay,
        closedMonths: Set<YearMonth>
    ) -> ClosedRange<CalendarDay>? {
        let lowerBound = earliestEditableDate(
            activeStartDate: activeStartDate,
            closedMonths: closedMonths
        )
        guard lowerBound <= today else { return nil }
        return lowerBound...today
    }

    /// 支出を登録・編集できる最も早い日。
    public static func earliestEditableDate(
        activeStartDate: CalendarDay,
        closedMonths: Set<YearMonth>
    ) -> CalendarDay {
        guard let latestClosed = closedMonths.max() else { return activeStartDate }
        return max(activeStartDate, latestClosed.next.firstDay)
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
