import Foundation

/// 円金額の表示。PRD §8.3「`¥2,000`、差額は `+¥1,800` / `−¥500` など符号を明示」に対応する。
enum Yen {
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return formatter
    }()

    /// 符号なしの金額。例：`¥2,000`。負数は `−¥500` になる。
    static func amount(_ yen: Int64) -> String {
        let digits = formatter.string(from: NSNumber(value: abs(yen))) ?? "\(abs(yen))"
        // 全角マイナス（U+2212）を使い、ハイフンとの見分けがつくようにする。
        return yen < 0 ? "−¥\(digits)" : "¥\(digits)"
    }

    /// 符号を必ず付ける差額表示。例：`+¥1,800` / `−¥500` / `¥0`。
    static func signedAmount(_ yen: Int64) -> String {
        if yen > 0 {
            return "+" + amount(yen)
        }
        return amount(yen)
    }

    /// VoiceOver 用の読み上げ文。記号ではなく語で伝える。
    static func spoken(_ yen: Int64) -> String {
        let digits = formatter.string(from: NSNumber(value: abs(yen))) ?? "\(abs(yen))"
        return yen < 0 ? "マイナス\(digits)円" : "\(digits)円"
    }
}
