import Foundation
import Testing
@testable import DailyBudgetCore

/// 日付境界・閏年・31日月の扱いを確認する（PRD §11 Phase 3 のテスト項目）。
struct CalendarArithmeticTests {
    @Test("epochDay への変換が往復する")
    func epochDayRoundTrips() {
        for offset in stride(from: -40_000, through: 40_000, by: 97) {
            let day = CalendarDay(epochDay: offset)
            #expect(day.epochDay == offset)
            #expect(CalendarDay(iso: day.iso) == day)
        }
    }

    @Test("既知の日付が既知の epochDay になる")
    func knownEpochDays() {
        #expect(CalendarDay(year: 1970, month: 1, day: 1).epochDay == 0)
        #expect(CalendarDay(year: 1969, month: 12, day: 31).epochDay == -1)
        #expect(CalendarDay(year: 2000, month: 3, day: 1).epochDay == 11_017)
        #expect(CalendarDay(year: 2026, month: 11, day: 1).epochDay == 20_758)
    }

    @Test("月末から翌日に進むと翌月1日になる")
    func crossingMonthBoundary() {
        #expect(CalendarDay(year: 2026, month: 11, day: 30).nextDay
                == CalendarDay(year: 2026, month: 12, day: 1))
        #expect(CalendarDay(year: 2026, month: 12, day: 31).nextDay
                == CalendarDay(year: 2027, month: 1, day: 1))
        #expect(CalendarDay(year: 2027, month: 1, day: 1).previousDay
                == CalendarDay(year: 2026, month: 12, day: 31))
    }

    @Test("閏年の2月末が正しく扱われる")
    func leapYearFebruary() {
        #expect(YearMonth(year: 2028, month: 2).dayCount == 29)
        #expect(YearMonth(year: 2026, month: 2).dayCount == 28)
        #expect(YearMonth(year: 2100, month: 2).dayCount == 28)  // 100で割れる年は平年
        #expect(YearMonth(year: 2000, month: 2).dayCount == 29)  // 400で割れる年は閏年
        #expect(CalendarDay(year: 2028, month: 2, day: 28).nextDay
                == CalendarDay(year: 2028, month: 2, day: 29))
        #expect(CalendarDay(year: 2028, month: 2, day: 29).nextDay
                == CalendarDay(year: 2028, month: 3, day: 1))
    }

    @Test("不正な日付は ISO 解析で拒否される")
    func invalidIsoStringsAreRejected() {
        #expect(CalendarDay(iso: "2026-02-29") == nil)
        #expect(CalendarDay(iso: "2026-13-01") == nil)
        #expect(CalendarDay(iso: "2026-11-31") == nil)
        #expect(CalendarDay(iso: "2026-1-1") == nil)
        #expect(CalendarDay(iso: "") == nil)
        #expect(CalendarDay(iso: "2026-02-28") != nil)
    }

    @Test("Asia/Tokyo の暦日として Date を解釈する")
    func interpretsDateInTokyoCalendar() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        // 2026-11-06T14:30:00Z は日本時間で 11/6 23:30。
        let beforeMidnight = Self.utcDate(2026, 11, 6, hour: 14, minute: 30)
        #expect(CalendarDay(beforeMidnight, in: tokyo) == CalendarDay(year: 2026, month: 11, day: 6))
        // その1時間後は日本時間で 11/7 00:30 なので暦日が変わる。
        let afterMidnight = beforeMidnight.addingTimeInterval(3_600)
        #expect(CalendarDay(afterMidnight, in: tokyo) == CalendarDay(year: 2026, month: 11, day: 7))
        // 同じ瞬間を UTC で見るとまだ 11/6。タイムゾーン固定が効いていることの確認。
        #expect(CalendarDay(afterMidnight, in: TimeZone(identifier: "UTC")!)
                == CalendarDay(year: 2026, month: 11, day: 6))
    }

    @Test("月の列挙と加減算が年をまたいでも正しい")
    func yearMonthArithmetic() {
        let november = YearMonth(year: 2026, month: 11)
        #expect(november.advanced(by: 1) == YearMonth(year: 2026, month: 12))
        #expect(november.advanced(by: 2) == YearMonth(year: 2027, month: 1))
        #expect(november.advanced(by: -11) == YearMonth(year: 2025, month: 12))
        #expect(november.months(until: YearMonth(year: 2027, month: 2)) == 3)
        #expect(november.through(YearMonth(year: 2027, month: 1)).count == 3)
        #expect(november.through(YearMonth(year: 2026, month: 10)).isEmpty)
    }

    @Test("日付範囲の列挙は昇順で両端を含む")
    func dayRangeEnumeration() {
        let from = CalendarDay(year: 2026, month: 11, day: 28)
        let to = CalendarDay(year: 2026, month: 12, day: 2)
        let days = from.through(to)
        #expect(days.count == 5)
        #expect(days.first == from)
        #expect(days.last == to)
        #expect(days == days.sorted())
        #expect(to.through(from).isEmpty)
        #expect(from.days(until: to) == 4)
    }

    /// UTC の年月日時分から `Date` を作る。協定世界時を基準に書くことで、
    /// 期待値が実行環境のタイムゾーンに左右されないようにする。
    private static func utcDate(
        _ year: Int, _ month: Int, _ day: Int, hour: Int, minute: Int
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        )!
    }
}
