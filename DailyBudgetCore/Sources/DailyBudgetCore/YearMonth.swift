import Foundation

/// 年月（`YYYY-MM`）。予算期間と月末確定の単位。
public struct YearMonth: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        precondition((1...12).contains(month), "不正な月: \(month)")
        self.year = year
        self.month = month
    }

    /// `YYYY-MM` 形式の文字列から生成する。
    public init?(iso: String) {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].count == 4, parts[1].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]),
              (1...12).contains(month)
        else { return nil }
        self.year = year
        self.month = month
    }

    public init(_ date: Date, in timeZone: TimeZone) {
        self = CalendarDay(date, in: timeZone).yearMonth
    }

    public var iso: String {
        let m = month < 10 ? "0\(month)" : "\(month)"
        return "\(year)-\(m)"
    }

    public var description: String { iso }

    /// 暦日数。PRD §4.2「月間予算は日額予算 × 暦日数」の暦日数にあたる。
    public var dayCount: Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: 31
        case 4, 6, 9, 11: 30
        default: Self.isLeapYear(year) ? 29 : 28
        }
    }

    public var firstDay: CalendarDay { CalendarDay(year: year, month: month, day: 1) }
    public var lastDay: CalendarDay { CalendarDay(year: year, month: month, day: dayCount) }

    public var allDays: [CalendarDay] { firstDay.through(lastDay) }

    public func advanced(by months: Int) -> YearMonth {
        let total = year * 12 + (month - 1) + months
        return YearMonth(year: total / 12, month: total % 12 + 1)
    }

    public var next: YearMonth { advanced(by: 1) }
    public var previous: YearMonth { advanced(by: -1) }

    /// `self` から `other` までの月数。`other` が後なら正。
    public func months(until other: YearMonth) -> Int {
        (other.year * 12 + other.month) - (year * 12 + month)
    }

    /// `self ... other` を昇順に列挙する。`other` が `self` より前なら空。
    public func through(_ other: YearMonth) -> [YearMonth] {
        guard self <= other else { return [] }
        return (0...months(until: other)).map { advanced(by: $0) }
    }

    public static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    public static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }
}
