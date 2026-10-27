import Foundation
import DailyBudgetCore

extension CalendarDay {
    /// `DatePicker` との受け渡しに使う `Date`。
    ///
    /// 正午を指すのは、タイムゾーンの差で前後の日に丸められるのを防ぐため。
    /// 集計には使わない（集計はすべて `CalendarDay` の上で行う）。
    func noonDate(in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: 12)
        ) ?? Date()
    }

    /// 「2026年11月6日」。ロケールに依存せず日本語表記で組み立てる（MVPは日本語UI固定）。
    var japaneseLongText: String { "\(year)年\(month)月\(day)日" }

    /// 「11/6」。一覧の行で使う短い表記。
    var shortText: String { "\(month)/\(day)" }
}
