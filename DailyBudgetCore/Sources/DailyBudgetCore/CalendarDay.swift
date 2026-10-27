import Foundation

/// 時刻を持たない暦日（`YYYY-MM-DD`）。
///
/// PRD §6.4「日次・月次の境界は `Asia/Tokyo` の暦日で判定し、グレゴリオ暦を使用する」に対応する。
/// 時刻を持たないため、保存・比較・集計のいずれでも時差やサマータイムの影響を受けない。
/// `Date` との変換は `init(_:in:)` だけで行い、計算系はすべてこの型の上で閉じる。
public struct CalendarDay: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// 妥当な暦日であることを前提に生成する。範囲外の値はプログラム上の誤りとして扱う。
    public init(year: Int, month: Int, day: Int) {
        precondition(
            Self.isValid(year: year, month: month, day: day),
            "不正な暦日: \(year)-\(month)-\(day)"
        )
        self.year = year
        self.month = month
        self.day = day
    }

    /// `YYYY-MM-DD` 形式の文字列から生成する。永続化された値の読み込みに使う。
    public init?(iso: String) {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              Self.isValid(year: year, month: month, day: day)
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// 指定タイムゾーンの暦日として `Date` を解釈する。
    public init(_ date: Date, in timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = components.year!
        self.month = components.month!
        self.day = components.day!
    }

    /// `YYYY-MM-DD`。永続化と表示の両方で使う正規形。
    public var iso: String {
        let m = month < 10 ? "0\(month)" : "\(month)"
        let d = day < 10 ? "0\(day)" : "\(day)"
        return "\(year)-\(m)-\(d)"
    }

    public var description: String { iso }

    public var yearMonth: YearMonth { YearMonth(year: year, month: month) }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public static func isValid(year: Int, month: Int, day: Int) -> Bool {
        guard (1...12).contains(month) else { return false }
        return (1...YearMonth(year: year, month: month).dayCount).contains(day)
    }
}

// MARK: - 日数演算

extension CalendarDay {
    /// 1970-01-01 を 0 とする連続日数。
    ///
    /// `Calendar` を介さず先発グレゴリオ暦の閉じた式で変換するため、
    /// 月末・閏年・年境界をまたぐ加減算が常に決定的になる。
    public var epochDay: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let monthTerm = month + (month > 2 ? -3 : 9)
        let dayOfYear = (153 * monthTerm + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    public init(epochDay: Int) {
        let z = epochDay + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra =
            (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let y = yearOfEra + era * 400
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthTerm = (5 * dayOfYear + 2) / 153
        self.day = dayOfYear - (153 * monthTerm + 2) / 5 + 1
        self.month = monthTerm + (monthTerm < 10 ? 3 : -9)
        self.year = self.month <= 2 ? y + 1 : y
    }

    public func adding(days: Int) -> CalendarDay {
        CalendarDay(epochDay: epochDay + days)
    }

    public var nextDay: CalendarDay { adding(days: 1) }
    public var previousDay: CalendarDay { adding(days: -1) }

    /// `self` から `other` までの日数。`other` が後なら正。
    public func days(until other: CalendarDay) -> Int {
        other.epochDay - epochDay
    }

    /// `self ... other` を昇順に列挙する。`other` が `self` より前なら空。
    public func through(_ other: CalendarDay) -> [CalendarDay] {
        guard self <= other else { return [] }
        return (epochDay...other.epochDay).map(CalendarDay.init(epochDay:))
    }
}
