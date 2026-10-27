import Foundation
import Testing
@testable import DailyBudgetCore

/// PRD §5.6 のカテゴリ別支出（金額・構成比）を確認する。
struct CategoryBreakdownTests {
    @Test("金額の降順に並び、構成比の合計が1になる")
    func sortsByAmountAndComputesShare() {
        let rows = CategoryBreakdown.make(from: [
            "食費": 6_000,
            "交通費": 3_000,
            "娯楽・交際": 1_000
        ])
        #expect(rows.map(\.name) == ["食費", "交通費", "娯楽・交際"])
        #expect(rows.map(\.amountYen) == [6_000, 3_000, 1_000])
        #expect(rows[0].share == 0.6)
        #expect(rows[1].share == 0.3)
        #expect(rows[2].share == 0.1)
        #expect(abs(rows.reduce(0) { $0 + $1.share } - 1.0) < 0.000_001)
    }

    @Test("同額のカテゴリはカテゴリ名の昇順で並ぶ")
    func tiesAreBrokenByName() {
        let rows = CategoryBreakdown.make(from: [
            "日用品": 1_000,
            "交通費": 1_000,
            "食費": 1_000
        ])
        #expect(rows.map(\.name) == ["交通費", "日用品", "食費"])
    }

    @Test("支出が無ければ空になる")
    func emptyWhenNoExpenses() {
        #expect(CategoryBreakdown.make(from: [:]).isEmpty)
        #expect(CategoryBreakdown.make(from: ["食費": 0]).isEmpty)
    }

    @Test("1カテゴリだけなら構成比は1になる")
    func singleCategoryTakesFullShare() {
        let rows = CategoryBreakdown.make(from: ["食費": 2_500])
        #expect(rows.count == 1)
        #expect(rows[0].share == 1.0)
    }
}
