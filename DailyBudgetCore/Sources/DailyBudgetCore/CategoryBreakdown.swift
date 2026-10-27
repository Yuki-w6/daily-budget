import Foundation

/// カテゴリ別支出の1行。PRD §5.6「カテゴリごとの金額・構成比」に対応する。
public struct CategoryShare: Hashable, Sendable, Identifiable {
    public let name: String
    public let amountYen: Int64
    /// 構成比。0.0〜1.0。支出合計が0なら0。
    public let share: Double

    public var id: String { name }

    public init(name: String, amountYen: Int64, share: Double) {
        self.name = name
        self.amountYen = amountYen
        self.share = share
    }
}

public enum CategoryBreakdown {
    /// カテゴリ名ごとの合計から構成比つきの一覧を作る。
    ///
    /// 金額の降順、同額ならカテゴリ名の昇順で並べる。順序を決めておくことで、
    /// 同じデータなら毎回同じ並びになり、画面がちらつかない。
    /// 金額が0以下のカテゴリは除外する。
    public static func make(from totals: [String: Int64]) -> [CategoryShare] {
        let positive = totals.filter { $0.value > 0 }
        let sum = positive.values.reduce(0, +)
        return positive
            .map { name, amount in
                CategoryShare(
                    name: name,
                    amountYen: amount,
                    // 支出が無い月は0除算になるため、合計0なら構成比も0とする。
                    share: sum > 0 ? Double(amount) / Double(sum) : 0
                )
            }
            .sorted { lhs, rhs in
                lhs.amountYen == rhs.amountYen
                    ? lhs.name < rhs.name
                    : lhs.amountYen > rhs.amountYen
            }
    }
}
