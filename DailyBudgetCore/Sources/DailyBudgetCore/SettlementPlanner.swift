import Foundation

/// 月末自動確定の対象を決める。PRD §6.2 の確定タイミングを計算に落としたもの。
public enum SettlementPlanner {
    /// 自動確定すべき過去月を時系列順に返す。
    ///
    /// 対象は「利用開始月から前月まで」のうち、確定レコードがまだ存在しない月だけ。
    /// アプリを数か月開かなかった場合も、未確定月が時系列順にすべて並ぶ（PRD AC-10）。
    ///
    /// - Important: `reopened`（確定解除して編集中）の月は対象に含めない。
    ///   PRD §6.2 は「未確定の過去月を自動確定する」、§6.3 は「`reopened` 中は未確定と表示する」と
    ///   書いているため、字面どおりに実装すると、訂正のため解除した月が次回起動で
    ///   編集前の状態のまま再確定されてしまう。確定解除はユーザーの明示的な操作なので、
    ///   自動処理より優先する。再確定は §6.3 の「再確定」操作で明示的に行う。
    ///
    /// - Parameters:
    ///   - recordedMonths: 確定レコードが存在する月。`closed` と `reopened` の両方を含める。
    /// - Returns: 確定処理を行う月の昇順配列。処理不要なら空。
    public static func monthsAwaitingSettlement(
        activeStartDate: CalendarDay,
        today: CalendarDay,
        recordedMonths: Set<YearMonth>
    ) -> [YearMonth] {
        let firstMonth = activeStartDate.yearMonth
        let lastClosableMonth = today.yearMonth.previous
        guard firstMonth <= lastClosableMonth else { return [] }
        return firstMonth.through(lastClosableMonth)
            .filter { !recordedMonths.contains($0) }
    }
}
